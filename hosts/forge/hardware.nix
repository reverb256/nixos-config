{
  pkgs,
  lib,
  ...
}: {
  hardware.gpu-compute = {
    enable = true;
    cuda.enable = true;
    rocm.enable = true;
    vulkan.enable = true;
  };

  hardware = {
    nvidia-common.enable = true;
    nvidia.powerLimits = {
      enable = true;
      gpus = {
        "rtx4060-0" = {
          index = 0;
          limit = 105; # Tuned for efficiency
        };
        "rtx4060-1" = {
          index = 1;
          limit = 105; # Tuned for efficiency
        };
      };
    };
    amdgpu.powerLimits = {
      enable = true;
      gpus = {
        "rx5700xt-0" = {
          index = 0;
          limit = 110;
        };
        "rx5700xt-1" = {
          index = 1;
          limit = 110;
        };
      };
    };
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
    kernelModules = ["tun"];
  };

  systemd.services = {
    amd-gpu-power-mgmt = {
      description = "AMD GPU Power Limit (120W for RX 5700 XT)";
      wantedBy = ["multi-user.target"];
      after = ["multi-user.target"];
      path = [pkgs.coreutils];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "amd-power-limit" ''
          #!/usr/bin/env bash
          set -eo pipefail
          POWER_LIMIT_MICROWATTS=120000000
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
      wantedBy = ["multi-user.target"];
      after = ["basic.target"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "nvidia-compute-mode" ''
          #!/usr/bin/env bash
          set -eo pipefail
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
      wantedBy = ["multi-user.target"];
      after = [
        "network.target"
      ];
      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = "10s";
        ExecStart = pkgs.writeShellScript "amd-fan-curve" ''
          #!/run/current-system/sw/bin/bash
          set -eo pipefail
          PATH=/run/current-system/sw/bin:$PATH
          FAN_CURVE=(
            "40:120"
            "45:140"
            "50:160"
            "55:180"
            "60:200"
            "65:220"
            "70:235"
            "75:245"
            "80:255"
          )
          HYSTERESIS=2
          MIN_ADJUST_INTERVAL=10
          MAX_FAN_CHANGE=20
          declare -A LAST_TEMP
          declare -A LAST_FAN
          declare -A LAST_ADJUST_TIME
          log() {
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] ''$*"
          }
          # Auto-detect hwmon paths - card numbers change between reboots
          declare -A GPU_HWMON
          for card_dir in /sys/class/drm/card*/device/hwmon/hwmon*; do
            if [ -f "''$card_dir/temp1_input" ]; then
              # Get temp to identify active GPUs (skip if 0 or very low)
              temp=''$(cat "''$card_dir/temp1_input" 2>/dev/null || echo "0")
              temp_c=''$((temp / 1000))
              if [ "''$temp_c" -gt 30 ]; then
                # Active GPU found - assign to next available slot
                gpu_count=''${#GPU_HWMON[@]}
                if [ "''$gpu_count" -lt 2 ]; then
                  GPU_HWMON[''$gpu_count]="''$card_dir"
                  log "Auto-detected GPU''$gpu_count: ''$card_dir (temp: ''${temp_c}°C)"
                fi
              fi
            fi
          done
          if [ ''${#GPU_HWMON[@]} -lt 2 ]; then
            log "ERROR: Only detected ''${#GPU_HWMON[@]} GPU(s), expected 2"
          fi
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
            local fan_level=$1
            local gpu=$2
            local hwmon="''${GPU_HWMON[$gpu]}"
            # Enable manual PWM mode (1=manual, 2=auto, 0=disabled)
            if echo "1" > "$hwmon/pwm1_enable" 2>/dev/null && echo "$fan_level" > "$hwmon/pwm1" 2>/dev/null; then
              log "GPU$gpu: Set fan to level $fan_level/255 (manual mode)"
            else
              log "GPU$gpu: Failed sysfs, rocm-smi fallback"
              rocm-smi -d $gpu --setfan $fan_level 2>/dev/null || true
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
                if (( fan_change >= 10 || fan_change <= -10 )); then
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
      wantedBy = ["multi-user.target"];
      after = ["basic.target"];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.bash}/bin/bash -c 'PATH=/run/current-system/sw/bin:$PATH /run/wrappers/bin/sudo rocminfo 2>/dev/null || echo \"AMD GPU detection failed\"'";
        RemainAfterExit = true;
      };
    };

    "amd-gpu-info" = {
      description = "AMD GPU Information Service";
      wantedBy = ["multi-user.target"];
      after = ["basic.target"];
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
      # ROCm/Mesa OpenCL (for compute mining) + Portaudio/PipeWire (for hermes audio)
      LD_LIBRARY_PATH = lib.mkForce (lib.makeSearchPath "lib" [
        pkgs.rocmPackages.clr
        pkgs.rocmPackages.clr.icd
        pkgs.mesa.opencl
        pkgs.portaudio
        "/run/current-system/sw/lib/pipewire-0.3"
        "/etc/sane-libs"
      ]);
      OCL_ICD_VENDORS = "/etc/OpenCL/vendors";
    };
    etc."OpenCL/vendors/amdocl64.icd".source = "${pkgs.rocmPackages.clr.icd}/etc/OpenCL/vendors/amdocl64.icd";
  };

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
    "L+ /etc/OpenCL/vendors/amdocl64.icd - - - - ${pkgs.rocmPackages.clr.icd}/amdocl64.icd"
  ];
}
