# Nexus Host Configuration - Build and Backup Node
# 10.1.1.120 - 24 cores, 1x RTX 3060 Ti
# Features: Gaming + VR, MCP Servers
#
# Module imports: Gaming, mining, monitoring, opencode are already imported
# via commonModules in flake.nix (./modules/default.nix)
{pkgs, lib, ...}: {
  imports = [
    # Monitoring configuration
    ./monitoring.nix
    # Hardware configuration (generated)
    ./hardware-configuration.nix

    # All other modules (desktop, gaming, networking, services, etc.)
    ../../modules/default.nix

    # NVIDIA GPU support (common + wayland-specific)
    ../../modules/hardware/nvidia-common.nix
    ../../modules/hardware/nvidia-wayland.nix

    # Desktop environment modules
    ../../modules/desktop/gamescope-tty.nix

    # Nexus-specific modules
    ../../modules/services/mcp-servers.nix
    ../../modules/security/aistor-secrets.nix
    ../../modules/services/podman-support.nix

    # Home Manager integration
    ../../modules/system/home-manager.nix

    # Kubernetes worker node
    ../../modules/services/kubernetes.nix
  ];

  # ============================================================================
  # HOST IDENTIFICATION
  # ============================================================================
  # Centralized cluster networking (search domains, DNS, firewall basics)
  clusterNetworking = {
    enable = true;
    hostName = "nexus";
    ipAddress = "10.1.1.120";
    interfaceName = "enp7s0";  # Native hardware interface name
    wireless.enable = true;  # Enable WiFi for versatility (interface: wlo1, native: wlp4s0)
    unbound.listenAddress = "10.1.1.120";  # Listen on node IP for cluster DNS
  };

  # Nexus-specific firewall rules (in addition to cluster defaults)
  networking.firewall.allowedTCPPorts = lib.mkOptionDefault [
    10250  # Kubelet API
  ];
  networking.firewall.allowedTCPPortRanges = [
    {
      from = 30000;
      to = 32767;
    }
  ];
  networking.firewall.allowedUDPPorts = lib.mkOptionDefault [
    8472  # Flannel VXLAN
  ];

  # ============================================================================
  # HARDWARE PROFILES
  # ============================================================================
  hardware = {
    profiles = {
      amd.zen = true; # Zen CPU optimizations
      nvidia.enable = true; # NVIDIA GPU support
      nvidia.multiGpu = false; # Single RTX 3060 Ti
      monitoring.enable = true; # Hardware monitoring
    };

    # BTRFS compression and deduplication
    btrfs-compression.enable = true;

    # Hardware monitoring extras (not covered by profile)
    monitoring = {
      autoDetect = true; # Auto-detect sensor chips
      fanControl = false; # BIOS fan control for now
    };
  };

  # ============================================================================
  # FILESYSTEM COMPRESSION - Enable zstd:3 on all BTRFS filesystems
  # ============================================================================
  fileSystems = {
    "/".options = lib.mkOptionDefault ["compress=zstd:3" "ssd" "discard=async"];
    "/home".options = lib.mkOptionDefault ["compress=zstd:3" "ssd" "discard=async"];
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
      options = ["subvol=home" "compress=zstd" "ssd" "discard=async" "nofail" "x-systemd.device-timeout=10s"];
    };

    "/data/shared" = {
      device = "/dev/disk/by-uuid/08cbb21c-adb0-4e3c-928f-7b6d1fa2d236";
      fsType = "btrfs";
      options = ["subvol=shared" "compress=zstd" "ssd" "discard=async" "nofail" "x-systemd.device-timeout=10s"];
    };

    "/data/backups" = {
      device = "/dev/disk/by-uuid/08cbb21c-adb0-4e3c-928f-7b6d1fa2d236";
      fsType = "btrfs";
      options = ["subvol=backups" "compress=zstd" "ssd" "discard=async" "nofail" "x-systemd.device-timeout=10s"];
    };

    "/data/media" = {
      device = "/dev/disk/by-uuid/08cbb21c-adb0-4e3c-928f-7b6d1fa2d236";
      fsType = "btrfs";
      options = ["subvol=media" "compress=zstd" "ssd" "discard=async" "nofail" "x-systemd.device-timeout=10s"];
    };

    "/var/lib/containers" = {
      device = "/dev/disk/by-uuid/08cbb21c-adb0-4e3c-928f-7b6d1fa2d236";
      fsType = "btrfs";
      options = ["subvol=containers" "compress=zstd" "ssd" "discard=async" "nofail" "x-systemd.device-timeout=10s"];
    };
  };

  # ============================================================================
  # BOOTLOADER
  # ============================================================================
  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };

    # ============================================================================
    # KERNEL - Zen for better desktop responsiveness
    # ============================================================================
    kernelPackages = pkgs.linuxPackages_zen;
  };

  # ============================================================================
  # ROLE PROFILES
  # ============================================================================
  profiles.role = {
    gaming = true; # Steam, Lutris, etc.
    vr = true; # WiVRn, SteamVR, OpenXR
    mining = true; # GPU/CPU mining
    aiInference = true; # AI inference gateway + MCP + RAG
  };

  # Note: profiles.role.gaming enables services.gaming automatically

  # ============================================================================
  # NETWORK PROFILES
  # ============================================================================
  profiles.network.tailscale.enable = true;

  # ============================================================================
  # SERVICES CONFIGURATION
  # ============================================================================

  # Enable Steam Gamescope session alongside Plasma
  # Both sessions will be available in SDDM for selection
  programs.steam = {
    enable = true;
    gamescopeSession.enable = true;
  };

  services = {
    # Crash detection and logging
    crash-watchdog.enable = true;

    # Kubernetes worker node
    kubernetes-module = {
      enable = true;
      masterAddress = "10.1.1.110"; # Zephyr control plane
      roles = ["node"]; # Worker node only
    };

    garnix.enable = false;
    nixos-auto-update.enable = true;

    # Spotify with SpotX patch (ad-free, premium features)
    spotify-spotx.enable = true;

    # Mining configuration - CPU uses xmrig-proxy on Zephyr
    # Uses defaults from mining.nix for pool URLs and wallet format
    # Note: profiles.role.mining enables services.mining automatically
    mining = {
      xmrig = {
        enable = true;
        autostart = true;
        threads = 12;
        pool = "10.1.1.110:3333";  # xmrig-proxy on Zephyr
        wallet = "nexus-cpu";        # Worker ID for proxy
        tls = false;                 # No TLS needed for local proxy
      };

      # GPU mining configuration (shared by NVIDIA)
      lolminer = {
        pool = "stratum+tcp://xtm-c29-us.kryptex.network:8040";
        wallet = "krxXVNVMM7.nexus-gpu";
      };

      # NVIDIA GPU mining (RTX 3060 Ti @ 130W)
      lolminer.nvidia = {
        enable = true;
        autostart = true;
        devices = "0";
        powerLimit = 130; # 130W for optimal efficiency
        apiPort = 4068;
      };
    };

    # GPU Proxy - Stratum proxy for GPU miners (lolMiner)
    gpu-proxy = {
      enable = true;
      listenPort = 3334;
      apiPort = 8083;
      logLevel = "INFO";
      pools = [
        {
          name = "Kryptex US";
          url = "stratum+tcp://xtm-c29-us.kryptex.network:8038";
          wallet = "krxXVNVMM7";
          password = "x";
          priority = 1;
          tls = false;
        }
        {
          name = "Kryptex EU";
          url = "stratum+tcp://xtm-c29-eu.kryptex.network:8038";
          wallet = "krxXVNVMM7";
          password = "x";
          priority = 2;
          tls = false;
        }
      ];
      workers = [
        { id = "nexus-gpu"; password = "x"; }
        { id = "zephyr-gpu"; password = "x"; }
        { id = "forge-gpu"; password = "x"; }
      ];
      openFirewall = true;
    };

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

    # Garage S3-compatible object storage (local storage)
    # TEMPORARILY DISABLED - permission issues with /data/shared/garage
    garage-cluster = {
      enable = false;
      dataDir = "/data/shared/garage";
      peers = ["zephyr" "sentry"];
      replicationFactor = 2;
    };
  };

  # ============================================================================
  # TAILSCALE (No route advertising - zephyr handles that)
  # ============================================================================
  systemd.services.tailscaled.environment = {
    TS_ADVERTISE_ROUTES = "";
    TS_ROUTES = "";
    TS_SSH = "true";
  };

  # ============================================================================
  # USER GROUPS
  # ============================================================================
  users.users.j_kro.extraGroups = ["plugdev" "audio" "input" "docker" "openrazer" "tailscale" "video" "render"];
}
