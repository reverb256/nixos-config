{ pkgs, lib, ... }:
{
  hardware.gpu-compute = {
    enable = true;
    cuda.enable = true;
    rocm.enable = true;
    vulkan.enable = true;
  };

  hardware = {
    nvidia-common.enable = true;
    btrfs-compression.enable = true;
    monitoring = {
      enable = true;
      autoDetect = false;
      fanControl = false;
    };
    rgb-control = {
      enable = true;
      openrgb.enable = true;
      temperatureReactive = {
        enable = true;
        sensor = "gpu";
        thresholds = {
          cool = 60;
          warm = 70;
          hot = 75;
        };
        interval = 10;
      };
    };
  };

  boot = {
    kernelParams = [
    ];
    kernelModules = [ "tun" ];
  };

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
          POWER_LIMIT_MICROWATTS=110000000
          log() {
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
          }
          for i in $(seq 1 30); do
            cards=$(ls /sys/class/drm/card*/device/hwmon/hwmon*/power1_cap 2>/dev/null || true)
            if [[ -n "$cards" ]]; then
              log "AMD GPU hwmon entries found"
              break
            fi
            log "Waiting for AMD GPU hwmon... ($i/30)"
            sleep 2
          done
          for card in /sys/class/drm/card*/device/hwmon/hwmon*/power1_cap; do
            if [[ -w "$card" ]]; then
              card_name=$(basename $(dirname $(dirname $(dirname "$card"))))
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
          for i in {1..30}; do
            if /run/current-system/sw/bin/nvidia-smi &>/dev/null; then
              log "NVIDIA driver ready"
              break
            fi
            log "Waiting for NVIDIA driver... ($i/30)"
            sleep 2
          done
          /run/current-system/sw/bin/nvidia-smi -c 3
          /run/current-system/sw/bin/nvidia-smi --query-gpu=name,compute_mode --format=csv,noheader | while IFS=, read -r name mode; do
            log "NVIDIA GPU ''${name// /}: Compute mode = ''${mode// /}"
          done
          log "NVIDIA GPUs set to compute-only mode"
        '';
      };
    };

    amd-gpu-fan-curve = {
      description = "AMD GPU Dynamic Fan Curve Control";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network.target"
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
            "45:40"
            "50:50"
            "55:55"
            "60:65"
            "65:75"
            "70:80"
            "75:85"
            "80:90"
          )
          HYSTERESIS=2
          MIN_ADJUST_INTERVAL=10
          MAX_FAN_CHANGE=10
          declare -A LAST_TEMP
          declare -A LAST_FAN
          declare -A LAST_ADJUST_TIME
          log() {
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
          }
          declare -A GPU_HWMON
          GPU_HWMON[0]="/sys/class/drm/card1/device/hwmon/hwmon0"
          GPU_HWMON[1]="/sys/class/drm/card2/device/hwmon/hwmon1"
          get_temp() {
            local gpu=$1
            local hwmon="''${GPU_HWMON[$gpu]}"
            local temp_milli=$(cat "$hwmon/temp1_input" 2>/dev/null || echo "0")
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
            if echo "0" > "$hwmon/pwm1_enable" 2>/dev/null && echo "$fan_value" > "$hwmon/pwm1" 2>/dev/null; then
              log "GPU$gpu: Set fan to $fan_pct% (pwm=$fan_value)"
            else
              log "GPU$gpu: Failed to set fan (rocm-smi fallback)"
              rocm-smi -d $gpu --setfan $fan_pct 2>/dev/null || true
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
            if (( fan_diff > 0 )); then
              if (( fan_diff > MAX_FAN_CHANGE )); then
                echo $((last_fan + MAX_FAN_CHANGE))
              else
                echo "$target_fan"
              fi
            else
              local neg_max_change=$((-MAX_FAN_CHANGE))
              if (( fan_diff < neg_max_change )); then
                echo $((last_fan - MAX_FAN_CHANGE))
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
            sleep 5
          done
        '';
      };
    };

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
      "L /etc/OpenCL/vendorsamdocl64.icd - - - - /etc/OpenCL/vendors/amdocl64.icd"
    ];
}
