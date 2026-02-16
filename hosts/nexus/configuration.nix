# Nexus Host Configuration - Build and Backup Node
# 10.1.1.120 - 24 cores, 2x RTX 3060 Ti
# Features: Gaming + VR, MCP Servers
{
  config,
  pkgs,
  ...
}: {
  imports = [
    # Hardware configuration (generated)
    ./hardware-configuration.nix

    # Common host imports (desktop, gaming, networking, etc.)
    ../../modules/common-host.nix

    # Host-specific GPU support
    ../../modules/nvidia-wayland.nix

    # Nexus-specific modules
    ../../modules/mcp-servers.nix
    ../../modules/aistor-secrets.nix
  ];

  # ============================================================================
  # HOST IDENTIFICATION
  # ============================================================================
  networking.hostName = "nexus";

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
          interface-name = "enp5s0";
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
  # KERNEL - CachyOS x86_64-v3 for gaming (Zen 2 architecture)
  # ============================================================================
  boot.kernelPackages = pkgs.cachyosKernels.linuxPackages-cachyos-latest-x86_64-v3;

  # ============================================================================
  # NVIDIA CONFIGURATION
  # ============================================================================
  hardware.nvidia = {
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    wayland = {
      enable = true;
      openModules = true;
      sddmWayland = true;
    };
    powerManagement.enable = true;
    powerManagement.finegrained = false;
  };

  boot.kernelParams = [
    "nvidia_drm.modeset=1"
    "nvidia_drm.fbdev=1"
    "nvidia.NVreg_PreserveVideoMemoryAllocations=1"
    "nvidia.NVreg_EnableResizableBar=1"
    "nvidia.NVreg_EnableGpuFirmware=1"
  ];

  # ============================================================================
  # DISPLAY MANAGER
  # ============================================================================
  services = {
    xserver.videoDrivers = ["nvidia"];

    displayManager = {
      sddm = {
        enable = true;
        wayland.enable = true;
      };
      defaultSession = "plasma";
      autoLogin = {
        enable = true;
        user = "j_kro";
      };
    };

    logind.settings.Login.KillUserProcesses = false;

    garnix.enable = false;
    nixos-auto-update.enable = true;

    # Mining configuration
    mining = {
      enable = true;
      user = "mining";
      xmrig = {
        enable = true;
        threads = 12;
        pool = "xtm-rx-us.kryptex.network:8038";
        wallet = "krxXVNVMM7.nexus";
      };
      lolminer = {
        enable = true;
        algorithm = "CR29";
        pool = "stratum+ssl://xtm-c29-us.kryptex.network:8040";
        nvidia = {
          enable = true;
          devices = "0,1";
          powerLimit = 120;
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
  users.users.j_kro.extraGroups = ["plugdev" "audio" "input" "docker" "openrazer" "tailscale"];

  system.stateVersion = "26.05";
}
