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
        procps
        kubernetes
        gnugrep
        gawk
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

          set -euo pipefail

          LOG_FILE="${config.services.mining-coordinator.logFile}"
          GAMING_STATE_FILE="${config.services.mining-coordinator.gamingStateFile}"
          PROFILE_REQUEST_FILE="${config.services.mining-coordinator.profileRequestFile}"
          CHECK_INTERVAL="${toString config.services.mining-coordinator.checkInterval}"

          PSI_CPU_BUILD_THRESHOLD="${config.services.mining-coordinator.psiCpuBuildThreshold}"
          PSI_CPU_IDLE_THRESHOLD="${config.services.mining-coordinator.psiCpuIdleThreshold}"
          PSI_MEM_SOME_THRESHOLD="1.0"
          PSI_MEM_FULL_THRESHOLD="0.5"
          PSI_IO_SOME_THRESHOLD="2.0"
          PSI_IO_FULL_THRESHOLD="0.3"
          PSI_HYSTERESIS_CYCLES=3

          PSI_BUILD_CYCLES=0

          log() {
              echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
          }

          get_hostname() {
              hostname
          }

          read_gaming_state() {
              if [[ -f "$GAMING_STATE_FILE" ]]; then
                  source "$GAMING_STATE_FILE"
                  echo "$GAMING_ACTIVE"
              else
                  echo "0"
              fi
          }

          write_profile_request() {
              local profile="$1"
              mkdir -p /run/mining-coordinator
              echo "$profile" > "$PROFILE_REQUEST_FILE"
              log "Profile request written: $profile"
          }

          clear_profile_request() {
              if [[ -f "$PROFILE_REQUEST_FILE" ]]; then
                  rm "$PROFILE_REQUEST_FILE"
                  log "Profile request cleared"
              fi
          }

          check_psi_cpu_pressure() {
              if [ ! -f /proc/pressure/cpu ]; then
                  return 1
              fi

              local psi_line=$(grep 'some' /proc/pressure/cpu 2>/dev/null || echo "")
              if [ -z "$psi_line" ]; then
                  return 1
              fi

              local psi_avg10=$(echo "$psi_line" | awk '{for(i=1;i<=NF;i++) if($i ~ /^avg10=/) {print $i}}' | cut -d'=' -f2)

              if [ -z "$psi_avg10" ]; then
                  return 1
              fi

              local above_threshold=$(echo "$psi_avg10" | awk "BEGIN {print (\$1 > $PSI_CPU_BUILD_THRESHOLD)}")
              local below_idle=$(echo "$psi_avg10" | awk "BEGIN {print (\$1 < $PSI_CPU_IDLE_THRESHOLD)}")

              if [ "$above_threshold" = "1" ]; then
                  PSI_BUILD_CYCLES=0
                  log "PSI: High CPU pressure detected (avg10=$psi_avg10 > $PSI_CPU_BUILD_THRESHOLD)"
                  return 0
              elif [ "$below_idle" = "1" ]; then
                  PSI_BUILD_CYCLES=$((PSI_BUILD_CYCLES + 1))

                  if [ "$PSI_BUILD_CYCLES" -ge "$PSI_HYSTERESIS_CYCLES" ]; then
                      log "PSI: CPU pressure cleared (avg10=$psi_avg10 < $PSI_CPU_IDLE_THRESHOLD for $PSI_BUILD_CYCLES cycles)"
                      return 1
                  else
                      log "PSI: Hysteresis waiting (avg10=$psi_avg10, cycle $PSI_BUILD_CYCLES/$PSI_HYSTERESIS_CYCLES)"
                      return 0
                  fi
              else
                  if [ "$PSI_BUILD_CYCLES" -gt 0 ]; then
                      log "PSI: Maintaining build state (avg10=$psi_avg10, between thresholds)"
                      return 0
                  fi
                  return 1
              fi
          }

          check_psi_memory_pressure() {
              if [ ! -f /proc/pressure/memory ]; then
                  return 1
              fi

              local psi_line=$(grep 'some' /proc/pressure/memory 2>/dev/null || echo "")
              if [ -z "$psi_line" ]; then
                  return 1
              fi

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

              if [ -n "$full_avg10" ]; then
                  local full_critical=$(echo "$full_avg10" | awk "BEGIN {print (\$1 > $PSI_MEM_FULL_THRESHOLD)}")
                  if [ "$full_critical" = "1" ]; then
                      PSI_BUILD_CYCLES=0
                      log "PSI: CRITICAL memory thrashing detected (full avg10=$full_avg10 > $PSI_MEM_FULL_THRESHOLD)"
                      return 0
                  fi
              fi

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
              if [ ! -f /proc/pressure/io ]; then
                  return 1
              fi

              local psi_line=$(grep 'some' /proc/pressure/io 2>/dev/null || echo "")
              if [ -z "$psi_line" ]; then
                  return 1
              fi

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

              if [ -n "$full_avg10" ]; then
                  local full_critical=$(echo "$full_avg10" | awk "BEGIN {print (\$1 > $PSI_IO_FULL_THRESHOLD)}")
                  if [ "$full_critical" = "1" ]; then
                      PSI_BUILD_CYCLES=0
                      log "PSI: CRITICAL I/O stall detected (full avg10=$full_avg10 > $PSI_IO_FULL_THRESHOLD)"
                      return 0
                  fi
              fi

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

          check_nix_daemon_activity() {
              if ! pgrep -x nix-daemon >/dev/null 2>&1; then
                  return 1
              fi

              local total_cpu="0.0"
              local count=0

              while IFS= read -r line; do
                  if [ -n "$line" ]; then
                      total_cpu=$(awk "BEGIN {print $total_cpu + $line}")
                      count=$((count + 1))
                  fi
              done < <(pgrep -x nix-daemon | xargs -r ps -p -o %cpu --no-headers 2>/dev/null | tr -d ' ')

              local is_active=$(awk "BEGIN {exit ($total_cpu > 10.0)}")
              if [ "$is_active" -eq 1 ]; then
                  log "nix-daemon activity detected: $total_cpu% CPU across $count processes"
                  return 0
              fi

              return 1
          }

          scale_gaming_placeholder() {
              local gaming_active=$1

              if ! command -v kubectl >/dev/null 2>&1; then
                  return 1
              fi

              if ! kubectl get nodes >/dev/null 2>&1; then
                  return 1
              fi

              local replicas=0
              if [[ "$gaming_active" == "1" ]]; then
                  replicas=1
                  log "K8s: Gaming detected - scaling up gaming-placeholder-volcano to preempt mining"
              fi

              if kubectl scale deployment gaming-placeholder-volcano -n mining --replicas=$replicas >/dev/null 2>&1; then
                  log "K8s: Scaled gaming-placeholder-volcano to $replicas replica(s)"
              else
                  log "K8s: Failed to scale gaming-placeholder-volcano"
                  return 1
              fi

              return 0
          }

          detect_workload() {

              local gaming_active=$(read_gaming_state)
              if [[ "$gaming_active" == "1" ]]; then
                  echo "gaming"
                  return
              fi

              if check_psi_memory_pressure; then
                  echo "builds"
                  return
              fi

              if check_psi_io_pressure; then
                  echo "builds"
                  return
              fi

              # Skip CPU PSI check when CPU mining is active (xmrig keeps PSI ~30%)
              if ! pgrep -x xmrig >/dev/null 2>&1; then
                  if check_psi_cpu_pressure; then
                      echo "builds"
                      return
                  fi
              else
                  log "PSI: Skipping CPU check - xmrig mining active"
              fi

              if check_nix_daemon_activity; then
                  echo "builds"
                  return
              fi

              echo "idle"
          }

          log "Starting mining coordinator (check interval: ''${CHECK_INTERVAL}s)"
          log "PSI thresholds: CPU_BUILD=$PSI_CPU_BUILD_THRESHOLD CPU_IDLE=$PSI_CPU_IDLE_THRESHOLD"
          log "Gaming state file: $GAMING_STATE_FILE"
          log "Profile request file: $PROFILE_REQUEST_FILE"

          mkdir -p /run/mining-coordinator

          CURRENT_WORKLOAD="idle"
          PREVIOUS_GAMING_STATE="0"

          while true; do
              new_workload=$(detect_workload)

              current_gaming_state=$(read_gaming_state)

              if [[ "$PREVIOUS_GAMING_STATE" != "$current_gaming_state" ]]; then
                  log "Gaming state changed: $PREVIOUS_GAMING_STATE -> $current_gaming_state"
                  scale_gaming_placeholder "$current_gaming_state"
                  PREVIOUS_GAMING_STATE="$current_gaming_state"
              fi

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

    systemd.tmpfiles.rules = [
      "d /run/mining-coordinator 0755 root root - -"
    ];
  };
}
