# Mining Coordinator Module
# K8s-aware workload coordination service
# Detects build workloads via PSI and coordinates with K8s Volcano scheduler
# Writes profile requests for gpu-profile-manager to consume
# NO service control - K8s Volcano handles all pod preemption
{
  config,
  pkgs,
  lib,
  ...
}: {
  options.services.mining-coordinator = {
    enable = lib.mkEnableOption "Mining coordinator for K8s-aware workload scheduling";

    checkInterval = lib.mkOption {
      type = lib.types.int;
      default = 10;
      description = "Check interval in seconds";
    };

    logFile = lib.mkOption {
      type = lib.types.str;
      default = "/var/log/mining-coordinator.log";
      description = "Path to log file";
    };

    gamingStateFile = lib.mkOption {
      type = lib.types.str;
      default = "/run/gaming-detection/gaming_state";
      description = "Path to gaming state file from gaming-detection service";
    };

    profileRequestFile = lib.mkOption {
      type = lib.types.str;
      default = "/run/mining-coordinator/requested-profile";
      description = "Path to profile request file for gpu-profile-manager";
    };

    psiCpuBuildThreshold = lib.mkOption {
      type = lib.types.str;
      default = "5.0";
      description = "PSI CPU threshold for detecting build workloads";
    };

    psiCpuIdleThreshold = lib.mkOption {
      type = lib.types.str;
      default = "2.0";
      description = "PSI CPU threshold for considering builds idle";
    };
  };

  config = lib.mkIf config.services.mining-coordinator.enable {
    systemd.services.mining-coordinator = {
      description = "Mining Coordinator - K8s-aware workload scheduling";
      wantedBy = ["multi-user.target"];
      after = [
        "network.target"
        "kubernetes.target"
        "gaming-detection.service"
      ];
      path = with pkgs; [
        procps # pgrep
        kubernetes # kubectl
        gnugrep
        gawk # awk
        coreutils
      ];

      serviceConfig = {
        Type = "simple";
        Environment = "PATH=${
          lib.makeBinPath (
            with pkgs; [
              procps
              kubernetes
              gnugrep
              gawk
              coreutils
            ]
          )
        }:/run/current-system/sw/bin";
        ExecStart = "${pkgs.writeShellScriptBin "mining-coordinator" ''
          # Mining Coordinator Service
          # Detects build workloads via PSI and coordinates with K8s
          # Writes profile requests for gpu-profile-manager
          # Scales Volcano placeholder for gaming preemption

          set -euo pipefail

          LOG_FILE="${config.services.mining-coordinator.logFile}"
          GAMING_STATE_FILE="${config.services.mining-coordinator.gamingStateFile}"
          PROFILE_REQUEST_FILE="${config.services.mining-coordinator.profileRequestFile}"
          CHECK_INTERVAL="${toString config.services.mining-coordinator.checkInterval}"

          # PSI Thresholds
          PSI_CPU_BUILD_THRESHOLD="${config.services.mining-coordinator.psiCpuBuildThreshold}"
          PSI_CPU_IDLE_THRESHOLD="${config.services.mining-coordinator.psiCpuIdleThreshold}"
          PSI_MEM_SOME_THRESHOLD="1.0"
          PSI_MEM_FULL_THRESHOLD="0.5"
          PSI_IO_SOME_THRESHOLD="2.0"
          PSI_IO_FULL_THRESHOLD="0.3"
          PSI_HYSTERESIS_CYCLES=3

          # Hysteresis state tracking
          PSI_BUILD_CYCLES=0

          # Logging function
          log() {
              echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
          }

          # Get hostname
          get_hostname() {
              hostname
          }

          # ============================================================================
          # STATE FILE READERS
          # ============================================================================
          # Read gaming state from gaming-detection service
          read_gaming_state() {
              if [[ -f "$GAMING_STATE_FILE" ]]; then
                  source "$GAMING_STATE_FILE"
                  echo "$GAMING_ACTIVE"
              else
                  echo "0"  # Default: no gaming
              fi
          }

          # Write profile request for gpu-profile-manager
          write_profile_request() {
              local profile="$1"
              mkdir -p /run/mining-coordinator
              echo "$profile" > "$PROFILE_REQUEST_FILE"
              log "Profile request written: $profile"
          }

          # Clear profile request (returns control to auto-detection)
          clear_profile_request() {
              if [[ -f "$PROFILE_REQUEST_FILE" ]]; then
                  rm "$PROFILE_REQUEST_FILE"
                  log "Profile request cleared"
              fi
          }

          # ============================================================================
          # PSI-BASED BUILD DETECTION
          # ============================================================================
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

              # Use awk for floating point comparison
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

          check_psi_memory_pressure() {
              # Check if PSI is available
              if [ ! -f /proc/pressure/memory ]; then
                  return 1
              fi

              local psi_line=$(grep 'some' /proc/pressure/memory 2>/dev/null || echo "")
              if [ -z "$psi_line" ]; then
                  return 1
              fi

              # Extract some avg10 and full avg10
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
                      PSI_BUILD_CYCLES=0
                      log "PSI: CRITICAL memory thrashing detected (full avg10=$full_avg10 > $PSI_MEM_FULL_THRESHOLD)"
                      return 0
                  fi
              fi

              # Check "some" - any memory pressure
              if [ -n "$some_avg10" ]; then
                  local some_pressure=$(echo "$some_avg10" | awk "BEGIN {print (\$1 > $PSI_MEM_SOME_THRESHOLD)}")
                  if [ "$some_pressure" = "1" ]; then
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

              # Extract some avg10 and full avg10
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

              # Check "full" first - severe I/O stall
              if [ -n "$full_avg10" ]; then
                  local full_critical=$(echo "$full_avg10" | awk "BEGIN {print (\$1 > $PSI_IO_FULL_THRESHOLD)}")
                  if [ "$full_critical" = "1" ]; then
                      PSI_BUILD_CYCLES=0
                      log "PSI: CRITICAL I/O stall detected (full avg10=$full_avg10 > $PSI_IO_FULL_THRESHOLD)"
                      return 0
                  fi
              fi

              # Check "some" - disk/swap pressure
              if [ -n "$some_avg10" ]; then
                  local some_pressure=$(echo "$some_avg10" | awk "BEGIN {print (\$1 > $PSI_IO_SOME_THRESHOLD)}")
                  if [ "$some_pressure" = "1" ]; then
                      PSI_BUILD_CYCLES=0
                      log "PSI: I/O pressure detected (some avg10=$some_avg10 > $PSI_IO_SOME_THRESHOLD)"
                      return 0
                  fi
              fi

              return 1
          }

          # Check for nix-daemon build processes (direct detection)
          check_nix_daemon_activity() {
              # Check if nix-daemon processes are running
              if ! pgrep -x nix-daemon >/dev/null 2>&1; then
                  return 1
              fi

              # Calculate total CPU usage across ALL nix-daemon processes
              local total_cpu="0.0"
              local count=0

              while IFS= read -r line; do
                  if [ -n "$line" ]; then
                      total_cpu=$(awk "BEGIN {print $total_cpu + $line}")
                      count=$((count + 1))
                  fi
              done < <(pgrep -x nix-daemon | xargs -r ps -p -o %cpu --no-headers 2>/dev/null | tr -d ' ')

              # Threshold: 10% total CPU across all nix-daemon processes
              local is_active=$(awk "BEGIN {exit ($total_cpu > 10.0)}")
              if [ "$is_active" -eq 1 ]; then
                  log "nix-daemon activity detected: $total_cpu% CPU across $count processes"
                  return 0
              fi

              return 1
          }

          # ============================================================================
          # KUBERNETES GAMING INTEGRATION (Volcano Preemption)
          # ============================================================================
          # Scale gaming-placeholder deployment based on gaming state
          # This is the ONLY K8s interaction for pod control
          scale_gaming_placeholder() {
              local gaming_active=$1  # 0 or 1

              # Check if kubectl is available
              if ! command -v kubectl >/dev/null 2>&1; then
                  return 1
              fi

              # Check if cluster is accessible
              if ! kubectl get nodes >/dev/null 2>&1; then
                  return 1
              fi

              local replicas=0
              if [[ "$gaming_active" == "1" ]]; then
                  replicas=1
                  log "K8s: Gaming detected - scaling up gaming-placeholder-volcano to preempt mining"
              fi

              # Scale the gaming-placeholder-volcano deployment in mining namespace
              # (Uses Volcano scheduler for priority-based GPU preemption)
              if kubectl scale deployment gaming-placeholder-volcano -n mining --replicas=$replicas >/dev/null 2>&1; then
                  log "K8s: Scaled gaming-placeholder-volcano to $replicas replica(s)"
              else
                  log "K8s: Failed to scale gaming-placeholder-volcano"
                  return 1
              fi

              return 0
          }

          # ============================================================================
          # WORKLOAD COORDINATION
          # ============================================================================
          detect_workload() {
              # Priority: Gaming > Builds > Idle

              # Check gaming state first (highest priority)
              local gaming_active=$(read_gaming_state)
              if [[ "$gaming_active" == "1" ]]; then
                  echo "gaming"
                  return
              fi

              # Check for build workloads using PSI (priority order)
              # Memory/I/O pressure checked first (more critical than CPU)
              if check_psi_memory_pressure; then
                  echo "builds"
                  return
              fi

              if check_psi_io_pressure; then
                  echo "builds"
                  return
              fi

              if check_psi_cpu_pressure; then
                  echo "builds"
                  return
              fi

              # nix-daemon activity detection (total CPU across all daemons)
              if check_nix_daemon_activity; then
                  echo "builds"
                  return
              fi

              # Default: idle (mining)
              echo "idle"
          }

          # ============================================================================
          # MAIN LOOP
          # ============================================================================
          log "Starting mining coordinator (check interval: ''${CHECK_INTERVAL}s)"
          log "PSI thresholds: CPU_BUILD=$PSI_CPU_BUILD_THRESHOLD CPU_IDLE=$PSI_CPU_IDLE_THRESHOLD"
          log "Gaming state file: $GAMING_STATE_FILE"
          log "Profile request file: $PROFILE_REQUEST_FILE"

          # Create state directory
          mkdir -p /run/mining-coordinator

          # State tracking
          CURRENT_WORKLOAD="idle"
          PREVIOUS_GAMING_STATE="0"

          while true; do
              # Detect current workload
              new_workload=$(detect_workload)

              # Check gaming state for K8s coordination
              current_gaming_state=$(read_gaming_state)

              # Detect gaming state transitions for Volcano preemption
              if [[ "$PREVIOUS_GAMING_STATE" != "$current_gaming_state" ]]; then
                  log "Gaming state changed: $PREVIOUS_GAMING_STATE -> $current_gaming_state"
                  scale_gaming_placeholder "$current_gaming_state"
                  PREVIOUS_GAMING_STATE="$current_gaming_state"
              fi

              # Handle workload transitions
              if [ "$new_workload" != "$CURRENT_WORKLOAD" ]; then
                  log "Workload changed: $CURRENT_WORKLOAD -> $new_workload"

                  case "$new_workload" in
                      gaming)
                          write_profile_request "gaming"
                          ;;
                      builds)
                          write_profile_request "builds"
                          ;;
                      idle)
                          clear_profile_request
                          ;;
                      *)
                          log "Unknown workload: $new_workload"
                          ;;
                  esac

                  CURRENT_WORKLOAD="$new_workload"
              fi

              sleep "$CHECK_INTERVAL"
          done
        ''}/bin/mining-coordinator";

        Restart = "on-failure";
        RestartSec = "10s";
      };
    };

    # Runtime state directory
    systemd.tmpfiles.rules = [
      "d /run/mining-coordinator 0755 root root - -"
    ];
  };
}
