# Zephyr Host Configuration - Steam + Wayland Optimized
# 10.1.1.110 - Master Workstation (32 cores, RTX 3090) - Steam Compatible
{pkgs, lib, config, ...}: {
  imports = [
    ./hardware-configuration.nix
    ../../modules/desktop.nix
    ../../modules/steam-wayland-robust.nix
    ../../modules/openagents-control.nix
    ../../modules/nvidia-wayland.nix
  ];

  # Host identification
  networking.hostName = "zephyr";

  # ============================================================================
  # NVIDIA CONFIGURATION - RTX 3090 (Beta drivers for latest features)
  # ============================================================================
  hardware.nvidia = {
    package = pkgs.linuxPackages_zen.nvidiaPackages.beta;
    # Required for Wayland
    modesetting.enable = true;
    nvidiaSettings = true;
    powerManagement.enable = true;
  };

  # Enable NVIDIA Wayland optimizations (module handles most settings)
  hardware.nvidia.wayland = {
    enable = true;
    enable32Bit = true;
    openModules = true;  # Use open-source kernel modules with proprietary userspace
    powerManagement = true;
    sddmWayland = true;
  };

  # CRITICAL: Build NVIDIA kernel modules (required even for pure Wayland)
  boot.extraModulePackages = [ pkgs.linuxPackages_zen.nvidiaPackages.beta ];
  
  # Load NVIDIA modules early
  boot.initrd.kernelModules = [ "nvidia" "nvidia_modeset" "nvidia_drm" ];

  # Additional Zephyr-specific graphics packages
  hardware.graphics.extraPackages = with pkgs; [
    nvidia-vaapi-driver
    libva
    libva-utils
    egl-wayland
  ];

  hardware.graphics.extraPackages32 = with pkgs.pkgsi686Linux; [
    nvidia-vaapi-driver
  ];

  # ============================================================================
  # DISPLAY MANAGER - SDDM with Wayland support
  # ============================================================================
  services.displayManager = {
    sddm.enable = true;
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
  # MOLT.BOT AI AGENT (LOCAL ONLY)
  # ============================================================================
  services.moltbot = {
    enable = true;
    backend = "lmstudio";
    localApiUrl = "http://127.0.0.1:1234/v1";  # LM Studio OpenAI-compatible API
    localApiKey = "lm-studio-local";  # Any non-empty string works for LM Studio
    model = "Qwen2.5-32B-Instruct";  # Load this in LM Studio first
    port = 18789;
    stateDir = "/var/lib/moltbot";  # Absolute path for systemd
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

  # ============================================================================
  # ZEPHYR-SPECIFIC ENVIRONMENT VARIABLES
  # Additional variables beyond what nvidia-wayland.nix provides
  # ============================================================================
  environment.sessionVariables = {
    # CUDA path for ML/AI workloads - use cuda_cudart for actual library path
    # Note: cudatoolkit is a wrapper, cuda_cudart contains the actual runtime libs
    CUDA_PATH = "${pkgs.cudaPackages.cuda_cudart}";

    # LD_LIBRARY_PATH for dynamically linked CUDA applications (LM Studio, AppImages)
    # Uses lib.mkDefault to allow other modules to extend it
    LD_LIBRARY_PATH = lib.mkDefault "/run/opengl-driver/lib:${pkgs.cudaPackages.cuda_cudart}/lib:${pkgs.cudaPackages.cudnn}/lib";

    # Disable G-SYNC to prevent buffer issues
    __GL_GSYNC_ALLOWED = "0";

    # Disable VRR for stability (can re-enable later)
    __GL_VRR_ALLOWED = "0";

    # Additional variables for NVIDIA EGL and NVENC
    NVD_BACKEND = "direct";
    __NV_PRIME_RENDER_OFFLOAD = "1";
  };
}
