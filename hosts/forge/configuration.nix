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
  ];

  # Host identification
  networking.hostName = "forge";

  # ============================================================================
  # BOOTLOADER - systemd-boot
  # ============================================================================

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  # ============================================================================
  # DESKTOP ENVIRONMENT - KDE Plasma 6
  # ============================================================================

  services = {
    xserver.enable = true;
    displayManager = {
      sddm.enable = true;
      autoLogin = {
        enable = true;
        user = "j_kro";
      };
    };
    desktopManager.plasma6.enable = true;
  };

  # ============================================================================
  # GPU DRIVERS (AMD & NVIDIA)
  # ============================================================================
  hardware.amdgpu.opencl.enable = true;
  hardware.opengl.enable = true;
  services.xserver.videoDrivers = ["amdgpu" "nvidia"];

  # ============================================================================
  # KERNEL PARAMETERS
  # ============================================================================

  # AMD GPU kernel parameters
  boot.kernelParams = [
    "amdgpu.noretry=0"
    "amdgpu.mcbp=1"
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

  # NOTE: AMD mining service is defined in mining module, not needed here
  # systemd.services.lolminer-amd = {
  #   description = "lolMiner AMD GPU Mining Service";
  #   wantedBy = ["multi-user.target"];
  #   after = ["NetworkManager.service"];
  #
  #   serviceConfig = {
  #     User = "root";
  #     Group = "mining";
  #     Slice = "mining.slice";
  #     ExecStartPre = [
  #       # Set up AMD GPU power limits if supported
  #       ''${pkgs.bash}/bin/bash -c '${pkgs.rocmPackages.rocm-smi}/bin/rocm-smi --setpoweroverdrive 140 || true'
  #     ];
  #     ExecStart = ''${pkgs.steam-run}/bin/steam-run ${pkgs.writeShellScriptBin "lolminer-amd-wrapper" ''
  #       #!/usr/bin/env bash
  #       # Set up OpenCL for AMD GPUs using ROCm
  #       mkdir -p /etc/OpenCL/vendors
  #
  #       # Use ROCm OpenCL driver
  #       echo "${pkgs.rocmPackages.clr}/lib/libamdocl64.so" > /etc/OpenCL/vendors/amdocl64.icd 2>/dev/null || true
  #
  #       # ROCm environment for Navi10 (RX 5700 XT)
  #       export LD_LIBRARY_PATH="/opt/rocm/lib:/opt/rocm/hip/lib:/opt/rocm/lib:/run/opengl-driver/lib:/run/current-system/sw/lib:$LD_LIBRARY_PATH"
  #       export HSA_OVERRIDE_GFX_VERSION=10.3.0
  #       export ROC_ENABLE_PRE_VEGA=1
  #       export GPU_MAX_HEAP_SIZE=100
  #       export GPU_MAX_ALLOC_PERCENT=100
  #       exec ${pkgs.lolminer}/bin/lolMiner "$@"
  #     ''}/bin/lolminer-amd-wrapper --algo CR29 --pool stratum+ssl://xtm-c29-us.kryptex.network:8040 --user krxXVNVMM7.forge --devices 2,3 --apiport 4069 --mode b --tls 1';
  #     ExecStopPost = ''${pkgs.bash}/bin/bash -c '${pkgs.rocmPackages.rocm-smi}/bin/rocm-smi --resetpoweroverdrive || true';
  #     Restart = "always";
  #     RestartSec = "30s";
  #     Environment = ["PATH=/run/current-system/sw/bin:$PATH"];
  #     NoNewPrivileges = false;
  #     PrivateTmp = true;
  #     PrivateDevices = false;
  #     ProtectKernelTunables = false;
  #     ProtectControlGroups = false;
  #     ProtectHostname = false;
  #     RestrictRealtime = true;
  #     LimitMEMLOCK = "4G";
  #   };
  # };

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
  # FIREWALL (Minimal - no VR ports on mining rig)
  # ============================================================================

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [];
    allowedUDPPorts = [];
  };
}
