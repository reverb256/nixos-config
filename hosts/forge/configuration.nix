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
    # Import fish shell with starship
    ../../modules/fish-starship.nix
    # Import NVIDIA Wayland module (best practices)
    ../../modules/nvidia-wayland.nix
    # Import OpenClaw AI agent orchestration (declarative container)
    # Import OpenClaw common configuration
    # Import Tailscale mesh VPN
    ../../modules/tailscale.nix
    # Import CI/CD and auto-update modules
    ../../modules/garnix.nix
    ../../modules/auto-update.nix
    ../../modules/ssh.nix
    # Import mining services module
    ../../modules/mining.nix
    # Import OpenClaw node host module
    ../../modules/openclaw-node-host.nix
  ];

  # Host identification
  networking.hostName = "forge";

  # Enable CI/CD features
  # garnix.enable = true;  # Disabled - requires nix-cache-key.sec
  # Determinate Nix is already installed via installer (no config needed)

  # Zen kernel for gaming/desktop - force use of currently running kernel version
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

  # ============================================================================
  # KERNEL PARAMETERS
  # ============================================================================

  # Override common kernelParams with minimal working set (Generation 2 compatible)
  # This replaces ALL common kernelParams to prevent conflicts with storage/SATA
  boot.kernelParams = lib.mkForce [
    "loglevel=4"
    "lsm=landlock,yama,bpf"
    "simpledrm.disable=1"  # Required for display
    "nvidia-drm.modeset=1"  # Required for NVIDIA display
  ];

  environment.variables = {
    ROC_ENABLE_PRE_VEGA = "1";
    LD_LIBRARY_PATH = lib.mkForce "${pkgs.rocmPackages.clr}/lib:${pkgs.rocmPackages.clr.icd}/lib:${pkgs.mesa.opencl}/lib";
    OCL_ICD_VENDORS = "/etc/OpenCL/vendors";
  };

  # ============================================================================
  # MINING CONFIGURATION (Forge: 6 cores, 2x RTX 4060 + 2x RX 5700 XT)
  # ============================================================================
  # ============================================================================
  # MINING CONFIGURATION
  # ============================================================================
   services.mining.enable = true;

  # Enable NVIDIA Wayland for RTX 4060s
  hardware.nvidia.wayland.enable = true;

  # NVIDIA GPUs (RTX 4060s) - Both GPUs
  services.mining.lolminer.nvidia.enable = true;
  services.mining.lolminer.nvidia.devices = "0,3";
  services.mining.lolminer.nvidia.powerLimit = 90;
  services.mining.lolminer.nvidia.apiPort = 4068;

  # AMD GPUs (RX 5700 XT) - Both GPUs on different API port
  services.mining.lolminer.amd.enable = true;
  services.mining.lolminer.amd.devices = "0,2";
  services.mining.lolminer.amd.powerLimit = 140;
  services.mining.lolminer.amd.apiPort = 4069;

  # AMD GPU Power Management - 140W limit, 86% fan speed
  systemd.services.amd-gpu-power-mgmt = {
    description = "AMD GPU Power and Fan Management";
    wantedBy = [ "multi-user.target" ];
    after = [ "basic.target" "amd-gpu-check.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "amd-power-mgmt" ''
        #!/usr/bin/env bash
        sleep 5
        if command -v rocm-smi &> /dev/null; then
          rocm-smi --setpoweroverdrive 140 2>/dev/null || true
          rocm-smi --setfan 220 2>/dev/null || true
          echo "AMD GPU: 140W power limit, 86% fan speed configured"
        fi
      '';
    };
  };

  # Disable OpenRGB on forge mining rig
  hardware.rgb.openrgb.enable = lib.mkForce false;

  # ============================================================================
  # ROCm HIP symlink for OpenCL (fixes SIGSEGV crash)
  # ============================================================================
  environment.systemPackages = with pkgs; [
    rocmPackages.rocm-smi
  ];

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

  programs.git = {
    enable = true;
    config = {
      init.defaultBranch = "main";
      user.name = "j_kro";
      user.email = "j_kro@forge";
    };
  };

  services.openclaw-node-host = {
    enable = true;
    gatewayHost = "zephyr";
    displayName = "Forge Build Node";
    execAllowlist = [
      "/run/current-system/sw/bin/uname"
      "/run/current-system/sw/bin/sw_vers"
    ];
  };
}
