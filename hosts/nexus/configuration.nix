# Nexus Host Configuration - Build and Backup Node
# 10.1.1.120 - 24 cores, 1x RTX 3060 Ti
# Features: Gaming + VR, MCP Servers
#
# Module imports: Gaming, mining, monitoring, opencode are already imported
# via commonModules in flake.nix (./modules/default.nix)
{
  lib,
  pkgs,
  inputs,
  ...
}: {
  imports = [
    ../../modules/system/secretspec-creds.nix
    ../../modules/system/secretspec-validator.nix
    # Monitoring configuration
    ./monitoring.nix
    # Hardware configuration (generated)
    ./hardware-configuration.nix

    # Declarative non-volatile state; replaces the retired impermanence module.
    ./preservation.nix
    # Nexus owns cluster ingress and the canonical TLS leaf certificate.
    ./services.nix
    ../../modules/services/cluster-services.nix
    ../../modules/services/central-auth.nix
    ../../modules/system/initrd-ssh-recovery.nix
    ../../modules/system/recovery-specialisation.nix
    ../../modules/services/nexus-exec.nix
    ../../modules/services/k8s-secret-sync.nix
    ../../modules/services/k8s-nix-deploy.nix
    ../../modules/services/mcp-server-registry.nix

    # AI Inference Service - MOVED from Zephyr
    ./ai-inference.nix

    # All other modules (desktop, gaming, networking, services, etc.)
    ../../modules/default.nix

    # Host desktop: SDDM + autoLogin + SteamOS gamescope session (4K TV).
    ./desktop.nix

    # NVIDIA GPU Wayland support (host-dependent)
    ../../modules/hardware/nvidia-common.nix
    ../../modules/hardware/nvidia-wayland.nix
    ../../modules/hardware/rgb-control.nix

    # Desktop environment modules
    # SteamOS gamescope session handled declaratively: desktop.nix enables
    # SDDM + autoLogin with the nixpkgs-native `programs.steam.gamescopeSession`
    # (see "SERVICES CONFIGURATION" below).

    # Nexus-specific modules
    ../../modules/security/aistor-secrets.nix
    ../../modules/services/podman-support.nix

    # Gaming on nexus runs natively on the GPU (gamescope session); the
    # Windows gaming VM is dropped from nexus — zephyr only (OOB direction
    # 2026-08-08).

    # SecretSpec Phase 4 credential provisioning (parallel with sops registry)

    # Kubernetes
    ../../modules/services/k3s-cluster.nix
    ../../modules/services/mosaic-k3s-manifests.nix
    # Bonsai 27B: ternary (when GPU idle, port 1238), 1-bit (port 1235)
    ../../modules/services/bonsai.nix
    # Keepalived VIP for HA API server access
    ../../modules/services/keepalived-vip.nix

    # Storage assertions (partlabel/uuid/boot checks)
    ../../modules/system/storage-assertions.nix
    # PeakMiner GPU mining stack
    ./peakminer.nix

    # Nix binary cache DISABLED
  ];
  # The repository CA certificate is the sole fleet trust anchor. The matching
  # signing key is provisioned by SecretSpec on Nexus only (see
  # ./secretspec-creds-wiring.nix CLUSTER_CA_KEY -> /etc/ssl/cluster-ca/ca.key)
  # and is never stored in the repository or exposed to Caddy.
  services.cluster-ca = {
    enable = true;
    caKeyProvisioned = true;
    caKeyService = "secretspec-creds.service";
    generateLeaf = true;
  };

  # Nexus owns SSO for the cluster ingress. SecretSpec materializes these
  # credentials at the paths consumed by oauth2-proxy; do not rely on the
  # retired sops.secrets option defaults here.
  services.central-auth = {
    enable = true;
    clientSecretFile = "/run/secrets/central-auth-client-secret";
    cookieSecretFile = "/run/secrets/central-auth-cookie-secret";
  };

  # Auth must not start until SecretSpec has materialized both credential files.
  systemd.services.central-auth = {
    after = ["secretspec-creds.service" "secretspec-validator.service"];
    requires = ["secretspec-creds.service"];
  };

  services.secretspec-creds = {
    enable = true;
    secrets = import ./secretspec-creds-wiring.nix;
  };

  services.secretspec-validator = {
    enable = true;
    production = true;
    # failOnMissing=false is the cluster default per
    # modules/system/SECRETSPEC-CONSOLIDATION.md (flipped 2026-07-25). The
    # manifest intentionally declares 33 env/dotenv-fallback secrets with no
    # sops route; failOnMissing=true made the unit fail every run by design
    # of those entries, drowning journals. Drift still surfaces as warnings.
    failOnMissing = false;
  };

  # ============================================================================
  # HOST IDENTIFICATION
  # ============================================================================
  # Centralized cluster networking (search domains, DNS, firewall basics)
  clusterNetworking = {
    enable = true;
    hostName = "nexus";
    ipAddress = "10.1.1.120";
    interfaceName = "enp7s0";
    wireless = {
      enable = true;
      ipAddress = "10.1.1.125"; # Static IP for WiFi backup
    };
    unbound.listenAddress = "10.1.1.120";
  };

  # FIX: Disable interface renaming - use actual interface names
  systemd.network.links = lib.mkForce {};


  # Windows gaming VM removed from nexus — zephyr only (OOB direction 2026-08-08).
  # GPU now stays on the nvidia driver for the gamescope session + miner.

  # STATUS.md auto-update (hourly from kubectl)
  services.status-auto-update.enable = true;

  # Populate /etc/hosts from central cluster configuration
  networking = {
    cluster-hosts = {
      enable = true;
      populateLocal = true;
    };

    # Nexus-specific firewall rules (in addition to cluster defaults)
    firewall = {
      allowedTCPPorts = lib.mkOptionDefault [
        10250 # Kubelet API
        3900 # Garage S3 API
        3901 # Garage RPC
        8080 # llama-server for autoresearch LLM evaluation
        9100 # Prometheus node-exporter
      ];
      allowedTCPPortRanges = [
        {
          from = 30000;
          to = 32767;
        }
      ];
      allowedUDPPorts = lib.mkOptionDefault [
        8472 # VXLAN (Calico)
      ];
    };
  };

  # ============================================================================
  # NODE PROFILE - Platform-level defaults
  # ============================================================================
  # This profile bundles role profiles, Kubernetes config, hardware profiles,
  # and networking configuration. Eliminates ~100 lines of duplication.
  profiles.node.nexus-gaming.enable = true;

  # Enable workstation role for full Plasma desktop environment
  # This matches Zephyr's desktop setup (enables services.gaming)
  profiles.role.workstation = true;

  # Autologin into Niri on boot (instead of Plasma).
  # To switch compositor, logout and pick from SDDM's session picker.
  programs.niri.enable = true;

  # ============================================================================
  # MONITORING - Prometheus, Grafana, AlertManager
  # ============================================================================
  # Nexus hosts the cluster monitoring stack (46GB RAM capacity)
  profiles.monitoring.enable = true;

  # ============================================================================
  # GPU COMPUTE - CUDA + Vulkan support for AI inference
  # ============================================================================
  hardware.gpu-compute = {
    enable = true;
    cuda.enable = true; # CUDA for NVIDIA RTX 3060 Ti
    vulkan.enable = true; # Vulkan as fallback
  };

  # ============================================================================
  # SERVICES - All service configurations
  # ============================================================================
  systemd.tmpfiles.rules = [
    # Clean old etcd data directory (standalone etcd removed — k3s uses embedded)
    "R /var/lib/etcd - - - - -"
  ];

  services = {
    # Keep automatic workload mutation disabled: PeakMiner remains enabled
    # declaratively, and Ampere coexistence is an explicit operator choice.
    gaming-detection.enable = lib.mkForce false;
    gpu-profile-manager.enable = lib.mkForce false;
    mining-coordinator.enable = lib.mkForce false;

    k3s-cluster = {
      enable = true;
      nvidia.enable = true;
      role = "server";
      clusterInit = true;
      nodeName = "nexus";
      serverAddr = "";
      tokenFile = "/run/secrets/k3s-cluster-token";
      nodeIP = "10.1.1.120";
      calico.enable = true;
      secretsEncryptionKeyFile = "/run/secrets/k3s-encryption-key";
    };

    k8s-manifest-autoapply.enable = true;

    keepalived-vip = {
      enable = true;
      vip = "10.1.1.100";
      interface = "eth0";
      priority = 110;
    };

    # KUBERNETES - k3s control plane (cluster bootstrap node)
    # Bootstrap node: first server to start, creates the cluster
    # All other servers/agents join via VIP: https://10.1.1.100:6443

    # Auto-apply K8s manifests on boot (control-plane node)

    # Bonsai 27B: ternary (when GPU idle, port 1238), 1-bit (port 1235)
    # Keepalived VIP for HA API server access

    # Host Dashboard - Web interface for cluster host status
    host-dashboard = {
      enable = true;
      role = "control-plane + storage + gaming";
      # 8090 is occupied by the user-scoped memlawb service on Nexus.
      # Keep the dashboard on a dedicated localhost port to avoid a restart
      # loop during boot and shutdown.
      port = 8091;
      prometheusUrl = "http://127.0.0.1:9090";
      featuredServices = [
        {
          name = "Prometheus";
          url = "http://127.0.0.1:9090";
        }
        {
          name = "Grafana";
          url = "http://127.0.0.1:3000";
        }
      ];
      services = [
        {
          name = "kubelet";
          active = true;
        }
        {
          name = "containerd";
          active = true;
        }
        {
          name = "cfssl";
          active = true;
        }
        {
          name = "keepalived";
          active = true;
        }
      ];
    };
  };

  # ============================================================================
  # HARDWARE PROFILES
  # ============================================================================
  # Nexus uses the kernel's autonomous AMD P-state driver with a balanced
  # default. The explicit performance profile below is opt-in for builds and
  # gaming; it does not permanently pin the 3900X at maximum power. The
  # power-profiles daemon is the sole base-policy owner; GameMode may request
  # performance transiently while a game is active.
  services.power-profiles-daemon.enable = true;
  systemd.services.nexus-cpu-balanced = {
    description = "Nexus default balanced CPU profile";
    wantedBy = ["multi-user.target"];
    conflicts = ["nexus-cpu-performance.service"];
    after = ["power-profiles-daemon.service"];
    wants = ["power-profiles-daemon.service"];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.power-profiles-daemon}/bin/powerprofilesctl set balanced";
      RemainAfterExit = true;
    };
  };

  # Base profiles provided by node-profiles.nexus-gaming:
  # - amd.zen, nvidia.enable (single GPU), monitoring.enable
  #
  # Nexus-specific hardware additions:
  hardware = {
    # NVIDIA GPU support (base driver)
    nvidia-common.enable = true;

    # BTRFS compression and deduplication
    btrfs-compression.enable = true;

    # Hardware monitoring extras (not covered by profile)
    monitoring = {
      autoDetect = false; # Disabled: sensors-detect has bug with --auto flag
      fanControl = false; # BIOS fan control for now
    };

    # RGB control for Razer Naga Pro and Gigabyte X470 Aorus motherboard.
    # The native OpenRGB module owns the SDK server and udev rules; the RGB
    # helper only issues client commands against that single server.
    rgb-control = {
      enable = true;
      openrgb = {
        enable = true;
        motherboard = "amd";
      };
      openrazer.enable = true; # Razer Naga Pro
    };
  };

  # ============================================================================
  # FILESYSTEM COMPRESSION - Enable zstd:3 on all BTRFS filesystems
  # ============================================================================
  fileSystems = {
    "/".options = lib.mkOptionDefault [
      "compress=zstd:3"
      "ssd"
      "discard=async"
    ];
    "/home".options = lib.mkOptionDefault [
      "compress=zstd:3"
      "ssd"
      "discard=async"
    ];
  };

  # ============================================================================
  # STORAGE CONFIGURATION
  # ============================================================================
  # Nexus has additional storage beyond the root filesystem:
  # - nvme1n1 (223.6GB) - "worn-storage" for high-write workloads
  # - bcache0 (3.6TB + 465GB cache) - "nexus-storage" with organized subvolumes

  fileSystems = {
    # Mount nexus-storage subvolumes (large bcache device)
    # Note: /data/worn is defined in hardware-configuration.nix
    "/data/home" = {
      device = "/dev/disk/by-uuid/08cbb21c-adb0-4e3c-928f-7b6d1fa2d236";
      fsType = "btrfs";
      options = [
        "subvol=home"
        "compress=zstd"
        "ssd"
        "discard=async"
        "nofail"
        "x-systemd.device-timeout=10s"
      ];
    };

    "/data/shared" = {
      device = "/dev/disk/by-uuid/08cbb21c-adb0-4e3c-928f-7b6d1fa2d236";
      fsType = "btrfs";
      options = [
        "subvol=shared"
        "compress=zstd"
        "ssd"
        "discard=async"
        "nofail"
        "x-systemd.device-timeout=10s"
      ];
    };

    "/data/backups" = {
      device = "/dev/disk/by-uuid/08cbb21c-adb0-4e3c-928f-7b6d1fa2d236";
      fsType = "btrfs";
      options = [
        "subvol=backups"
        "compress=zstd"
        "ssd"
        "discard=async"
        "nofail"
        "x-systemd.device-timeout=10s"
      ];
    };

    "/data/media" = {
      device = "/dev/disk/by-uuid/08cbb21c-adb0-4e3c-928f-7b6d1fa2d236";
      fsType = "btrfs";
      options = [
        "subvol=media"
        "compress=zstd"
        "ssd"
        "discard=async"
        "nofail"
        "x-systemd.device-timeout=10s"
      ];
    };

    "/var/lib/containers" = {
      device = "/dev/disk/by-uuid/08cbb21c-adb0-4e3c-928f-7b6d1fa2d236";
      fsType = "btrfs";
      options = [
        "subvol=containers"
        "compress=zstd"
        "ssd"
        "discard=async"
        "nofail"
        "x-systemd.device-timeout=10s"
      ];
    };
  };

  # ============================================================================
  # BOOT CONFIGURATION
  # ============================================================================
  # Base bootloader settings provided by common-host-defaults.nix:
  # - systemd-boot.enable, efi.canTouchEfiVariables, kernelPackages (linux_zen)
  # NOTE: Using CachyOS kernel — binary cached, x86-64-v3 optimized, BORE scheduler.
  boot.kernelPackages = inputs.nix-cachyos-kernel.legacyPackages.x86_64-linux.linuxPackages-cachyos-latest-x86_64-v3;

  boot.kernelParams = [
    "amd_iommu=on" # Enable AMD IOMMU for device passthrough
    "iommu=pt" # IOMMU passthrough mode (better performance)
    "amd_pstate=active" # AMD autonomous P-state/EPP policy for the 3900X
    "hugepages=3"
  ];

  # ============================================================================
  # ROLE PROFILES
  # ============================================================================
  # Base role profiles provided by node-profiles.nexus-gaming:
  # - gaming, vr, mining, aiInference
  # Kubernetes and networking also handled by node profile
  #
  # No additional role profiles needed - all handled by node profile

  # Note: profiles.role.gaming enables services.gaming automatically

  # ============================================================================
  # NETWORK PROFILES
  # ============================================================================
  # Base Tailscale configuration provided by node-profiles.nexus-gaming
  # No additional network profile configuration needed

  # ============================================================================
  # SERVICES CONFIGURATION
  # ============================================================================
  # Base Kubernetes configuration provided by node-profiles.nexus-gaming:
  # - worker role, masterAddress to zephyr
  #
  # Nexus-specific service additions:

  services = {
    # Compute workload monitor - pauses mining during builds
    # Modular workload monitoring (replaces old compute-workload-monitor monolith)

    # Crash detection and logging
    # services.crash-watchdog.enable = true; # Module not available yet

    # Kubernetes worker configuration provided by node-profiles.nexus-gaming
    # No need to duplicate here

    nixos-auto-update.enable = true;

    # Spotify with SpotX patch (ad-free, premium features)
    spotify-spotx.enable = true;

    # GPU mining DISABLED: 3060 Ti is used for desktop (VRAM exhausted by KWin/Xwayland)
    # CPU mining DISABLED: Migrated to Kubernetes
    mining = {
      enable = lib.mkForce false;
    };

    # GPU Proxy - DISABLED: Using centralized gpu-proxy-cpp on Forge (10.1.1.130:3334)
    # gpu-proxy = {
    #   enable = lib.mkForce false;
    #   listenPort = 3334;
    #   apiPort = 8083;
    #   logLevel = "INFO";
    #   pools = [
    #     {
    #       name = "Kryptex US";
    #       url = "xtm-c29-us.kryptex.network:8040";
    #       wallet = "krxXVNVMM7";
    #       password = "x";
    #       priority = 1;
    #       tls = true;
    #     }
    #     {
    #       name = "Kryptex EU";
    #       url = "xtm-c29-eu.kryptex.network:8040";
    #       wallet = "krxXVNVMM7";
    #       password = "x";
    #       priority = 2;
    #       tls = true;
    #     }
    #   ];
    #   workers = [
    #     {
    #       id = "krxXVNVMM7.nexus-gpu";
    #       password = "x";
    #     }
    #     {
    #       id = "krxXVNVMM7.zephyr-gpu";
    #       password = "x";
    #     }
    #     {
    #       id = "krxXVNVMM7.forge-gpu";
    #       password = "x";
    #     }
    #   ];
    #   openFirewall = true;
    # };

    # MCP servers
    mcp-servers = {
      enable = true;
      servers.playwright.enable = true;
    };

    # Mount /etc/nixos from zephyr (single-source-of-truth)

    # Hermes Agent module removed (2026-04-06) - missing flake input made it undeletable
  };
  # Host-specific override: Nexus does not advertise routes (zephyr handles that)
  # This overrides the base Tailscale configuration from node profile
  systemd.services.tailscaled.environment = {
    TS_ADVERTISE_ROUTES = "";
    TS_ROUTES = "";
    TS_SSH = "true";
  };

  # Grant user-space RGB tools the native, group-scoped I2C access rather
  # than the old world-writable catch-all udev rule.
  hardware.i2c.enable = true;

  # Reversible runtime CPU profile control. Balanced is the normal state;
  # `systemctl start nexus-cpu-performance` opts into performance and stopping
  # it restores balanced. No fan/PWM control is claimed here.
  systemd.services.nexus-cpu-performance = {
    description = "Nexus CPU performance profile (opt-in)";
    conflicts = ["nexus-cpu-balanced.service"];
    after = ["power-profiles-daemon.service" "nexus-cpu-balanced.service"];
    wants = ["power-profiles-daemon.service"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.power-profiles-daemon}/bin/powerprofilesctl set performance";
      ExecStop = "${pkgs.power-profiles-daemon}/bin/powerprofilesctl set balanced";
    };
  };

  # ============================================================================
  # USER GROUPS
  # ============================================================================
  users.users.j_kro.extraGroups = [
    "plugdev"
    "audio"
    "input"
    "docker"
    "openrazer"
    "tailscale"
    "video"
    "render"
  ];

  # ============================================================================
  # ADDITIONAL PACKAGES
  # ============================================================================
  environment.systemPackages = with pkgs; [
    opencode # AI coding agent (migrated from nix profile)
    llama-cpp # CUDA-enabled llama.cpp for autoresearch LLM evaluation
    (writeShellScriptBin "nexus-cpu-mode" ''
      set -euo pipefail
      case "''${1:-status}" in
        balanced)
          exec ${sudo-rs}/bin/sudo ${systemd}/bin/systemctl stop nexus-cpu-performance.service
          ;;
        performance)
          exec ${sudo-rs}/bin/sudo ${systemd}/bin/systemctl start nexus-cpu-performance.service
          ;;
        status)
          exec ${power-profiles-daemon}/bin/powerprofilesctl get
          ;;
        *)
          echo "usage: nexus-cpu-mode {balanced|performance|status}" >&2
          exit 2
          ;;
      esac
    '')
  ];

  # ============================================================================
  # NIX SETTINGS - Nexus-specific cache configuration
  # ============================================================================
  # Nexus uses common substituters from distributed-builds.nix
  # Note: Harmonia binary cache was removed (no local cache server running)
  # garnix.enable = true configures cache.garnix.io remote cache access
  nix.settings = {
    # No local substituters needed - using common caches from distributed-builds.nix
  };

  # ============================================================================
  # SECURITY
  # ============================================================================
  # Trust Caddy Ingress local CA certificate
  security.caddyCa.enable = true;

  # ============================================================================
  # AGENIX SECRETS
  # ============================================================================
  # Centralized registry - see modules/system/agenix-secrets-registry.nix
  # SecretSpec Phase 4 — credential provisioning (replaces sops-nix)

  # Override specific secret permissions for mining service

  # ============================================================================
  # NVIDIA CDI GENERATOR FIX
  # ============================================================================
  # UNBOUND DNS WITH DNS-OVER-TLS (Cluster-wide configuration)
  # ============================================================================
  # Nix binary cache — serves /nix/store as HTTP binary cache for cluster builds
  services.binary-cache = {
    enable = true;
    port = 50000;
    bindAddress = "10.1.1.120";
    keyName = "nexus-cache-1";
  };

  services.unbound-common.enable = true;
  # DisplayManager handled in desktop.nix (SDDM + autoLogin + Steam session).
  # NOTE: do NOT set services.displayManager.defaultSession here — desktop.nix
  # owns it (mkForce "steam") and a second mkForce would conflict at eval.

  # ComfyUI — FLUX.1-schnell GGUF image generation
  # Canonical venv: ~/ComfyUI/.venv — ComfyUI's OWN venv, NOT the site-agency
  # pipeline's (~/Projects/site-agency/.venv). j_kro rule: nothing in the OS
  # codebase may depend on a ~/Projects/ path. LD_LIBRARY_PATH uses the
  # declarative stdenv.cc.cc.lib instead of a hardcoded store path that
  # rotates after every nixos-rebuild.
  systemd.services.comfyui = {
    description = "ComfyUI — FLUX image generation server";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    environment.LD_LIBRARY_PATH = "/run/opengl-driver/lib:${pkgs.stdenv.cc.cc.lib}/lib";
    serviceConfig = {
      WorkingDirectory = "/home/j_kro/ComfyUI";
      ExecStart = "/home/j_kro/ComfyUI/.venv/bin/python main.py --listen 0.0.0.0 --port 8188 --log-stdout";
      User = "j_kro";
      Restart = "always";
      RestartSec = "10s";
    };
  };

  # Pin nixpkgs to latest for NVIDIA 610+ driver (production is 595)

  services.storage-assertions.enable = true;
  services.thermal-monitor.enable = true;
  # Cross-fleet read-only CPU thermal watchdog: alerts at 90C warn / 95C crit.

  # Bonsai 27B: 1-bit on RTX 3060 Ti (port 1235), ternary (port 1238) when GPU idle
  services.bonsai = {
    enable = true;
  };
}