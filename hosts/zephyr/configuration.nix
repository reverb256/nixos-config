# Zephyr Host Configuration
# RTX 3090, Quest Pro, 4K HDR TV
{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: {
  imports = [
    ../../modules/system/secretspec-creds.nix
    ../../modules/system/secretspec-validator.nix
    # ========================================================================
    # BASE MODULES
    # ========================================================================

    # Monitoring configuration
    ./monitoring.nix
    # Hardware configuration (generated)
    ./hardware-configuration.nix
    # Per-host firewall rules (source-restricted ports, extra rules)
    ./firewall.nix
    # Desktop configuration (SDR brightness, Samsung TV, SDDM)
    ./desktop.nix
    # Kubernetes control plane (zephyr does NOT enable k3s — see services block below)
    # Keepalived VIP for Kubernetes HA
    ../../modules/services/keepalived-vip.nix

    # Storage assertions (partlabel/uuid/boot checks)
    ../../modules/system/storage-assertions.nix
    ../../modules/services/hermes/default.nix
    # FIX: Systemd user unit reload timeout (nixos-rebuild switch hang)
    ../../modules/system/systemd-user-timeout.nix

    # All other modules auto-imported via ../../modules/default.nix
    # This includes: system, desktop, shell, gaming, development, services,
    # plus zephyr-specific modules (nvidia-common, gstreamer, spotify, cluster networking)
    ../../modules/default.nix

    # NVIDIA GPU Wayland support (host-dependent)
    ../../modules/hardware/nvidia-common.nix
    ../../modules/hardware/nvidia-wayland.nix
    # Incus-only Game Pass Windows VM backend — RTX 3060 Ti only.
    # The former libvirt backend is retired; the RTX 3090 remains host-owned.
    ../../modules/hardware/incus-gamepass.nix
    # Noctalia desktop compositor (niri shell, iced/winit/Smithay deps)
    # noctalia: now built-in to nixpkgs-unstable (programs.noctalia)
    # RGB control for peripherals and components
    ../../modules/hardware/rgb-control.nix
    # PeakMiner GPU mining stack (Zephyr NVIDIA GPUs, Kryptex plain TCP)
    ./peakminer.nix
    # Bonsai 27B: ternary (RTX 3090, port 1237, CUDA), 1-bit (3060 Ti, port 1236)
    ../../modules/services/bonsai.nix
    # GPU workload registry: single source for the fuzzel menu (workloads.json)
    ../../modules/services/gpu-workload-registry.nix
    # NVIDIA Switchyard LLM routing proxy (routes.toml + systemd unit)
    ../../modules/services/switchyard.nix

    # Gitlawb flake-based client + remote helper
    inputs.gitlawb.nixosModule
  ];

  # ============================================================================
  # GITLAWB — self-hosted decentralized git client + remote helper
  # ============================================================================
  # 2026-07-29: Temporarily disabled — gitlawb-0.7.0 tarball hash mismatch
  # on this build. Will re-enable when upstream is stable.
  programs.gitlawb.enable = false;

  # ============================================================================
  # HOST IDENTIFICATION
  # ============================================================================
  # Centralized cluster networking (search domains, DNS, firewall basics)
  # Note: interfaceName provided by node-profiles.zephyr-workstation
  clusterNetworking = {
    enable = true;
    hostName = "zephyr";
    ipAddress = "10.1.1.110";
    wireless = {
      enable = true;
      ipAddress = "10.1.1.115"; # Static IP for WiFi backup
    };
    usbEthernet.enable = true; # Support USB ethernet adapters
    unbound.listenAddress = "10.1.1.110";
  };

  # ============================================================================
  # SECRETSPEC FORK SUPPORT — See modules/system/secretspec-cluster-mode.nix.
  # Zephyr carries ~/Projects/secretspec-core (cachix-fork with sops
  # subprocess provider) and ~/Projects/secretspec/provider-rust (NDJSON
  # dispatcher fork). `cluster.localSealSupport` was REMOVED 2026-07-25
  # (vestigial after Phase 1a). 2026-08-13 the deploy scripts briefly added
  # a GLOBAL `nix.settings.pure-eval = true` (claiming "home-manager eval
  # cleanly under pure-eval") — that claim was FALSE: home-manager's news
  # step does a NIX_PATH `<home-manager/...>` lookup which pure mode forbids
  # (`cannot look up '<home-manager/home-manager/build-news.nix>' in pure
  # evaluation mode`), breaking every `home-manager switch`. Removed
  # 2026-08-14 in modules/system/nix-config.nix. Pure-eval is opt-in per
  # command now; the secretspec fork path already forces
  # `--option pure-eval false` in the justfile where it needs impure eval.
  # See .plans/2026-07-25-cluster-localSealSupport-scope.md.
  # ============================================================================

  # Validator is auto-coupled to services.sops-secrets-registry.enable (set below in
  # the services block) — no explicit services.secretspec-validator block needed.
  # → enable defaults to true (coupled) + production defaults to true.
  # Eval-mode note (2026-08-14): the global pure-eval experiment (2026-08-13)
  # was REVERTED in modules/system/nix-config.nix — it broke home-manager
  # switch (news NIX_PATH lookup fails in pure mode). No host requires
  # cluster.localSealSupport; the secretspec fork build path forces
  # `--option pure-eval false` in the justfile where needed.

  # FIX: Disable interface renaming - use actual interface names
  systemd.network.links = lib.mkForce {};

  # ============================================================================
  # MEMORY OPTIMIZATION - zram compressed swap + kernel tuning
  # ============================================================================
  # VM sysctls (vfs_cache_pressure, swappiness, overcommit) handled by
  # vm-tuning.nix with mkForce — only host-specific overrides here.
  # Previous vfs_cache_pressure=1000 caused excessive page cache eviction,
  # forcing more SSD swap. vm-tuning.nix sets 150 (mkForce).

  # ZRAM compressed swap — reduces SSD wear, faster than disk swap
  # 25% of 31GB ≈ 8GB compressed swap (zstd compression ~2-3x ratio)
  # 40% of 31GB ~= 12GB compressed swap. Bumped from 25% after the
  # 2026-07-23 swap-exhaustion event (8GB zram pool filled, earlyoom fired
  # at swap 0 MiB). zswap is DISABLED below because it intercepts pages
  # before they reach zram and fights it; kernel-MM guidance: never run
  # zswap in front of zram.
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50; # 40 -> 50 (2026-08-03): Cyberpunk + transient nix jobs filled 12.5G; 50% ~= 15.6G headroom
    priority = 999; # Prefer zram over disk swap
  };

  # Disk-backed swapfile as overflow behind zram (2026-08-14).
  # zram alone (15.6G, priority 999) had NO fallback: at 100% it OOM-killed
  # herdr/llama-server/freebuff via earlyoom. 16G swapfile on the btrfs root
  # subvolume (175G free) with CoW disabled — created once by hand with
  # chattr +C (btrfs swapfiles need nocow), then declared here so NixOS
  # keeps it enabled across rebuilds.
  swapDevices = [
    {
      device = "/swapfile";
      size = 16384;
    }
  ];

  # Disable zswap (conflicts with zram). Emits zswap.enabled=0 on cmdline.
  kernel-hardening.zswap.enable = false;

  # Hermes Agent CLI: nixos-config no longer builds/installs hermes (issue #334);
  # the `hermes` binary comes from the user nix profile. Keep the module enabled
  # only for SOUL.md / dir setup + fish completions if desired. Disabled here to
  # avoid forcing it; enable explicitly if you want the activation scripts.
  # services.hermes-cli.enable = true;

  boot.kernel.sysctl = {
    # Network buffer tuning (frees unused socket buffers)
    "net.core.rmem_default" = 262144; # 256KB (default: 212992)
    "net.core.wmem_default" = 262144; # 256KB
    "net.core.rmem_max" = 16777216; # 16MB max
    "net.core.wmem_max" = 16777216;

    # Reverse path filtering (loose mode) — cluster-wide BGP/Calico hardening.
    # zephyr is not a k3s node, but the rest of the cluster runs Calico VXLAN
    # which requires rp_filter=1 on every participating host's interfaces.
    "net.ipv4.conf.all.rp_filter" = 1;

    # ------------------------------------------------------------------
    # IN-MEMORY SWAP TUNING (zram-only). swappiness > 100 is appropriate
    # for in-memory swap (kernel docs); Pop!_OS/Arch zram standard = 180 +
    # page-cluster=0. Overrides vm-tuning.nix mkForce 40 (assumes zswap).
    "vm.swappiness" = 180;
    "vm.page-cluster" = 0;
    "vm.vfs_cache_pressure" = 50;
  };

  # ------------------------------------------------------------------
  # EARLYOOM - primary OOM defense for this desktop host.
  # --avoid protects the graphical session (subtracts 300 from oom_score,
  # last-to-die); --prefer targets reloadable browser content / nix builds.
  # -s 50 adds a swap-pressure trigger (not just a RAM floor).
  services.earlyoom = {
    enable = true;
    freeMemThreshold = 12;
    freeSwapThreshold = 50;
    freeMemKillThreshold = 6;
    freeSwapKillThreshold = 25;
    enableNotifications = true;
    extraArgs = [
      "--prefer"
      "(Web Content|Isolated Web|nix)"
      "--avoid"
      "(niri|noctalia|zen|spotify|vesktop|opencode|hermes|herdr|herdr-simple-mc|Xwayland|pipewire|steam|GameThread|REDprelauncher)"
      # Bonsai 27B: ternary (RTX 3090, port 1237, CUDA), 1-bit (3060 Ti, port 1236)
    ];
  };

  # ------------------------------------------------------------------
  # SYSTEMD-OOMD - fleet-wide defaults are now provided by
  # modules/system/oomd-fleet.nix (loaded via common-modules-list.nix).
  # Fleet default: MemoryUsedPercent=90, SwapUsedPercent=85 (corrected
  # NixOS 26.11 percent-based keys; the SwapUsedLimit=90 integer form was
  # silently ignored). Per-host slice opt-in remains below.
  # systemd.oomd = { enable = true; settings.OOM.SwapUsedLimit = 90; ... };
  #   ^^^ REMOVED — superseded by oomd-fleet.nix (#328 + #318 audit fixes).
  systemd.slices."-".sliceConfig = {
    ManagedOOMSwap = "kill";
  };

  networking = {
    cluster-hosts = {
      enable = true;
      populateLocal = true;
    };
    # Zephyr-specific firewall rules (in addition to cluster defaults)
    firewall = {
      allowedTCPPorts = [
        9757 # WiVRn main port
        18789 # Steam Remote Play
        18790 # Steam Remote Play (secondary)
        19898 # Moonlight/GameStream AND Spacebot Web UI
        8080 # AI Inference Gateway
        8083 # Llamafile standalone LLM service
        53317 # LocalSend (file sharing)
        8888 # CFSSL CA API server (for worker node certificate generation)
        3900 # Garage S3 API
        3901 # Garage RPC
        50000 # Nix binary cache server
        9100 # Prometheus node-exporter
        # Bonsai 27B: ternary (RTX 3090, port 1237, CUDA), 1-bit (3060 Ti, port 1236)
      ];
      allowedUDPPorts = [
        9757 # WiVRn
        9758 # WiVRn
        9759 # WiVRn
        27031 # Steam UDP
        27036 # Steam UDP
        9947 # WiVRn
        53317 # LocalSend (multicast discovery)
        8472 # VXLAN (Calico)
        4789 # VXLAN (Calico)
        # Bonsai 27B: ternary (RTX 3090, port 1237, CUDA), 1-bit (3060 Ti, port 1236)
      ];
      interfaces = {
        # mDNS restricted to LAN interface only (not 0.0.0.0)
        "tailscale0".allowedTCPPorts = [
          18789
          18790
          # Bonsai 27B: ternary (RTX 3090, port 1237, CUDA), 1-bit (3060 Ti, port 1236)
        ];

        "enp38s0".allowedTCPPorts = [
          111
          2049
          20048
          # Bonsai 27B: ternary (RTX 3090, port 1237, CUDA), 1-bit (3060 Ti, port 1236)
        ];
      };
    };
  };

  # ============================================================================
  # NODE PROFILE - Platform-level defaults
  # ============================================================================
  # This profile bundles role profiles, Kubernetes config, hardware profiles,
  # and networking configuration. Eliminates ~100 lines of duplication.
  profiles.node.zephyr-workstation.enable = true;

  # Tailscale authkey: sops-managed preauth key (declarative join).
  # Ignored once the node is already joined; used on first boot / rejoin.
  services.tailscale-cluster.authKeyFile = "/run/secrets/tailscale/authkey";

  # MONITORING DISABLED - Protect 31GB RAM for gaming/VR/AI workloads
  # Monitoring stack moved to Nexus (46GB RAM) to prevent OOM on Zephyr
  # Prometheus/Grafana running on Kubernetes (ai-inference namespace)
  # AlertManager running on Nexus via monitoring profile
  profiles.monitoring.enable = lib.mkForce false;

  # ============================================================================
  # SECURITY AUDIT REMEDIATION
  # ============================================================================
  # Enables firewall, Tailscale SSH, and service hardening
  security.clusterAudit = {
    enable = true;
    enableFirewall = true;
    enableTailscaleSSH = true;
    bindServicesToLocalhost = true;
  };

  # TPM 2.0: hardware-bind the cluster age key (secretspec/sops identity).
  # The age key is sealed to PCR 0+7 (firmware + Secure Boot) at boot,
  # then unsealed into /run/secrets/cluster-age-key before secretspec-creds
  # runs. Requires: /dev/tpmrm0 (present), operator runs
  # 'systemctl start tpm2-seal-age-keygen' once to provision the sealed blob.
  # Zephyr is first; nexus/forge/sentry follow after keygen succeeds here.
  security.tpm2AgeBinding = {
    enable = true;
    primaryKeyPath = "/home/j_kro/.config/sops/age/keys-combined.txt";
  };

  # Kubernetes security tools for runtime monitoring
  security.kubernetes.enable = true;

  # Trust Caddy Ingress local CA certificate
  security.caddyCa.enable = true;

  # The Zephyr desktop workload menu may control only these four declared
  # system services. Keep this scoped to the exact unit names rather than
  # granting general systemd management to the graphical session.
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      var zephyrWorkloads = [
        "peakminer-zephyr-3090.service",
        "peakminer-zephyr-3060ti.service",
        "bonsai-ternary-zephyr.service",
        "bonsai-1bit-zephyr.service"
      ];
      if (action.id == "org.freedesktop.systemd1.manage-units" &&
          subject.user == "j_kro" &&
          subject.active && subject.local &&
          (action.lookup("verb") == "start" ||
           action.lookup("verb") == "stop") &&
          zephyrWorkloads.indexOf(action.lookup("unit")) >= 0) {
        return polkit.Result.YES;
      }
    });
  '';

  # ============================================================================
  # GPU COMPUTE - CUDA + Vulkan support for AI inference
  # ============================================================================
  hardware.gpu-compute = {
    enable = true;
    cuda.enable = true; # CUDA for NVIDIA RTX 3090 + 3060 Ti
    vulkan.enable = true; # Vulkan as fallback/universal backend
  };

  # DDC/CI support for external monitor brightness control
  # Note: hardware.video.ddcutil module doesn't exist in NixOS
  # Using ddcutil package + udev rules instead (added to systemPackages)
  services.udev.extraRules = ''
    # Give i2c group access to DDC/CI monitors
    # Allows non-root users to control monitor brightness via ddcutil
    KERNEL=="i2c-[0-9]*", GROUP="i2c", MODE="0660"

    # Allow users to control laptop display brightness
    SUBSYSTEM=="backlight", KERNEL=="intel_backlight", MODE="0666", RUN+="${pkgs.coreutils}/bin/chown j_kro:j_kro %k/brightness"
  '';

  # ============================================================================
  # SYSTEMD - Service overrides
  # ============================================================================
  # GameMode daemon - Start at boot for gaming-detection service
  # The gaming module (programs.gamemode) configures GameMode but the daemon
  # is D-Bus activated and doesn't start until a game requests it. This
  # override ensures gamemoded runs at boot so the gaming-detection service
  # can query gaming state via `gamemoded -s` for cluster-wide coordination.
  #
  # Note: GameMode is a D-Bus session service, so we use systemd.user.services
  # to run it in the user session context, not as a system service.
  #
  # FIX: Don't override ExecStart or Type - let gaming module handle those.
  # Only add wantedBy to start at boot. This prevents duplicate ExecStart lines.
  systemd.user.services.gamemoded = {
    wantedBy = ["default.target"];
  };

  # ============================================================================
  # SERVICES - All service configurations consolidated here
  # ============================================================================
  services = {
    # KUBERNETES - zephyr does NOT run k3s.
    # Control plane (k3s servers): nexus, forge, sentry (VIP 10.1.1.100).
    # No manifest auto-apply on zephyr -- only control-plane nodes do this.
    k8s-manifest-autoapply.enable = false;
    # zephyr stays OFF k3s: the option is never imported (see
    # tests/k3s-topology-evidence.nix). A dangling `k3s-cluster.enable =
    # lib.mkForce false` here would reference a nonexistent option (k3s-cluster.nix
    # is not in zephyr's imports chain) and break eval — absence of the import IS
    # the guard.

    # Keepalived VIP lives on the k3s servers (nexus/forge/sentry), not zephyr.
    # Removed to stop the enp38s0 dual-IP collision that broke k3s startup.

    # Crash watchdog - detect and log system crashes
    # TEMPORARILY DISABLED: Module being fixed (2026-03-23)
    # crash-watchdog.enable = true;

    # Backup to Garage S3 - automated daily backups
    # Garage S3 server runs on nexus (10.1.1.120), not zephyr.
    backup-to-garage = {
      enable = true;
      endpoint = "http://10.1.1.120:3900";
      region = "garage";
      bucket = "backups";
      accessKeyFile = "/run/secrets/garage-s3-access-key-id";
      secretKeyFile = "/run/secrets/garage-s3-secret-key";
      retentionDays = 30;
      startAt = "02:00"; # 2 AM daily
      # zephyr has /data but NOT /data/shared (that is nexus storage). The
      # module default includes /data/shared which broke the mount namespace
      # (NAMESPACE 226, 2026-08-14) — declare the real source explicitly.
      # IMPORTANT: /data on zephyr holds games + models (hundreds of GB,
      # regenerable). It must NEVER be a backup source — 2026-08-14 the
      # job tar+gzip'd all of /data to /tmp on the same 99%-full disk for
      # ~3h, filling the disk and thrashing btrfs. Config-only backups.
      backupPaths = [
        "/etc/nixos"
        "/home/j_kro/Projects"
        "/home/j_kro/.hermes"
      ];
    };

    # RCLONE — declarative cloud storage sync (Garage S3 on nexus).
    # The config file (/etc/rclone/rclone.conf) is generated from cfg.remotes
    # by the rclone module; credential fields left empty here are supplied at
    # runtime via env vars wired through sops-nix paths in each syncJob.
    rclone-sync = {
      enable = true;

      remotes = {
        # Garage S3 cluster (runs on nexus, endpoint 10.1.1.120:3900).
        # Credentials are left empty in the config so rclone reads them from
        # env vars — the sops-nix-decrypted files under /run/secrets/.
        garage = {
          type = "s3";
          provider = "Other";
          endpoint = "http://10.1.1.120:3900";
          accessKeyId = "";
          secretAccessKey = "";
          region = "garage";
        };
      };

      # Verification job: list the garage bucket contents every day at 03:00.
      # Reads the garage S3 secret from /run/secrets (populated by sops-nix).
      syncJobs = [
        {
          name = "garage-list";
          source = "garage:";
          destination = "garage:";
          mode = "ls";
          startAt = "03:00";
          enableTimer = true;
          sopsSecretEnvs = [
            {
              var = "AWS_ACCESS_KEY_ID";
              secretPath = "/run/secrets/storage/garage-s3-access-key-id";
            }
            {
              var = "AWS_SECRET_ACCESS_KEY";
              secretPath = "/run/secrets/storage/garage-s3-secret-key";
            }
          ];
        }
      ];
    };
  };

  # Freebuff Desktop — hicolor icon only (launcher + binary are owned by
  # home-manager-config appimage-updater: ~/.local/opt/freebuff-desktop).
  services.freebuff-desktop.enable = true;

  # STATUS.md auto-update (hourly from kubectl)
  services.status-auto-update.enable = true;

  # FIX: Systemd user unit reload timeout (prevents nixos-rebuild switch hang)
  services.systemd-user-timeout.enable = true;

  # Internal CA for cluster services (trusted certificates)
  services.cluster-ca.enable = true;

  # ============================================================================
  # DESKTOP - Wayland compositors (select via SDDM session picker)
  desktop.uwsm-sessions.enable = true;
  programs.niri.enable = true;

  # Autologin into Niri (niri-uwsm) on boot.
  services.displayManager.autoLogin.enable = true;
  services.displayManager.autoLogin.user = "j_kro";
  # HDR gamescope is a Zephyr-only display feature; keep it explicit so the
  # effective configuration includes the SDL/HDR arguments, not just the WSI
  # package support.
  services.gaming.hdr.enable = true;

  # Pin DXVK/NVAPI + the GameMode overclock hook to the display-attached
  # RTX 3090 (multi-GPU host: 3090 + 3060 Ti). Left null on single-GPU hosts.
  services.gaming.gpuFilter = "NVIDIA GeForce RTX 3090";

  # NOTE (2026-07-21, issue #300): upstream NixOS removed the bare
  # `plasma` session name from the SDDM valid-session registry. Valid
  # values are now `niri-uwsm` and `niri`. Uswm-managed Niri is the
  # currently active desktop on Zephyr (see desktop.nix) so keep
  # `niri-uwsm` as the default.
  services.displayManager.defaultSession = "niri-uwsm";

  # HARDWARE PROFILES
  # ============================================================================
  # Base profiles provided by node-profiles.zephyr-workstation:
  # - amd.zen, nvidia.enable, nvidia.multiGpu, monitoring.enable
  #
  # Zephyr-specific hardware overrides/additions:
  hardware = {
    profiles = {
      corsair.enable = true; # Corsair AIO + RGB (not in node profile)
    };

    # BTRFS compression and deduplication
    btrfs-compression.enable = true;

    # Hardware monitoring extras (not covered by profile)
    monitoring = {
      autoDetect = false; # Skip auto-detect, we know the hardware
      fanControl = true; # Custom fan curve control
      # Board-specific curve script; required when fanControl is on
      # (monitoring.nix asserts this and coerces it into ExecStart).
      fanScript = "/etc/nixos/scripts/simple-fancontrol.py";
    };

    # Corsair extras (not covered by profile)
    corsair = {
      aio.enable = true; # Corsair H115i AIO control
      rgb.enable = true; # OpenRGB for RGB control
      autoStartRgb = false; # Don't auto-start (conflicts with liquidctl)
    };

    # RGB control for peripherals and components
    rgb-control = {
      enable = true;
      openrgb.enable = true; # Motherboard, GPU, Corsair devices
      openrazer.enable = true; # Razer Naga Pro mouse
    };

    # Bluetooth support via BlueZ
    bluetooth.enable = true;
  };

  # ============================================================================
  # FILESYSTEM COMPRESSION - Enable zstd on all BTRFS filesystems
  # ============================================================================
  # Root and home filesystems lack compression in hardware-configuration.nix
  # Use mkOptionDefault to add compression without breaking other options
  fileSystems = {
    "/".options = lib.mkOptionDefault [
      "compress=zstd:3"
      "ssd"
      "discard=async"
      # Bonsai 27B: ternary (RTX 3090, port 1237, CUDA), 1-bit (3060 Ti, port 1236)
    ];
    "/home".options = lib.mkOptionDefault [
      "compress=zstd:3"
      "ssd"
      "discard=async"
      # Bonsai 27B: ternary (RTX 3090, port 1237, CUDA), 1-bit (3060 Ti, port 1236)
    ];
  };

  # ============================================================================
  # WIRELESS HARDWARE
  # ============================================================================

  # Locale (timezone inherits cluster default: UTC)
  i18n.defaultLocale = "en_CA.UTF-8";

  # ============================================================================
  # BOOT CONFIGURATION
  # ============================================================================
  # Base bootloader settings provided by common-host-defaults.nix:
  # - systemd-boot.enable, efi.canTouchEfiVariables, kernelPackages (linux_zen)
  # NOTE: Using CachyOS kernel for better sched_ext/scx_lavd support.
  # Zen kernel lacks CONFIG_SCHED_DEADLINE which breaks scx_lavd core compaction.
  # CachyOS 6.19.11: BORE scheduler, x86-64-v3 opts, sched_ext integration.
  # Kernel binary is CACHED (no compilation). Only nvidia module needs building.
  # Uses the flake input's linuxPackages directly to hit the binary cache.
  boot.kernelPackages = inputs.nix-cachyos-kernel.legacyPackages.x86_64-linux.linuxPackages-cachyos-latest-x86_64-v3;
  #
  # Zephyr-specific additions:
  boot = {
    # Multi-GPU kernel modules for RTX 3090 + 3060 Ti
    # (Note: hardware.profiles.nvidia.enable adds nvidia modules automatically)
    kernelModules = [
      "nvidia_uvm" # Unified Memory (CRITICAL for multi-GPU!)
      # Bonsai 27B: ternary (RTX 3090, port 1237, CUDA), 1-bit (3060 Ti, port 1236)
    ];

    extraModprobeConfig = ''
      options nvidia NVreg_EnableBacklightHandler=1
      # Disable HMM in nvidia_uvm: HMM + multi-GPU (3090 + 3060 Ti) causes UVM
      # page-fault stalls under CUDA. Was hand-placed in
      # /etc/modprobe.d/nvidia-uvm.conf (drift, 2026-07-30); declared here now.
      # NOTE: hosts/zephyr/hardware.nix declares this too but is NOT imported.
      options nvidia_uvm uvm_disable_hmm=1
    '';

    # Blacklist unused kernel modules to reduce memory footprint
    # Each loaded module consumes memory - disable what we don't use
    # NOTE: Bluetooth (btusb, bluetooth) and WiFi (iwlmvm, iwlwifi) ARE in use
    blacklistedKernelModules = [
      # Audio dummy modules (rarely used on desktop)
      "snd_seq_dummy"
      "snd_hrtimer"

      # Filesystems not used (Zephyr uses ext4/btrfs only)
      "ufs"
      "hfs"
      "hfsplus"
      "reiserfs"

      # Old networking protocols (not used)
      "appletalk"
      "ipx"
      "decnet"
      # Bonsai 27B: ternary (RTX 3090, port 1237, CUDA), 1-bit (3060 Ti, port 1236)
    ];

    # Zephyr-specific kernel params for gaming
    # (Note: hardware.profiles.amd.zen adds split_lock_detect, threadirqs, preempt)
    kernelParams = [
      "amd_iommu=on" # Enable AMD IOMMU for device passthrough
      "iommu=pt" # IOMMU passthrough mode (better performance)
      "processor.max_cstate=1"
      "intel_idle.max_cstate=1"
      "hugepages=3"
      "btrfs.commit_interval=300" # From btrfs-tuning module
      "nvidia.NVreg_RegistryDwords=EnableBrightnessControl=1" # Enable laptop brightness control
      # Bonsai 27B: ternary (RTX 3090, port 1237, CUDA), 1-bit (3060 Ti, port 1236)
    ];
  };

  # 32-bit graphics for 32-bit Steam games (Proton/older indie titles).
  # Overrides nvidia-common.nix's mkForce false (a multi-GPU Wayland-stability
  # measure from the pre-vfio era — the 3060 Ti is vfio-bound to the gaming VM
  # now, so that concern is moot on zephyr). Priority 40 beats mkForce (50).
  hardware.graphics.enable32Bit = lib.mkOverride 40 true;

  # REMOVED 2026-08-08: the drm.edid_firmware=HDMI-A-2 override + hardware.firmware
  # EDID patch were (a) keyed on a connector name (HDMI-A-2) that does not exist on
  # this GPU (the TV is on HDMI-A-1) and (b) redundant — the TV's native EDID
  # already advertises PQ/ST-2084 (EOTF 0x01|0x04|0x08), so the niri HDR fork can
  # signal HDR without any patched firmware. Removing the last port-label
  # dependency in the HDR stack; niri output config is keyed on EDID identity
  # ("Samsung Electric Company SAMSUNG 0x01000E00") instead.

  # ============================================================================
  # ROLE PROFILES
  # ============================================================================
  # Base role profiles provided by node-profiles.zephyr-workstation:
  # - workstation, gaming, vr, mining, aiInference
  # Kubernetes and networking also handled by node profile
  #
  # No additional role profiles needed - all handled by node profile

  # Note: profiles.role.gaming enables services.gaming automatically
  # Zephyr never builds locally (31 GiB RAM — local `nix build` is the
  # documented OOM root cause). The shared distributed-builds module owns
  # this policy: max-jobs = 0, distributed builds enabled, builders = machines.
  # Do NOT override nix.settings here; the shared module's mkForce applies.

  # ============================================================================
  # SERVICES - Consolidated service configuration
  # ============================================================================
  # Base Kubernetes configuration provided by node-profiles.zephyr-workstation
  # (master + node roles, masterAddress, etc.)
  #
  # Zephyr-specific service additions:
  services = {
    # ============================================================================
    # Modular Workload Monitoring
    # ============================================================================
    # Replaced old compute-workload-monitor monolith with:
    # - gaming-detection: Pure sensor (GameMode + GPU fallback)
    # - gpu-profile-manager: GPU power profile actuator (nvidia-smi)
    # - mining-coordinator: PSI build detection + K8s Volcano preemption
    gaming-detection = {
      enable = true;
      checkInterval = 10;
    };

    gpu-profile-manager = {
      enable = true;
      checkInterval = 10;
    };

    mining-coordinator = {
      enable = true;
      checkInterval = 10;
      # Use conservative thresholds for memory-constrained system
      psiCpuBuildThreshold = "5.0";
      psiCpuIdleThreshold = "2.0";
    };

    # AI CODING AGENT - OpenCode with Kubernetes gateway
    opencode.enable = true;

    # NIX BINARY CACHE - Serve pre-built packages to cluster
    # Eliminates redundant builds across nodes, speeds up deployments
    # ENABLED: Required for distributed builds (2026-03-24)
    # Remote nodes need this cache available during builds
    binary-cache = {
      enable = true;
      port = 50000;
      bindAddress = "10.1.1.110";
    };

    # 2026-08-06: disable nixos-sync force-reset while nexus (gitlawb origin)
    # is down. The force-reset to origin/main fails on every switch and
    # corrupts dependent services (libvirtd-config). Re-enable when nexus
    # returns. Local edits are the source of truth in the meantime.
    nixos-sync.enable = false;

    # NOTE (2026-07-21, issue #300): the previous `services.mining` block,
    # `gaming.hdr.enable` outermost statement were removed as part of the
    # peakminer-only consolidation. Pre-existing bracket typo from a botched
    # xmrig-strip cleanup was fixed in the same edit.

    # Zephyr still serves the local `/etc/nixos` checkout; remote hosts track
    # `origin/main` via the git-sync timer in modules/services/nixos-sync.nix,

    # requires a parent `services = { ... }`); expose a placeholder entry

    # Caddy reverse proxy - Replace nginx for all services
    caddy = {
      enable = true;
      # Custom Caddyfile for complex configurations (Nextcloud)
      # NOTE: Global options manually included because configFile overrides globalConfig
      configFile = pkgs.writeText "Caddyfile" ''
        # Global options
        {
          admin 127.0.0.1:2019
          default_sni cluster.local
        }

        # AI Inference Gateway (via Tailscale)
        ai.zephyr.tigris-ule.ts.net:9002 {
          header {
            Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
            X-Content-Type-Options "nosniff"
            X-Frame-Options "SAMEORIGIN"
            Referrer-Policy "strict-origin-when-cross-origin"
            -Server
          }
          encode zstd gzip
          reverse_proxy 127.0.0.1:8080
        }

        # Host Dashboard (LAN access - no TLS)
        http://zephyr.lan {
          header {
            X-Content-Type-Options "nosniff"
            X-Frame-Options "SAMEORIGIN"
            -Server
          }
          encode zstd gzip
          reverse_proxy 127.0.0.1:8090
        }
        http://dashboard.zephyr.lan {
          header {
            X-Content-Type-Options "nosniff"
            X-Frame-Options "SAMEORIGIN"
            -Server
          }
          encode zstd gzip
          reverse_proxy 127.0.0.1:8090
        }

        # Kubernetes Ingress (proxy to Caddy ingress controller on Nexus)
        # Using IP directly — Caddy's Go resolver ignores /etc/hosts
        http://search.lan, http://search.cluster.local {
          encode zstd gzip
          reverse_proxy 10.1.1.120:30080
        }
        http://ai.lan, http://ai.cluster.local {
          encode zstd gzip
          reverse_proxy 10.1.1.120:30080
        }
        http://openwebui.lan, http://openwebui.cluster.local {
          encode zstd gzip
          reverse_proxy 10.1.1.120:30080
        }

        # CivicIntel — Canadian Government Intelligence Dashboard
        http://civicintel.lan, http://10.1.1.100 {
          encode zstd gzip
          handle_path /CivicIntel/* {
            reverse_proxy 10.1.1.120:30085
          }
          handle_path /CivicIntel {
            redir /CivicIntel/ permanent
          }
        }
      '';
    };

    # NOTE: caddy-common NOT enabled because configFile overrides globalConfig
    # Global options manually included in configFile above
    # caddy-common = {
    #   enable = true;
    #   adminListenAddress = "127.0.0.1";  # Localhost only for systemd
    # };

    # Redis - For gateway rate limiting and caching
    redis.servers."".enable = true;
    # Note: redis-ai-gateway.service already provides Redis on port 6380

    # MCP Servers for AI tools
    mcp-servers = {
      enable = true;
      servers.playwright.enable = true;
      servers.context7.apiKeyFile = "/run/secrets/context7-api-key";
    };

    # AI Coding Tools - Harmonized MCP configs (Droid, Claude, Crush, OpenCode)
    ai-coding-tools = {
      enable = true;
      context7ApiKeyFile = "/run/secrets/context7-api-key";
      tools.pi.packages = [
        "npm:pi-annotated-reply@0.4.1"
        "npm:pi-btw@0.2.1"
        "npm:pi-context@1.1.2"
        "npm:pi-lens@3.8.5"
        "npm:pi-powerline-footer@0.4.9"
        "npm:pi-rewind@0.5.0"
        "npm:pi-show-diffs@0.2.7"
        "npm:pi-subagents@0.12.4"
        "npm:pi-web-access@0.10.6"
        "npm:pi-worktree@1.3.3"
        # Bonsai 27B: ternary (RTX 3090, port 1237, CUDA), 1-bit (3060 Ti, port 1236)
      ];
    };

    # WEB TESTING - Playwright/Puppeteer system dependencies
    web-testing.enable = true;

    # CI/CD - Self-hosted GitHub Actions runner
    secretspec-creds = {
      enable = true;
      ageKeyFile = "/home/j_kro/.config/sops/age/keys-combined.txt";
      secrets = import ./secretspec-creds-wiring.nix;
    };

    # hosts/zephyr/services.nix is NOT imported — enable here
    secretspec-validator = {
      enable = true;
      ageKeyFile = "/home/j_kro/.config/sops/age/keys-combined.txt";
      production = true;
      # Zephyr provisions the host-required subset; the full cluster manifest
      # also contains credentials owned by Nexus/Kubernetes workloads.
      # Keep validation visible without blocking every NixOS activation.
      failOnMissing = false;
    };
    ci-runner = {
      enable = false;
      repo = "username/nixos-config";
      autoStart = false;
    };

    # MULTIMEDIA - GStreamer support for Qt/KDE applications
    multimedia.gstreamer.enable = true;

    # Spotify with SpotX patch (ad-free, premium features)
    spotify-spotx = {
      enable = true;
      forceX11 = true;
      clearCacheOnPatch = true;
    };

    # FLATPAK - Flatpak support with Discover and Flathub
    flatpak-kde = {
      enable = true;
      autoUpdate = true;
    };

    # Krig owns local GPU mining; the inference coordinator pauses the primary
    # Krig unit when llama-server or ComfyUI needs the 3090.
  };

  # ============================================================================
  programs = {
    scopebuddy = {
      enable = true;
      # 2026-08-15: build scopebuddy against the SYSTEM gamescope (pkgs.gamescope).
      # The scopebuddy flake builds its own package with its own nixpkgs (no
      # overlay), so without this override the wrapper PATH would bake a
      # different gamescope than the system. 2026-08-15 later: gamescope pin
      # reverted to 3.16.25 (the 28h-working version) — 3.16.22 broke nested
      # Xwayland on niri-hdr. This override now aligns scopebuddy with 3.16.25.
      # 2026-08-16: ALSO add xwayland to the wrapper PATH. gamescope spawns its
      # internal Xwayland BY NAME via wlroots; upstream's package.nix prepends
      # [gamescope perl jq wlr-randr] but omits xwayland, so nested gamescope
      # ran headless ('could not connect to wayland server') and Proton games
      # crashed at swapchain create with E_INVALIDARG (-2147024809). Upstream
      # PR OpenGamingCollective/ScopeBuddy#50; this re-wrap makes zephyr work
      # without waiting for the merge.
      package =
        let
          scb =
            (inputs.scopebuddy.packages.${pkgs.stdenv.hostPlatform.system}.default)
            .override {gamescope = pkgs.gamescope;};
        in
        pkgs.symlinkJoin {
          name = "scopebuddy-with-xwayland";
          paths = [ scb ];
          nativeBuildInputs = [ pkgs.makeWrapper ];
          postBuild = ''
            wrapProgram $out/bin/scopebuddy \
              --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.xwayland ]}
            wrapProgram $out/bin/scb \
              --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.xwayland ]}
          '';
        };
      # 2026-08-14: ALL autoDetect off. scb.conf (home-manager
      # zephyr-gaming-hdr.nix) hard-codes 4K60/HDR — it is the single source of
      # truth. The autoDetect exports (SCB_AUTO_RES/HDR/HZ/SCALE=1) contradict
      # the hard-coded scb.conf and leak into every process env; on niri they
      # can force a lower logical resolution (Samsung TV 4K @ scale 1.5 →
      # 2560x1440) and refresh changes.
      autoDetect = {
        resolution = false;
        hdr = false;
        vrr = false;
        refreshRate = false;
        scaling = false;
      };
    };

    # Anime game launchers
    anime-game-launcher.enable = true;
    sleepy-launcher.enable = true;
    honkers-railway-launcher.enable = true;
    wavey-launcher.enable = true;

    # AI services
    stability-matrix.enable = true;
  };

  # Podman container runtime (for Spacebot)
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    dockerSocket.enable = true;
  };

  # ============================================================================
  # AGENIX SECRETS - Centralized registry (2026-03-16 migration)
  # ============================================================================
  # All secrets managed via agenix-secrets-registry module
  # Categories: aiServices, monitoring, storage, mining, cloud, selfHosting
  # See: modules/system/agenix-secrets-registry.nix
  services.sops-secrets-registry = {
    enable = true;
    aiServices = true; # For autoresearch skill optimization (ANTHROPIC_API_KEY)
    monitoring = false; # No monitoring secrets currently needed (sentry-dsn removed with GlitchTip)
    storage = true; # Required for backup-to-garage service (S3 API key)
    mining = true;
    # kubernetes = false — zephyr is NOT a k3s node; the k3s token secret is
    # not needed here (control plane is nexus/forge/sentry).
    selfHosting = false; # These services run on other hosts
  };

  # Override specific secret permissions (registry defaults can be overridden)
  sops.secrets."cloud/cloudflared-token" = lib.mkForce {
    sopsFile = "${inputs.nixos-secrets}/secrets/cloud/cloudflared-token.yaml";
    format = "yaml";
    key = "data";
    mode = "400";
    owner = "root";
    group = "root";
  };
  # AI INFERENCE SERVICE - Gateway with authentication and metrics
  # Gateway routes to local and approved inference backends.
  # Gateway: OpenAI-compatible API on port 8080
  # ============================================================================

  # ============================================================================
  # WEB TESTING - Playwright/Puppeteer system dependencies
  # Provides GTK libraries and fonts for Chromium-based browsers
  # ============================================================================

  # ============================================================================
  # CI/CD - Self-hosted GitHub Actions runner
  # ============================================================================
  # SETUP REQUIRED (one-time):
  #   sudo /etc/nixos/scripts/ci/setup-runner.sh owner/repo
  # After setup, set enable = true and autoStart = true below

  # ============================================================================
  # MINING - GPU Mining (RTX 3090)
  # DISABLED: Mining conflicts with AI inference services (LM Studio)
  # Note: profiles.role.mining enables services.mining automatically

  # ============================================================================
  # FLATPAK - Flatpak support with Discover and Flathub
  # ============================================================================

  # ============================================================================
  # PER-GPU POWER LIMITS
  # ============================================================================
  # NOTE: Power limits are now managed by the mining.nix module via
  # nvidia-gpu-power-limit.service using perGpuPowerLimits configuration.
  # The old gpu-0-power-limit and gpu-1-power-limit services have been
  # removed to avoid conflicts. Current limits: 3090 @ 250W (3060 Ti disabled).
  #
  # See: modules/mining/mining.nix -> nvidia-gpu-power-limit.service

  # Systems Intelligence Plasmoid - Cluster monitoring widget

  # LM Studio - Local LLM inference with GPU acceleration
  programs.lm-studio.enable = true;

  # Pi agent model registry (declarative models.json)
  # programs.pi-agent.enable = true;  # TODO: option not found — disabled for now

  # ============================================================================
  # MONITORING - Full monitoring stack
  # ============================================================================

  # ============================================================================
  # NETWORK PROFILES
  # ============================================================================
  # Base Tailscale configuration provided by node-profiles.zephyr-workstation
  # No additional network profile configuration needed

  # ============================================================================
  # ADDITIONAL PACKAGES
  # ============================================================================
  # Noctalia CLI binary (needed for keybindings: Mod+Space, Print, etc.)
  # Package referenced via flake input (outside with pkgs; scope)
  environment.systemPackages = with pkgs; [
    # Shell & CLI
    fish
    zoxide
    fzf
    eza
    btop
    tmux
    mosh
    git

    # Networking
    tailscale
    networkmanager
    dbus-broker
    slirp4netns # Required for Spacebot/Podman networking
    podman-compose # Docker Compose compatibility for Podman
    localsend # Local network file sharing (AirDrop alternative)
    grsync # GTK rsync frontend — visual manual sync between hosts/drives (2026-08-14)

    # Deployment
    inputs.colmena.packages.${pkgs.stdenv.hostPlatform.system}.colmena

    # Hardware monitoring & fan control helpers
    ddcutil # DDC/CI monitor brightness control
    # lsfg-vk — Lossless Scaling frame-gen (PancakeTAS/lsfg-vk, GPLv3).
    # RE-ADDED 2026-08-16 the PROPER way. The Aug-14 removal was correct:
    # 2.0.0-dev with a stale config (version!=2) + no kill-switch broke EVERY
    # Vulkan app ("unsupported configuration version"). The proper setup:
    #   - DISABLE_LSFGVK=1 globally (environment.sessionVariables below) —
    #     the implicit GLOBAL layer never loads by default; llama.cpp,
    #     upscayl etc. are untouched.
    #   - v2 conf.toml (home-manager xdg.configFile) pointing dll at the
    #     Steam install: /data/games/SteamLibrary/steamapps/common/Lossless Scaling/Lossless.dll
    #   - Per-game opt-in via Steam launch options: DISABLE_LSFGVK=0
    #     LSFGVK_ENV=1 LSFGVK_DLL_PATH=<path> — layer activates only there.
    lsfg-vk # Lossless Scaling frame generation Vulkan layer (needs Steam app 993090 installed for the DLL)
    lsfg-vk-ui # lsfg-vk config GUI (per-game profiles)
    (pkgs.writeShellScriptBin "fan-set" ''
      #!${pkgs.bash}/bin/bash
      # Set fan speed (0-255) for a specific fan
      # Usage: fan-set <fan_number> <pwm_value>
      # Example: fan-set 1 128 (sets fan 1 to 50%)
      if [ "$#" -ne 2 ]; then
        echo "Usage: fan-set <fan_number> <pwm_value (0-255)>"
        echo "Example: fan-set 1 128  # Set fan 1 to 50%"
        exit 1
      fi
      fan=$1
      pwm=$2
      pwm_file="/sys/class/hwmon/hwmon6/pwm$fan"
      if [ ! -w "$pwm_file" ]; then
        echo "Error: Cannot write to $pwm_file"
        echo "You may need to disable BIOS fan control first"
        exit 1
      fi
      echo "$pwm" > "$pwm_file"
      echo "Set fan $fan to PWM $pwm ($(awk "BEGIN {printf \"%.0f\", $pwm/255*100}")%)"
    '')

    (pkgs.writeShellScriptBin "fan-get" ''
      #!${pkgs.bash}/bin/bash
      # Get current fan speed and PWM for all fans
      echo "Fan Status for MSI X570 TOMAHAWK:"
      echo "────────────────────────────────────────"
      for i in 1 2 3 4 5 6 7; do
        pwm_file="/sys/class/hwmon/hwmon6/pwm''$i"
        rpm_file="/sys/class/hwmon/hwmon6/fan''${i}_input"
        label_file="/sys/class/hwmon/hwmon6/fan''${i}_label"
        if [ -f "$pwm_file" ]; then
          pwm=$(cat "$pwm_file" 2>/dev/null || echo "N/A")
          rpm=$(cat "$rpm_file" 2>/dev/null || echo "0")
          label="Fan ''$i"
          [ -f "$label_file" ] && label=$(cat "$label_file")
          percent=$(awk "BEGIN {printf \"%.0f\", $pwm/255*100}")
          printf "%-12s: %4d RPM  PWM: %3d (%3s%%)\n" "$label" "$rpm" "$pwm" "$percent"
        fi
      done
    '')

    (pkgs.writeShellScriptBin "temp-get" ''
      #!${pkgs.bash}/bin/bash
      # Get all temperature readings
      echo "Temperature Readings:"
      echo "────────────────────"
      # AMD CPU temps
      echo "AMD CPU (k10temp):"
      ${pkgs.lm_sensors}/bin/sensors -j k10temp-pci-00c3 2>/dev/null | ${pkgs.jq}/bin/jq -r 'to_entries[] | "  \(.key): \(.value.value // .value | tonumber | floor)°C"' 2>/dev/null || ${pkgs.lm_sensors}/bin/sensors k10temp-pci-00c3
      echo ""
      # Motherboard temps
      echo "Motherboard (NCT6775):"
      ${pkgs.lm_sensors}/bin/sensors -j nct6797-isa-0a20 2>/dev/null | ${pkgs.jq}/bin/jq -r 'to_entries[] | select(.key | contains("temp")) | "  \(.key): \(.value.value // .value | tonumber | floor)°C"' 2>/dev/null || ${pkgs.lm_sensors}/bin/sensors nct6797-isa-0a20 | grep -E "SYSTIN|CPUTIN|TSI"
      echo ""
      # NVMe temps
      echo "NVMe Drives:"
      ${pkgs.lm_sensors}/bin/sensors -j 2>/dev/null | ${pkgs.jq}/bin/jq -r 'to_entries[] | select(.key | contains("nvme")) | "  \(.key): \(.value[\"Composite\"].value | tonumber | floor)°C"' 2>/dev/null || ${pkgs.lm_sensors}/bin/sensors | grep -A2 nvme
    '')

    (pkgs.writeShellScriptBin "sys-mon" ''
      #!${pkgs.bash}/bin/bash
      # Comprehensive system monitoring dashboard
      exec /etc/nixos/scripts/monitor-sensors.sh
    '')

    (pkgs.writeShellScriptBin "aio-status" ''
      #!${pkgs.bash}/bin/bash
      # Corsair AIO cooler status
      exec /etc/nixos/scripts/corsair-status.sh
    '')

    (pkgs.writeShellScriptBin "corsair-rgb" ''
      #!${pkgs.bash}/bin/bash
      # Start OpenRGB GUI for Corsair RGB control
      exec /etc/nixos/scripts/corsair-rgb
    '')

    (pkgs.writeShellScriptBin "corsair-rgb-server" ''
      #!${pkgs.bash}/bin/bash
      # Start OpenRGB server for programmatic RGB control
      exec /etc/nixos/scripts/corsair-rgb-server
    '')

    # Network discovery & mapping
    nmap
    netdiscover
    arp-scan
    iproute2 # ip, ss, route commands
    iputils # ping, traceroute
    dnsutils # dig, nslookup
    whois
    net-tools # arp, ifconfig, route

    # Development
    nodejs
    gh
    jq
    inputs.claude-native.packages.x86_64-linux.claude

    # AI & ML
    llama-cpp
    whisper-cpp
    pipx
    pkgs.python312Packages.huggingface-hub # HF CLI: hf download/upload/login
    opencode # AI coding agent (terminal-based)

    # Mining (manual only, no auto-start)

    # Desktop
    inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.twilight
    # telegram-desktop intentionally NOT in system packages (2026-08-14):
    # HM's opencode module installs it into ~/.nix-profile (opencode.nix
    # programs.opencode.telegramDesktop, default true). A system copy
    # duplicated the org.telegram.desktop DBus service -> dbus-broker
    # "Ignoring duplicate name" warnings on every session start.
    # Freebuff Desktop — runnable copy + launcher owned by home-manager-config
    # appimage-updater (~/.local/opt/freebuff-desktop/current + the
    # freebuff-desktop.desktop entry). services.freebuff-desktop.enable = true
    # only installs the hicolor icon; no package entry is needed here.

    # Network automation - for switch/modem configuration scripts
    python3Packages.playwright

    # Diagrams & data
    # mermaid-cli provided by modules/development/tools.nix (all non-sentry hosts)
    graphviz # Graphviz (dot) diagrams
    python312Packages.openpyxl # Excel read/write
    # Noctalia CLI binary for keybindings (Mod+Space, Print, notifications)
    pkgs.noctalia
    # Bonsai 27B: ternary (RTX 3090, port 1237, CUDA), 1-bit (3060 Ti, port 1236)
  ];

  # ============================================================================
  # MULTI-GPU ENVIRONMENT VARIABLES - RTX 3090 + 3060 Ti
  # ============================================================================
  environment.sessionVariables = {
    # lsfg-vk kill-switch: the implicit GLOBAL layer is registered by the
    # package but must NEVER load into every Vulkan app. This disables it
    # everywhere by default; per-game launch options override to 0.
    DISABLE_LSFGVK = "1";

    # GPU visibility
    CUDA_VISIBLE_DEVICES = "0,1";

    # NCCL (NVIDIA Collective Communications Library) settings
    NCCL_P2P_LEVEL = "2"; # PCIe bridge level (P2P limited on heterogeneous GPUs)
    NCCL_P2P_DISABLE = "0"; # Try P2P first, disable if issues occur
    NCCL_IB_DISABLE = "1"; # Disable InfiniBand (not applicable)
    NCCL_ALGO = "Tree"; # Tree algorithm for multi-GPU communication

    # llama.cpp/llama-cpp CUDA settings
    GGML_CUDA_ENABLE_UNIFIED_MEMORY = "0"; # UMA spills VRAM to RAM over PCIe; every llama overrides to 0 anyway
    GGML_CUDA_GPU_MEMORY_FRACTION = "0.9"; # Use 90% of GPU VRAM (leave headroom)
    LLAMA_GRAPH_POOL_SIZE = "0.2"; # CUDA Graphs pool (20% of VRAM)
    # KV cache quantization (Q4_0) is configured per-model in backend
  };

  # ============================================================================

  # ============================================================================

  # ============================================================================

  # ============================================================================

  # LLAMA-SERVER - Local LLM inference for autoresearch
  # ============================================================================

  # ============================================================================
  # SWAP - Using 32GB partition on nvme0n1p1 (configured in hardware-configuration.nix)
  # ============================================================================
  # Previous 8GB swapfile removed to use partition instead (2026-03-25)
  # Partition UUID: b733be92-f327-4613-9530-a5380ed77216

  # ============================================================================
  # SYSTEM STATE
  # ============================================================================
  system.stateVersion = "26.05";

  # ============================================================================
  # CRASH DETECTION
  # ============================================================================
  # Enable crash watchdog to detect and log system crashes
  # Configured in services block above

  # ============================================================================
  # BACKUP TO GARAGE S3
  # ============================================================================
  # Automated daily backups to Garage S3 cluster (runs at 2 AM)
  # Configured in services block above

  # ============================================================================
  # NVIDIA CDI GENERATOR FIX
  # ============================================================================
  # ============================================================================
  # UNBOUND DNS WITH DNS-OVER-TLS
  # ============================================================================
  # Local recursive DNS resolver with DNS-over-TLS to Cloudflare, Google, Quad9
  # Accessible on localhost for local applications and cluster network
  # Survives NixOS rebuilds without restart (restartIfChanged = false)
  services.unbound-common.enable = true;

  # Point Steam/pressure-vessel to the NVIDIA Vulkan ICD.
  # 2026-08-14 (permanent): NO global VK_DRIVER_FILES. The Vulkan loader
  # discovers the ICD automatically: nixpkgs builds it with
  # SYSTEM_SEARCH_PATH=/run/opengl-driver/share (KhronosLoader PR #195) and
  # hardware.graphics sets XDG_DATA_DIRS to include /run/opengl-driver/share;
  # the /etc/xdg/vulkan/icd.d/nvidia_icd.json link (nvidia-wayland.nix) covers
  # tools that only search /etc. A global VK_DRIVER_FILES REPLACES that
  # discovery with a single brittle path — the previous value
  # (/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.x86_64.json) never
  # existed on disk (tmpfiles race at boot), so EVERY Vulkan process died
  # ("Found no drivers" / pressure-vessel "Failed to load Vulkan ICD";
  # PoE2/DX12 engine-init crash, VRChat swapchain errors under Steam).
  # Verified 2026-08-14: env -u VK_DRIVER_FILES vulkaninfo --summary
  # enumerates RTX 3090 + 3060 Ti. Do not re-add this variable.
  # Bonsai 27B: ternary (RTX 3090, port 1237, CUDA), 1-bit (3060 Ti, port 1236)

  # Resolve K8s ingress hostnames to the cluster VIP (10.1.1.100)
  # Local DNS records are in modules/services/unbound-common.nix (shared
  # across all hosts). Fallback /etc/hosts entries below.

  networking.extraHosts = lib.mkOptionDefault ''
    10.1.1.100 search.lan search.cluster.local
    10.1.1.100 ai.lan ai.cluster.local
    10.1.1.100 openwebui.lan openwebui.cluster.local
    10.1.1.100 civicintel.lan civicintel.cluster.local
  '';

  # ============================================================================
  # CLAUDE CODE ROUTER - Route Claude Code to approved local/NVIDIA models
  # ============================================================================
  # Corsair keyboard/mouse driver daemon (ckb-next)
  systemd.services.ckb-next = {
    description = "Corsair Keyboards and Mice Daemon";
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      ExecStart = "${pkgs.ckb-next}/bin/ckb-next-daemon";
      Restart = "on-failure";
    };
  };

  # Gamma-based brightness for HDMI TV (no DDC/CI)
  services.fake-backlight-bridge.enable = true;

  # Lossless Scaling Frame Generation

  # Lossless Scaling Frame Generation via Vulkan
  services.storage-assertions.enable = true;
  services.thermal-monitor.enable = true;
  # Cross-fleet read-only CPU thermal watchdog: alerts at 90C warn / 95C crit.

  # Fix nixpkgs tcl-8_6 regression: nixpkgs-unstable has tcl aliased to 8.5.19
  # but python tkinter requires 8.6. Pin tcl-8_6 to the explicit 8.6.nix.

  # Disable edk2-uefi-shell to avoid python3 → tkinter → tcl-8_6 eval error
  boot.loader.systemd-boot.edk2-uefi-shell.enable = false;

  # Bonsai services are OWNED BY HOME-MANAGER (bonsai-ternary-3090-262k.service
  # + bonsai-1bit-3060ti-128k-turbo4.service, correct CUDA pinning + UMA=0).
  # The system-level module must stay OFF or its units (bonsai-*-zephyr.service,
  # old binary, --host 0.0.0.0) crash-loop on the same ports (8005/1236).
  services.bonsai = {
    enable = false;
  };

  # NVIDIA Switchyard LLM routing proxy - local + remote backends.
  # Routes: switchyard/{muse,bonsai,nim,opencode-go,opencode-zen,local}.
  # Nous Portal deliberately omitted: OAuth rotating token, not a static key.
  services.switchyard = {
    enable = true;
    host = "127.0.0.1";
    port = 4000;
    configFile = ../../modules/services/switchyard/routes.toml;
    envFiles = {
      NVIDIA_API_KEY = "/run/secrets/nvidia-api-key";
      OPENCODE_GO_API_KEY = "/run/secrets/opencode-go-api-key";
      OPENCODE_ZEN_API_KEY = "/run/secrets/opencode-api-key";
    };
  };

  # ── Hermes Agent config.yaml — SPOC (2026-08-12) ────────────────────────
  # hermes-config-emit.service rewrites `providers:` + `fallback_providers:`
  # at boot from this block. All other sections (MCP servers, toolsets,
  # imperative channel config) are preserved. Do NOT edit the live
  # ~/.hermes/config.yaml providers by hand — edit here, then:
  #   systemctl restart hermes-config-emit.service
  # Fallback policy (j_kro, 2026-08-11): local DSpark bonsai → zen free
  # nemotron → go flash → NIM lightning. Hermes v0.20.0 requires fallback
  # entries as {provider, model} dicts (strings are silently dropped).
  services.hermes-cli = {
    enable = true;
    user = "j_kro";
    managedConfig = true;
    nvidiaApiKeyFile = "/run/secrets/nvidia-api-key";
    opencodeGoApiKeyFile = "/run/secrets/opencode-go-api-key";
    opencodeZenApiKeyFile = "/run/secrets/opencode-api-key";
    secretspecEnvVarMappings = {
      "NVIDIA_API_KEY" = "NVIDIA_API_KEY";
      "OPENCODE_API_KEY" = "OPENCODE_ZEN_API_KEY";
      "OPENCODE_GO_API_KEY" = "OPENCODE_GO_API_KEY";
    };
    managedProviders = {
      "switchyard" = {
        api_key_env = "NVIDIA_API_KEY"; # local proxy; key unused for localhost
        base_url = "http://127.0.0.1:4000/v1";
        discover_models = true;
        model = "switchyard/local";
      };
      "opencode-zen" = {
        api_key_env = "OPENCODE_API_KEY";
        base_url = "https://opencode.ai/zen/v1";
        discover_models = true;
        model = "nemotron-3.5-lightning-free";
      };
      "opencode-go" = {
        api_key_env = "OPENCODE_GO_API_KEY";
        base_url = "https://opencode.ai/zen/go/v1";
        discover_models = true;
        model = "deepseek-v4-flash";
      };
      "nvidia" = {
        api_key_env = "NVIDIA_API_KEY";
        base_url = "https://integrate.api.nvidia.com/v1";
        discover_models = true;
        model = "nvidia/nemotron-3.5-lightning-30b-a3b";
      };
    };
    managedFallbackProviders = [
      {
        provider = "switchyard";
        model = "switchyard/local";
      }
      {
        provider = "opencode-zen";
        model = "nemotron-3.5-lightning-free";
      }
      {
        provider = "opencode-go";
        model = "deepseek-v4-flash";
      }
      {
        provider = "nvidia";
        model = "nvidia/nemotron-3.5-lightning-30b-a3b";
      }
    ];
  };

  # A2A mesh: shared peer definitions + inbound gateway platform (port 9900)
  # rendered from Nix by hermes-config-emit. Dendritic SPOC — peers live here,
  # token values stay in the hermes-owned config.yaml.
  services.hermes-a2a.enable = true;

  # Periodic memlawb health check (reachability + passphrase decrypt round-trip).
  # Runs on zephyr because the MCP client + zero-knowledge passphrase live here.
  services.memlawb-healthcheck.enable = true;
}
