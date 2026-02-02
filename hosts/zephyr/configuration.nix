# Zephyr Host Configuration - MINIMAL NVIDIA + Wayland
# 10.1.1.110 - Master Workstation (32 cores, RTX 3090)
{
  pkgs,
  config,
  inputs,
  ...
}: {
  imports = [
    # Host-specific hardware
    ./hardware-configuration.nix
    # Import desktop module for Plasma 6
    ../../modules/desktop.nix
    # Import gaming module
    ../../modules/gaming.nix
    # Import NVIDIA Wayland module (best practices)
    ../../modules/nvidia-wayland.nix
    # Import OpenClaw AI agent orchestration
    ../../modules/openclaw.nix
    # Import OpenClaw common configuration
    ../../modules/openclaw-common.nix
    # Import AIStor secrets generation
    ../../modules/aistor-secrets.nix
    inputs.nixpkgs-xr.nixosModules.nixpkgs-xr
  ];

  # Host identification
  networking.hostName = "zephyr";

  # ============================================================================
  # NVIDIA CONFIGURATION - RTX 3090 Optimized for Gaming/Wayland/Plasma 6
  # ============================================================================
  # Based on NixOS Wiki and NVIDIA best practices as of 2025
  # Reference: https://wiki.nixos.org/wiki/NVIDIA

  # Enable NVIDIA driver
  services.xserver.videoDrivers = ["nvidia"];

  # Use stable driver - beta driver causing black screen issues
  hardware.nvidia.package = config.boot.kernelPackages.nvidiaPackages.stable;

  # NVIDIA Wayland support (via nvidia-wayland module)
  hardware.nvidia.wayland = {
    enable = true;
    openModules = true; # Use open kernel modules with proprietary userspace (standard across all nodes)
    sddmWayland = true;
  };

  # ============================================================================
  # STEAM + GAMING CONFIGURATION (via steam-wayland-robust module)
  # ============================================================================
  services.steamWayland = {
    enable = true;
    protonVersion = "GE-Proton9-25";
  };

  # ============================================================================
  # DISPLAY MANAGER - SDDM with Wayland (Pure Wayland, no X11)
  # ============================================================================
  # Modern NixOS: services.displayManager replaces services.xserver
  # SDDM runs in Wayland mode, Plasma 6 uses native Wayland
  # No services.xserver.enable needed for pure Wayland setups
  services.displayManager = {
    sddm = {
      enable = true; # REQUIRED: Actually enables SDDM service
      wayland.enable = true; # SDDM runs in Wayland mode (not X11)
    };
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
  # This is critical for Plasma 6 Wayland session persistence
  services.logind.settings.Login.KillUserProcesses = false;

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
  users.users.j_kro.extraGroups = ["plugdev" "audio" "input" "docker"];

  # ============================================================================
  # VIRTUALISATION - Docker
  # ============================================================================
  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
  };

  # Install docker-compose for container management
  environment.systemPackages = with pkgs; [
    docker-compose
  ];

  # ============================================================================
  # OLLAMA - Local LLMs
  # ============================================================================
  services.ollama = {
    enable = true;
    package = pkgs.ollama-cuda; # Use NVIDIA RTX 3090 CUDA acceleration
    environmentVariables = {
      OLLAMA_KEEP_ALIVE = "24h";
    };
  };

  # ============================================================================
  # MCP SERVERS - Browser automation and AI assistant tools
  # ============================================================================
  # TODO: services.mcp-servers module missing - temporarily disabled
  # services.mcp-servers = {
  #   enable = true;
  #   servers.playwright.enable = true;
  # };
}
