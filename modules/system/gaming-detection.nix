# Gaming Detection Module
# Pure gaming detection service - monitors GameMode daemon and GPU patterns
# Exports gaming state for other services to consume
# NO service control (mining pause/resume handled by K8s Volcano scheduler)
{
  config,
  pkgs,
  lib,
  ...
}: {
  options.services.gaming-detection = {
    enable = lib.mkEnableOption "Gaming detection service";

    checkInterval = lib.mkOption {
      type = lib.types.int;
      default = 10;
      description = "Check interval in seconds";
    };

    logFile = lib.mkOption {
      type = lib.types.str;
      default = "/var/log/gaming-detection.log";
      description = "Path to log file";
    };
  };

  config = lib.mkIf config.services.gaming-detection.enable {
    systemd.services.gaming-detection = {
      description = "Gaming Detection - GameMode and GPU pattern monitoring";
      wantedBy = ["multi-user.target"];
      after = ["network.target"];
      path = with pkgs; [
        procps # pgrep
        util-linux # runuser for GameMode detection
        gnugrep # grep
        coreutils # echo, cat, etc.
      ];

      serviceConfig = {
        Type = "simple";
        Environment = "PATH=${
          lib.makeBinPath (
            with pkgs; [
              procps
              util-linux
              gnugrep
              coreutils
            ]
          )
        }:/run/current-system/sw/bin";
        ExecStart = "${pkgs.writeShellScriptBin "gaming-detection" ''
          # Gaming Detection Service
          # Monitors GameMode daemon and GPU utilization patterns
          # Exports state to /run/gaming-detection/gaming_state
          # Exports metrics to node_exporter textfile collector

          set -euo pipefail

          LOG_FILE="${config.services.gaming-detection.logFile}"
          STATE_DIR="/run/gaming-detection"
          STATE_FILE="$STATE_DIR/gaming_state"
          CHECK_INTERVAL="${toString config.services.gaming-detection.checkInterval}"

          # Logging function
          log() {
              echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
          }

          # Get hostname for metrics
          get_hostname() {
              hostname
          }

          # ============================================================================
          # GAMEMODE DETECTION (Primary Method)
          # ============================================================================
          # Detect gaming using GameMode daemon (primary detection method)
          # Returns: 1 if gaming active, 0 if not, 2 if unavailable (use GPU fallback)
          # Uses: gamemoded -s (outputs "gamemode is active" or "gamemode is inactive")
          detect_gaming_gamemode() {
              # Check if gamemoded is available
              if ! command -v gamemoded &>/dev/null; then
                  log "GameMode not installed - will use GPU fallback"
                  return 2  # Special code for "not available"
              fi

              # Query GameMode state as the user (GameMode runs in user session)
              # Try common usernames; if none work, fall back to GPU detection
              local gaming_output=""
              local target_user=""

              # Try to detect the logged-in user (the one with a running X session)
              for user in j_kro root; do
                  if [[ -d "/home/$user" ]] || [[ "$user" == "root" ]]; then
                      gaming_output=$(runuser -u "$user" -- gamemoded -s 2>/dev/null) && break
                  fi
              done

              # If runuser didn't work, try sudo -u
              if [[ -z "$gaming_output" ]] || [[ "$gaming_output" != *"gamemode"* ]]; then
                  gaming_output=$(sudo -u j_kro gamemoded -s 2>/dev/null)
              fi

              # Parse the output: "gamemode is active" or "gamemode is inactive"
              if [[ "$gaming_output" == *"active"* ]]; then
                  log "GameMode: Gaming detected"
                  return 1  # Gaming active
              elif [[ "$gaming_output" == *"inactive"* ]]; then
                  log "GameMode: No gaming detected"
                  return 0  # No gaming
              else
                  log "GameMode: Daemon not responding (output: '$gaming_output') - will use GPU fallback"
                  return 2  # Unavailable
              fi
          }

          # ============================================================================
          # GPU PATTERN DETECTION (Fallback Method)
          # ============================================================================
          # Detect gaming by analyzing GPU utilization patterns (fallback)
          # Returns: 1 if gaming pattern detected, 0 if mining/other pattern
          # Uses: nvidia-smi to analyze utilization variability over time
          detect_gpu_pattern() {
              # Need NVIDIA GPU
              if ! command -v nvidia-smi &>/dev/null; then
                  log "No NVIDIA GPU available - assume no gaming"
                  return 0
              fi

              # Get current GPU utilization
              local current_util
              current_util=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null | head -1)

              if [[ -z "$current_util" ]]; then
                  log "Failed to query GPU utilization - assume no gaming"
                  return 0
              fi

              # Read previous utilization from state file (if exists)
              local prev_util=""
              local util_history_file="$STATE_DIR/gpu-util-history"
              if [[ -f "$util_history_file" ]]; then
                  source "$util_history_file"
                  prev_util="$LAST_GPU_UTIL"
              fi

              # Save current utilization
              mkdir -p "$STATE_DIR"
              echo "LAST_GPU_UTIL=$current_util" > "$util_history_file"

              # If we don't have history, can't detect pattern yet
              if [[ -z "$prev_util" ]]; then
                  log "No GPU utilization history - assume no gaming"
                  return 0
              fi

              # Calculate variability (simple absolute difference)
              local util_diff
              util_diff=$((current_util - prev_util))
              if [[ "$util_diff" -lt 0 ]]; then
                  util_diff=$((-util_diff))
              fi

              # Gaming pattern: High utilization with HIGH variability (>15% change)
              # Mining pattern: High utilization with LOW variability (<5% change)
              if [[ "$current_util" -gt 80 ]] && [[ "$util_diff" -gt 15 ]]; then
                  log "GPU pattern: Gaming detected (util=$current_util%, variance=$util_diff%)"
                  return 1
              else
                  log "GPU pattern: No gaming (util=$current_util%, variance=$util_diff%)"
                  return 0
              fi
          }

          # ============================================================================
          # UNIFIED GAMING DETECTION
          # ============================================================================
          # Unified gaming detection (GameMode primary, GPU fallback)
          # Returns: exit code 1 if gaming detected, 0 if not
          #          echoes detection method to stdout ("gamemode", "gpu_fallback", "none")
          detect_gaming() {
              # Try GameMode first (authoritative)
              detect_gaming_gamemode
              local gamemode_result=$?

              case "$gamemode_result" in
                  0|1)
                      # GameMode available - use its result
                      if [[ "$gamemode_result" == "1" ]]; then
                          echo "gamemode"
                      else
                          echo "none"
                      fi
                      return $gamemode_result
                      ;;
                  2)
                      # GameMode unavailable - use GPU fallback
                      log "GameMode unavailable, using GPU pattern detection"
                      detect_gpu_pattern
                      local gpu_result=$?
                      if [[ "$gpu_result" == "1" ]]; then
                          echo "gpu_fallback"
                      else
                          echo "none"
                      fi
                      return $gpu_result
                      ;;
                  *)
                      log "Unexpected GameMode result: $gamemode_result"
                      echo "none"
                      return 0
                      ;;
              esac
          }

          # ============================================================================
          # STATE MANAGEMENT
          # ============================================================================
          # Read gaming state from file
          # Sets: GAMING_ACTIVE (0 or 1), DETECTION_METHOD, HYSTERESIS_COUNT, PAUSE_COUNT
          read_gaming_state() {
              if [[ -f "$STATE_FILE" ]]; then
                  source "$STATE_FILE"
              else
                  # Default state
                  GAMING_ACTIVE=0
                  DETECTION_METHOD="none"
                  HYSTERESIS_COUNT=0
                  PAUSE_COUNT=0
              fi
          }

          # Write gaming state to file
          write_gaming_state() {
              local gaming_active=$1  # 0 or 1
              local detection_method=$2  # "gamemode" or "gpu_fallback" or "none"
              local hysteresis_count=$3  # countdown before resume (0-3)
              local pause_count=$4  # total number of pauses

              mkdir -p "$STATE_DIR"
              {
                  echo "GAMING_ACTIVE=$gaming_active"
                  echo "DETECTION_METHOD=$detection_method"
                  echo "HYSTERESIS_COUNT=$hysteresis_count"
                  echo "PAUSE_COUNT=$pause_count"
                  echo "LAST_UPDATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
              } > "$STATE_FILE"
          }

          # Export gaming state to Prometheus via node_exporter textfile collector
          export_gaming_metric() {
              local gaming_active=$1  # 0 or 1
              local detection_method=$2  # "gamemode" or "gpu_fallback" or "none"
              local hostname=$(get_hostname)

              local metric_dir="/var/lib/node_exporter/textfile_collector"
              local metric_file="$metric_dir/gaming.prom"

              # Ensure directory exists
              if [[ ! -d "$metric_dir" ]]; then
                  mkdir -p "$metric_dir" || {
                      log "Failed to create node_exporter directory: $metric_dir"
                      return 1
                  }
              fi

              # Write metric (with help and type for Prometheus)
              {
                  echo "# HELP gaming_active Whether a game is currently running (1=yes, 0=no)"
                  echo "# TYPE gaming_active gauge"
                  echo "gaming_active{host=\"$hostname\",detection_method=\"$detection_method\"} $gaming_active"
                  echo "# HELP gaming_detection_method Which detection method identified the gaming state"
                  echo "# TYPE gaming_detection_method gauge"
                  echo "gaming_detection_method{host=\"$hostname\",method=\"$detection_method\"} 1"
              } > "$metric_file"

              log "Exported gaming metric: gaming_active=$gaming_active (method=$detection_method)"
          }

          # Manage gaming state with hysteresis
          # Parameters: $1 = gaming_detected (0/1), $2 = detection_method ("gamemode"/"gpu_fallback"/"none")
          manage_gaming_state() {
              local current_gaming=$1  # 1 if gaming, 0 if not
              local detection_method=$2  # "gamemode" or "gpu_fallback"

              # Read previous state
              local previous_gaming=0
              local hysteresis_count=0
              local pause_count=0

              read_gaming_state
              previous_gaming=$GAMING_ACTIVE
              hysteresis_count=$HYSTERESIS_COUNT
              pause_count=$PAUSE_COUNT

              # State transition: NOT gaming -> gaming
              # Update state immediately
              if [[ "$previous_gaming" == "0" ]] && [[ "$current_gaming" == "1" ]]; then
                  log "Gaming STARTED (detected by $detection_method)"
                  pause_count=$((pause_count + 1))
                  write_gaming_state 1 "$detection_method" 0 "$pause_count"

              # State transition: gaming -> NOT gaming
              # Start hysteresis countdown
              elif [[ "$previous_gaming" == "1" ]] && [[ "$current_gaming" == "0" ]]; then
                  log "Gaming STOPPED - starting hysteresis countdown (3 checks)"
                  write_gaming_state 0 "$detection_method" 3 "$pause_count"

              # State: Gaming stopped, in hysteresis countdown
              # Decrement counter
              elif [[ "$previous_gaming" == "0" ]] && [[ "$current_gaming" == "0" ]] && [[ "$hysteresis_count" -gt 0 ]]; then
                  local new_count=$((hysteresis_count - 1))
                  log "Hysteresis countdown: $hysteresis_count -> $new_count"
                  write_gaming_state 0 "$detection_method" "$new_count" "$pause_count"

              # State: No change (gaming or not gaming)
              # Just update state file with current timestamp
              else
                  write_gaming_state "$current_gaming" "$detection_method" "$hysteresis_count" "$pause_count"
              fi
          }

          # ============================================================================
          # MAIN LOOP
          # ============================================================================
          log "Starting gaming detection service (check interval: ''${CHECK_INTERVAL}s)"
          log "State file: $STATE_FILE"
          log "Metrics: /var/lib/node_exporter/textfile_collector/gaming.prom"

          # Create state directory
          mkdir -p "$STATE_DIR"

          while true; do
              # Detect gaming
              gaming_output=$(detect_gaming)
              gaming_detected=$?
              detection_method="$gaming_output"

              # Manage state with hysteresis
              manage_gaming_state "$gaming_detected" "$detection_method"

              # Export to Prometheus
              export_gaming_metric "$gaming_detected" "$detection_method"

              sleep "$CHECK_INTERVAL"
          done
        ''}/bin/gaming-detection";

        Restart = "on-failure";
        RestartSec = "10s";
      };
    };

    # Runtime state directory and node_exporter textfile collector directory
    systemd.tmpfiles.rules = [
      "d /run/gaming-detection 0755 root root - -"
      "d /var/lib/node_exporter/textfile_collector 0755 root root - -"
    ];
  };
}
