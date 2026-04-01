# Gaming Detection Module (Pure Sensor)
# Detects gaming via GameMode daemon and GPU utilization patterns
# Writes state to /run/gpu-workload/gaming_state
# Exports Prometheus metrics to node_exporter textfile collector
#
# Responsibilities:
#   - Detect gaming via gw_detect_gaming() (GameMode primary, GPU fallback)
#   - Manage state with hysteresis via gw_write_gaming_state()
#   - Export Prometheus metrics via gw_export_gaming_metric()
#
# Does NOT:
#   - Run nvidia-smi (GPU profile management is in gpu-profiles.nix)
#   - Control mining services (mining control is in gpu-profiles.nix)
#   - Write profile requests (orchestration is in mining-coordinator.nix)
{ config, lib, pkgs, ... }:

let
  cfg = config.services.gpu-workload.gaming-detection;
in {
  options.services.gpu-workload.gaming-detection = {
    enable = lib.mkEnableOption "GPU workload gaming detection (pure sensor)";

    checkInterval = lib.mkOption {
      type = lib.types.int;
      default = 10;
      description = "Gaming detection check interval in seconds";
    };

    logFile = lib.mkOption {
      type = lib.types.str;
      default = "/var/log/gpu-workload-gaming-detection.log";
      description = "Path to the gaming detection log file";
    };

    hysteresisCycles = lib.mkOption {
      type = lib.types.int;
      default = 3;
      description = "Number of consecutive idle checks before clearing GAMING_ACTIVE";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.gpu-workload-gaming-detection = {
      description = "GPU Workload Gaming Detection (Pure Sensor)";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      path = with pkgs; [
        procps    # pgrep
        util-linux # runuser for GameMode detection
        gnugrep   # grep
        coreutils # echo, cat, mkdir, date, etc.
      ];

      serviceConfig = {
        Type = "simple";
        Environment = "PATH=${lib.makeBinPath (with pkgs; [ procps util-linux gnugrep coreutils ])}:/run/current-system/sw/bin";
        ExecStart = lib.getExe (pkgs.writeShellScriptBin "gpu-workload-gaming-detection" ''
          # GPU Workload Gaming Detection Service (Pure Sensor)
          # Monitors GameMode daemon and GPU utilization patterns
          # Writes state to /run/gpu-workload/gaming_state
          # Exports metrics to node_exporter textfile collector
          #
          # Does NOT control nvidia-smi or mining services.

          set -euo pipefail

          # Source shared library (provides gw_* functions)
          . "$(command -v gpu-workload-lib)"

          # Configuration from NixOS options
          STATE_DIR="/run/gpu-workload"
          STATE_FILE="$STATE_DIR/gaming_state"
          CHECK_INTERVAL="${toString cfg.checkInterval}"
          HYSTERESIS_THRESHOLD="${toString cfg.hysteresisCycles}"
          LOG_FILE="${cfg.logFile}"

          # ============================================================================
          # HYSTERESIS STATE MANAGEMENT
          # ============================================================================

          # Manage gaming state with configurable hysteresis
          # Prevents rapid GAMING_ACTIVE flapping when gaming stops/starts intermittently
          # Parameters:
          #   $1 = gaming_detected (0 or 1)
          #   $2 = detection_method ("gamemode", "gpu_fallback", "none")
          manage_gaming_state() {
              local current_gaming="$1"
              local detection_method="$2"

              # Read previous state via shared library
              gw_read_gaming_state "$STATE_FILE"
              local previous_gaming="$GAMING_ACTIVE"
              local hysteresis_count="$HYSTERESIS_COUNT"
              local pause_count="$PAUSE_COUNT"

              # Transition: NOT gaming -> gaming (immediate)
              if [[ "$previous_gaming" == "0" ]] && [[ "$current_gaming" == "1" ]]; then
                  pause_count=$((pause_count + 1))
                  gw_log "Gaming STARTED (method=$detection_method, pause #$pause_count)"
                  gw_write_gaming_state 1 "$detection_method" 0 "$pause_count"

              # Transition: gaming -> NOT gaming (begin hysteresis)
              elif [[ "$previous_gaming" == "1" ]] && [[ "$current_gaming" == "0" ]]; then
                  gw_log "Gaming STOPPED - starting hysteresis ($HYSTERESIS_THRESHOLD cycles)"
                  # Keep GAMING_ACTIVE=1 during hysteresis, but set countdown
                  gw_write_gaming_state 1 "$detection_method" "$HYSTERESIS_THRESHOLD" "$pause_count"

              # Hysteresis countdown: still in cooldown, gaming not detected
              elif [[ "$current_gaming" == "0" ]] && [[ "$hysteresis_count" -gt 0 ]]; then
                  local new_count=$((hysteresis_count - 1))
                  if [[ "$new_count" -gt 0 ]]; then
                      gw_log "Hysteresis countdown: $hysteresis_count -> $new_count (GAMING_ACTIVE remains 1)"
                      # Stay in gaming state during hysteresis
                      gw_write_gaming_state 1 "$detection_method" "$new_count" "$pause_count"
                  else
                      # Hysteresis expired - transition to idle
                      gw_log "Hysteresis expired - transitioning to IDLE"
                      gw_write_gaming_state 0 "$detection_method" 0 "$pause_count"
                  fi

              # No state change (steady state)
              else
                  gw_write_gaming_state "$current_gaming" "$detection_method" "$hysteresis_count" "$pause_count"
              fi
          }

          # ============================================================================
          # MAIN LOOP
          # ============================================================================
          gw_log "Starting gaming detection service"
          gw_log "  Check interval: $CHECK_INTERVAL"
          gw_log "  Hysteresis cycles: $HYSTERESIS_THRESHOLD"
          gw_log "  State file: $STATE_FILE"
          gw_log "  Metrics: /var/lib/node_exporter/textfile_collector/gaming.prom"

          # Ensure state directory exists
          mkdir -p "$STATE_DIR"

          while true; do
              # Detect gaming via shared library (GameMode primary, GPU fallback)
              detection_method=$(gw_detect_gaming)
              gaming_detected=$?

              # Manage state with hysteresis
              manage_gaming_state "$gaming_detected" "$detection_method"

              # Read final state for Prometheus export
              gw_read_gaming_state "$STATE_FILE"
              gw_export_gaming_metric "$GAMING_ACTIVE" "$DETECTION_METHOD"

              sleep "$CHECK_INTERVAL"
          done
        '');

        Restart = "on-failure";
        RestartSec = "10s";
      };
    };

    # Runtime state directories
    systemd.tmpfiles.rules = lib.mkOptionDefault [
      "d /run/gpu-workload 0755 root root - -"
      "d /var/lib/node_exporter/textfile_collector 0755 root root - -"
    ];
  };
}
