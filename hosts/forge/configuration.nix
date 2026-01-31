# Forge Host Configuration
# 10.1.1.130 - GPU Mining Rig (6 cores, 2x RTX 4060 + 2x RX 5700 XT)
{
  lib,
  pkgs,
  ...
}: {
  imports = [
    # Host-specific hardware
    ./hardware-configuration.nix
    # Import desktop module for Plasma 6
    ../../modules/desktop.nix
    # Import NVIDIA Wayland module (best practices)
    ../../modules/nvidia-wayland.nix
    # Import OpenClaw AI assistant
    ../../modules/openclaw.nix
  ];

  # Host identification
  networking.hostName = "forge";

  # ============================================================================
  # DESKTOP ENVIRONMENT - KDE Plasma 6
  # ============================================================================

  services.xserver = {
    enable = true;
    videoDrivers = ["nvidia"];
  };

  services.displayManager = {
    sddm.enable = true;
    defaultSession = "plasma";
    autoLogin = {
      enable = true;
      user = "j_kro";
    };
  };

  # ============================================================================
  # GPU DRIVERS (AMD & NVIDIA) - Consistent with main configuration
  # ============================================================================
  hardware.amdgpu = {
    opencl.enable = true;
  };

  # NVIDIA configuration for RTX 4060s (use proprietary beta drivers with ZEN kernel)
  hardware.nvidia = {
    package = pkgs.linuxPackages_zen.nvidiaPackages.beta;
  };

  # Enable NVIDIA Wayland optimizations
  hardware.nvidia.wayland = {
    enable = true;
    enable32Bit = true;
    openModules = true; # Use open-source kernel modules with proprietary userspace
    powerManagement = true;
    sddmWayland = true;
  };

  # ============================================================================
  # KERNEL PARAMETERS
  # ============================================================================

  # Combined AMD and NVIDIA GPU kernel parameters
  boot.kernelParams = [
    # AMD GPU kernel parameters
    "amdgpu.noretry=0"
    "amdgpu.mcbp=1"

    # Enhanced NVIDIA RTX 4060 optimizations (Zen kernel compatible)
    # Note: Basic Wayland params are set by nvidia-wayland.nix module
    "nvidia.NVreg_RegistryDwords=PerfLevelSrc=0x2222"
    "nvidia.NVreg_UsePageAttributeTable=1" # Better memory management
    "nvidia.NVreg_EnableResizableBar=1" # Resizable BAR for RTX 40xx series
    "nvidia-uvm/uvm_disable_huge_pages=1" # Fix Wayland compatibility
    "threadirqs"
  ];

  environment.variables = {
    ROC_ENABLE_PRE_VEGA = "1";
  };

  # ============================================================================
  # MINING CONFIGURATION (GPU compute rig)
  # ============================================================================
  services.mining.enable = true;
  services.mining.xmrig.enable = false; # Disable CPU mining
  services.mining.lolminer.enable = true;
  services.mining.lolminer.algorithm = "CR29";
  services.mining.lolminer.pool = "stratum+ssl://xtm-c29-us.kryptex.network:8040";
  services.mining.lolminer.wallet = "krxXVNVMM7.forge";

  # NVIDIA GPUs (RTX 4060s)
  services.mining.lolminer.nvidia.enable = true;
  services.mining.lolminer.nvidia.devices = "0,1";
  services.mining.lolminer.nvidia.powerLimit = 90;
  services.mining.lolminer.nvidia.apiPort = 4068;

  # AMD GPUs (RX 5700 XTs)
  services.mining.lolminer.amd.enable = true;
  services.mining.lolminer.amd.devices = "2,3";
  services.mining.lolminer.amd.powerLimit = 140;
  services.mining.lolminer.amd.apiPort = 4069;

  # ============================================================================
  # ROCm HIP symlink for OpenCL (fixes SIGSEGV crash)
  # ============================================================================

  systemd.tmpfiles.rules = let
    rocmEnv = pkgs.symlinkJoin {
      name = "rocm-combined";
      paths = with pkgs.rocmPackages; [
        clr
        clr.icd
        rocblas
        hipblas
        rpp
      ];
    };
  in [
    "L+ /opt/rocm - - - - ${rocmEnv}"
    "L+ /opt/rocm/hip - - - - ${pkgs.rocmPackages.clr}"
  ];

  # Mesa OpenCL packages for AMD GPU mining
  environment.systemPackages = with pkgs; [
    mesa.opencl # Rusticl OpenCL implementation
  ];

  # ============================================================================
  # nix-ld for improved library access in mining services
  # ============================================================================
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    # AMD/ROCm libraries for GPU mining
    rocmPackages.clr
    rocmPackages.clr.icd
    rocmPackages.rocminfo
    rocmPackages.rocm-smi
    rocmPackages.rocm-runtime
    rocmPackages.rocblas
    rocmPackages.hipblas
    rocmPackages.hipsparse
    rocmPackages.rocfft
    rocmPackages.rocrand
    rocmPackages.rocthrust

    # OpenCL and GPU compute libraries
    ocl-icd
    opencl-headers
    clinfo

    # NVIDIA libraries (for completeness)
    libGL
    libGLU
    libglvnd
    vulkan-loader
    nvidia-vaapi-driver

    # System libraries commonly needed by mining software
    zlib
    libpng
    libjpeg
    freetype
    fontconfig
    xorg.libX11
    xorg.libXext
    xorg.libXrender
    xorg.libxcb
    xorg.libXau
    xorg.libXdmcp

    # Essential libraries for mining compatibility
    SDL2
    alsa-lib
    systemd
    libusb1
    curl
    openssl
  ];

  # ============================================================================
  # NETWORKING (Static IP via NetworkManager - required for desktop environment)
  # ============================================================================
  # Wired ethernet only - disable wireless and avahi services
  networking.wireless.enable = lib.mkForce false;
  services.avahi = lib.mkForce {
    enable = false;
    nssmdns4 = false;
    openFirewall = false;
  };

  # Configure NetworkManager for static IP (desktop environment requires NetworkManager)
  networking.networkmanager = {
    enable = true;
    unmanaged = []; # Let NetworkManager manage all interfaces
    ensureProfiles.profiles."eno1" = {
      connection = {
        id = "eno1";
        type = "ethernet";
        interface-name = "eno1";
      };
      ipv4 = {
        method = "manual";
        address1 = "10.1.1.130/24";
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
  # OPENCLAW + OLLAMA - AI Assistant with Local LLMs
  # ============================================================================
  programs.openclaw = {
    enable = true;
    nodeName = "forge";
  };

  services.ollama = {
    enable = true;
    acceleration = "cuda";  # Use NVIDIA RTX 4060
    environmentVariables = {
      OLLAMA_KEEP_ALIVE = "24h";
    };
  };

  # ============================================================================
  # FIREWALL (Minimal - no VR ports on mining rig)
  # ============================================================================

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [];
    allowedUDPPorts = [];
  };
}
