# Compute Workload Monitor Module
# Autonomous GPU workload detection and profile management
# Detects workload type and adjusts GPU profiles automatically
# Manages mining pauses when AI/Gaming/Kubernetes GPU workloads detected
{
  config,
  pkgs,
  lib,
  ...
}: {
  options.services.compute-workload-monitor = {
    enable = lib.mkEnableOption "Compute workload monitor for GPU scheduling";

    checkInterval = lib.mkOption {
      type = lib.types.int;
      default = 10;
      description = "Check interval in seconds";
    };

    logFile = lib.mkOption {
      type = lib.types.str;
      default = "/var/log/compute-workload-monitor.log";
      description = "Path to log file";
    };
  };

  config = lib.mkIf config.services.compute-workload-monitor.enable {
    # Create the compute-workload-monitor service
    systemd.services.compute-workload-monitor = {
      description = "Compute Workload Monitor - GPU workload detection and profile management";
      wantedBy = ["multi-user.target"];
      after = [
        "network.target"
        "kubernetes.target"
      ];
      path = with pkgs; [
        procps # pgrep
        systemd # systemctl
        kubernetes # kubectl for Kubernetes GPU workload detection
        bc # for floating point arithmetic in nix-daemon CPU detection
        curl # for XMRig HTTP API control
      ];

      serviceConfig = {
        Type = "simple";
        Environment = "PATH=${
          lib.makeBinPath (
            with pkgs; [
              procps
              systemd
              kubernetes
            ]
          )
        }:/run/current-system/sw/bin";
        ExecStart = "${pkgs.writeShellScriptBin "compute-workload-monitor" ''
          # Autonomous GPU Workload Monitor
          # Detects workload type and adjusts GPU profiles automatically
          # Manages mining pauses when AI/Gaming/K8s workloads detected

          set -euo pipefail

          LOG_FILE="${config.services.compute-workload-monitor.logFile}"
          MINING_SERVICES=("lolminer-nvidia" "xmrig" "xmrig-flexible" "xmrig-always")
          BUILD_PROCESSES=("nixos-rebuild" "colmena" "nix-build" "nix-daemon" "nix-store" "gcc" "clang" "cargo build" "make" "cmake" "ninja")

          # Detect gaming using GameMode daemon (primary detection method)
          # Returns: 1 if gaming active, 0 if not, 2 if unavailable (use GPU fallback)
          # Uses: gamemoded -s (returns 1 if gaming, 0 if not)
          detect_gaming_gamemode() {
              # Check if gamemoded is available
              if ! command -v gamemoded &>/dev/null; then
                  log "GameMode not installed - will use GPU fallback"
                  return 2  # Special code for "not available"
              fi

              # Check if GameMode daemon is running
              if ! systemctl is-active --quiet gamemoded; then
                  log "GameMode daemon not running - will use GPU fallback"
                  return 2
              fi

              # Query GameMode state
              local gaming_state
              gaming_state=$(gamemoded -s 2>/dev/null || echo "0")

              # gamemoded -s returns 1 if gaming active, 0 if not
              if [[ "$gaming_state" == "1" ]]; then
                  log "GameMode: Gaming detected"
                  return 1  # Gaming active
              else
                  log "GameMode: No gaming detected"
                  return 0  # No gaming
              fi
          }

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
              local util_history_file="/tmp/gpu-util-history"
              if [[ -f "$util_history_file" ]]; then
                  source "$util_history_file"
                  prev_util="$LAST_GPU_UTIL"
              fi

              # Save current utilization
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
          # GAMING STATE MANAGEMENT
          # ============================================================================
          # State directory for gaming detection
          GAMING_STATE_DIR="/run/compute-workload-monitor"
          GAMING_STATE_FILE="$GAMING_STATE_DIR/gaming_state"

          # Read gaming state from file
          # Sets: GAMING_ACTIVE (0 or 1), DETECTION_METHOD ("gamemode", "gpu_fallback", "none")
          read_gaming_state() {
              if [[ -f "$GAMING_STATE_FILE" ]]; then
                  source "$GAMING_STATE_FILE"
              else
                  # Default state
                  GAMING_ACTIVE=0
                  DETECTION_METHOD="none"
              fi
          }

          # Write gaming state to file
          write_gaming_state() {
              local gaming_active=$1  # 0 or 1
              local detection_method=$2  # "gamemode" or "gpu_fallback" or "none"
              local hysteresis_count=$3  # countdown before resume (0-3)
              local pause_count=$4  # total number of pauses

              mkdir -p "$GAMING_STATE_DIR"
              {
                  echo "GAMING_ACTIVE=$gaming_active"
                  echo "DETECTION_METHOD=$detection_method"
                  echo "HYSTERESIS_COUNT=$hysteresis_count"
                  echo "PAUSE_COUNT=$pause_count"
              } > "$GAMING_STATE_FILE"
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
              } > "$metric_file"

              log "Exported gaming metric: gaming_active=$gaming_active (method=$detection_method)"
          }

          # Manage lolminer pause/resume based on gaming detection with hysteresis
          # Parameters: $1 = gaming_detected (0/1), $2 = detection_method ("gamemode"/"gpu_fallback"/"none")
          manage_lolminer_for_gaming() {
              local current_gaming=$1  # 1 if gaming, 0 if not
              local detection_method=$2  # "gamemode" or "gpu_fallback"

              # Read previous state
              local previous_gaming=0
              local hysteresis_count=0
              local pause_count=0

              if [[ -f "$GAMING_STATE_FILE" ]]; then
                  source "$GAMING_STATE_FILE"
                  previous_gaming=$GAMING_ACTIVE
                  hysteresis_count=$HYSTERESIS_COUNT
                  pause_count=$PAUSE_COUNT
              fi

              # State transition: NOT gaming -> gaming
              # Pause immediately
              if [[ "$previous_gaming" == "0" ]] && [[ "$current_gaming" == "1" ]]; then
                  log "Gaming STARTED (detected by $detection_method)"
                  log "Pausing lolminer-nvidia to free GPU for gaming"

                  if systemctl is-active --quiet lolminer-nvidia; then
                      systemctl stop lolminer-nvidia
                      pause_count=$((pause_count + 1))
                      log "lolminer-nvidia stopped (pause #$pause_count)"
                  else
                      log "lolminer-nvidia already stopped"
                  fi

                  # Update state
                  write_gaming_state 1 "$detection_method" 0 "$pause_count"

              # State transition: gaming -> NOT gaming
              # Start hysteresis countdown
              elif [[ "$previous_gaming" == "1" ]] && [[ "$current_gaming" == "0" ]]; then
                  log "Gaming STOPPED - starting hysteresis countdown (3 checks)"

                  # Initialize countdown at 3
                  write_gaming_state 0 "$detection_method" 3 "$pause_count"

              # State: Gaming stopped, in hysteresis countdown
              # Decrement counter, resume when reaches 0
              elif [[ "$previous_gaming" == "0" ]] && [[ "$current_gaming" == "0" ]] && [[ "$hysteresis_count" -gt 0 ]]; then
                  local new_count=$((hysteresis_count - 1))
                  log "Hysteresis countdown: $hysteresis_count -> $new_count"

                  if [[ "$new_count" -eq 0 ]]; then
                      log "Hysteresis complete - resuming lolminer-nvidia"

                      if systemctl is-active --quiet lolminer-nvidia; then
                          log "lolminer-nvidia already running"
                      else
                          systemctl start lolminer-nvidia
                          log "lolminer-nvidia started"
                      fi
                  fi

                  # Update state
                  write_gaming_state 0 "$detection_method" "$new_count" "$pause_count"

              # State: No change (gaming or not gaming)
              # Just update state file with current timestamp
              else
                  write_gaming_state "$current_gaming" "$detection_method" "$hysteresis_count" "$pause_count"
              fi
          }

          log() {
              echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
          }

          # Check for recent wrapper-initiated build events (lightweight visibility)
          check_build_wrapper_events() {
              local events_log="/run/gpu-scheduler/build-events.log"

              # Only check if we're detecting a build workload
              if [ ! -f "$events_log" ]; then
                  return 0
              fi

              # Get events from last 5 minutes
              local recent_events=$(grep "BUILD_START" "$events_log" 2>/dev/null | tail -5)

              if [ -n "$recent_events" ]; then
                  log "Recent wrapper-initiated builds detected (may overlap with current build detection)"
                  echo "$recent_events" | while read -r event; do
                  log "  Event: $event"
              done
              fi

              return 0
          }

          check_process_running() {
              local process="$1"
              pgrep -f "$process" >/dev/null
          }

          # ============================================================================
          # KUBERNETES GPU WORKLOAD DETECTION (Phase 1)
          # ============================================================================
          check_kubernetes_gpu_workload() {
              # Check if kubectl is available and cluster is accessible
              if ! command -v kubectl >/dev/null 2>&1; then
                  return 1
              fi

              # Check if we can connect to the cluster
              if ! kubectl get nodes >/dev/null 2>&1; then
                  return 1
              fi

              # Check for GPU pods across all namespaces
              # Look for pods with nvidia.com/gpu resource requests
              local gpu_pods=$(kubectl get pods --all-namespaces \
                  -o jsonpath='{range .items[?(@.spec.containers[*].resources.limits.nvidia\.com/gpu)]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}' \
                  2>/dev/null || echo "")

              if [ -n "$gpu_pods" ]; then
                  # Filter out non-running pods
                  local running_gpu_pods=$(echo "$gpu_pods" | while read -r pod; do
                      [ -z "$pod" ] && continue
                      local namespace=$(echo "$pod" | cut -d'/' -f1)
                      local name=$(echo "$pod" | cut -d'/' -f2)

                      if kubectl get pod "$name" -n "$namespace" -o jsonpath='{.status.phase}' 2>/dev/null | grep -q "Running"; then
                          echo "$pod"
                      fi
                  done)

                  if [ -n "$running_gpu_pods" ]; then
                      log "Kubernetes GPU workload detected: $running_gpu_pods"
                      return 0
                  fi
              fi

              return 1
          }

          check_incoming_build_job() {
              # Detect distributed build jobs from coordinators via SSH
              # This catches when nix-daemon on worker receives build job from coordinator
              local coordinators=("zephyr" "nexus" "forge")
              local hostname=$(hostname)

              # Skip if we are the coordinator (we already detect nix-build directly)
              for coord in "''${coordinators[@]}"; do
                  if [ "$hostname" = "$coord" ]; then
                      continue
                  fi

                  # Check for SSH connections from known coordinators
                  if command -v ss >/dev/null 2>&1; then
                      if ss -tnp 2>/dev/null | grep -q "ESTAB .*''${coord}.*ssh"; then
                          # Check if nix-daemon is using significant CPU (>30%)
                          local nix_pid=$(pgrep -o nix-daemon | head -1)
                          if [ -n "$nix_pid" ]; then
                              local nix_cpu=$(ps -p "$nix_pid" -o %cpu 2>/dev/null | tail -1)
                              if [ -n "$nix_cpu" ] && [ "$nix_cpu" != "%CPU" ]; then
                                  # Use bc for floating point comparison (30.0 threshold)
                                  if [ "$nix_cpu" \> "30.0" ] 2>/dev/null; then
                                      log "Detected incoming build from ''${coord} (nix-daemon CPU: ''${nix_cpu}%)"
                                      return 0
                                  fi
                              fi
                          fi
                      fi
                  fi
              done

              return 1
          }

          # ============================================================================
          # PSI-BASED BUILD DETECTION (kernel-level resource contention detection)
          # ============================================================================
          # PSI (Pressure Stall Information) provides kernel-level signals for resource
          # contention. This is more reliable than process polling for distributed builds.
          #
          # Format: some avg10=1.19 avg60=1.15 avg300=0.95 total=16120473
          #         ^^^^ Percentage of time tasks were delayed waiting for resource
          #         full avg10=X.XX = Percentage of time ALL tasks were stalled (thrashing)
          #
          # Threshold loading (priority order):
          #   1. Environment variables (set by systemd service from NixOS config)
          #   2. Runtime config file: /run/compute-workload-monitor/thresholds.conf (imperative)
          #   3. Declarative config: /etc/compute-workload-monitor/thresholds.conf (NixOS)
          #   4. Built-in defaults (fallback)
          #
          # To change thresholds imperatively without rebuild:
          #   echo "PSI_CPU_BUILD_THRESHOLD=3.0" > /run/compute-workload-monitor/thresholds.conf
          #   systemctl reload compute-workload-monitor
          # ============================================================================

          # Function to load threshold with fallback chain
          load_psi_threshold() {
              local var_name="$1"
              local default_value="$2"
              local value=""

              # Check environment first (set by systemd from NixOS config)
              if [ -n "''${!var_name+x}" ]; then
                  value="''${!var_name}"
              fi

              # Check runtime override file (imperative changes)
              if [ -z "$value" ] && [ -f /run/compute-workload-monitor/thresholds.conf ]; then
                  value=$(grep "^''${var_name}=" /run/compute-workload-monitor/thresholds.conf 2>/dev/null | cut -d'=' -f2)
              fi

              # Check declarative config file (NixOS generated)
              if [ -z "$value" ] && [ -f /etc/compute-workload-monitor/thresholds.conf ]; then
                  value=$(grep "^''${var_name}=" /etc/compute-workload-monitor/thresholds.conf 2>/dev/null | cut -d'=' -f2)
              fi

              # Use default if not found
              if [ -z "$value" ]; then
                  value="$default_value"
              fi

              echo "$value"
          }

          # Load thresholds (with fallback to defaults)
          PSI_CPU_BUILD_THRESHOLD=$(load_psi_threshold "PSI_CPU_BUILD_THRESHOLD" "5.0")
          PSI_CPU_IDLE_THRESHOLD=$(load_psi_threshold "PSI_CPU_IDLE_THRESHOLD" "2.0")
          PSI_MEM_SOME_THRESHOLD=$(load_psi_threshold "PSI_MEM_SOME_THRESHOLD" "1.0")
          PSI_MEM_FULL_THRESHOLD=$(load_psi_threshold "PSI_MEM_FULL_THRESHOLD" "0.5")
          PSI_IO_SOME_THRESHOLD=$(load_psi_threshold "PSI_IO_SOME_THRESHOLD" "2.0")
          PSI_IO_FULL_THRESHOLD=$(load_psi_threshold "PSI_IO_FULL_THRESHOLD" "0.3")
          PSI_HYSTERESIS_CYCLES=3         # Require N consecutive low readings before resume

          # Hysteresis state tracking
          PSI_BUILD_CYCLES=0

          check_psi_cpu_pressure() {
              # Check if PSI is available
              if [ ! -f /proc/pressure/cpu ]; then
                  return 1
              fi

              # Parse "some avg10=X" from /proc/pressure/cpu
              local psi_line=$(grep 'some' /proc/pressure/cpu 2>/dev/null || echo "")
              if [ -z "$psi_line" ]; then
                  return 1
              fi

              # Extract avg10 value (format: "some avg10=X.XX avg60=...")
              local psi_avg10=$(echo "$psi_line" | awk '{for(i=1;i<=NF;i++) if($i ~ /^avg10=/) {print $i}}' | cut -d'=' -f2)

              # Validate we got a number
              if [ -z "$psi_avg10" ]; then
                  return 1
              fi

              # Use awk for floating point comparison (more portable than bc)
              # Returns 0 if condition is TRUE, 1 if FALSE
              local above_threshold=$(echo "$psi_avg10" | awk "BEGIN {print (\$1 > $PSI_CPU_BUILD_THRESHOLD)}")
              local below_idle=$(echo "$psi_avg10" | awk "BEGIN {print (\$1 < $PSI_CPU_IDLE_THRESHOLD)}")

              if [ "$above_threshold" = "1" ]; then
                  # CPU pressure detected - builds are active
                  PSI_BUILD_CYCLES=0  # Reset hysteresis counter
                  log "PSI: High CPU pressure detected (avg10=$psi_avg10 > $PSI_CPU_BUILD_THRESHOLD)"
                  return 0
              elif [ "$below_idle" = "1" ]; then
                  # Low pressure - increment hysteresis counter
                  PSI_BUILD_CYCLES=$((PSI_BUILD_CYCLES + 1))

                  if [ "$PSI_BUILD_CYCLES" -ge "$PSI_HYSTERESIS_CYCLES" ]; then
                      # Sustained low pressure - builds are done
                      log "PSI: CPU pressure cleared (avg10=$psi_avg10 < $PSI_CPU_IDLE_THRESHOLD for $PSI_BUILD_CYCLES cycles)"
                      return 1
                  else
                      # Still in hysteresis period - treat as builds active
                      log "PSI: Hysteresis waiting (avg10=$psi_avg10, cycle $PSI_BUILD_CYCLES/$PSI_HYSTERESIS_CYCLES)"
                      return 0
                  fi
              else
                  # Between thresholds - maintain current state
                  if [ "$PSI_BUILD_CYCLES" -gt 0 ]; then
                      # We were in build state, keep it
                      log "PSI: Maintaining build state (avg10=$psi_avg10, between thresholds)"
                      return 0
                  fi
                  return 1
              fi
          }

          # Check if mining processes are causing PSI pressure (should not trigger BUILDS profile)
          is_mining_causing_pressure() {
              # Check if lolminer or xmrig are top memory consumers
              local top_memory_procs=$(ps aux --sort=-%mem 2>/dev/null | head -10 | awk '{print $11}' | grep -E "lolMiner|xmrig" | wc -l)
              if [ "$top_memory_procs" -gt 0 ]; then
                  return 0  # Mining is causing pressure - don't apply BUILDS profile
              fi
              return 1
          }

          check_psi_memory_pressure() {
              # Check if PSI is available
              if [ ! -f /proc/pressure/memory ]; then
                  return 1
              fi

              local psi_line=$(grep 'some' /proc/pressure/memory 2>/dev/null || echo "")
              if [ -z "$psi_line" ]; then
                  return 1
              fi

              # Extract some avg10 and full avg10 using pure awk (more portable)
              local some_avg10=$(echo "$psi_line" | awk '{
                  for(i=1;i<=NF;i++) {
                      if($i ~ /^some/) {
                          for(j=1;j<=NF;j++) {
                              if($j ~ /^avg10=/) {
                                  sub(/avg10=/, "", $j)
                                  print $j
                                  exit
                              }
                          }
                      }
                  }
              }')
              local full_avg10=$(echo "$psi_line" | awk '{
                  for(i=1;i<=NF;i++) {
                      if($i ~ /^full/) {
                          for(j=1;j<=NF;j++) {
                              if($j ~ /^avg10=/) {
                                  sub(/avg10=/, "", $j)
                                  print $j
                                  exit
                              }
                          }
                      }
                  }
              }')

              # Check "full" first - system thrashing is critical
              if [ -n "$full_avg10" ]; then
                  local full_critical=$(echo "$full_avg10" | awk "BEGIN {print (\$1 > $PSI_MEM_FULL_THRESHOLD)}")
                  if [ "$full_critical" = "1" ]; then
                      # CRITICAL thrashing - check if mining is the cause
                      if is_mining_causing_pressure; then
                          log "PSI: Memory thrashing from mining (full avg10=$full_avg10) - ignoring for build detection"
                          return 1
                      fi
                      PSI_BUILD_CYCLES=0
                      log "PSI: CRITICAL memory thrashing detected (full avg10=$full_avg10 > $PSI_MEM_FULL_THRESHOLD)"
                      return 0
                  fi
              fi

              # Check "some" - any memory pressure
              if [ -n "$some_avg10" ]; then
                  local some_pressure=$(echo "$some_avg10" | awk "BEGIN {print (\$1 > $PSI_MEM_SOME_THRESHOLD)}")
                  if [ "$some_pressure" = "1" ]; then
                      # Memory pressure detected - check if mining is the cause
                      if is_mining_causing_pressure; then
                          log "PSI: Memory pressure from mining (some avg10=$some_avg10) - ignoring for build detection"
                          return 1
                      fi
                      PSI_BUILD_CYCLES=0
                      log "PSI: Memory pressure detected (some avg10=$some_avg10 > $PSI_MEM_SOME_THRESHOLD)"
                      return 0
                  fi
              fi

              return 1
          }

          check_psi_io_pressure() {
              # Check if PSI is available
              if [ ! -f /proc/pressure/io ]; then
                  return 1
              fi

              local psi_line=$(grep 'some' /proc/pressure/io 2>/dev/null || echo "")
              if [ -z "$psi_line" ]; then
                  return 1
              fi

              # Extract some avg10 and full avg10 using pure awk
              local some_avg10=$(echo "$psi_line" | awk '{
                  for(i=1;i<=NF;i++) {
                      if($i ~ /^some/) {
                          for(j=1;j<=NF;j++) {
                              if($j ~ /^avg10=/) {
                                  sub(/avg10=/, "", $j)
                                  print $j
                                  exit
                              }
                          }
                      }
                  }
              }')
              local full_avg10=$(echo "$psi_line" | awk '{
                  for(i=1;i<=NF;i++) {
                      if($i ~ /^full/) {
                          for(j=1;j<=NF;j++) {
                              if($j ~ /^avg10=/) {
                                  sub(/avg10=/, "", $j)
                                  print $j
                                  exit
                              }
                          }
                      }
                  }
              }')

              # Check "full" first - severe I/O stall (likely swap thrashing)
              if [ -n "$full_avg10" ]; then
                  local full_critical=$(echo "$full_avg10" | awk "BEGIN {print (\$1 > $PSI_IO_FULL_THRESHOLD)}")
                  if [ "$full_critical" = "1" ]; then
                      # CRITICAL I/O stall - check if mining is the cause
                      if is_mining_causing_pressure; then
                          log "PSI: I/O pressure from mining (full avg10=$full_avg10) - ignoring for build detection"
                          return 1
                      fi
                      PSI_BUILD_CYCLES=0
                      log "PSI: CRITICAL I/O stall detected (full avg10=$full_avg10 > $PSI_IO_FULL_THRESHOLD)"
                      return 0
                  fi
              fi

              # Check "some" - disk/swap pressure
              if [ -n "$some_avg10" ]; then
                  local some_pressure=$(echo "$some_avg10" | awk "BEGIN {print (\$1 > $PSI_IO_SOME_THRESHOLD)}")
                  if [ "$some_pressure" = "1" ]; then
                      # I/O pressure detected - check if mining is the cause
                      if is_mining_causing_pressure; then
                          log "PSI: I/O pressure from mining (some avg10=$some_avg10) - ignoring for build detection"
                          return 1
                      fi
                      PSI_BUILD_CYCLES=0
                      log "PSI: I/O pressure detected (some avg10=$some_avg10 > $PSI_IO_SOME_THRESHOLD)"
                      return 0
                  fi
              fi

              return 1
          }

          # Enhanced distributed build detection using total nix-daemon CPU
          check_nix_daemon_activity() {
              # Check if nix-daemon processes are running
              if ! pgrep -x nix-daemon >/dev/null 2>&1; then
                  return 1
              fi

              # Calculate total CPU usage across ALL nix-daemon processes
              # (Distributed builds use multiple daemons, each using 3-8% CPU)
              local total_cpu="0.0"
              local count=0

              while IFS= read -r line; do
                  if [ -n "$line" ]; then
                      total_cpu=$(awk "BEGIN {print $total_cpu + $line}")
                      count=$((count + 1))
                  fi
              done < <(pgrep -x nix-daemon | xargs -r ps -p -o %cpu --no-headers 2>/dev/null | tr -d ' ')

              # Threshold: 10% total CPU across all nix-daemon processes
              # (Multiple daemons each using 3-8% = distributed build active)
              local is_active=$(awk "BEGIN {exit ($total_cpu > 10.0)}")
              if [ "$is_active" -eq 1 ]; then
                  log "nix-daemon activity detected: $total_cpu% CPU across $count processes"
                  return 0
              fi

              return 1
          }

          # Check for AI gateway signals (highest priority)
          check_gateway_signal() {
              local state_file="/run/gpu-scheduler/ai-state"

              # Check if state file exists
              if [ ! -f "$state_file" ]; then
                  return 1
              fi

              # Read the current state
              local state=$(cat "$state_file" 2>/dev/null || echo "")

              case "$state" in
                  "AI_START")
                      log "Gateway signal: AI workload starting"
                      return 0
                      ;;
                  "AI_STOP")
                      log "Gateway signal: AI workload stopping"
                      return 1
                      ;;
                  "")
                      # Empty state = idle, no signal
                      return 1
                      ;;
                  *)
                      log "Unknown gateway state: $state"
                      return 1
                      ;;
              esac
          }

          get_workload_type() {
              # Priority: Gateway Signal (AI only) > MINING > Gaming > Kubernetes GPU > VRAM Pressure > Builds > Idle
              # AI workloads are detected ONLY via explicit gateway signal (no process-based detection)
              # MINING takes priority over EVERYTHING (except AI) to prevent interference with lolminer power limits

              # Check for gateway signal (explicit AI workload notification)
              if check_gateway_signal; then
                  echo "ai"
                  return
              fi

              # Note: Gaming detection now handled by GameMode in main loop
              # This get_workload_type() function focuses on GPU power profiles

              # Check for Kubernetes GPU workloads (Phase 1)
              if check_kubernetes_gpu_workload; then
                  echo "kubernetes-gpu"
                  return
              fi



              # Check for build workloads using multiple detection methods (priority order)

              # DIRECT PROCESS DETECTION: Check for nix-daemon build processes
              # This catches builds even when PSI pressure is low (idle builds waiting for jobs)
              if pgrep -f "nix-daemon" >/dev/null 2>&1; then
                  echo "builds"
                  return
              fi

              # PSI-based detection (kernel-level, most reliable for distributed builds)
              # Memory/I/O pressure checked first (more critical than CPU)
              if check_psi_memory_pressure; then
                  echo "builds"
                  return
              fi

              if check_psi_io_pressure; then
                  echo "builds"
                  return
              fi

              # Check for active mining (LOWEST PRIORITY - runs only when no other workload)
              # Mining is paused during builds, gaming, AI, or Kubernetes workloads
              for service in "''${MINING_SERVICES[@]}"; do
                  if systemctl is-active --quiet "$service"; then
                      echo "mining"
                      return
                  fi
              done

              if check_psi_cpu_pressure; then
                  echo "builds"
                  return
              fi

              # nix-daemon activity detection (total CPU across all daemons)
              if check_nix_daemon_activity; then
                  echo "builds"
                  return
              fi

              # 3. Process name detection (direct build commands)
              for proc in "''${BUILD_PROCESSES[@]}"; do
                  if check_process_running "$proc"; then
                      echo "builds"
                      return
                  fi
              done

              # 4. Incoming distributed build jobs (SSH + nix-daemon detection)
              if check_incoming_build_job; then
                  echo "builds"
                  return
              fi

              echo "idle"
          }

          # Helper function to get available GPU list
          get_gpu_list() {
              nvidia-smi --query-gpu=index --format=csv,noheader,nounits 2>/dev/null || echo ""
          }

          # Helper function to get GPU name
          get_gpu_name() {
              local gpu_id="$1"
              nvidia-smi -i "$gpu_id" --query-gpu=name --format=csv,noheader 2>/dev/null || echo "Unknown"
          }

          # Helper to safely apply nvidia-smi command
          nvidia_safe() {
              "$@" 2>/dev/null || true
          }

          # Host-specific mining policies
          get_hostname() {
              hostname
          }

          get_xmrig_gaming_threads() {
              local host=$(get_hostname)
              case "$host" in
                  zephyr) echo "6" ;;   # ~19% of 32 threads - always mining
                  nexus)  echo "4" ;;   # 17% of 24 threads
                  sentry) echo "4" ;;   # 25% of 16 threads
                  *)      echo "4" ;;   # Conservative default
              esac
          }

          get_xmrig_idle_threads() {
              local host=$(get_hostname)
              case "$host" in
                  zephyr) echo "16" ;;  # 50% of 32 threads
                  nexus)  echo "12" ;;  # 50% of 24 threads
                  sentry) echo "8" ;;   # 50% of 16 threads
                  *)      echo "8" ;;   # Conservative default
              esac
          }

          reduce_xmrig_threads() {
              local target_threads=$1
              log "Reducing XMRig threads to $target_threads"

              # Get current XMRig PID
              local xmrig_pid
              xmrig_pid=$(pgrep -f "xmrig.*--threads" | head -1) || true
              if [ -z "$xmrig_pid" ]; then
                  log "No XMRig process found"
                  return 1
              fi

              # Reduce effective threads using CPU affinity
              # This limits which cores XMRig can use without restarting
              local cores_to_use=$target_threads
              taskset -cp "0-$((cores_to_use - 1))" "$xmrig_pid" 2>/dev/null || true
              log "Set XMRig (PID $xmrig_pid) CPU affinity to cores 0-$((cores_to_use - 1))"
          }

          reset_xmrig_threads() {
              local target_threads=$1
              log "Resetting XMRig threads to $target_threads"

              local xmrig_pid
              xmrig_pid=$(pgrep -f "xmrig.*--threads" | head -1) || true
              if [ -z "$xmrig_pid" ]; then
                  log "No XMRig process found"
                  return 1
              fi

              # Reset to use all available cores
              taskset -cp "$xmrig_pid" 0-63 2>/dev/null || true
              log "Reset XMRig (PID $xmrig_pid) CPU affinity to all cores"
          }

          # ============================================================================
          # XMRIG HTTP API CONTROL (via xmrig-api-control helper)
          # ============================================================================
          # Uses the modular xmrig-api-control script for pause/resume/thread control
          # ============================================================================

          pause_xmrig() {
              log "Pausing XMRig during build workload"
              # Stop both instances (XMRig API v2 /2/control endpoint not available, using systemctl stop)
              if systemctl is-active --quiet xmrig-always; then
                  systemctl stop xmrig-always
                  log "XMRig [always] stopped - builds get full CPU priority"
              fi
              if systemctl is-active --quiet xmrig-flexible; then
                  systemctl stop xmrig-flexible
                  log "XMRig [flexible] stopped - builds get full CPU priority"
              fi
          }

          resume_xmrig() {
              local threads="''$1"
              log "Resuming XMRig (threads: ''${threads:-auto})"
              # Start both instances (XMRig API v2 /2/control endpoint not available, using systemctl start)
              if ! systemctl is-active --quiet xmrig-always; then
                  systemctl start xmrig-always
                  log "XMRig [always] started"
              fi
              if ! systemctl is-active --quiet xmrig-flexible; then
                  systemctl start xmrig-flexible
                  log "XMRig [flexible] started"
              fi
          }

          set_xmrig_threads() {
              local target_threads="''$1"
              log "Setting XMRig threads to ''$target_threads via HTTP API"
              # Set threads on always instance (primary miner)
              if systemctl is-active --quiet xmrig-always; then
                  xmrig-api-control threads "''$target_threads" always
              fi
          }

          # Get XMRig status for state tracking (check if service is running)
          xmrig_status() {
              if systemctl is-active --quiet xmrig-flexible || systemctl is-active --quiet xmrig-always; then
                  echo "running"
              else
                  echo "stopped"
              fi
          }









          # ============================================================================
          # KUBERNETES GPU PROFILE (Phase 1)
          # ============================================================================
          apply_kubernetes_gpu_profile() {
              echo "=== Applying GPU KUBERNETES GPU WORKLOAD profile ==="

              local gpus=$(get_gpu_list)
              local gpu_count=$(echo "$gpus" | wc -l)

              if [ "$gpu_count" -eq 0 ]; then
                  echo "WARNING: No NVIDIA GPUs detected"
                  return 0
              fi

              echo "Detected $gpu_count GPU(s) for Kubernetes GPU workload profile"

              # Set GPUs to balanced mode for K8s workloads
              for gpu_id in $gpus; do
                  local gpu_name=$(get_gpu_name "$gpu_id")
                  echo "Configuring GPU $gpu_id ($gpu_name)..."

                  case "$gpu_name" in
                      *"3060"*)
                          # 3060 Ti: Balanced for K8s
                          nvidia_safe nvidia-smi -i "$gpu_id" -pl 150
                          nvidia_safe nvidia-smi -i "$gpu_id" -lgc 1800
                          nvidia_safe nvidia-smi -i "$gpu_id" -lmc 6000
                          echo "  3060 Ti: 1800 MHz GPU, 6000 MHz mem, 150W limit"
                          ;;
                      *"3090"*)
                          # 3090: Balanced for K8s (liquid cooled)
                          nvidia_safe nvidia-smi -i "$gpu_id" -pl 280
                          nvidia_safe nvidia-smi -i "$gpu_id" -lgc 1800
                          nvidia_safe nvidia-smi -i "$gpu_id" -lmc 6800
                          echo "  3090: 1800 MHz GPU (liquid-cooled), 6800 MHz mem, 280W limit"
                          ;;
                      *)
                          # Default: Balanced
                          nvidia_safe nvidia-smi -i "$gpu_id" -pl 200
                          nvidia_safe nvidia-smi -i "$gpu_id" -rgc
                          nvidia_safe nvidia-smi -i "$gpu_id" -rmc
                          echo "  $gpu_name: Default balanced profile"
                          ;;
                  esac
              done

              echo "KUBERNETES GPU profile applied: Mode: Balanced for containerized workloads"

              # STOP GPU mining completely to free VRAM for K8s pods
              if systemctl is-active --quiet lolminer-nvidia; then
                  log "Stopping lolminer-nvidia to free VRAM for Kubernetes GPU pods"
                  systemctl stop lolminer-nvidia
              fi

              if systemctl is-active --quiet lolminer-amd; then
                  log "Stopping lolminer-amd to free VRAM for Kubernetes GPU pods"
                  systemctl stop lolminer-amd
              fi

              # Reduce CPU mining to 50% (K8s workloads may need CPU for orchestration)
              if systemctl is-active --quiet xmrig-always; then
                  log "Limiting xmrig to 50% CPU for Kubernetes workloads"
                  systemctl set-property xmrig-always.service CPUQuota="50%" --runtime 2>/dev/null || true
              fi
          }

          apply_gaming_profile() {
              echo "=== Applying GPU GAMING profile ==="

              local gpus=$(get_gpu_list)
              local gpu_count=$(echo "$gpus" | wc -l)

              if [ "$gpu_count" -eq 0 ]; then
                  echo "WARNING: No NVIDIA GPUs detected"
                  return 0
              fi

              echo "Detected $gpu_count GPU(s) for gaming profile"

              for gpu_id in $gpus; do
                  local gpu_name=$(get_gpu_name "$gpu_id")
                  echo "Configuring GPU $gpu_id ($gpu_name)..."

                  case "$gpu_name" in
                      *"3060"*)
                          # 3060 Ti: Skip power limit changes (tight power budget, not primary gaming GPU)
                          # Keep clock locks for stability but don't touch power limit
                          nvidia_safe nvidia-smi -i "$gpu_id" -lgc 1800
                          nvidia_safe nvidia-smi -i "$gpu_id" -lmc 6000
                          echo "  3060 Ti: Clock locks only (1800/6000 MHz), power limit unchanged"
                          ;;
                      *"3090"*)
                          # 3090: Primary gaming GPU - max performance (liquid cooled)
                          nvidia_safe nvidia-smi -i "$gpu_id" -pl 350
                          nvidia_safe nvidia-smi -i "$gpu_id" -lgc 2050
                          nvidia_safe nvidia-smi -i "$gpu_id" -lmc 7500
                          echo "  3090: 2050 MHz GPU (liquid-cooled), 7500 MHz mem, 350W limit (PRIMARY GAMING GPU)"
                          ;;
                      *)
                          # Default: Max performance
                          nvidia_safe nvidia-smi -i "$gpu_id" -pl 250
                          nvidia_safe nvidia-smi -i "$gpu_id" -rgc
                          nvidia_safe nvidia-smi -i "$gpu_id" -rmc
                          echo "  $gpu_name: Default max performance profile"
                          ;;
                  esac
              done

              echo "GAMING profile applied: Mode: Maximum performance"

              # Reduce CPU mining during gaming
              # On zephyr: use HTTP API to reduce thread count (more elegant than CPUQuota)
              # On other hosts: use CPUQuota method
              if systemctl is-active --quiet xmrig-always; then
                  local host=$(get_hostname)
                  if [ "$host" = "zephyr" ]; then
                      local gaming_threads=$(get_xmrig_gaming_threads)
                      log "Reducing xmrig to $gaming_threads threads on zephyr for gaming"
                      set_xmrig_threads "$gaming_threads"
                  else
                      log "Limiting xmrig to 25% CPU for gaming"
                      systemctl set-property xmrig-always.service CPUQuota="25%" --runtime 2>/dev/null || true
                  fi
              fi
          }

          apply_ai_profile() {
              echo "=== Applying GPU AI INFERENCE profile ==="

              local gpus=$(get_gpu_list)
              local gpu_count=$(echo "$gpus" | wc -l)

              if [ "$gpu_count" -eq 0 ]; then
                  echo "WARNING: No NVIDIA GPUs detected"
                  return 0
              fi

              echo "Detected $gpu_count GPU(s) for AI inference profile"

              for gpu_id in $gpus; do
                  local gpu_name=$(get_gpu_name "$gpu_id")
                  echo "Configuring GPU $gpu_id ($gpu_name)..."

                  case "$gpu_name" in
                      *"3060"*)
                          # 3060 Ti: Balanced
                          nvidia_safe nvidia-smi -i "$gpu_id" -pl 110
                          nvidia_safe nvidia-smi -i "$gpu_id" -lgc 1950
                          nvidia_safe nvidia-smi -i "$gpu_id" -lmc 6200
                          echo "  3060 Ti: 1950 MHz GPU, 6200 MHz mem, 110W limit"
                          ;;
                      *"3090"*)
                          # 3090: Liquid cooled, can push harder
                          nvidia_safe nvidia-smi -i "$gpu_id" -pl 300
                          nvidia_safe nvidia-smi -i "$gpu_id" -lgc 1900
                          nvidia_safe nvidia-smi -i "$gpu_id" -lmc 7000
                          echo "  3090: 1900 MHz GPU (liquid-cooled), 7000 MHz mem, 300W limit"
                          ;;
                      *)
                          # Default: Balanced
                          nvidia_safe nvidia-smi -i "$gpu_id" -pl 200
                          nvidia_safe nvidia-smi -i "$gpu_id" -rgc
                          nvidia_safe nvidia-smi -i "$gpu_id" -rmc
                          echo "  $gpu_name: Default balanced profile"
                          ;;
                  esac
              done

              echo "AI INFERENCE profile applied: Mode: Balanced performance with thermal safety"

              # STOP GPU mining completely to free VRAM (prevents eviction freeze)
              if systemctl is-active --quiet lolminer-nvidia; then
                  log "Stopping lolminer-nvidia to free VRAM for AI inference"
                  systemctl stop lolminer-nvidia
              fi

              if systemctl is-active --quiet lolminer-amd; then
                  log "Stopping lolminer-amd to free VRAM for AI inference"
                  systemctl stop lolminer-amd
              fi

              # Keep CPU mining at 100% (GPU is bottleneck, CPU just coordinates)
              if systemctl is-active --quiet xmrig-always; then
                  log "Keeping xmrig at 100% CPU (GPU is bottleneck for AI)"
                  systemctl set-property xmrig-always.service CPUQuota="100%" --runtime 2>/dev/null || true
              fi
          }

          apply_builds_profile() {
              echo "=== Applying GPU/CPU BUILDS profile ==="

              # Check for wrapper-initiated build events (visibility only)
              check_build_wrapper_events

              local gpus=$(get_gpu_list)
              local gpu_count=$(echo "$gpus" | wc -l)

              if [ "$gpu_count" -eq 0 ]; then
                  echo "WARNING: No NVIDIA GPUs detected"
              else
                  echo "Detected $gpu_count GPU(s) for builds profile"
              fi

              # Detect if we're on a Ryzen node (should pause xmrig during builds)
              local host=$(get_hostname)
              local is_ryzen_node=false
              case "$host" in
                  zephyr|nexus|sentry) is_ryzen_node=true ;;
              esac

              # Reduce GPU mining to 10% (builds may need GPU for CUDA/heavy workloads)
              # Only limit on nexus due to heat issues - other hosts can mine while building
              if [ "$host" = "nexus" ]; then
                  if systemctl is-active --quiet lolminer-nvidia; then
                      log "Limiting lolminer-nvidia to 10% CPU for builds (nexus heat management)"
                      systemctl set-property lolminer-nvidia.service CPUQuota="10%" --runtime 2>/dev/null || true
                  fi

                  if systemctl is-active --quiet lolminer-amd; then
                      log "Limiting lolminer-amd to 10% CPU for builds (nexus heat management)"
                      systemctl set-property lolminer-amd.service CPUQuota="10%" --runtime 2>/dev/null || true
                  fi
              else
                  log "Build detected on $host - allowing GPU mining to continue (no heat issues)"
              fi

              # PAUSE CPU mining on Ryzen nodes (builds need maximum CPU)
              # Use HTTP API pause for clean suspend without restart
              if systemctl is-active --quiet xmrig-always; then
                  if [ "$is_ryzen_node" = true ]; then
                      log "PAUSING xmrig completely on Ryzen node during builds"
                      pause_xmrig
                  else
                      log "Limiting xmrig to 10% CPU on non-Ryzen node during builds"
                      systemctl set-property xmrig-always.service CPUQuota="10%" --runtime 2>/dev/null || true
                  fi
              fi

              # Ensure nix-daemon gets high priority for builds
              if systemctl is-active --quiet nix-daemon; then
                  log "Setting nix-daemon to high CPU weight for builds"
                  systemctl set-property nix-daemon.service CPUWeight=2048 --runtime
              fi

              echo "BUILDS profile applied: Mode: $([ "$is_ryzen_node" = true ] && echo "PAUSED xmrig" || echo "10% mining"), builds get priority"
          }

          apply_mining_profile() {
              echo "=== Applying GPU MINING profile ==="

              local gpus=$(get_gpu_list)
              local gpu_count=$(echo "$gpus" | wc -l)

              if [ "$gpu_count" -eq 0 ]; then
                  echo "WARNING: No NVIDIA GPUs detected"
                  return 0
              fi

              echo "Detected $gpu_count GPU(s) for mining profile"

              for gpu_id in $gpus; do
                  local gpu_name=$(get_gpu_name "$gpu_id")
                  echo "Configuring GPU $gpu_id ($gpu_name)..."

                  case "$gpu_name" in
                      *"3060"*)
                          # 3060 Ti: Reset to mining power limits (zephyr/nexus mining config
                          nvidia_safe nvidia-smi -i "$gpu_id" -pl 130
                          nvidia_safe nvidia-smi -i "$gpu_id" -lgc 1700
                          nvidia_safe nvidia-smi -i "$gpu_id" -lmc 5200
                          echo "  3060 Ti: 1700 MHz GPU, 5200 MHz mem (130W limit (mining-optimized)"
                          ;;
                      *"3090"*)
                          # 3090: Reset to mining power limits (zephyr mining config
                          nvidia_safe nvidia-smi -i "$gpu_id" -pl 250
                          nvidia_safe nvidia-smi -i "$gpu_id" -lgc 1750
                          nvidia_safe nvidia-smi -i "$gpu_id" -lmc 6500
                          echo "  3090: 1750 MHz GPU (liquid-cooled), 6500 MHz mem (250W limit (mining-optimized)"
                          ;;
                      *)
                          # Default: Don't override power limits, let mining module manage
                          nvidia_safe nvidia-smi -i "$gpu_id" -rgc
                          nvidia-safe nvidia-smi -i "$gpu_id" -rmc
                          echo "  $gpu_name: Default efficiency profile (power limit from mining module)"
                          ;;
                  esac
              done

              echo "MINING profile applied: Mode: Efficiency-optimized"

              # Reset all mining to 100% CPU
              if systemctl is-active --quiet lolminer-nvidia; then
                  log "Resetting lolminer-nvidia to 100% CPU"
                  systemctl set-property lolminer-nvidia.service CPUQuota="100%" --runtime 2>/dev/null || true
              fi

              if systemctl is-active --quiet lolminer-amd; then
                  log "Resetting lolminer-amd to 100% CPU"
                  systemctl set-property lolminer-amd.service CPUQuota="100%" --runtime 2>/dev/null || true
              fi

              if systemctl is-active --quiet xmrig-always; then
                  local idle_threads=$(get_xmrig_idle_threads)
                  log "Resetting xmrig to 100% CPU ($idle_threads threads)"
                  systemctl set-property xmrig-always.service CPUQuota="100%" --runtime 2>/dev/null || true

                  # Use HTTP API to resume if it was paused
                  local current_status=$(xmrig_status)
                  if [ "$current_status" = "paused" ]; then
                      log "XMRig is paused, resuming via HTTP API"
                      resume_xmrig "$idle_threads"
                  else
                      reset_xmrig_threads "$idle_threads"
                  fi
              fi

              # Start GPU mining if not running AND no VRAM pressure
              if ! systemctl is-active --quiet lolminer-nvidia; then
                  # Check VRAM pressure before starting miner
                  if check_vram_pressure; then
                      local max_gpu_info=$(get_max_vram_gpu)
                      local pressure_gpu=$(echo "$max_gpu_info" | cut -d':' -f1)
                      local pressure_usage=$(echo "$max_gpu_info" | cut -d':' -f2)

                      log "🛑 BLOCKING miner start due to VRAM pressure"
                      log "   GPU ''${pressure_gpu} at ''${pressure_usage}% usage - likely AI models loaded"
                      log "   Miner will auto-start when VRAM is freed"

                      # Don't start mining - VRAM is too full
                      return 0
                  fi

                  log "Starting lolminer-nvidia (no other workloads detected, VRAM OK)"
                  systemctl start lolminer-nvidia
              fi
          }

          apply_idle_profile() {
              echo "=== Resetting GPUs to DEFAULT/AUTO profile ==="

              local gpus=$(get_gpu_list)
              local gpu_count=$(echo "$gpus" | wc -l)

              if [ "$gpu_count" -eq 0 ]; then
                  echo "WARNING: No NVIDIA GPUs detected"
                  return 0
              fi

              echo "Detected $gpu_count GPU(s), resetting to defaults"

              for gpu_id in $gpus; do
                  local gpu_name=$(get_gpu_name "$gpu_id")
                  echo "Resetting GPU $gpu_id ($gpu_name)..."

                  # Reset power limits based on GPU model
                  case "$gpu_name" in
                      *"3060"*)
                          nvidia_safe nvidia-smi -i "$gpu_id" -pl 200
                          ;;
                      *"3090"*)
                          nvidia_safe nvidia-smi -i "$gpu_id" -pl 350
                          ;;
                      *)
                          # Try to get max power limit
                          local max_power=$(nvidia-smi -i "$gpu_id" --query-gpu=power.max_limit --format=csv,noheader,nounits 2>/dev/null | tr -d '.' || echo "300")
                          nvidia_safe nvidia-smi -i "$gpu_id" -pl "''${max_power%.*}"
                          ;;
                  esac

                  # Reset locked clocks
                  nvidia_safe nvidia-smi -i "$gpu_id" -rgc
                  nvidia_safe nvidia-smi -i "$gpu_id" -rmc

                  echo "  GPU $gpu_id: Reset to defaults (adaptive mode)"
              done

              echo "RESET to defaults applied: Mode: Adaptive (auto)"
          }

          apply_vram_pressure_profile() {
              echo "=== Applying GPU VRAM PRESSURE profile ==="

              local gpus=$(get_gpu_list)
              local gpu_count=$(echo "$gpus" | wc -l)

              if [ "$gpu_count" -eq 0 ]; then
                  echo "WARNING: No NVIDIA GPUs detected"
                  return 0
              fi

              echo "Detected VRAM pressure - preventing miner start to avoid freeze"

              # Get detailed VRAM info
              for gpu_id in $gpus; do
                  local gpu_name=$(get_gpu_name "$gpu_id")
                  local usage=$(get_vram_usage_percent "$gpu_id")
                  local vram_info=$(nvidia-smi -i "$gpu_id" --query-gpu=memory.used,memory.total --format=csv,noheader,nounits)

                  local used=$(echo "$vram_info" | cut -d',' -f1)
                  local total=$(echo "$vram_info" | cut -d',' -f2)

                  echo "GPU $gpu_id ($gpu_name): ''${used}MB / ''${total}MB (''${usage}%)"
              done

              # Ensure GPU miners are completely stopped
              if systemctl is-active --quiet lolminer-nvidia; then
                  log "Stopping lolminer-nvidia due to VRAM pressure"
                  systemctl stop lolminer-nvidia
              fi

              if systemctl is-active --quiet lolminer-amd; then
                  log "Stopping lolminer-amd due to VRAM pressure"
                  systemctl stop lolminer-amd
              fi

              # Set GPUs to balanced mode (not max, not idle)
              for gpu_id in $gpus; do
                  local gpu_name=$(get_gpu_name "$gpu_id")

                  case "$gpu_name" in
                      *"3060"*)
                          nvidia_safe nvidia-smi -i "$gpu_id" -pl 150
                          ;;
                      *"3090"*)
                          nvidia_safe nvidia-smi -i "$gpu_id" -pl 250
                          ;;
                      *)
                          nvidia_safe nvidia-smi -i "$gpu_id" -pl 200
                          ;;
                  esac
              done

              echo "VRAM PRESSURE profile applied: Miners stopped, waiting for VRAM to free"
          }

          apply_profile() {
              local profile="$1"
              log "Applying profile: $profile"

              case "$profile" in
                  gaming)
                      apply_gaming_profile
                      ;;
                  ai)
                      apply_ai_profile
                      ;;
                  kubernetes-gpu)
                      apply_kubernetes_gpu_profile
                      ;;
                  vram-pressure)
                      apply_vram_pressure_profile
                      ;;
                  builds)
                      apply_builds_profile
                      ;;
                  mining)
                      apply_mining_profile
                      ;;
                  idle)
                      apply_idle_profile
                      ;;
                  *)
                      log "Unknown profile: $profile"
                      ;;
              esac
          }

          # Store original power limits for restoration
          store_original_power_limits() {
              local gpus=$(get_gpu_list)
              for gpu_id in $gpus; do
                  local current_limit=$(nvidia-smi -i "$gpu_id" --query-gpu=power.limit --format=csv,noheader,nounits 2>/dev/null | tr -d '[:space:]')
                  echo "$current_limit" > /run/compute-workload-monitor/gpu"$gpu_id"_original_power
                  log "Stored original power limit for GPU $gpu_id: $current_limit W"
              done
          }

          restore_original_power_limits() {
              local gpus=$(get_gpu_list)
              for gpu_id in $gpus; do
                  local stored_file="/run/compute-workload-monitor/gpu"$gpu_id"_original_power"
                  if [ -f "$stored_file" ]; then
                      local original_limit=$(cat "$stored_file")
                      log "Restoring GPU $gpu_id power limit to $original_limit W"
                      nvidia_safe nvidia-smi -i "$gpu_id" -pl "$original_limit"
                  fi
              done
          }

          # State tracking
          CURRENT_WORKLOAD="idle"
          CHECK_INTERVAL="${toString config.services.compute-workload-monitor.checkInterval}"
          FIRST_RUN=true

          # Signal handler for runtime reload
          reload_thresholds() {
              log "Reloading PSI thresholds..."
              PSI_CPU_BUILD_THRESHOLD=$(load_psi_threshold "PSI_CPU_BUILD_THRESHOLD" "5.0")
              PSI_CPU_IDLE_THRESHOLD=$(load_psi_threshold "PSI_CPU_IDLE_THRESHOLD" "2.0")
              PSI_MEM_SOME_THRESHOLD=$(load_psi_threshold "PSI_MEM_SOME_THRESHOLD" "1.0")
              PSI_MEM_FULL_THRESHOLD=$(load_psi_threshold "PSI_MEM_FULL_THRESHOLD" "0.5")
              PSI_IO_SOME_THRESHOLD=$(load_psi_threshold "PSI_IO_SOME_THRESHOLD" "2.0")
              PSI_IO_FULL_THRESHOLD=$(load_psi_threshold "PSI_IO_FULL_THRESHOLD" "0.3")
              log "Thresholds reloaded: CPU_BUILD=$PSI_CPU_BUILD_THRESHOLD MEM_SOME=$PSI_MEM_SOME_THRESHOLD"
          }

          # Trap SIGUSR1 for reload
          trap reload_thresholds SIGUSR1

          log "Starting GPU workload monitor (check interval: ''${CHECK_INTERVAL}s)"
          log "Thresholds: CPU_BUILD=$PSI_CPU_BUILD_THRESHOLD MEM_SOME=$PSI_MEM_SOME_THRESHOLD IO_FULL=$PSI_IO_FULL_THRESHOLD"

          # Store original power limits on first run (before any profile changes them)
          log "Storing original GPU power limits for restoration..."
          store_original_power_limits

          while true; do
              new_workload=$(get_workload_type)

              if [ "$new_workload" != "$CURRENT_WORKLOAD" ]; then
                  log "Workload changed: $CURRENT_WORKLOAD -> $new_workload"

                  # If switching FROM ai/gaming/kubernetes-gpu/builds back to mining/idle, restore original limits
                  case "$CURRENT_WORKLOAD" in
                      ai|gaming|kubernetes-gpu|builds)
                          if [[ "$new_workload" =~ (mining|idle) ]]; then
                              log "Restoring original power limits after $CURRENT_WORKLOAD workload"
                              restore_original_power_limits
                          fi
                          ;;
                  esac

                  CURRENT_WORKLOAD="$new_workload"
                  apply_profile "$new_workload"
              fi

              # Gaming detection and pause/resume (per-host, all nodes)
              gaming_output=$(detect_gaming)
              gaming_detected=$?
              detection_method="$gaming_output"

              # Manage lolminer pause/resume with hysteresis
              manage_lolminer_for_gaming "$gaming_detected" "$detection_method"

              # Export gaming state to Prometheus (use current values, not stale state)
              export_gaming_metric "$gaming_detected" "$detection_method"

              sleep "$CHECK_INTERVAL"
          done
        ''}/bin/compute-workload-monitor";
        # Runtime reload support - reload config when SIGHUP received
        ExecReload = "${pkgs.coreutils}/bin/kill -USR1 $MAINPID";
        Restart = "on-failure";
        RestartSec = "10s";
        # Allow access to nvidia-smi and systemd
        AmbientCapabilities = ["CAP_NET_ADMIN"];
      };
    };

    # Runtime config directory for imperative threshold overrides and state storage
    # Also create node_exporter textfile collector directory for gaming metrics
    systemd.tmpfiles.rules = [
      "d /run/compute-workload-monitor 0755 root root - -"
      "d /var/lib/node_exporter/textfile_collector 0755 root root - -"
    ];
  };
}
