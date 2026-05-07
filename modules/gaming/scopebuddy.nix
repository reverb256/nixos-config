{
  config,
  lib,
  pkgs,
  inputs ? null,
  ...
}:
with lib; let
  cfg = config.programs.scopebuddy;
  scopebuddyCfg = config.services.gaming;
in {
  options.programs.scopebuddy = {
    enable = mkEnableOption "ScopeBuddy - gamescope wrapper with maximum automation";

    user = mkOption {
      type = types.str;
      default = "j_kro";
      example = "alice";
      description = "Username for whom ScopeBuddy is enabled";
    };

    package = mkOption {
      type = types.nullOr types.package;
      default =
        if inputs != null && inputs ? scopebuddy
        then inputs.scopebuddy.packages.${pkgs.stdenv.hostPlatform.system}.default
        else null;
      defaultText = literalExpression "inputs.scopebuddy.packages.\${system}.default";
      description = "ScopeBuddy package to use";
    };

    autoDetect = {
      resolution = mkOption {
        type = types.bool;
        default = true;
        description = "Automatically detect and set display resolution";
      };

      hdr = mkOption {
        type = types.bool;
        default = true;
        description = "Automatically enable HDR if display has HDR enabled";
      };

      vrr = mkOption {
        type = types.bool;
        default = true;
        description = "Automatically enable adaptive sync if VRR is active";
      };

      refreshRate = mkOption {
        type = types.bool;
        default = true;
        description = "Automatically detect and set optimal refresh rate";
      };

      scaling = mkOption {
        type = types.bool;
        default = true;
        description = "Automatically detect and configure scaling (FSR/NIS)";
      };
    };

    performance = {
      enableGameMode = mkOption {
        type = types.bool;
        default = true;
        description = "Enable GameMode integration for performance optimization";
      };

      mangoHud = mkOption {
        type = types.bool;
        default = true;
        description = "Auto-configure MangoHUD for games launched with ScopeBuddy";
      };

      cpuGovernor = mkOption {
        type = types.nullOr (types.enum ["performance" "schedutil"]);
        default = "performance";
        description = "CPU governor to set when gaming (null to disable)";
      };
    };

    profiles = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          enable = mkOption {
            type = types.bool;
            default = true;
            description = "Enable this profile";
          };

          gamescopeArgs = mkOption {
            type = types.listOf types.str;
            default = [];
            description = "Custom gamescope arguments for this game";
          };

          envVars = mkOption {
            type = types.attrsOf types.str;
            default = {};
            description = "Custom environment variables for this game";
          };

          mangoHudPreset = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "MangoHUD configuration preset to use";
          };
        };
      });
      default = {};
      description = "Per-game automation profiles";
      example = {
        cyberpunk2077 = {
          enable = true;
          gamescopeArgs = ["-f" "--rt" "--force-grab-cursor"];
          envVars = {VKD3D_CONFIG = "dx12";};
        };
      };
    };

    scripts = mkOption {
      type = types.bool;
      default = true;
      description = "Enable auto-detection helper scripts";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs;
      [
        jq
        wlr-randr
      ]
      ++ optionals cfg.performance.enableGameMode [gamemode]
      ++ optionals cfg.performance.mangoHud [mangohud]
      ++ optionals cfg.scripts [
        (
          pkgs.writeShellScriptBin "scopebuddy-detect" ''
            #!/usr/bin/env bash

            set -euo pipefail

            CONFIG_DIR="''${HOME}/.config/scopebuddy"
            CONFIG_FILE="''${CONFIG_DIR}/scb.conf"

            mkdir -p "''${CONFIG_DIR}"

            echo "[ScopeBuddy] Detecting display capabilities..."

            if command -v wlr-randr &> /dev/null; then
              RESOLUTION=$(wlr-randr --json | jq -r '.[0].modes | map(select(.current == true)) | .[0] | "\(.width)x\(.height)"')
              echo "[ScopeBuddy] Detected resolution: ''${RESOLUTION}"
            else
              RESOLUTION="1920x1080"
              echo "[ScopeBuddy] Using fallback resolution: ''${RESOLUTION}"
            fi

            HDR_CAPABLE=false
            if command -v wlr-randr &> /dev/null; then
              if wlr-randr --json | jq -e '.[0].enabled | not' > /dev/null; then
                if wlr-randr --json | jq -e '.[0].hdr_enabled == true' > /dev/null 2>&1; then
                  HDR_CAPABLE=true
                  echo "[ScopeBuddy] HDR detected and will be enabled"
                fi
              fi
            fi

            VRR_CAPABLE=false
            if command -v wlr-randr &> /dev/null; then
              if wlr-randr --json | jq -e '.[0].adaptive_sync == true' > /dev/null 2>&1; then
                VRR_CAPABLE=true
                echo "[ScopeBuddy] VRR detected and will be enabled"
              fi
            fi

            REFRESH_RATE=144
            if command -v wlr-randr &> /dev/null; then
              DETECTED_HZ=$(wlr-randr --json | jq -r '.[0].modes | map(select(.current == true)) | .[0].refresh // 144')
              REFRESH_RATE=$(echo "''${DETECTED_HZ}" | cut -d'.' -f1)
              echo "[ScopeBuddy] Detected refresh rate: ''${REFRESH_RATE} Hz"
            fi

            cat > "''${CONFIG_FILE}" << EOF

            [Display]
            Resolution=''${RESOLUTION}
            RefreshRate=''${REFRESH_RATE}

            [HDR]
            Enabled=''${HDR_CAPABLE}

            [VRR]
            Enabled=''${VRR_CAPABLE}

            [Scaling]
            Method=FSR
            Sharpness=5
            EOF

            echo "[ScopeBuddy] Configuration written to ''${CONFIG_FILE}"
            echo "[ScopeBuddy] Ready to launch with optimal settings!"
          ''
        )
        (
          pkgs.writeShellScriptBin "scopebuddy-launch" ''
            #!/usr/bin/env bash

            set -euo pipefail

            CURR_GOVERNOR=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "unknown")

            ${optionalString (cfg.performance.cpuGovernor != null) ''
              if [ "''${CURR_GOVERNOR}" != "${cfg.performance.cpuGovernor}" ]; then
                echo "[ScopeBuddy] Setting CPU governor to ${cfg.performance.cpuGovernor}"
                echo ${cfg.performance.cpuGovernor} | ${pkgs.sudo}/bin/sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor > /dev/null
              fi
            ''}

            echo "[ScopeBuddy] Launching: $@"
            ${
              if cfg.package != null
              then "${cfg.package}/bin/scopebuddy"
              else "scopebuddy"
            } "$@"

            ${optionalString (cfg.performance.cpuGovernor != null) ''
              if [ "''${CURR_GOVERNOR}" != "unknown" ]; then
                echo "[ScopeBuddy] Restoring CPU governor to ''${CURR_GOVERNOR}"
                echo "''${CURR_GOVERNOR}" | ${pkgs.sudo}/bin/sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor > /dev/null
              fi
            ''}
          ''
        )
      ];

    programs.fish.shellAliases = {
      scb =
        if cfg.package != null
        then "${cfg.package}/bin/scopebuddy"
        else "scopebuddy";
      scopebuddy =
        if cfg.package != null
        then "${cfg.package}/bin/scopebuddy"
        else "scopebuddy";
      scb-detect = "scopebuddy-detect";
      scb-launch = "scopebuddy-launch";
    };

    environment.sessionVariables =
      {
        SCB_CONFIG_PATH = "/home/${cfg.user}/.config/scopebuddy/scb.conf";
        SCB_PROFILES_PATH = "/home/${cfg.user}/.config/scopebuddy/profiles";
      }
      // optionalAttrs cfg.autoDetect.resolution {
        SCB_AUTO_RES = "1";
      }
      // optionalAttrs scopebuddyCfg.hdr.enable {
        SCB_AUTO_HDR = "1";
      }
      // optionalAttrs cfg.autoDetect.vrr {
        SCB_AUTO_VRR = "1";
      }
      // optionalAttrs cfg.autoDetect.refreshRate {
        SCB_AUTO_HZ = "1";
      }
      // optionalAttrs cfg.autoDetect.scaling {
        SCB_AUTO_SCALE = "1";
      }
      // optionalAttrs cfg.performance.enableGameMode {
        SCB_GAMEMODE = "1";
      }
      // optionalAttrs cfg.performance.mangoHud {
        SCB_MANGOHUD = "1";
      };

    systemd.tmpfiles.rules =
      [
        "d /home/${cfg.user}/.config/scopebuddy 0755 ${cfg.user} users -"
        "d /home/${cfg.user}/.config/scopebuddy/appid 0755 ${cfg.user} users -"
        "d /home/${cfg.user}/.config/scopebuddy/profiles 0755 ${cfg.user} users -"
      ]
      ++ optionals scopebuddyCfg.hdr.enable [
        "f /home/${cfg.user}/.config/scopebuddy/scb.conf 0644 ${cfg.user} users - -"
      ];

    programs.gamemode = mkIf cfg.performance.enableGameMode {
      enable = true;
      settings = {
        general = {
          reaprocess = true;
          desiredgov = cfg.performance.cpuGovernor or "performance";
        };
        gpu = {
          apply_gpu_optimisations = "accept-responsibility";
          gpu_device = 0;
          amd_performance_level = "high";
        };
      };
    };
  };
}
