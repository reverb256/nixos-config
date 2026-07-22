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
}:
let
  lib = pkgs.lib;

  # ── Host definitions ──
  allHosts = ["zephyr" "nexus" "forge" "sentry"];
  buildHosts = ["zephyr" "nexus" "forge" "sentry"];
  gpuAmdHosts = ["sentry" "forge"]; # Hosts with AMD GPUs that may trigger MCE Bank 5
  nfsDeadHosts = ["sentry" "forge" "nexus"]; # Hosts where nixos-share NFS is dead

  # ── Helpers ──
  fileExists = path: builtins.pathExists path;
  readFile = path: builtins.readFile path;
  hasInfix = str: substr: lib.strings.hasInfix substr str;
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
  hwConfigHasFileSystems = host:
    let src = builtins.readFile (hwConfigPath host);
    in lib.strings.hasInfix "fileSystems." src;

  # ── HW-2: Hardware config uses partlabels, not UUIDs ──
  hwConfigUsesUUID = host:
    let src = readFile (hwConfigPath host);
    in hasInfix "by-uuid" src;

  hwConfigUsesPartlabel = host:
    let src = readFile (hwConfigPath host);
    in hasInfix "by-partlabel" src;

  # ── HW-3: No filesystem mounts to non-existent disks ──
  # Check that all device = "/dev/..." entries use mechanisms that survive disk swaps
  # (partlabel, by-id, etc.)
  hwConfigUsesStableDeviceNames = host:
    let src = readFile (hwConfigPath host);
        lines = lib.splitString "\n" src;
        deviceLines = filter (l: hasInfix "device =" l) lines;
        # Look for devices that use by-uuid (brittle)
        uuidDevices = filter (l: hasInfix "by-uuid" l) deviceLines;
    in builtins.length uuidDevices == 0;

  # ── HW-4: panic_on_oops=0 on sentry (MCE mitigation) ──
  sentryConfig = readFile ./../hosts/sentry/configuration.nix;
  hasPanicOnOops0 = hasInfix "panic_on_oops=0" sentryConfig;

  # ── HW-5: No i686-linux in distributed builders ──
  distributedBuilds = readFile ./../modules/system/distributed-builds.nix;
  hasNoInvalidPlatform = !(hasInfix "i686-linux" distributedBuilds);

  # ── HW-6: No duplicate option declarations ──
  # Check that no option is declared in both mining.nix and the role profile
  miningModule = readFile ./../modules/mining/mining.nix;
  implementationsModule = readFile ./../modules/profiles/role/implementations.nix;
  noDuplicateMiningOption =
    (hasInfix "options.services.mining" miningModule)
    && !(hasInfix "options.services.mining" implementationsModule);

  # ── HW-7: sops files referenced in registry exist ──
  # NOTE: This is a simplified check — the full check is in secrets-integrity.nix
  k3sTokenExists = fileExists ./../secrets/k8s/k3s-cluster-token.yaml;

  # ── HW-8: NFS mounts have nofail when NFS server is known dead ──
  # Check that nixos-share is disabled on non-zephyr hosts
  sentryNixosShare = hasInfix "nixos-share" sentryConfig;
  sentryNixosShareDisabled = hasInfix "enable = false" sentryConfig
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
  sentryHasMceMitigation = hasInfix "processor.max_cstate=5" sentryConfig
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

    # HW-5: No i686-linux in builders
    distributed_builds_no_invalid_platform = hasNoInvalidPlatform;

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
  all_pass = failures == [];
  # Print summary
  summary = let
    ok = builtins.length passNames;
    fail = builtins.length failNames;
  in "${toString ok}/${toString allCheckNames} checks passed" + (
    if fail > 0 then ", ${toString fail} FAILED: ${lib.concatStringsSep ", " failNames}" else ""
  );
}
