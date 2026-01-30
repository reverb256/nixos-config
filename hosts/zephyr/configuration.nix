# Zephyr Host Configuration - MINIMAL NVIDIA + Wayland
# 10.1.1.110 - Master Workstation (32 cores, RTX 3090)
{
  pkgs,
  lib,
  config,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    ../../modules/desktop.nix
    ../../modules/nvidia-wayland.nix
    # REMOVED: ../../modules/steam-wayland-robust.nix - using minimal Steam in home.nix
    # REMOVED: ../../modules/openagents-control.nix - not needed for minimal config
  ];

  # Host identification
  networking.hostName = "zephyr";

  # ============================================================================
  # MINIMAL NVIDIA CONFIGURATION - RTX 3090
  # ============================================================================
  # Absolute minimum required for NVIDIA + Wayland + Plasma 6
  # Based on https://wiki.nixos.org/wiki/NVIDIA

  # Enable NVIDIA driver (ZEN kernel optimized)
  services.xserver.videoDrivers = ["nvidia"];

  # Use ZEN-specific NVIDIA driver package for better performance
  hardware.nvidia.package = config.boot.kernelPackages.nvidiaPackages.stable;

  # NVIDIA Wayland support (via nvidia-wayland module)
  hardware.nvidia.wayland = {
    enable = true;
    openModules = true;
    sddmWayland = true;
  };

  # ============================================================================
  # MINIMAL STEAM CONFIGURATION
  # ============================================================================
  programs.steam.enable = true;

  # ============================================================================
  # DISPLAY MANAGER - SDDM with Wayland support
  # ============================================================================
  # Required for SDDM (can be minimal, just for display manager)
  services.xserver.enable = true;

  services.displayManager = {
    sddm = {
      enable = true;
      wayland.enable = false;  # WORKAROUND: Use X11 for greeter (Wayland greeter crashes on NVIDIA)
    };
    defaultSession = "plasma";
    autoLogin = {
      enable = true;
      user = "j_kro";
    };
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
  users.users.j_kro.extraGroups = ["plugdev" "audio" "input"];

  # ============================================================================
  # OPENCLAW + OLLAMA - AI Assistant with Local LLMs
  # ============================================================================
  # DISABLED: OpenClaw module has upstream bugs (agent attribute missing)
  # programs.openclaw = {
  #   enable = true;
  #   model = "llama3.2:3b";
  # };

  services.ollama = {
    enable = true;
    package = pkgs.ollama-cuda;  # Use NVIDIA RTX 3090 CUDA acceleration
    environmentVariables = {
      OLLAMA_KEEP_ALIVE = "24h";
    };
  };

  # ============================================================================
  # OPENAGENTS CONTROL
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
