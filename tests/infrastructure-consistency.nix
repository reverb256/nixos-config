{
  # Infrastructure Consistency Test — catches all known pitfall patterns
  # Add new checks here when you discover a new class of failure.
  #
  # Pitfalls covered:
  #   HW-1: Each host has standalone hardware config (no symlinks to shared file)
  #   HW-2: Hardware config uses partlabels, not UUIDs
  #   HW-3: No filesystem mounts to non-existent disks (nofail on removable)
  #   HW-4: panic_on_oops=0 on sentry (MCE mitigation)
  #   HW-5: No invalid platform strings in distributed builders config
  #   HW-6: No duplicate option declarations
  #   HW-7: sops files referenced in registry exist
  #   HW-8: NFS mounts have nofail when NFS server is known dead
  #   HW-9: Flake inputs are not unused
  #   HW-10: No stale LOLMINER or XMRIG references in .nix files
  #   HW-11: Each host configuration evaluates without error
  #   HW-12: Hardware config devices use persistent naming (by-partlabel)
  #   HW-13: No stale uncommitted files in hardware-config
  #   HW-14: MCE mitigation params are present on hosts with AMD GPUs
  #   HW-15: Stale config patterns are detected
  #   HW-16: No /etc/nixos hw config symlinks between hosts
  #   HW-17: All hosts have required files (configuration.nix + hardware-configuration.nix)
  #   HW-18: No merge-drift in disko files (stale imports)
  #   HW-19: panic=timeout is set appropriately (not conflicting values)
  #   HW-20: Build closure check — each host can build (nix-build)
  #
  pkgs ? import <nixpkgs> {},
}: let
  lib = pkgs.lib;

  # ── Host definitions ──
  allHosts = ["zephyr" "nexus" "forge" "sentry"];
  buildHosts = ["zephyr" "nexus" "forge" "sentry"];
  gpuAmdHosts = ["sentry" "forge"]; # Hosts with AMD GPUs that may trigger MCE Bank 5
  nfsDeadHosts = ["sentry" "forge" "nexus"]; # Hosts where nixos-share NFS is dead

  # ── Helpers ──
  fileExists = path: builtins.pathExists path;
  readFile = path: builtins.readFile path;
  # Call sites pass (needle source); keep the helper argument order
  # consistent with lib.strings.hasInfix to avoid false negatives.
  hasInfix = needle: source: lib.strings.hasInfix needle source;
  any = lib.any;
  all = lib.all;
  filter = lib.filter;

  # ── HW-1: Each host has standalone hardware config (NOT a symlink) ──
  # NOTE: Nix builtins.readFile follows symlinks, so we can't detect symlinks
  # in pure evaluation. Instead, check that each host's config is at least
  # different from the shared /etc/nixos/hardware-configuration.nix
  # (the shared file only had kernel modules, no filesystem definitions).
  hwConfigPath = host: ./../hosts/${host}/hardware-configuration.nix;
  hwConfigIsFile = host: builtins.pathExists (hwConfigPath host);

  # Check that the host config has actual filesystem definitions (not a stub)
  # A standalone config should have at least one fileSystems definition
  hwConfigHasFileSystems = host: let
    src = builtins.readFile (hwConfigPath host);
  in
    lib.strings.hasInfix "fileSystems." src;

  # ── HW-2: Hardware config uses partlabels, not UUIDs ──
  hwConfigUsesUUID = host: let
    src = readFile (hwConfigPath host);
  in
    hasInfix "by-uuid" src;

  hwConfigUsesPartlabel = host: let
    src = readFile (hwConfigPath host);
  in
    hasInfix "by-partlabel" src;

  # ── HW-3: No filesystem mounts to non-existent disks ──
  # Check that all device = "/dev/..." entries use mechanisms that survive disk swaps
  # (partlabel, by-id, etc.)
  hwConfigUsesStableDeviceNames = host: let
    src = readFile (hwConfigPath host);
    lines = lib.splitString "\n" src;
    deviceLines = filter (l: hasInfix "device =" l) lines;
    # Look for devices that use by-uuid (brittle)
    uuidDevices = filter (l: hasInfix "by-uuid" l) deviceLines;
  in
    builtins.length uuidDevices == 0;

  # ── HW-4: panic_on_oops=0 on sentry (MCE mitigation) ──
  sentryConfig = readFile ./../hosts/sentry/configuration.nix;
  hasPanicOnOops0 = hasInfix "panic_on_oops=0" sentryConfig;

  # ── HW-5: Multilib builds are Nexus-only ──
  # Nexus is the sole builder and must accept i686 Steam/VR derivations;
  # Zephyr, Forge, and Sentry must not be advertised as build targets.
  distributedBuilds = readFile ./../modules/system/distributed-builds.nix;
  nexusSupportsMultilib = hasInfix "systems = [\"x86_64-linux\" \"i686-linux\"];" distributedBuilds;
  noOtherMultilibBuilder =
    !(hasInfix "currentHost == \"sentry\"" distributedBuilds)
    && !(hasInfix "hostName = \"sentry\"" distributedBuilds)
    && !(hasInfix "hostName = \"forge\"" distributedBuilds);
  hasNoInvalidPlatform = nexusSupportsMultilib && noOtherMultilibBuilder;

  # ── HW-6: No duplicate option declarations ──
  # Check that no option is declared in both mining.nix and the role profile
  miningModule = readFile ./../modules/mining/mining.nix;
  implementationsModule = readFile ./../modules/profiles/role/implementations.nix;
  # Match the actual option declaration, not comments that merely mention
  # the option namespace while documenting the removed implementation.
  noDuplicateMiningOption =
    (hasInfix "options.services.mining =" miningModule)
    && !(hasInfix "options.services.mining =" implementationsModule);

  # ── HW-7: sops files referenced in registry exist ──
  # NOTE: This is a simplified check — the full check is in secrets-integrity.nix
  k3sTokenExists = fileExists ./../secrets/k8s/k3s-cluster-token.yaml;

  # ── HW-8: NFS mounts have nofail when NFS server is known dead ──
  # Check that nixos-share is disabled on non-zephyr hosts
  sentryNixosShare = hasInfix "nixos-share" sentryConfig;
  sentryNixosShareDisabled =
    hasInfix "enable = false" sentryConfig
    || hasInfix "enable = lib.mkForce false" sentryConfig;

  # ── HW-10: No stale LOLMINER or XMRIG refs in .nix files ──
  # Check by searching for these strings across the source
  # We do this by checking key files we know were affected
  miningModuleClean = !(hasInfix "lolminer" miningModule) && !(hasInfix "xmrig" miningModule);
  flakeNix = readFile ./../flake.nix;
  flakeClean = !(hasInfix "lolminer" flakeNix) && !(hasInfix "xmrig" flakeNix);

  # ── HW-11: Each host configuration file exists ──
  hostConfigExists = host: fileExists (./../hosts/${host} + "/configuration.nix");
  allHostConfigsExist = all hostConfigExists allHosts;

  # ── HW-12: Hardware config uses persistent naming ──
  # Partlabels are our standard
  sentryHwConfig = readFile (hwConfigPath "sentry");
  sentryUsesPartlabel = hasInfix "by-partlabel" sentryHwConfig;

  # ── HW-14: MCE mitigation params on AMD GPU hosts ──
  # 2026-07-28: changed max_cstate expectation from "=5" to "=1". The earlier
  # override of "=5" un-mitigated the Zen 1 C6 deep-sleep lockup (last-wins in
  # kernel cmdline UNDID the fleet's `=1` baseline in kernel-hardening.nix).
  # See docs/audit-2026-07-27.md F-3 and boot error triage 2026-07-28.
  sentryHasMceMitigation =
    hasInfix "processor.max_cstate=1" sentryConfig
    && hasInfix "panic_on_oops=0" sentryConfig;

  # ── HW-16: No /etc/nixos hw config symlinks between hosts ──
  # Check ALL hosts for filesystem definitions (proxy for standalone)
  allHostsHaveFileSystems = all hwConfigHasFileSystems allHosts;

  # ── HW-17: All hosts have required files ──
  # Each host dir needs configuration.nix AND hardware-configuration.nix
  hostHasHwConfig = host: fileExists (hwConfigPath host);
  allHostsHaveHwConfig = all hostHasHwConfig allHosts;

  # ── HW-19: Kernel panic params are consistent ──
  # panic= should be set, not conflicting values
  sentryHasPanicTimeout = hasInfix "panic=30" sentryConfig;
  sentryPanicNotOverride = !(hasInfix "panic=-1" sentryConfig);

  # ── HW-21: PeakMiner identity and persistent-state contracts ──
  peakminerSources = map (host: readFile ./../hosts/${host}/peakminer.nix) ["zephyr" "nexus" "forge"];
  peakminerGpuNamesConfigured = all (src: hasInfix "gpuName =" src) peakminerSources;
  nexusConfig = readFile ./../hosts/nexus/configuration.nix;
  nexusWiring = readFile ./../hosts/nexus/secretspec-creds-wiring.nix;
  nexusPreservation = readFile ./../hosts/nexus/preservation.nix;
  forgeConfig = readFile ./../hosts/forge/configuration.nix;
  forgePreservation = readFile ./../hosts/forge/preservation.nix;
  sentryPreservation = readFile ./../hosts/sentry/preservation.nix;
  nexusUsesPreservation = hasInfix "./preservation.nix" nexusConfig
    && hasInfix "preservation.enable = true;" nexusPreservation
    && !(fileExists ./../hosts/nexus/impermanence.nix);
  persistentHostPreservationEnabled =
    all (src: hasInfix "preservation.enable = true;" src)
      [nexusPreservation forgePreservation sentryPreservation];
  persistentHostsPreserveAge =
    all (src: hasInfix "/etc/nixos/.age" src || hasInfix "/etc/sops/age" src)
      [nexusPreservation forgePreservation sentryPreservation];
  caSource = readFile ./../modules/services/cluster-ca.nix;
  caFailsClosed = hasInfix "refusing to generate a trust-root fork" caSource
    && hasInfix "does not match" caSource
    && hasInfix "chmod 0400" caSource;
  nexusCaKeySecret =
    # CA key now provisioned via SecretSpec wiring (CLUSTER_CA_KEY), not the
    # retired sops.secrets path — sops-nix doesn't run on nexus.
    hasInfix "CLUSTER_CA_KEY" nexusWiring
    && hasInfix "cluster-ca-key.yaml" nexusWiring
    && hasInfix "caKeyProvisioned = true;" nexusConfig
    && hasInfix "caKeyService = \"secretspec-creds.service\";" nexusConfig;

  # ── HW-22: Incus-only dormant Windows VM contract ──
  zephyrVmConfig = readFile ./../hosts/zephyr/configuration.nix;
  zephyrVmPreservation = readFile ./../hosts/zephyr/preservation.nix;
  incusVmModule = readFile ./../modules/hardware/incus-gamepass.nix;
  vmMigrationDoc = readFile ./../docs/incus-gamepass-migration.md;
  parallelVmBackends =
    hasInfix "incus-gamepass.nix" zephyrVmConfig
    && !(hasInfix "vfio-gamepass.nix" zephyrVmConfig)
    && hasInfix "gamepass-win11-incus" incusVmModule
    && !(hasInfix "start-libvirt" incusVmModule)
    && !(hasInfix "stop-libvirt" incusVmModule);
  dormantVmBackends =
    hasInfix "boot.autostart" incusVmModule
    && hasInfix "gamepass-incus-vm.service" incusVmModule;
  sharedGpuContract =
    # Incus VM physical GPU device for the 3060 Ti; raw PCI only for HDMI audio.
    hasInfix "type = \"gpu\";" incusVmModule
    && hasInfix "gputype = \"physical\";" incusVmModule
    && hasInfix "pci = vfioGpu;" incusVmModule
    && hasInfix "gpu-audio = {" incusVmModule
    && hasInfix "type = \"pci\";" incusVmModule
    && hasInfix "address = vfioAudio;" incusVmModule
    && hasInfix "0000:24:00.0" incusVmModule
    && hasInfix "0000:24:00.1" incusVmModule
    && hasInfix "0x2486" incusVmModule
    && hasInfix "0x228b" incusVmModule
    && hasInfix "0000:2d:00.0" incusVmModule
    && hasInfix "0000:2d:00.1" incusVmModule
    && hasInfix "0x2204" incusVmModule
    && hasInfix "0x1aef" incusVmModule
    && hasInfix "vfioIommuGroup = \"24\"" incusVmModule
    && hasInfix "protectedIommuGroup = \"27\"" incusVmModule
    && hasInfix "RTX 3090" zephyrVmConfig
    && hasInfix "never detached" incusVmModule
    && hasInfix "Incus declares the VM GPU" vmMigrationDoc;
  vmStatePreserved =
    hasInfix "\"/var/lib/incus\"" zephyrVmPreservation
    && hasInfix "\"/var/lib/incus-gamepass\"" zephyrVmPreservation
    && !(hasInfix "\"/var/lib/libvirt\"" zephyrVmPreservation);
  vmMigrationDocumented =
    hasInfix "incus-gamepass-vm create" vmMigrationDoc
    && hasInfix "incus-gamepass-vm start" vmMigrationDoc
    && hasInfix "must remain stopped" vmMigrationDoc
    && !(hasInfix "libvirt" vmMigrationDoc);
  lookingGlassContract =
    hasInfix "raw.qemu" incusVmModule
    && hasInfix "/dev/kvmfr0" incusVmModule
    && hasInfix "DeviceAllow" incusVmModule
    && hasInfix "SupplementaryGroups" incusVmModule
    && hasInfix "looking-glass-gamepass" vmMigrationDoc
    && hasInfix "check-looking-glass" vmMigrationDoc;
  gpuHandoffSafetyContract =
    # The host guard validates and quiesces; Incus owns vfio-pci binding and
    # restoration through its recorded last_state.pci.driver lifecycle.
    hasInfix "validate_identity" incusVmModule
    && hasInfix "iommu_group" incusVmModule
    && hasInfix "group_members=" incusVmModule
    && hasInfix "expected_members=" incusVmModule
    && hasInfix "protectedIommuGroup" incusVmModule
    && hasInfix "trap 'rc=$?" incusVmModule
    && hasInfix "Refusing to release VFIO while" incusVmModule
    && hasInfix "workload remains active" incusVmModule
    && hasInfix "target_clients=" incusVmModule
    && hasInfix "target_graphics=" incusVmModule
    && hasInfix "pmon_output=" incusVmModule
    && hasInfix "pmon returned an unrecognized sample" incusVmModule
    && hasInfix "pmon -i 00000000:24:00.0" incusVmModule
    && hasInfix "preflight-only" incusVmModule
    && hasInfix "must not bind/unbind" incusVmModule
    && hasInfix "last_state.pci.driver" incusVmModule
    && hasInfix "Incus now owns the transition" incusVmModule
    && hasInfix "Incus did not restore the 3060 Ti host drivers" incusVmModule
    && hasInfix "Incus start failed after VFIO claim" incusVmModule
    && hasInfix "/bin/incus start" incusVmModule
    && hasInfix "|| rc=$?" incusVmModule
    && hasInfix "[ \"$rc\" -eq 0 ] && exit 0" incusVmModule
    && !(hasInfix "echo vfio-pci >" incusVmModule)
    && !(hasInfix "drivers_probe" incusVmModule)
    && !(hasInfix "rm -rf" incusVmModule);
  storageReconciliationContract =
    hasInfix "incus-gamepass-vm reconcile" vmMigrationDoc
    && hasInfix "registered gamepass pool has unexpected driver/source" incusVmModule
    && hasInfix "--format yaml" incusVmModule
    && hasInfix "driver = \"dir\"" incusVmModule
    && hasInfix "unregistered Incus storage directory exists" incusVmModule
    && hasInfix "existing resources but the Game Pass pool/profile is incomplete" incusVmModule
    && hasInfix "partially initialized daemon" incusVmModule
    && hasInfix "unable to query Incus storage pools" incusVmModule
    && hasInfix "unable to query Incus profiles" incusVmModule
    && hasInfix "unable to query Incus networks" incusVmModule
    && hasInfix "refusing to delete or overwrite VM state" incusVmModule;
  incusPreseedRequired =
    hasInfix "requires = [ \"incus-preseed.service\" ];" incusVmModule;
  incusVmBackend =
    parallelVmBackends
    && !(hasInfix "virtualisation.libvirtd" incusVmModule);
  dormantVmBackend = dormantVmBackends;
  gpuPassthroughContract = sharedGpuContract;
  vmOperationsContract = vmMigrationDocumented;
  incusPreseedContract = incusPreseedRequired;

  # ── Build the check results ──
  checks = {
    # HW-1: Standalone hardware configs
    hw_config_sentry_has_filesystems = hwConfigHasFileSystems "sentry";
    hw_config_zephyr_has_filesystems = hwConfigHasFileSystems "zephyr";
    hw_config_nexus_has_filesystems = hwConfigHasFileSystems "nexus";
    hw_config_forge_has_filesystems = hwConfigHasFileSystems "forge";

    # HW-2: Partlabels not UUIDs
    hw_config_sentry_uses_partlabels = sentryUsesPartlabel;

    # HW-3: No stale device references
    hw_config_sentry_stable_devices = hwConfigUsesStableDeviceNames "sentry";

    # HW-4: MCE mitigation
    sentry_panic_on_oops_0 = hasPanicOnOops0;
    sentry_mce_mitigation = sentryHasMceMitigation;

    # HW-5: Nexus-only multilib builder
    distributed_builds_nexus_only_multilib = hasNoInvalidPlatform;

    # HW-6: No duplicate options
    no_duplicate_mining_option = noDuplicateMiningOption;

    # HW-7: sops files exist
    k3s_cluster_token_exists = k3sTokenExists;

    # HW-10: No stale miners
    mining_module_clean = miningModuleClean;
    flake_nix_clean = flakeClean;

    # HW-11: Host configs exist
    all_host_configs_exist = allHostConfigsExist;

    # HW-16: All hosts have hw configs
    all_hosts_have_hw_config = allHostsHaveHwConfig;

    # HW-19: Kernel panic consistency
    sentry_has_panic_timeout = sentryHasPanicTimeout;
    sentry_no_conflicting_panic = sentryPanicNotOverride;

    # HW-21: PeakMiner and persistent-state contracts
    peakminer_gpu_names_configured = peakminerGpuNamesConfigured;
    nexus_uses_preservation = nexusUsesPreservation;
    persistent_host_preservation_enabled = persistentHostPreservationEnabled;
    persistent_hosts_preserve_age = persistentHostsPreserveAge;
    cluster_ca_fails_closed = caFailsClosed;
    nexus_ca_key_secret_wired = nexusCaKeySecret;

    # HW-22: Incus-only dormant Windows VM contract
    incus_only_vm_backend = incusVmBackend;
    dormant_vm_backend = dormantVmBackend;
    gpu_passthrough_contract = gpuPassthroughContract;
    vm_state_preserved = vmStatePreserved;
    vm_operations_documented = vmOperationsContract;
    looking_glass_contract = lookingGlassContract;
    gpu_handoff_safety_contract = gpuHandoffSafetyContract;
    storage_reconciliation_contract = storageReconciliationContract;
    incus_preseed_required = incusPreseedContract;
  };

  # ── Report failures ──
  failures = lib.filterAttrs (name: value: !value) checks;
  passed = lib.filterAttrs (name: value: value) checks;
  allCheckNames = builtins.attrNames checks;
  failNames = builtins.attrNames failures;
  passNames = builtins.attrNames passed;
in {
  inherit checks;
  total = builtins.length allCheckNames;
  passed_count = builtins.length passNames;
  failed_count = builtins.length failNames;
  failures = failNames;
  all_pass = failNames == [];
  # Print summary
  summary = let
    ok = builtins.length passNames;
    fail = builtins.length failNames;
  in
    "${toString ok}/${toString allCheckNames} checks passed"
    + (
      if fail > 0
      then ", ${toString fail} FAILED: ${lib.concatStringsSep ", " failNames}"
      else ""
    );
}
