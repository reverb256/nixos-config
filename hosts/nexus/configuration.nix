# Nexus Host Configuration
# 10.1.1.120 - Build Server (24 cores, 2x RTX 3060 Ti)
{pkgs, ...}: {
  imports = [
    # Host-specific hardware
    ./hardware-configuration.nix
    # Import desktop module for Plasma 6
    ../../modules/desktop.nix
    # Import gaming module
    ../../modules/gaming.nix
    # Import NVIDIA Wayland module (best practices)
    ../../modules/nvidia-wayland.nix
    # Import OpenClaw common configuration
    ../../modules/openclaw-common.nix
  ];

  # Host identification
  networking.hostName = "nexus";

  # ============================================================================
  # NVIDIA WAYLAND CONFIGURATION (RTX 3060 Ti)
  # ============================================================================
  hardware.nvidia = {
    package = pkgs.linuxPackages_zen.nvidiaPackages.stable;
  };

  # Enable NVIDIA Wayland optimizations
  hardware.nvidia.wayland = {
    enable = true;
    enable32Bit = true;
    openModules = true; # Use open-source kernel modules with proprietary userspace
    powerManagement = true;
    sddmWayland = true;
  };

  # Legacy X11 video driver setting (kept for compatibility)
  services.xserver.videoDrivers = ["nvidia"];

  services.displayManager = {
    sddm.enable = true;
    defaultSession = "plasma";
    autoLogin = {
      enable = true;
      user = "j_kro";
    };
  };

  # ============================================================================
  # PREVENT PLASMA SESSION KILL DURING REBUILD
  # ============================================================================
  # Stop display-manager from restarting during nixos-rebuild switch
  # This prevents Plasma 6 Wayland session termination on configuration changes
  systemd.services.display-manager.restartIfChanged = false;
  systemd.services.sddm.restartIfChanged = false;

  # Prevent systemd-logind from killing user processes during session changes
  services.logind.settings.Login.KillUserProcesses = false;

  # ============================================================================
  # MINING CONFIGURATION (Nexus: 24 cores, 2x RTX 3060 Ti)
  # ============================================================================
  services.mining.enable = true;
  services.mining.xmrig.enable = true;
  services.mining.xmrig.threads = 16;
  services.mining.lolminer.enable = true;
  services.mining.lolminer.nvidia.enable = true;
  services.mining.lolminer.nvidia.devices = "0";
  services.mining.lolminer.algorithm = "CR29";
  services.mining.lolminer.pool = "stratum+ssl://xtm-c29-us.kryptex.network:8040";
  services.mining.lolminer.wallet = "krxXVNVMM7.nexus";

  # ============================================================================
  # NETWORKING (Static IP via NetworkManager - required for desktop environment)
  # ============================================================================

  # Configure NetworkManager for static IP (desktop environment requires NetworkManager)
  networking.networkmanager = {
    enable = true;
    unmanaged = []; # Let NetworkManager manage all interfaces
    ensureProfiles.profiles."enp7s0" = {
      connection = {
        id = "enp7s0";
        type = "ethernet";
        interface-name = "enp7s0";
      };
      ipv4 = {
        method = "manual";
        address1 = "10.1.1.120/24";
        gateway = "10.1.1.1";
        dns = "127.0.0.1,::1"; # Use local Unbound DNS
      };
    };
  };

  networking.dhcpcd.enable = false;
  networking.useDHCP = false;

  # ============================================================================
  # LOCAL HOSTS ENTRIES
  # ============================================================================

  networking.hosts = {
    "10.1.1.110" = ["zephyr"];
    "10.1.1.120" = ["nexus"];
    "10.1.1.130" = ["forge"];
    "10.1.1.140" = ["sentry"];
  };

  # ============================================================================
  # OLLAMA - Local LLMs
  # ============================================================================
  services.ollama = {
    enable = true;
    package = pkgs.ollama-cuda; # Use NVIDIA RTX 3060 Ti
    environmentVariables = {
      OLLAMA_KEEP_ALIVE = "24h";
    };
  };

  # ============================================================================
  # OPENCLAW - AI Agent Gateway
  # ============================================================================
  services.openclaw = {
    enable = true;
    common = {
      enable = true; # Use common configuration for all nodes
    };
    # Let OpenClaw handle model configuration via its auth system
    settings = {};
  };

  # ============================================================================
  # FIREWALL (Base config - no extra ports)
  # ============================================================================

  networking.firewall = {
    allowedTCPPorts = [];
    allowedUDPPorts = [];
  };
}
