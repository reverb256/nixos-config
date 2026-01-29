# Zephyr Host Configuration - Steam + Wayland Optimized
# 10.1.1.110 - Master Workstation (32 cores, RTX 3090) - Steam Compatible
{pkgs, ...}: {
  imports = [
    ./hardware-configuration.nix
    ../../modules/desktop.nix
    ../../modules/steam-wayland-robust.nix
    ../../modules/openagents-control.nix
  ];

  # Host identification
  networking.hostName = "zephyr";

  # ============================================================================
  # NVIDIA CONFIGURATION - RTX 3090 (consolidated here, removed from main config)
  # ============================================================================
  hardware.nvidia = {
    package = pkgs.linuxPackages_zen.nvidiaPackages.beta;
    modesetting.enable = true;
    open = false;
    nvidiaSettings = true;
    powerManagement.enable = true;
  };

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages = with pkgs; [
      nvidia-vaapi-driver
    ];
  };

  # ============================================================================
  # DISPLAY MANAGER - SDDM with Wayland support
  # ============================================================================
  services.displayManager = {
    sddm.enable = true;
    sddm.wayland.enable = true;
    defaultSession = "plasma";
    autoLogin = {
      enable = true;
      user = "j_kro";
    };
  };

  # ============================================================================
  # HOME MANAGER CONFIGURATION
  # ============================================================================
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    users.j_kro = {pkgs, ...}: {
      imports = [
        ../../modules/fish-starship.nix
      ];

      home = {
        username = "j_kro";
        homeDirectory = "/home/j_kro";
        stateVersion = "26.05";
      };

      programs = {
        home-manager.enable = true;
        fish.enable = true;
      };

      xdg = {
        enable = true;
        userDirs.enable = true;
      };
    };
  };

  # ============================================================================
  # BOOTLOADER
  # ============================================================================
  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  # ============================================================================
  # MINING CONFIGURATION
  # ============================================================================
  services.mining = {
    enable = true;
    xmrig = {
      enable = true;
      threads = 16;
      pool = "xtm-rx-us.kryptex.network:8038";
      wallet = "krxXVNVMM7.zephyr";
    };
    lolminer = {
      enable = true;
      algorithm = "CR29";
      pool = "stratum+ssl://xtm-c29-us.kryptex.network:8040";
      wallet = "krxXVNVMM7.zephyr";
      nvidia = {
        enable = true;
        devices = "0";
      };
    };
  };

  # ============================================================================
  # NETWORKING (Static IP)
  # ============================================================================
  networking.networkmanager.ensureProfiles = {
    profiles."Wired connection 1" = {
      connection = {
        id = "Wired connection 1";
        type = "ethernet";
        interface-name = "enp38s0";
        autoconnect = true;
      };
      ipv4 = {
        method = "manual";
        address1 = "10.1.1.110/24";
        gateway = "10.1.1.1";
        dns = "127.0.0.1,::1";
      };
      ipv6.method = "auto";
    };
  };

  networking.hosts = {
    "10.1.1.110" = ["zephyr"];
    "10.1.1.120" = ["nexus"];
    "10.1.1.130" = ["forge"];
    "10.1.1.140" = ["sentry"];
  };

  # ============================================================================
  # USER GROUPS
  # ============================================================================
  users.users.j_kro.extraGroups = ["plugdev"];

  # ============================================================================
  # OPENAGENTS CONTROL
  # ============================================================================
  services.openagents-control = {
    enable = true;
    installProfile = "advanced";
    installDir = "$HOME/.config/opencode";
    autoUpdate = false;
  };

  # ============================================================================
  # FIREWALL
  # ============================================================================
  networking.firewall = {
    allowedTCPPorts = [9757];
    allowedUDPPorts = [
      9757
      9758
      9759
      27031
      27036
    ];
  };
}
