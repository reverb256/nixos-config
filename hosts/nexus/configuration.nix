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
}:
{
  imports = [
    # Monitoring configuration
    ./monitoring.nix
    # Hardware configuration (generated)
    ./hardware-configuration.nix

    # AI Inference Service - MOVED from Zephyr
    ./ai-inference.nix

    # All other modules (desktop, gaming, networking, services, etc.)
    ../../modules/default.nix

    # NVIDIA GPU Wayland support (host-dependent)
    ../../modules/hardware/nvidia-common.nix
    ../../modules/hardware/nvidia-wayland.nix
    ../../modules/hardware/rgb-control.nix

    # Desktop environment modules
    # TEMPORARY: Disabled due to build failures blocking deployments
    # ../../modules/desktop/gamescope-tty.nix

    # Nexus-specific modules
    ../../modules/security/aistor-secrets.nix
    ../../modules/services/podman-support.nix

    # Kubernetes
    ../../modules/services/k3s-cluster.nix
    # Keepalived VIP for HA API server access
    ../../modules/services/keepalived-vip.nix

    # Nix binary cache DISABLED
  ];

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
  systemd.network.links = lib.mkForce { };

  # Disable flake-lock-sync (nixos-shared mount not available)
  services.flake-lock-sync.enable = lib.mkForce false;

  # Directly disable the systemd timer (blocking rebuilds)
  systemd.timers.flake-lock-sync.enable = false;

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
        8472 # VXLAN (Flannel or Calico)
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
  services.displayManager.defaultSession = "niri";

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
    # KUBERNETES - k3s control plane (cluster bootstrap node)
    # This is the first server (clusterInit=true, oldest etcd data)
    # All other servers/agents join via VIP: https://10.1.1.100:6443
    k3s-cluster = {
      enable = true;
      nvidia.enable = true;
      role = "server";
      clusterInit = true;
      nodeName = "nexus";
      serverAddr = "https://10.1.1.100:6443";
      tokenFile = "/run/secrets/k3s-cluster-token";
      nodeIP = "10.1.1.120";
      calico.enable = true;
    };

    # Auto-apply K8s manifests on boot (control-plane node)
    k8s-manifest-autoapply.enable = true;

    # Keepalived VIP for HA API server access
    keepalived-vip = {
      enable = true;
      vip = "10.1.1.100";
      interface = "enp7s0";
      priority = 100;
    };

    # Host Dashboard - Web interface for cluster host status
    host-dashboard = {
      enable = true;
      role = "control-plane + storage + gaming";
      port = 8090;
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
        {
          name = "NFS Server";
          active = true;
        }
      ];
    };
  };

  # ============================================================================
  # HARDWARE PROFILES
  # ============================================================================
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

    # RGB control for Razer Naga Pro and Gigabyte motherboard
    rgb-control = {
      enable = true;
      openrgb.enable = true;
      openrazer.enable = true; # Razer Naga Pro
      temperatureReactive = {
        enable = true;
        sensor = "cpu"; # Monitor CPU temps
        thresholds = {
          cool = 50;
          warm = 65;
          hot = 75;
        };
        interval = 5;
      };
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

  # Enable Steam Gamescope session alongside Plasma
  # Both sessions will be available in SDDM for selection
  programs.steam = {
    enable = true;
    gamescopeSession.enable = true;
  };

  services = {
    # Compute workload monitor - pauses mining during builds
    # Modular workload monitoring (replaces old compute-workload-monitor monolith)
    gaming-detection.enable = true;
    gpu-profile-manager.enable = true;
    mining-coordinator.enable = true;

    # Crash detection and logging
    # services.crash-watchdog.enable = true; # Module not available yet

    # Kubernetes worker configuration provided by node-profiles.nexus-gaming
    # No need to duplicate here

    garnix.enable = true;
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
    #   enable = false;
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
    nixos-share = {
      enable = true;
      client.enable = true;
    };

    # NFS Server - Export shared storage for cluster
    nfs.server.enable = true;

    # Syncthing P2P file sync for /etc/nixos config sync
    syncthing-cluster = {
      enable = true;
      deviceId = "NEXUS-PLACEHOLDER";
    };

    # Garage S3-compatible object storage (single-node cluster)
    # Nexus hosts the primary storage on local bcache0
    # Zephyr and Sentry Garage nodes disabled - centralized storage
    garage-cluster = {
      enable = true;
      dataDir = "/data/shared/garage"; # Local on nexus (bcache0)
      replicationFactor = 1; # Single-node operation (no replication)
      consistencyMode = "consistent"; # Full consistency with zones
      enableMetrics = true; # Prometheus metrics on port 3903
      enableBackup = false; # Nexus IS the backup storage
    };

    # Hermes Agent module removed (2026-04-06) - missing flake input made it undeletable
  };
  # Host-specific override: Nexus does not advertise routes (zephyr handles that)
  # This overrides the base Tailscale configuration from node profile
  systemd.services.tailscaled.environment = {
    TS_ADVERTISE_ROUTES = "";
    TS_ROUTES = "";
    TS_SSH = "true";
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
  services.sops-secrets-registry = {
    enable = true;
    aiServices = true; # HF_TOKEN for vLLM model downloads
    storage = true; # Garage S3 cluster (Nexus is a storage node)
    kubernetes = true; # k3s cluster token
  };

  # Override specific secret permissions for mining service

  # ============================================================================
  # NVIDIA CDI GENERATOR FIX
  # ============================================================================
  # UNBOUND DNS WITH DNS-OVER-TLS (Cluster-wide configuration)
  # ============================================================================
  services.unbound-common.enable = true;
}
