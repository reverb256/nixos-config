# Nexus Host Configuration - Build and Backup Node
# 10.1.1.120 - 24 cores, 2x RTX 3060 Ti
# Features: Gaming + VR, MCP Servers
{pkgs, ...}: {
  imports = [
    # Monitoring configuration
    ./monitoring.nix
    # Hardware configuration (generated)
    ./hardware-configuration.nix

    # Common host imports (desktop, gaming, networking, etc.)
    ../../modules/common-host.nix

    # Gaming support
    ../../modules/gaming/gaming.nix

    # Mining support
    ../../modules/mining/mining.nix

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

  # NVIDIA GPU support (2x RTX 3060 Ti)
  hardware.nvidia-common.enable = true;

  # ============================================================================
  # BOOTLOADER
  # ============================================================================
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # ============================================================================
  # GAMING + VR (Full support - 2x RTX 3060 Ti)
  # ============================================================================
  services.gaming = {
    enable = true;
    vr.enable = true; # WiVRn, SteamVR, OpenXR
  };

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
      allowedTCPPorts = [9757 18789 18790];
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
    mining = {
      enable = true;
      xmrig = {
        enable = true;
        threads = 12;
      };
      lolminer = {
        enable = true;
        nvidia = {
          enable = true;
          devices = "0,1";
          powerLimit = 130;
        };
      };
    };

    tailscale.enable = true;

    mcp-servers = {
      enable = true;
      servers.playwright.enable = true;
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
