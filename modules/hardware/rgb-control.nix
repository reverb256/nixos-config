# RGB Control Module - Temperature-based lighting control
# Supports OpenRGB, OpenRAZER, and AMD Wraith Prism
#
# Per-host RGB capabilities:
# - Nexus: Razer Naga Pro (openrazer)
# - Forge: ASRock RX 5700 XT RGB (OpenRGB, potentially)
# - Sentry: AMD Wraith Prism (cm-rgb)
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.hardware.rgb-control;
in {
  options.hardware.rgb-control = {
    enable = lib.mkEnableOption "RGB control with temperature-based lighting";

    # OpenRGB - Motherboard, GPU, and general RGB control
    openrgb.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable OpenRGB for motherboard/GPU RGB control";
    };

    # OpenRAZER - Razer peripherals
    openrazer.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable OpenRAZER for Razer peripherals";
    };

    # AMD Wraith Prism cooler
    wraithRgb.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable cm-rgb for AMD Wraith Prism cooler";
    };

    # Temperature-based RGB control
    temperatureReactive.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable temperature-reactive RGB color changes";
    };

    temperatureReactive.sensor = lib.mkOption {
      type = lib.types.str;
      default = "cpu";
      example = "gpu";
      description = "Temperature sensor to use: cpu, gpu, or both";
    };

    # Temperature thresholds (Celsius)
    temperatureReactive.thresholds = lib.mkOption {
      type = lib.types.attrsOf lib.types.int;
      default = {
        cool = 50;
        warm = 65;
        hot = 75;
      };
      description = "Temperature thresholds for color changes";
    };

    # Colors for each temperature zone (RGB hex)
    temperatureReactive.colors = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {
        cool = "0000FF";   # Blue
        warm = "00FF00";   # Green
        hot = "FFFF00";    # Yellow
        critical = "FF0000"; # Red
      };
      description = "RGB colors for temperature zones";
    };

    # Update interval for temperature polling
    temperatureReactive.interval = lib.mkOption {
      type = lib.types.int;
      default = 5;
      description = "Temperature polling interval in seconds";
    };
  };

  config = lib.mkIf cfg.enable {
    # Install RGB control packages
    environment.systemPackages =
      [
        pkgs.openrgb
      ]
      ++ lib.optionals cfg.openrgb.enable [
        pkgs.openrgb-plugin-effects
        pkgs.python3Packages.openrgb-python
      ]
      ++ lib.optionals cfg.openrazer.enable [
        # Note: openrazer daemon is provided by hardware.openrazer module
        pkgs.polychromatic
        pkgs.razer-cli
      ]
      ++ lib.optionals cfg.wraithRgb.enable [
        pkgs.cm-rgb
      ];

    # Load i2c-dev module for motherboard RGB control
    boot.kernelModules = ["i2c-dev" "i2c-piix4" "i2c-i801"];

    # OpenRGB udev rules
    services.udev.extraRules = lib.mkIf cfg.openrgb.enable ''
      # OpenRGB - Motherboard and RGB controller access
      SUBSYSTEM=="i2c-dev", MODE="0666"
      SUBSYSTEM=="leds", MODE="0666"

      # ASRock motherboard RGB
      ATTR{idVendor}=="1b1c", ATTR{idProduct}=="1b27", MODE="0666"

      # Generic RGB controller access
      KERNEL=="hidraw*", MODE="0666"
    '';

    # OpenRAZER daemon and configuration
    hardware.openrazer = lib.mkIf cfg.openrazer.enable {
      enable = true;
      users = ["j_kro"];
    };

    # Temperature-reactive RGB control service
    systemd.services.rgb-temperature-control = lib.mkIf cfg.temperatureReactive.enable {
      description = "Temperature-reactive RGB lighting control";
      wantedBy = ["multi-user.target"];
      after = ["graphical-session.target"];
      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = "10s";
        ExecStart = pkgs.writeShellScript "rgb-temperature-control" ''
          #!/usr/bin/env bash
          set -euo pipefail

          PATH=/run/current-system/sw/bin:$PATH

          # Configuration
          COOL_THRESHOLD=${toString cfg.temperatureReactive.thresholds.cool}
          WARM_THRESHOLD=${toString cfg.temperatureReactive.thresholds.warm}
          HOT_THRESHOLD=${toString cfg.temperatureReactive.thresholds.hot}
          CRITICAL_THRESHOLD=85

          UPDATE_INTERVAL=${toString cfg.temperatureReactive.interval}

          SENSOR_TYPE="${cfg.temperatureReactive.sensor}"

          # Colors (RGB hex)
          COOL_COLOR="${cfg.temperatureReactive.colors.cool}"
          WARM_COLOR="${cfg.temperatureReactive.colors.warm}"
          HOT_COLOR="${cfg.temperatureReactive.colors.hot}"
          CRITICAL_COLOR="${cfg.temperatureReactive.colors.critical}"

          # Device-specific settings
          # Adjust these based on your actual hardware
          OPENRGB_DEVICE=0  # First RGB device detected by OpenRGB
          OPENRAZER_DEVICE=0  # First Razer device

          log() {
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
          }

          # Get CPU temperature
          get_cpu_temp() {
            # Try different temperature sensors
            for sensor in /sys/class/thermal/thermal_zone*/temp; do
              if [[ -r "$sensor" ]]; then
                temp=$(cat "$sensor" 2>/dev/null || echo "0")
                if [[ "$temp" -gt 1000 ]]; then
                  echo $((temp / 1000))
                  return 0
                fi
              fi


done

            # Fallback to lm-sensors if available
            if command -v sensors &>/dev/null; then
              sensors -j 2>/dev/null | grep -oE '"Core.*_input": [0-9.]+' | head -1 | grep -oE '[0-9.]+' || echo "0"
            else
              echo "0"
            fi
          }

          # Get GPU temperature
          get_gpu_temp() {
            # Try NVIDIA
            if command -v nvidia-smi &>/dev/null; then
              nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null | head -1 || echo "0"
            # Try AMD
            elif command -v rocm-smi &>/dev/null; then
              rocm-smi --showtemp --json 2>/dev/null | grep -oE '"GPU temp": [0-9.]+' | grep -oE '[0-9.]+' | head -1 || echo "0"
            else
              echo "0"
            fi
          }

          # Get temperature based on sensor type
          get_temperature() {
            case "$SENSOR_TYPE" in
              cpu)
                get_cpu_temp
                ;;
              gpu)
                get_gpu_temp
                ;;
              both)
                cpu=$(get_cpu_temp)
                gpu=$(get_gpu_temp)
                # Return the higher temperature
                if (( $(echo "$cpu > $gpu" | bc -l 2>/dev/null || echo "$cpu > $gpu") )); then
                  echo "$cpu"
                else
                  echo "$gpu"
                fi
                ;;
              *)
                get_cpu_temp
                ;;
            esac
          }

          # Determine color based on temperature
          get_color_for_temp() {
            local temp=$1

            if (( temp >= CRITICAL_THRESHOLD )); then
              echo "$CRITICAL_COLOR"
            elif (( temp >= HOT_THRESHOLD )); then
              echo "$HOT_COLOR"
            elif (( temp >= WARM_THRESHOLD )); then
              echo "$WARM_COLOR"
            else
              echo "$COOL_COLOR"
            fi
          }

          # Set OpenRGB color
          set_openrgb_color() {
            local color=$1
            if command -v openrgb &>/dev/null; then
              # Convert hex to RGB format for OpenRGB
              local r=$((16#${color:0:2}))
              local g=$((16#${color:2:2}))
              local b=$((16#${color:4:2}))

              # Set color for device
              openrgb -d $OPENRGB_DEVICE -c "$r,$g,$b" 2>/dev/null || true
            fi
          }

          # Set Razer color (if available)
          set_razer_color() {
            local color=$1
            if command -v razer-cli &>/dev/null; then
              # Convert hex to RGB format
              local r=$((16#${color:0:2}))
              local g=$((16#${color:2:2}))
              local b=$((16#${color:4:2}))

              razer-cli -c "$r,$g,$b" 2>/dev/null || true
            fi
          }

          # Set Wraith Prism color (if available)
          set_wraith_color() {
            local color=$1
            if command -v cm-rgb &>/dev/null; then
              cm-rgb -c "$color" 2>/dev/null || true
            fi
          }

          # Main control loop
          log "Starting temperature-reactive RGB control"
          log "Sensor: $SENSOR_TYPE | Thresholds: $COOL_THRESHOLD°C / $WARM_THRESHOLD°C / $HOT_THRESHOLD°C"

          # Initialize with current temperature
          current_temp=$(get_temperature)
          current_color=$(get_color_for_temp "$current_temp")
          log "Initial temperature: $current_temp°C -> Color: #$current_color"

          # Set initial colors
          set_openrgb_color "$current_color"
          set_razer_color "$current_color"
          set_wraith_color "$current_color"

          last_color="$current_color"

          # Main loop
          while true; do
            temp=$(get_temperature)
            new_color=$(get_color_for_temp "$temp")

            # Only update if color changed
            if [[ "$new_color" != "$last_color" ]]; then
              log "Temperature: $temp°C -> Color: #$new_color"
              set_openrgb_color "$new_color"
              set_razer_color "$new_color"
              set_wraith_color "$new_color"
              last_color="$new_color"
            fi

            sleep "$UPDATE_INTERVAL"
          done
        '';
        # Security hardening
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        RestrictRealtime = true;
        RestrictAddressFamilies = ["AF_UNIX"];
      };
    };

    # Helper script: Manual RGB control
    environment.etc."rgb-control.sh".source = pkgs.writeShellScriptBin "rgb-control" ''
      #!/usr/bin/env bash
      # RGB Control Helper Script

      COLOR=''${1:-"0000FF"}  # Default to blue
      MODE=''${2:-"static"}   # static, rainbow, breathe, etc.

      echo "RGB Control: Setting color to #$COLOR (mode: $MODE)"

      # OpenRGB
      if command -v openrgb &>/dev/null; then
        echo "Setting OpenRGB color..."
        r=$((16#${COLOR:0:2}))
        g=$((16#${COLOR:2:2}))
        b=$((16#${COLOR:4:2}))
        openrgb -d 0 -c "$r,$g,$b" 2>/dev/null || true
      fi

      # Razer
      if command -v razer-cli &>/dev/null; then
        echo "Setting Razer color..."
        r=$((16#${COLOR:0:2}))
        g=$((16#${COLOR:2:2}))
        b=$((16#${COLOR:4:2}))
        razer-cli -c "$r,$g,$b" 2>/dev/null || true
      fi

      # Wraith Prism
      if command -v cm-rgb &>/dev/null; then
        echo "Setting Wraith Prism color..."
        cm-rgb -c "$COLOR" 2>/dev/null || true
      fi

      echo "Done!"
    '';
  };
}
