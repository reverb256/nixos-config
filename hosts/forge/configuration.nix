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

    # NVIDIA GPU support (common + wayland-specific)
    ../../modules/hardware/nvidia-common.nix
    ../../modules/hardware/nvidia-wayland.nix
    ../../modules/services/podman-support.nix
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
  # Note: NVIDIA base config is in nvidia-common.nix
  # ============================================================================
  hardware.amdgpu = {
    opencl.enable = true;
  };

  boot.kernelModules = ["amdgpu" "tun"];
  boot.initrd.kernelModules = ["amdgpu"];

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
  # AMD GPU DYNAMIC FAN CURVE (Temperature-Based with Hysteresis)
  # ============================================================================
  # Smooth fan curve for RX 5700 XT to prevent spiking
  # - Temperature-based targeting with hysteresis
  # - Dead zones to prevent rapid oscillation
  # - Gradual ramp changes
  systemd.services.amd-gpu-fan-curve = {
    description = "AMD GPU Dynamic Fan Curve Control";
    wantedBy = ["multi-user.target"];
    after = ["network.target" "amd-gpu-power-mgmt.service"];
    serviceConfig = {
      Type = "simple";
      Restart = "always";
      RestartSec = "10s";
      ExecStart = pkgs.writeShellScript "amd-fan-curve" ''
        #!/run/current-system/sw/bin/bash
        set -euo pipefail

        PATH=/run/current-system/sw/bin:$PATH

        # Fan curve configuration (RX 5700 XT optimized)
        # Format: "TEMP:TARGET_FAN_SPEED"
        # Temp in Celsius, fan speed as percentage (0-100)
        # AGGRESSIVE curve to keep junction temps well below 70°C AMD driver threshold
        FAN_CURVE=(
          "50:50"   # 50°C -> 50% (higher base to prevent thermal creep)
          "55:65"   # 55°C -> 65%
          "60:75"   # 60°C -> 75%
          "65:85"   # 65°C -> 85%
          "68:90"   # 68°C -> 90% (critical - approaching driver override)
          "70:95"   # 70°C -> 95% (emergency - at driver threshold)
          "75:100"  # 75°C -> 100% (maximum cooling)
        )

        # Hysteresis configuration (prevents rapid oscillation)
        # Only change fan speed if temperature changes by this many degrees
        HYSTERESIS=3

        # Minimum time between fan adjustments (seconds)
        # Prevents rapid successive changes
        MIN_ADJUST_INTERVAL=5

        # State tracking per GPU
        declare -A LAST_TEMP
        declare -A LAST_FAN
        declare -A LAST_ADJUST_TIME

        log() {
          echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
        }

        get_temp() {
          local gpu=$1
          rocm-smi --showtemp --csv 2>/dev/null | \
            awk -F',' -v gpu="$gpu" '$1 == gpu {gsub(/[^0-9.]/, "", $2); print $2; exit}'
        }

        get_target_fan() {
          local temp=$1
          local target_fan=30

          for entry in "''${FAN_CURVE[@]}"; do
            local curve_temp="''${entry%%:*}"
            local curve_fan="''${entry##*:}"

            if (( $(echo "$temp >= $curve_temp" | bc -l) )); then
              target_fan=$curve_fan
            fi
          done

          echo "$target_fan"
        }

        set_fan() {
          local fan_pct=$1
          local gpu=$2
          # Convert percentage to 0-255 range
          local fan_value=$((fan_pct * 255 / 100))

          rocm-smi --setfan $fan_value -d $gpu >/dev/null 2>&1
        }

        calculate_fan() {
          local temp=$1
          local last_temp=$2
          local last_fan=$3

          local target_fan=$(get_target_fan "$temp")

          # Apply hysteresis - only change if temp moved significantly
          local temp_diff=$(echo "$temp - $last_temp" | bc -l)
          local abs_diff=$(echo "if ($temp_diff < 0) -$temp_diff else $temp_diff" | bc -l)

          if (( $(echo "$abs_diff < $HYSTERESIS" | bc -l) )); then
            # Within hysteresis zone - keep last fan speed
            echo "$last_fan"
            return
          fi

          # Calculate smoothed fan change (gradual ramp)
          # Higher max_change when temps are high to prevent driver override
          local fan_diff=$((target_fan - last_fan))
          local max_change=25  # Max 25% change per adjustment (increased for thermal safety)

          if (( fan_diff > 0 )); then
            # Ramping up
            if (( fan_diff > max_change )); then
              echo $((last_fan + max_change))
            else
              echo "$target_fan"
            fi
          else
            # Ramping down
            local neg_max_change=$((-max_change))
            if (( fan_diff < neg_max_change )); then
              echo $((last_fan - max_change))
            else
              echo "$target_fan"
            fi
          fi
        }

        log "Starting temperature-based fan control for RX 5700 XT (devices 0,1)"
        log "Fan curve with hysteresis: ''${HYSTERESIS}°C dead zone, ''${MIN_ADJUST_INTERVAL}s min interval"

        # Initialize with current temps
        for gpu in 0 1; do
          temp=$(get_temp $gpu)
          if [[ -n "$temp" ]]; then
            LAST_TEMP[$gpu]=$temp
            LAST_FAN[$gpu]=$(get_target_fan "$temp")
            LAST_ADJUST_TIME[$gpu]=0
            log "GPU$gpu initial: ''${temp}°C -> fan set to ''${LAST_FAN[$gpu]}%"
            set_fan "''${LAST_FAN[$gpu]}" $gpu
          fi
        done

        sleep 3

        # Main control loop
        while true; do
          current_time=$(date +%s)

          for gpu in 0 1; do
            temp=$(get_temp $gpu)

            if [[ -z "$temp" ]]; then
              continue
            fi

            # Check if enough time has passed since last adjustment
            time_since_last=$((current_time - LAST_ADJUST_TIME[$gpu]))

            if (( time_since_last >= MIN_ADJUST_INTERVAL )); then
              new_fan=$(calculate_fan "$temp" "''${LAST_TEMP[$gpu]}" "''${LAST_FAN[$gpu]}")

              # Only update if fan speed changed significantly (>= 5%)
              fan_change=$((new_fan - LAST_FAN[$gpu]))
              if (( fan_change >= 5 || fan_change <= -5 )); then
                log "GPU$gpu: ''${temp}°C (was ''${LAST_TEMP[$gpu]}°C) -> fan ''${new_fan}% (was ''${LAST_FAN[$gpu]}%)"
                set_fan "$new_fan" $gpu
                LAST_FAN[$gpu]=$new_fan
                LAST_TEMP[$gpu]=$temp
                LAST_ADJUST_TIME[$gpu]=$current_time
              else
                # Update temp tracker even if we don't change fan
                LAST_TEMP[$gpu]=$temp
              fi
            fi
          done

          sleep 2
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
