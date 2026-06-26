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

    openrgb.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable OpenRGB for motherboard/GPU RGB control";
    };

    openrazer.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable OpenRAZER for Razer peripherals";
    };

    wraithRgb.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable cm-rgb for AMD Wraith Prism cooler";
    };

    temperatureReactive = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable temperature-reactive RGB color changes";
      };

      sensor = lib.mkOption {
        type = lib.types.str;
        default = "cpu";
        example = "gpu";
        description = "Temperature sensor to use: cpu, gpu, or both";
      };

      thresholds = lib.mkOption {
        type = lib.types.attrsOf lib.types.int;
        default = {
          cool = 55;
          warm = 70;
          hot = 80;
        };
        description = "Temperature thresholds for color changes";
      };

      colors = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = {
          cool = "0000FF";
          warm = "FFFF00";
          hot = "FF4500";
          critical = "FF0000";
        };
        description = "RGB colors for temperature zones";
      };

      interval = lib.mkOption {
        type = lib.types.int;
        default = 5;
        description = "Temperature polling interval in seconds";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages =
      [
        pkgs.openrgb
      ]
      ++ lib.optionals cfg.openrgb.enable [
        pkgs.openrgb-plugin-effects
        pkgs.python3Packages.openrgb-python
      ]
      ++ lib.optionals cfg.openrazer.enable [
        pkgs.polychromatic
        pkgs.razer-cli
      ]
      ++ lib.optionals cfg.wraithRgb.enable [
        pkgs.cm-rgb
      ];

    boot.kernelModules =
      [
        "i2c-dev"
        "i2c-piix4"
        "i2c-i801"
      ]
      ++ lib.optionals cfg.openrazer.enable [
        "razeraccessory"
        "razerkbd"
        "razerkraken"
        "razermouse"
      ];

    services.udev.extraRules = lib.mkIf cfg.openrgb.enable ''
      SUBSYSTEM=="i2c-dev", MODE="0666"
      SUBSYSTEM=="leds", MODE="0666"

      ATTR{idVendor}=="1b1c", ATTR{idProduct}=="1b27", MODE="0666"

      KERNEL=="hidraw*", MODE="0666"
    '';

    hardware.openrazer = lib.mkIf cfg.openrazer.enable {
      enable = lib.mkDefault true;
      users = ["j_kro"];
    };
    boot.extraModulePackages = lib.optionals cfg.openrazer.enable [
      config.boot.kernelPackages.openrazer
    ];

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

                    COOL_THRESHOLD=${toString cfg.temperatureReactive.thresholds.cool}
                    WARM_THRESHOLD=${toString cfg.temperatureReactive.thresholds.warm}
                    HOT_THRESHOLD=${toString cfg.temperatureReactive.thresholds.hot}
                    CRITICAL_THRESHOLD=85

                    UPDATE_INTERVAL=${toString cfg.temperatureReactive.interval}

                    SENSOR_TYPE="${cfg.temperatureReactive.sensor}"

                    COOL_COLOR="${cfg.temperatureReactive.colors.cool}"
                    WARM_COLOR="${cfg.temperatureReactive.colors.warm}"
                    HOT_COLOR="${cfg.temperatureReactive.colors.hot}"
                    CRITICAL_COLOR="${cfg.temperatureReactive.colors.critical}"

                    MOTHERBOARD_DEVICE=6
                    GPU_DEVICE=2
                    FAN_DEVICE=7
                    AIO_DEVICE=9
                    OPENRAZER_DEVICE=0

                    log() {
                      echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
                    }

                    get_cpu_temp() {
                      for sensor in /sys/class/thermal/thermal_zone*/temp; do
                        if [[ -r "$sensor" ]]; then
                          temp=$(cat "$sensor" 2>/dev/null || echo "0")
                          if [[ "$temp" -gt 1000 ]]; then
                            echo $((temp / 1000))
                            return 0
                          fi
                        fi


          done

                      if command -v sensors &>/dev/null; then
                        sensors -j 2>/dev/null | grep -oE '"Core.*_input": [0-9.]+' | head -1 | grep -oE '[0-9.]+' || echo "0"
                      else
                        echo "0"
                      fi
                    }

                    get_gpu_temp() {
                      if command -v nvidia-smi &>/dev/null; then
                        nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null | head -1 || echo "0"
                      elif command -v rocm-smi &>/dev/null; then
                        rocm-smi --showtemp --json 2>/dev/null | grep -oE '"GPU temp": [0-9.]+' | grep -oE '[0-9.]+' | head -1 || echo "0"
                      else
                        echo "0"
                      fi
                    }

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

                    set_openrgb_color() {
                      local color=$1

                      if [[ ! "$color" =~ ^[0-9A-Fa-f]{6}$ ]]; then
                        echo "Invalid color format: $color (expected 6-digit hex)"
                        return 1
                      fi

                      if command -v openrgb &>/dev/null; then
                        local r=$((16#$(echo "$color" | cut -c1-2))) g=$((16#$(echo "$color" | cut -c3-4))) b=$((16#$(echo "$color" | cut -c5-6)))

                        openrgb -d $MOTHERBOARD_DEVICE -m Direct -c "$r,$g,$b" 2>/dev/null || true
                        openrgb -d $GPU_DEVICE -m Direct -c "$r,$g,$b" 2>/dev/null || true
                        openrgb -d $FAN_DEVICE -m Direct -c "$r,$g,$b" 2>/dev/null || true
                        openrgb -d $AIO_DEVICE -m Direct -c "$r,$g,$b" 2>/dev/null || true
                      fi
                    }

                    set_razer_color() {
                      local color=$1

                      if [[ ! "$color" =~ ^[0-9A-Fa-f]{6}$ ]]; then
                        return 1
                      fi

                      if command -v razer-cli &>/dev/null; then
                        local r=$((16#$(echo "$color" | cut -c1-2))) g=$((16#$(echo "$color" | cut -c3-4))) b=$((16#$(echo "$color" | cut -c5-6)))

                        razer-cli -c "$r,$g,$b" 2>/dev/null || true
                      fi
                    }

                    set_wraith_color() {
                      local color=$1

                      if [[ ! "$color" =~ ^[0-9A-Fa-f]{6}$ ]]; then
                        return 1
                      fi

                      if command -v cm-rgb &>/dev/null; then
                        cm-rgb -c "$color" 2>/dev/null || true
                      fi
                    }

                    log "Starting temperature-reactive RGB control"
                    log "Sensor: $SENSOR_TYPE | Thresholds: $COOL_THRESHOLD°C / $WARM_THRESHOLD°C / $HOT_THRESHOLD°C"

                    current_temp=$(get_temperature)
                    current_color=$(get_color_for_temp "$current_temp")
                    log "Initial temperature: $current_temp°C -> Color: #$current_color"

                    set_openrgb_color "$current_color"
                    set_razer_color "$current_color"
                    set_wraith_color "$current_color"

                    last_color="$current_color"

                    while true; do
                      temp=$(get_temperature)
                      new_color=$(get_color_for_temp "$temp")

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
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        RestrictRealtime = true;
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
        ];
      };
    };

    environment.etc."rgb-control.sh".source = pkgs.writeShellScriptBin "rgb-control" ''
      #!/usr/bin/env bash

      COLOR=''${1:-"0000FF"}
      MODE=''${2:-"static"}

      echo "RGB Control: Setting color to #$COLOR (mode: $MODE)"

      if command -v openrgb &>/dev/null; then
        echo "Setting OpenRGB color..."
        r=$((16#$(echo "$COLOR" | cut -c1-2))) g=$((16#$(echo "$COLOR" | cut -c3-4))) b=$((16#$(echo "$COLOR" | cut -c5-6)))
        openrgb -d 0 -c "$r,$g,$b" 2>/dev/null || true
      fi

      if command -v razer-cli &>/dev/null; then
        echo "Setting Razer color..."
        r=$((16#$(echo "$COLOR" | cut -c1-2))) g=$((16#$(echo "$COLOR" | cut -c3-4))) b=$((16#$(echo "$COLOR" | cut -c5-6)))
        razer-cli -c "$r,$g,$b" 2>/dev/null || true
      fi

      if command -v cm-rgb &>/dev/null; then
        echo "Setting Wraith Prism color..."
        cm-rgb -c "$COLOR" 2>/dev/null || true
      fi

      echo "Done!"
    '';
  };
}
