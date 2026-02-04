# Forge Host Configuration
# 10.1.1.130 - GPU Mining Rig (6 cores, 2x RTX 4060 + 2x RX 5700 XT)
{
  lib,
  pkgs,
  inputs,
  ...
}: {
  imports = [
    # Host-specific hardware
    ./hardware-configuration.nix
    # Import desktop module for Plasma 6
    ../../modules/desktop.nix
    # Import NVIDIA Wayland module (best practices)
    ../../modules/nvidia-wayland.nix
    # Import OpenClaw AI agent orchestration (declarative container)
    ../../modules/openclaw-declarative-container.nix
    # Import OpenClaw common configuration
    ../../modules/openclaw-common.nix
    # Import Tailscale mesh VPN
    ../../modules/tailscale.nix
    # Import CI/CD and auto-update modules
    ../../modules/garnix.nix
    ../../modules/auto-update.nix
  ];

  # Host identification
  networking.hostName = "forge";

  # Enable CI/CD features
  services.garnix.enable = true;
  services.nixos-auto-update.enable = true;

  # Multi-kernel support: Zen primary kernel
  boot.kernelPackages = pkgs.linuxPackages_zen;

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
  # GPU DRIVERS (AMD & NVIDIA) - Consistent with main configuration
  # ============================================================================
  hardware.amdgpu = {
    opencl.enable = true;
  };

  # Ensure AMDGPU kernel modules are loaded
  boot.kernelModules = [
    "amdgpu"
    "tun" # Required for Tailscale VPN
  ];

  # Add AMDGPU to initrd modules for early loading
  boot.initrd.kernelModules = [
    "amdgpu"
  ];

  # NVIDIA configuration for RTX 4060s (use proprietary beta drivers with ZEN kernel)
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
    LD_LIBRARY_PATH = lib.mkForce "${pkgs.rocmPackages.clr}/lib:${pkgs.rocmPackages.clr.icd}/lib:${pkgs.mesa.opencl}/lib";
    OCL_ICD_VENDORS = "/etc/OpenCL/vendors";
  };

  # ============================================================================
  # MINING CONFIGURATION (Forge: 6 cores, 2x RTX 4060 + 2x RX 5700 XT)
  # ============================================================================
  services.mining.enable = true;
  services.mining.xmrig.enable = true;
  services.mining.xmrig.threads = 6;
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
    "c /dev/net/tun 666 root root - - - -" # TUN device for Tailscale VPN
    "L+ /opt/rocm - - - - ${rocmEnv}"
    "L+ /opt/rocm/hip - - - - ${pkgs.rocmPackages.clr}"
  ];

  # AMD GPU detection and health monitoring
  systemd.services."amd-gpu-check" = {
    description = "AMD GPU Detection and Health Check";
    wantedBy = ["multi-user.target"];
    after = ["basic.target"];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash -c 'PATH=/run/current-system/sw/bin:$PATH /run/wrappers/bin/sudo rocminfo 2>/dev/null || echo \"AMD GPU detection failed\"'";
      RemainAfterExit = true;
    };
  };

  # AMD GPU info service for debugging
  systemd.services."amd-gpu-info" = {
    description = "AMD GPU Information Service";
    wantedBy = ["multi-user.target"];
    after = ["basic.target"];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash -c 'PATH=/run/current-system/sw/bin:$PATH /run/wrappers/bin/sudo rocminfo > /tmp/amd-gpu-info.log 2>&1 || lspci -v | grep -i amd > /tmp/amd-gpu-info.log 2>&1'";
      RemainAfterExit = true;
    };
  };

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
  # SYSTEMD SLICES - Optimized for mining performance
  # ============================================================================
  systemd.slices.mining = {
    description = "Mining Services Slice";
    sliceConfig = {
      CPUAccounting = true;
      CPUQuota = "95%"; # Allow mining to use up to 95% of CPU when needed
      MemoryAccounting = true;
      MemoryHigh = "8G"; # High limit before throttling
      MemoryMax = "12G"; # Hard limit before OOM
      IOAccounting = true;
      IOWeight = 10; # Lower priority than system services
      TasksAccounting = true;
      TasksMax = 100; # Limit concurrent mining tasks
      BlockIOAccounting = true;
    };
  };

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
  # OLLAMA - Local LLMs
  # ============================================================================
  services.ollama = {
    enable = true;
    package = pkgs.ollama-cuda; # Use NVIDIA RTX 4060
    environmentVariables = {
      OLLAMA_KEEP_ALIVE = "24h";
    };
  };

  # ============================================================================
  # OPENCLAW - AI Agent Gateway (declarative container)
  # ============================================================================
  services.openclaw.declarative = {
    enable = true;
    image = "ghcr.io/openclaw/openclaw:latest";
    port = 18789;
    apiPort = 18790;
    stateDir = "/var/lib/openclaw";
    dataDir = "/var/lib/openclaw/data";
    configDir = "/etc/openclaw";
    memory = "2G";
    cpuShares = 512;
    gatewayMode = "local";
    gatewayBind = "127.0.0.1"; # Bind to localhost only for security
    environmentFile = "/run/agenix/openclaw-env";
    enableLegacyEnv = true;
  };

  # ============================================================================
  # FIREWALL (Minimal - no VR ports on mining rig)
  # ============================================================================

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [];
    allowedUDPPorts = [];
  };

  # ============================================================================
  # TAILSCALE - Secure mesh VPN (using standard nixpkgs module)
  # ============================================================================
  services.tailscale = {
    enable = true;
  };

  # Routing features configured via tailscaled environment
  systemd.services.tailscaled.environment = {
    TS_ADVERTISE_ROUTES = "10.1.1.0/24";
    TS_ROUTES = "";
    TS_SSH = "true";
  };
}
