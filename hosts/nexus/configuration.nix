# Nexus Configuration - Build and Backup Node
# 10.1.1.120 - 24 cores, 2x RTX 3060 Ti

{pkgs, ...}: {
  imports = [
    ./hardware-configuration.nix
    ../../modules/desktop.nix
    ../../modules/fish-starship.nix
    ../../modules/gaming.nix
    ../../modules/nvidia-wayland.nix
    ../../modules/garnix.nix
    ../../modules/networking.nix
    ../../modules/tailscale.nix
    ../../modules/aistor-secrets.nix
    ../../modules/mcp-servers.nix
    ../../modules/mining.nix
    ../../modules/auto-update.nix
    ../../modules/ssh.nix
    ../../modules/distributed-builds.nix
    ../../modules/storage-btrfs.nix
    ../../modules/mining-build-wrapper.nix
    # ../../modules/quadlet-openclaw-simple.nix  # Disabled - module options not properly defined
  ];

  networking = {
    hostName = "nexus";
    networkmanager.enable = true;

    networkmanager.ensureProfiles = {
      profiles."Wired connection 1" = {
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

    hosts = {
      "10.1.1.110" = ["zephyr"];
      "10.1.1.120" = ["nexus"];
      "10.1.1.130" = ["forge"];
      "10.1.1.140" = ["sentry"];
    };

    firewall = {
      allowedTCPPorts = [9757 18789 18790];
      allowedUDPPorts = [9757 9758 9759];
      interfaces."tailscale0".allowedTCPPorts = [18789 18790];
    };
  };

  hardware.nvidia = {
    package = pkgs.linuxPackages_zen.nvidiaPackages.stable;

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

  systemd = {
    services = {
      display-manager.restartIfChanged = false;
      sddm.restartIfChanged = false;
    };

    oomd.enable = true;
    coredump.enable = true;
  };

  users.users.j_kro.extraGroups = ["plugdev" "audio" "input" "docker" "openrazer" "tailscale"];

  # ============================================================================
  # TAILSCALE - Secure mesh VPN
  # ============================================================================
  systemd.services.tailscaled.environment = {
    TS_ADVERTISE_ROUTES = "";
    TS_ROUTES = "";
    TS_SSH = "true";
  };

  system.stateVersion = "26.05";
}
