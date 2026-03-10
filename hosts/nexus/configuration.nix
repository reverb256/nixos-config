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
  networking = {
    hostName = "nexus";
    networkmanager = {
      enable = true;
      ensureProfiles.profiles."Wired connection 1" = {
        connection = {
          id = "Wired connection 1";
          type = "ethernet";
          interface-name = "lan0";  # Updated from enp7s0 for consistent interface naming
          autoconnect = true;
        };
        ipv4 = {
          method = "manual";
          address1 = "10.1.1.120/24";
          gateway = "10.1.1.1"; # Default gateway for stratum connectivity
          dns = "127.0.0.1,::1";
        };
        ipv6.method = "auto";
      };
    };

    firewall = {
      allowedTCPPorts = [22 9757 18789 18790 10250]; # Added SSH + Kubelet API
      allowedTCPPortRanges = [
        {
          from = 30000;
          to = 32767;
        }
      ];
      allowedUDPPorts = [9757 9758 9759 8472]; # Added Flannel VXLAN
      interfaces."tailscale0".allowedTCPPorts = [18789 18790];
    };
  };

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
    # Mount worn-storage (worn NVMe - suitable for high-write workloads)
    "/data/worn" = {
      device = "/dev/disk/by-uuid/2056c7e4-cd6c-4a67-9b3d-001178a70eaa";
      fsType = "btrfs";
      options = ["compress=zstd" "ssd" "discard=async" "nofail" "x-systemd.device-timeout=10s"];
    };

    # Mount nexus-storage subvolumes (large bcache device)
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

    # Mining configuration
    # Uses defaults from mining.nix for pool URLs and wallet format
    # Note: profiles.role.mining enables services.mining automatically
    mining = {
      xmrig = {
        enable = true;
        autostart = true;
        threads = 12;
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
