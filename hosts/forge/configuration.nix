# Forge Host Configuration - GPU Mining Rig
# 10.1.1.130 - 6 cores, 2x RTX 4060 + 2x RX 5700 XT
# Features: Mining only (no gaming/VR), ROCm + CUDA
{
  lib,
  pkgs,
  ...
}: {
  imports = [
    # Hardware configuration (generated)
    ./hardware-configuration.nix

    # Common host imports (desktop, networking, etc.)
    # Note: gaming.nix is imported but not enabled (services.gaming.enable = false by default)
    ../../modules/common-host.nix

    # Host-specific GPU support (NVIDIA for RTX 4060s)
    ../../modules/nvidia-wayland.nix
  ];

  # ============================================================================
  # HOST IDENTIFICATION
  # ============================================================================
  networking.hostName = "forge";

  # ============================================================================
  # GAMING - DISABLED (Mining-focused host)
  # ============================================================================
  services.gaming.enable = false;

  # ============================================================================
  # KERNEL - Zen for better desktop responsiveness
  # ============================================================================
  boot.kernelPackages = pkgs.linuxPackages_zen;

  # ============================================================================
  # KERNEL PARAMETERS (Minimal - avoids storage conflicts)
  # ============================================================================
  boot.kernelParams = lib.mkForce [
    "loglevel=4"
    "lsm=landlock,yama,bpf"
    "simpledrm.disable=1"
    "nvidia-drm.modeset=1"
  ];

  # ============================================================================
  # GPU DRIVERS (Hybrid AMD + NVIDIA)
  # ============================================================================
  services.xserver.videoDrivers = ["nvidia"];

  hardware.amdgpu = {
    opencl.enable = true;
  };

  hardware.nvidia.wayland.enable = true;

  boot.kernelModules = ["amdgpu" "tun"];
  boot.initrd.kernelModules = ["amdgpu"];

  # ============================================================================
  # DISPLAY MANAGER
  # ============================================================================
  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
  };

  services.logind.settings.Login.KillUserProcesses = false;

  # ============================================================================
  # MINING CONFIGURATION (Forge: 6 cores, 2x RTX 4060 + 2x RX 5700 XT)
  # ============================================================================
  services.mining.enable = true;

  # NVIDIA GPUs (RTX 4060s)
  services.mining.lolminer.nvidia = {
    enable = true;
    devices = "2,3";
    powerLimit = 90;
    apiPort = 4068;
  };

  # AMD GPUs (RX 5700 XT)
  services.mining.lolminer.amd = {
    enable = true;
    devices = "0,1";
    powerLimit = 140;
    apiPort = 4069;
  };

  # ============================================================================
  # AMD GPU POWER MANAGEMENT
  # ============================================================================
  systemd.services.amd-gpu-power-mgmt = {
    description = "AMD GPU Power Limit (One-Time)";
    wantedBy = ["multi-user.target"];
    after = ["basic.target" "amd-gpu-check.service"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "amd-power-limit" ''
        #!/usr/bin/env bash
        sleep 5
        if command -v rocm-smi &> /dev/null; then
          rocm-smi --setpoweroverdrive 140 2>/dev/null || true
          echo "AMD GPU: 140W power limit configured"
        fi
      '';
    };
  };

  # ============================================================================
  # AMD GPU DYNAMIC FAN CURVE
  # ============================================================================
  systemd.services.amd-gpu-fan-curve = {
    description = "AMD GPU Dynamic Fan Curve Control";
    wantedBy = ["multi-user.target"];
    after = ["network.target" "amd-gpu-power-mgmt.service"];
    serviceConfig = {
      Type = "simple";
      Restart = "always";
      RestartSec = "10s";
      ExecStart = pkgs.writeShellScript "amd-fan-curve" ''
        #!/usr/bin/env bash
        set -e

        PATH=/run/current-system/sw/bin:$PATH

        log() {
          echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
        }

        get_temp() {
          local gpu=$1
          rocm-smi --showtemp --gpu $gpu 2>/dev/null | grep "Junction" | awk '{print $4}' | cut -d'C' -f1
        }

        set_fan() {
          local gpu=$1
          local fan_percent=$2
          local fan_level=$((fan_percent * 255 / 100))
          rocm-smi --gpu $gpu --setfan $fan_level 2>/dev/null || true
        }

        log "Starting dynamic fan curve for RX 5700 XT (devices 0,1)"

        while true; do
          for gpu in 0 1; do
            temp=$(get_temp $gpu) || continue

            # Fan curve based on junction temperature
            # <70C: 40% fan
            # 70-75C: 50% fan
            # 75-80C: 60% fan
            # 80-85C: 75% fan
            # 85-90C: 85% fan
            # >90C: 100% fan (emergency)
            if (( $(echo "$temp < 70" | bc -l) )); then
                fan=40
            elif (( $(echo "$temp < 75" | bc -l) )); then
                fan=50
            elif (( $(echo "$temp < 80" | bc -l) )); then
                fan=60
            elif (( $(echo "$temp < 85" | bc -l) )); then
                fan=75
            elif (( $(echo "$temp < 90" | bc -l) )); then
                fan=85
            else
                fan=100
            fi

            set_fan $gpu $fan
            log "GPU$gpu: Temp $temp°C -> Fan $fan%"
          done

          sleep 15
        done
      '';
    };
  };

  # ============================================================================
  # ROCm SETUP
  # ============================================================================
  environment.variables = {
    ROC_ENABLE_PRE_VEGA = "1";
    LD_LIBRARY_PATH = lib.mkForce "${pkgs.rocmPackages.clr}/lib:${pkgs.rocmPackages.clr.icd}/lib:${pkgs.mesa.opencl}/lib";
    OCL_ICD_VENDORS = "/etc/OpenCL/vendors";
  };

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
    "c /dev/net/tun 666 root root - - - -"
    "L+ /opt/rocm - - - - ${rocmEnv}"
    "L+ /opt/rocm/hip - - - - ${pkgs.rocmPackages.clr}"
  ];

  # ============================================================================
  # AMD GPU HEALTH CHECKS
  # ============================================================================
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

  systemd.services."amd-gpu-info" = {
    description = "AMD GPU Information Service";
    wantedBy = ["multi-user.target"];
    after = ["basic.target"];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash -c 'PATH=/run/current-system/sw/bin:$PATH /run/wrappers/bin/sudo rocminfo > /tmp/amd-gpu-info.log 2>&1 || true'";
      RemainAfterExit = true;
    };
  };

  # ============================================================================
  # NIX-LD (For mining software compatibility)
  # ============================================================================
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    # AMD/ROCm libraries
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

    # OpenCL
    ocl-icd
    opencl-headers
    clinfo

    # NVIDIA libraries
    libGL
    libGLU
    libglvnd
    vulkan-loader
    nvidia-vaapi-driver

    # System libraries
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
    SDL2
    alsa-lib
    systemd
    libusb1
    curl
    openssl
  ];

  # ============================================================================
  # MINING SLICE (Resource limits)
  # ============================================================================
  systemd.slices.mining = {
    description = "Mining Services Slice";
    sliceConfig = {
      CPUAccounting = true;
      CPUQuota = "95%";
      MemoryAccounting = true;
      MemoryHigh = "8G";
      MemoryMax = "12G";
      IOAccounting = true;
      IOWeight = 10;
      TasksAccounting = true;
      TasksMax = 100;
      BlockIOAccounting = true;
    };
  };

  # ============================================================================
  # NETWORKING
  # ============================================================================
  networking.wireless.enable = lib.mkForce false;
  services.avahi = lib.mkForce {
    enable = false;
    nssmdns4 = false;
    openFirewall = false;
  };

  networking.networkmanager = {
    enable = true;
    unmanaged = [];
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
        dns = "127.0.0.1,::1";
      };
    };
  };

  networking.dhcpcd.enable = false;
  networking.useDHCP = false;

  # ============================================================================
  # FIREWALL (Minimal - no VR ports)
  # ============================================================================
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [];
    allowedUDPPorts = [];
  };

  # ============================================================================
  # TAILSCALE
  # ============================================================================
  services.tailscale.enable = true;

  systemd.services.tailscaled.environment = {
    TS_ADVERTISE_ROUTES = "10.1.1.0/24";
    TS_ROUTES = "";
    TS_SSH = "true";
  };

  # ============================================================================
  # GIT CONFIGURATION
  # ============================================================================
  programs.git = {
    enable = true;
    config = {
      init.defaultBranch = "main";
      user.name = "j_kro";
      user.email = "j_kro@forge";
    };
  };

  # ============================================================================
  # OLLAMA (Local LLMs with CUDA)
  # ============================================================================
  services.ollama = {
    enable = true;
    package = pkgs.ollama-cuda;
    environmentVariables = {
      OLLAMA_KEEP_ALIVE = "24h";
    };
  };
}
