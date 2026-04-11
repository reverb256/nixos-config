# Forge Hardware Configuration
# 2x RTX 4060 + 2x RX 5700 XT (hybrid AMD + NVIDIA)
# GPU compute, ROCm setup, AMD/NVIDIA GPU management systemd services
{ pkgs, lib, ... }:
{
  # GPU COMPUTE - CUDA + ROCm + Vulkan support for AI inference
  # Forge has BOTH AMD (5700XT) and NVIDIA GPUs (RTX 4060)
  hardware.gpu-compute = {
    enable = true;
    cuda.enable = true; # CUDA for NVIDIA RTX 4060
    rocm.enable = true; # ROCm for AMD 5700XT
    vulkan.enable = true; # Universal backend (all GPUs)
  };

  # HARDWARE PROFILES
  # Base profiles provided by node-profiles.forge-mining:
  # - intel, nvidia.enable (multiGpu), amdgpu.enable, amdgpu.wayland, monitoring.enable
  hardware = {
    # NVIDIA GPU support (base driver)
    nvidia-common.enable = true;
    # BTRFS compression and deduplication
    btrfs-compression.enable = true;
    # Hardware monitoring
    monitoring = {
      enable = true;
      autoDetect = false; # Disabled: sensors-detect has bug with --auto flag
      fanControl = false; # BIOS fan control for now
    };
    # RGB control for ASRock RX 5700 XT and motherboard
    rgb-control = {
      enable = true;
      openrgb.enable = true;
      temperatureReactive = {
        enable = true;
        sensor = "gpu"; # Monitor GPU temps for mining
        thresholds = {
          cool = 60;
          warm = 70;
          hot = 75;
        };
        interval = 10; # Poll every 10 seconds
      };
    };
  };

  # BOOT - Forge-specific kernel parameters
  boot = {
    kernelParams = [
      # No overrides needed - using hardened defaults from kernel-hardening.nix
    ];
    # GPU DRIVERS (Hybrid AMD + NVIDIA)
    kernelModules = [ "tun" ]; # amdgpu added by profile, not duplicated here
  };

  # ============================================================================
  # AMD GPU POWER MANAGEMENT (RX 5700 XT @ 110W)
  # ============================================================================
  systemd.services = {
    amd-gpu-power-mgmt = {
      description = "AMD GPU Power Limit (110W for RX 5700 XT)";
      wantedBy = [ "multi-user.target" ];
      after = [ "multi-user.target" ];
      path = [ pkgs.coreutils ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "amd-power-limit" ''
          #!/usr/bin/env bash
          set -euo pipefail
          POWER_LIMIT_MICROWATTS=110000000  # 110W in microwatts
          log() {
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
          }
          # Wait for AMD GPUs to enumerate hwmon entries
          for i in $(seq 1 30); do
            cards=$(ls /sys/class/drm/card*/device/hwmon/hwmon*/power1_cap 2>/dev/null || true)
            if [[ -n "$cards" ]]; then
              log "AMD GPU hwmon entries found"
              break
            fi
            log "Waiting for AMD GPU hwmon... ($i/30)"
            sleep 2
          done
          # Set power limit for all AMD GPUs via sysfs
          for card in /sys/class/drm/card*/device/hwmon/hwmon*/power1_cap; do
            if [[ -w "$card" ]]; then
              card_name=$(basename $(dirname $(dirname $(dirname "$card"))))
              # Validate the requested limit is within hwmon range
              cap_min=$(cat "$(dirname "$card")/power1_cap_min" 2>/dev/null || echo 0)
              cap_max=$(cat "$(dirname "$card")/power1_cap_max" 2>/dev/null || echo 0)
              if (( POWER_LIMIT_MICROWATTS < cap_min )); then
                log "AMD GPU $card_name: Requested $((POWER_LIMIT_MICROWATTS/1000000))W below min $((cap_min/1000000))W, using min"
                POWER_LIMIT_MICROWATTS=$cap_min
              elif (( POWER_LIMIT_MICROWATTS > cap_max )); then
                log "AMD GPU $card_name: Requested $((POWER_LIMIT_MICROWATTS/1000000))W above max $((cap_max/1000000))W, using max"
                POWER_LIMIT_MICROWATTS=$cap_max
              fi
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

    # NVIDIA COMPUTE MODE - EXCLUSIVE_PROCESS for mining only
    nvidia-compute-mode = {
      description = "NVIDIA GPU Compute-Only Mode (EXCLUSIVE_PROCESS)";
      wantedBy = [ "multi-user.target" ];
      after = [ "basic.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "nvidia-compute-mode" ''
          #!/usr/bin/env bash
          set -euo pipefail
          log() {
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
          }
          # Wait for NVIDIA driver to be ready
          for i in {1..30}; do
            if /run/current-system/sw/bin/nvidia-smi &>/dev/null; then
              log "NVIDIA driver ready"
              break
            fi
            log "Waiting for NVIDIA driver... ($i/30)"
            sleep 2
          done
          # Set compute mode for all NVIDIA GPUs
          /run/current-system/sw/bin/nvidia-smi -c 3
          /run/current-system/sw/bin/nvidia-smi --query-gpu=name,compute_mode --format=csv,noheader | while IFS=, read -r name mode; do
            log "NVIDIA GPU ''${name// /}: Compute mode = ''${mode// /}"
          done
          log "NVIDIA GPUs set to compute-only mode"
        '';
      };
    };

    # AMD GPU DYNAMIC FAN CURVE
    amd-gpu-fan-curve = {
      description = "AMD GPU Dynamic Fan Curve Control";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network.target"
        "amd-gpu-power-mgmt.service"
      ];
      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = "10s";
        ExecStart = pkgs.writeShellScript "amd-fan-curve" ''
          #!/run/current-system/sw/bin/bash
          set -euo pipefail
          PATH=/run/current-system/sw/bin:$PATH
          FAN_CURVE=(
            "50:50"
            "55:60"
            "60:70"
            "65:80"
            "70:80"
            "75:80"
          )
          HYSTERESIS=3
          MIN_ADJUST_INTERVAL=5
          declare -A LAST_TEMP
          declare -A LAST_FAN
          declare -A LAST_ADJUST_TIME
          log() {
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
          }
          declare -A GPU_HWMON
          GPU_HWMON[0]="/sys/class/drm/card0/device/hwmon/hwmon1"
          GPU_HWMON[1]="/sys/class/drm/card1/device/hwmon/hwmon0"
          get_temp() {
            local gpu=$1
            local hwmon="''${GPU_HWMON[$gpu]}"
            local temp_milli=$(cat "$hwmon/temp2_input" 2>/dev/null || echo "0")
            echo "scale=1; $temp_milli / 1000" | bc
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
            local fan_value=$((fan_pct * 255 / 100))
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
            local temp_diff=$(awk "BEGIN {print $temp - $last_temp}")
            local abs_diff=$(awk "BEGIN {if ($temp_diff < 0) print (0 - $temp_diff); else print $temp_diff}")
            if (( $(awk "BEGIN {print ($abs_diff < $HYSTERESIS)}") )); then
              echo "$last_fan"
              return
            fi
            local fan_diff=$((target_fan - last_fan))
            local max_change=25
            if (( fan_diff > 0 )); then
              if (( fan_diff > max_change )); then
                echo $((last_fan + max_change))
              else
                echo "$target_fan"
              fi
            else
              local neg_max_change=$((-max_change))
              if (( fan_diff < neg_max_change )); then
                echo $((last_fan - max_change))
              else
                echo "$target_fan"
              fi
            fi
          }
          log "Starting temperature-based fan control for RX 5700 XT (devices 0,1)"
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
          while true; do
            current_time=$(date +%s)
            for gpu in 0 1; do
              temp=$(get_temp $gpu)
              if [[ -z "$temp" ]]; then
                continue
              fi
              time_since_last=$((current_time - LAST_ADJUST_TIME[$gpu]))
              if (( time_since_last >= MIN_ADJUST_INTERVAL )); then
                new_fan=$(calculate_fan "$temp" "''${LAST_TEMP[$gpu]}" "''${LAST_FAN[$gpu]}")
                fan_change=$((new_fan - LAST_FAN[$gpu]))
                if (( fan_change >= 5 || fan_change <= -5 )); then
                  log "GPU$gpu: ''${temp}°C (was ''${LAST_TEMP[$gpu]}°C) -> fan ''${new_fan}% (was ''${LAST_FAN[$gpu]}%)"
                  LAST_FAN[$gpu]=$new_fan
                  LAST_TEMP[$gpu]=$temp
                  LAST_ADJUST_TIME[$gpu]=$current_time
                else
                  LAST_TEMP[$gpu]=$temp
                fi
                set_fan "''${LAST_FAN[$gpu]}" $gpu
              fi
            done
            sleep 2
          done
        '';
      };
    };

    # AMD GPU HEALTH CHECKS
    "amd-gpu-check" = {
      description = "AMD GPU Detection and Health Check";
      wantedBy = [ "multi-user.target" ];
      after = [ "basic.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.bash}/bin/bash -c 'PATH=/run/current-system/sw/bin:$PATH /run/wrappers/bin/sudo rocminfo 2>/dev/null || echo \"AMD GPU detection failed\"'";
        RemainAfterExit = true;
      };
    };

    # AMD GPU MAX FAN SPEED (DISABLED - using fan curve instead)
    "amd-gpu-max-fan" = {
      description = "AMD GPU Max Fan Speed (100%) - DISABLED, using fan curve instead";
      after = [
        "basic.target"
        "amd-gpu-power-mgmt.service"
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "amd-max-fan" ''
          #!/usr/bin/env bash
          set -euo pipefail
          log() {
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
          }
          sleep 5
          if /run/wrappers/bin/sudo /run/current-system/sw/bin/rocm-smi --setfan 100%; then
            log "AMD GPUs set to 100% fan speed"
          else
            log "Failed to set AMD GPU fan speed"
          fi
        '';
      };
    };

    "amd-gpu-info" = {
      description = "AMD GPU Information Service";
      wantedBy = [ "multi-user.target" ];
      after = [ "basic.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.bash}/bin/bash -c 'PATH=/run/current-system/sw/bin:$PATH /run/wrappers/bin/sudo rocminfo > /tmp/amd-gpu-info.log 2>&1 || true'";
        RemainAfterExit = true;
      };
    };
  };

  # ============================================================================
  # MINING SLICE - Resource limits for mining services
  # ============================================================================
  systemd.slices.mining = {
    description = "Mining Services Slice";
    sliceConfig = {
      CPUAccounting = true;
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
  # ROCm SETUP - Libraries and symlinks for AMD GPU compute
  # ============================================================================
  environment = {
    variables = {
      LD_LIBRARY_PATH = lib.mkForce "${pkgs.rocmPackages.clr}/lib:${pkgs.rocmPackages.clr.icd}/lib:${pkgs.mesa.opencl}/lib";
      OCL_ICD_VENDORS = "/etc/OpenCL/vendors";
    };
    etc."OpenCL/vendors/amdocl64.icd".source =
      "${pkgs.rocmPackages.clr.icd}/etc/OpenCL/vendors/amdocl64.icd";
  };

  systemd.tmpfiles.rules =
    let
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
    in
    [
      "c /dev/net/tun 666 root root - - - -"
      "L+ /opt/rocm - - - - ${rocmEnv}"
      "L+ /opt/rocm/hip - - - - ${pkgs.rocmPackages.clr}"
      # lolMiner workaround for OpenCL ICD path bug
      "L /etc/OpenCL/vendorsamdocl64.icd - - - - /etc/OpenCL/vendors/amdocl64.icd"
    ];
}
