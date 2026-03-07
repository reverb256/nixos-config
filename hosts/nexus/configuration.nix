# Nexus Host Configuration - Build and Backup Node
# 10.1.1.120 - 24 cores, 2x RTX 3060 Ti
# Features: Gaming + VR, MCP Servers
#
# Module imports: Gaming, mining, monitoring, opencode are already imported
# via commonModules in flake.nix (./modules/default.nix)
{pkgs, ...}: {
  imports = [
    # Monitoring configuration
    ./monitoring.nix
    # Hardware configuration (generated)
    ./hardware-configuration.nix

    # Common host imports (desktop, gaming, networking, etc.)
    ../../modules/common-host.nix

    # NVIDIA GPU support (common + wayland-specific)
    ../../modules/hardware/nvidia-common.nix
    ../../modules/hardware/nvidia-wayland.nix

    # Nexus-specific modules
    ../../modules/services/mcp-servers.nix
    ../../modules/security/aistor-secrets.nix
    ../../modules/services/podman-support.nix
  ];

  # ============================================================================
  # HOST IDENTIFICATION
  # ============================================================================
  networking.hostName = "nexus";

  # ============================================================================
  # HARDWARE PROFILES
  # ============================================================================
  hardware.profiles = {
    nvidia.enable = true;  # NVIDIA GPU support
    nvidia.multiGpu = true;  # 2x RTX 3060 Ti
    monitoring.enable = true;  # Hardware monitoring
  };

  # Hardware monitoring extras (not covered by profile)
  hardware.monitoring.autoDetect = true; # Auto-detect sensor chips
  hardware.monitoring.fanControl = false; # BIOS fan control for now

  # ============================================================================
  # STORAGE CONFIGURATION
  # ============================================================================
  # Nexus has additional storage beyond the root filesystem:
  # - nvme1n1 (223.6GB) - "worn-storage" for high-write workloads
  # - bcache0 (3.6TB + 465GB cache) - "nexus-storage" with organized subvolumes

  # Mount worn-storage (worn NVMe - suitable for high-write workloads)
  fileSystems."/data/worn" = {
    device = "/dev/disk/by-uuid/2056c7e4-cd6c-4a67-9b3d-001178a70eaa";
    fsType = "btrfs";
    options = ["compress=zstd" "ssd" "discard=async"];
  };

  # Mount nexus-storage subvolumes (large bcache device)
  fileSystems."/data/home" = {
    device = "/dev/disk/by-uuid/08cbb21c-adb0-4e3c-928f-7b6d1fa2d236";
    fsType = "btrfs";
    options = ["subvol=home" "compress=zstd" "ssd" "discard=async"];
  };

  fileSystems."/data/shared" = {
    device = "/dev/disk/by-uuid/08cbb21c-adb0-4e3c-928f-7b6d1fa2d236";
    fsType = "btrfs";
    options = ["subvol=shared" "compress=zstd" "ssd" "discard=async"];
  };

  fileSystems."/data/backups" = {
    device = "/dev/disk/by-uuid/08cbb21c-adb0-4e3c-928f-7b6d1fa2d236";
    fsType = "btrfs";
    options = ["subvol=backups" "compress=zstd" "ssd" "discard=async"];
  };

  fileSystems."/data/media" = {
    device = "/dev/disk/by-uuid/08cbb21c-adb0-4e3c-928f-7b6d1fa2d236";
    fsType = "btrfs";
    options = ["subvol=media" "compress=zstd" "ssd" "discard=async"];
  };

  fileSystems."/var/lib/containers" = {
    device = "/dev/disk/by-uuid/08cbb21c-adb0-4e3c-928f-7b6d1fa2d236";
    fsType = "btrfs";
    options = ["subvol=containers" "compress=zstd" "ssd" "discard=async"];
  };

  # ============================================================================
  # BOOTLOADER
  # ============================================================================
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # ============================================================================
  # ROLE PROFILES
  # ============================================================================
  profiles.role = {
    gaming = true;  # Steam, Lutris, etc.
    vr = true;  # WiVRn, SteamVR, OpenXR
    mining = true;  # GPU/CPU mining
  };

  # Note: profiles.role.gaming enables services.gaming automatically

  # ============================================================================
  # NETWORK PROFILES
  # ============================================================================
  profiles.network.tailscale.enable = true;

  # Spotify with SpotX patch (ad-free, premium features)
  services.spotify-spotx.enable = true;

  # ============================================================================
  # NETWORKING
  # ============================================================================
  networking = {
    networkmanager = {
      enable = true;
      ensureProfiles.profiles."Wired connection 1" = {
        connection = {
          id = "Wired connection 1";
          type = "ethernet";
          interface-name = "enp7s0";
          autoconnect = true;
        };
        ipv4 = {
          method = "manual";
          address1 = "10.1.1.120/24";
          gateway = "10.1.1.1";
          dns = "127.0.0.1,::1";
        };
        ipv6.method = "auto";
      };
    };

    firewall = {
      allowedTCPPorts = [22 9757 18789 18790];  # Added SSH port 22
      allowedUDPPorts = [9757 9758 9759];
      interfaces."tailscale0".allowedTCPPorts = [18789 18790];
    };
  };

  # ============================================================================
  # KERNEL - Zen for better desktop responsiveness
  # ============================================================================
  boot.kernelPackages = pkgs.linuxPackages_zen;

  # ============================================================================
  # NVIDIA CONFIGURATION
  # Note: Base config is in nvidia-common.nix
  # ============================================================================
  # Nexus-specific kernel params (appended after nvidia-common.nix defaults)
  # No additional params needed beyond nvidia-common.nix defaults

  # ============================================================================
  # SERVICES
  # ============================================================================
  services = {
    xserver.videoDrivers = ["nvidia"];

    garnix.enable = false;
    nixos-auto-update.enable = true;

    # Mining configuration
    # Uses defaults from mining.nix for pool URLs and wallet format
    # Note: profiles.role.mining enables services.mining automatically
    mining = {
      xmrig = {
        enable = true;
        autostart = true;
        threads = 12;
      };
      lolminer = {
        enable = true;
        nvidia = {
          enable = true;
          autostart = true;
          devices = "0,1";
          powerLimit = 130;
        };
      };
    };

    # Note: tailscale now enabled via profiles.network.tailscale.enable

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
