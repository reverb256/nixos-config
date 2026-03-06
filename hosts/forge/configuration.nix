# Forge Host Configuration - GPU Mining Rig
# 10.1.1.130 - 6 cores, 2x RTX 4060 + 2x RX 5700 XT
# Features: Mining only (no gaming/VR), ROCm + CUDA
#
# Module imports: Gaming, mining, monitoring, opencode are already imported
# via commonModules in flake.nix (./modules/default.nix)
# Note: Gaming module imported globally but gaming.enable=false for this host
{
  lib,
  pkgs,
  ...
}: {
  imports = [
    # Hardware configuration (generated)
    ./hardware-configuration.nix

    # Common host imports (desktop, networking, etc.)
    ../../modules/common-host.nix

    # NVIDIA GPU support (common + wayland-specific)
    ../../modules/hardware/nvidia-common.nix
    ../../modules/hardware/nvidia-wayland.nix
    ../../modules/system/security.nix
    ../../modules/services/podman-support.nix

    # ============================================================================
    # XNM1 MODULES - Minimal (mining-focused host)
    # ============================================================================
    # Shell (XNM1 - for administration)
    ../../modules/shell/fish.nix
    ../../modules/shell/starship.nix

    # Development (XNM1 - essential tools)
    ../../modules/development/tools.nix

    # System (XNM1)
    ../../modules/system/nix-settings.nix
  ];

  # ============================================================================
  # HOST IDENTIFICATION
  # ============================================================================
  networking.hostName = "forge";

  # NVIDIA GPU support (2x RTX 4060)
  hardware.nvidia-common.enable = true;

  # ============================================================================
  # BOOTLOADER
  # ============================================================================
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # ============================================================================
  # MONITORING - Node exporter, GPU (NVIDIA + AMD) and Mining metrics exporters
  # ============================================================================
  services.monitoring.node-exporter.enable = true;
  services.gpu-exporters.enable = true;
  services.mining-exporter.enable = true;

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
  # RX 5700 XT power limit set to 140W for stability and thermal management
  # Uses direct sysfs interface (more reliable than rocm-smi)
  # ============================================================================
  systemd.services.amd-gpu-power-mgmt = {
    description = "AMD GPU Power Limit (140W for RX 5700 XT)";
    wantedBy = ["multi-user.target"];
    after = ["basic.target" "multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "amd-power-limit" ''
        #!/usr/bin/env bash
        set -euo pipefail

        POWER_LIMIT_MICROWATTS=140000000  # 140W in microwatts

        log() {
          echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
        }

        # Wait for GPUs to be ready
        sleep 5

        # Set power limit for all AMD GPUs via sysfs
        for card in /sys/class/drm/card*/device/hwmon/hwmon*/power1_cap; do
          if [[ -w "$card" ]]; then
            card_name=$(basename $(dirname $(dirname $(dirname "$card"))))
            echo "$POWER_LIMIT_MICROWATTS" > "$card"
            actual=$(cat "$card")
            watts=$((actual / 1000000))
            log "AMD GPU $card_name: Power limit set to ''${watts}W"
          fi
        done

        log "AMD GPU power management configured"
      '';
    };
  };

  # Also apply power limit on resume from suspend/hibernate
  systemd.services.amd-gpu-power-mgmt-resume = {
    description = "AMD GPU Power Limit on Resume";
    after = ["suspend.target" "hibernate.target" "hybrid-sleep.target"];
    wantedBy = ["suspend.target" "hibernate.target" "hybrid-sleep.target"];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "amd-power-limit-resume" ''
        #!/usr/bin/env bash
        POWER_LIMIT_MICROWATTS=140000000
        sleep 3  # Wait for GPUs to wake up
        for card in /sys/class/drm/card*/device/hwmon/hwmon*/power1_cap; do
          if [[ -w "$card" ]]; then
            echo "$POWER_LIMIT_MICROWATTS" > "$card"
          fi
        done
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
        # Balanced curve - max 80% to reduce noise while keeping temps reasonable
        # Note: AMD driver may still override to 100% if junction temp hits ~70°C
        FAN_CURVE=(
          "50:50"   # 50°C -> 50% (quiet operation)
          "55:60"   # 55°C -> 60%
          "60:70"   # 60°C -> 70%
          "65:80"   # 65°C -> 80% (max fan speed - noise limit)
          "70:80"   # 70°C -> 80% (at driver threshold - will likely override)
          "75:80"   # 75°C -> 80%
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

        # GPU to hwmon mapping (bypass rocm-smi which gets overridden by driver)
        declare -A GPU_HWMON
        GPU_HWMON[0]="/sys/class/drm/card0/device/hwmon/hwmon0"
        GPU_HWMON[1]="/sys/class/drm/card1/device/hwmon/hwmon1"

        get_temp() {
          local gpu=$1
          local hwmon="''${GPU_HWMON[$gpu]}"
          # Read junction temperature from temp2_input (millidegrees Celsius)
          local temp_milli=$(cat "$hwmon/temp2_input" 2>/dev/null || echo "0")
          awk "BEGIN {printf \"%.1f\", $temp_milli / 1000}"
        }

        get_target_fan() {
          local temp=$1
          local target_fan=30

          for entry in "''${FAN_CURVE[@]}"; do
            local curve_temp="''${entry%%:*}"
            local curve_fan="''${entry##*:}"

            if (( $(awk "BEGIN {print ($temp >= $curve_temp)}") )); then
              target_fan=$curve_fan
            fi
          done

          echo "$target_fan"
        }

        set_fan() {
          local fan_pct=$1
          local gpu=$2
          local hwmon="''${GPU_HWMON[$gpu]}"
          # Convert percentage to 0-255 range
          local fan_value=$((fan_pct * 255 / 100))

          # Set manual mode and fan speed via sysfs (direct hardware control)
          if echo "1" > "$hwmon/pwm1_enable" 2>/dev/null && echo "$fan_value" > "$hwmon/pwm1" 2>/dev/null; then
            log "GPU$gpu: Set pwm to $fan_value ($fan_pct%)"
          else
            log "GPU$gpu: Failed to set pwm!"
          fi
        }

        calculate_fan() {
          local temp=$1
          local last_temp=$2
          local last_fan=$3

          local target_fan=$(get_target_fan "$temp")

          # Apply hysteresis - only change if temp moved significantly
          local temp_diff=$(awk "BEGIN {print $temp - $last_temp}")
          local abs_diff=$(awk "BEGIN {if ($temp_diff < 0) print (0 - $temp_diff); else print $temp_diff}")

          if (( $(awk "BEGIN {print ($abs_diff < $HYSTERESIS)}") )); then
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

              # Update fan speed if changed significantly (>= 5%)
              fan_change=$((new_fan - LAST_FAN[$gpu]))
              if (( fan_change >= 5 || fan_change <= -5 )); then
                log "GPU$gpu: ''${temp}°C (was ''${LAST_TEMP[$gpu]}°C) -> fan ''${new_fan}% (was ''${LAST_FAN[$gpu]}%)"
                LAST_FAN[$gpu]=$new_fan
                LAST_TEMP[$gpu]=$temp
                LAST_ADJUST_TIME[$gpu]=$current_time
              else
                # Update temp tracker even if we don't change fan target
                LAST_TEMP[$gpu]=$temp
              fi

              # ALWAYS write PWM to fight driver overrides (every 5s min)
              set_fan "''${LAST_FAN[$gpu]}" $gpu
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
    ensureProfiles.profiles."Wired connection 1" = {
      connection = {
        id = "Wired connection 1";
        type = "ethernet";
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
  # TAILSCALE - Now managed by modules/system/tailscale.nix
  # ============================================================================
  # Tailscale routing automatically configured via network-constants

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
  services = {
    # OpenCode - AI coding assistant configuration
    opencode.enable = true;

    ollama = {
    enable = true;
    package = pkgs.ollama-cuda;
    environmentVariables = {
      OLLAMA_KEEP_ALIVE = "24h";
    };
    };
  };
}
