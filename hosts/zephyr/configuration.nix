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
    # Import Garnix cache configuration
    ../../modules/garnix.nix
    # Import OpenClaw (container-based - avoids pnpm/hasown issues)
    ../../modules/openclaw-container.nix
    # Import Tailscale
    ../../modules/tailscale.nix
    # Import LM Studio Docker
    ../../modules/lmstudio-docker.nix
    # Import AIStor secrets generation
    ../../modules/aistor-secrets.nix
    # Import nix-ld for dynamically linked executables (Proton/Steam support)
    ../../modules/nix-ld.nix
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

  # CRITICAL: Kernel parameters for NVIDIA Wayland + Proton support
  # nvidia_drm.modeset=1 - Required for Wayland support
  # nvidia_drm.fbdev=1 - Required for proper display initialization
  boot.kernelParams = [ 
    "nvidia_drm.modeset=1"
    "nvidia_drm.fbdev=1"
    "nvidia.NVreg_PreserveVideoMemoryAllocations=1"
    
    # === PERFORMANCE ENHANCING ===
    # Disable split lock detection (prevents performance penalties)
    "split_lock_detect=off"
    
    # Enable resizable BAR for better GPU performance
    "nvidia.NVreg_EnableResizableBar=1"
    
    # Enable GPU firmware
    "nvidia.NVreg_EnableGpuFirmware=1"
    
    # Threaded IRQs for better responsiveness
    "threadirqs"
    
    # Full kernel preemption for better gaming responsiveness
    "preempt=full"
    
    # Disable CPU idle deep states for lower latency (better for gaming)
    "processor.max_cstate=1"
    "intel_idle.max_cstate=1"
    
    # IOMMU for better device isolation (helps with GPU passthrough if ever needed)
    "iommu=pt"
  ];

  # NVIDIA power management (helps with VRAM issues on 555+ drivers)
  hardware.nvidia.powerManagement.enable = true;
  hardware.nvidia.powerManagement.finegrained = false;

  # ============================================================================
  # STEAM + GAMING CONFIGURATION
  # ============================================================================
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true;
  };

  # GameMode for performance optimization
  programs.gamemode.enable = true;

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
  # GARNIX - CI/CD Cache for faster builds
  # ============================================================================
  services.garnix = {
    enable = true;
  };

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
  # OPENCLAW - AI Agent Gateway (Container-based - avoids pnpm/hasown issues)
  # ============================================================================
  services.openclaw-container = {
    enable = true;
    image = "ghcr.io/openclaw/openclaw";  # Official GitHub container registry
    tag = "latest";
    port = 18789;
    apiPort = 18790;
    stateDir = "/var/lib/openclaw";
    dataDir = "/var/lib/openclaw/data";
    configDir = "/etc/openclaw";
    runtime = "docker";  # Use docker (lmstudio-docker also uses docker)
    memory = "2g";
    cpuShares = 512;
    healthCheckInterval = 30;
    gatewayMode = "local";
    gatewayBind = "0.0.0.0";
    nginxProxy = true;
  };

  # ============================================================================
  # TAILSALE - Secure mesh VPN
  # ============================================================================
  services.tailscale-custom = {
    enable = true;
    useRoutingFeatures = "client";
  };

  # ============================================================================
  # LM STUDIO - Desktop LLM Interface (GUI only)
  # ============================================================================
  services.lmstudio-docker = {
    enable = true;
    daemonPort = 1234;
    modelsDir = "/home/j_kro/.local/share/lm-studio/models";
    dataDir = "/home/j_kro/.local/share/lm-studio/data";
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
