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
      after = ["network.target" "kubernetes.target"];
      path = with pkgs; [
        procps # pgrep
        systemd # systemctl
        kubernetes # kubectl for Kubernetes GPU workload detection
        bc # for floating point arithmetic in nix-daemon CPU detection
      ];

      serviceConfig = {
        Type = "simple";
        Environment = "PATH=${lib.makeBinPath (with pkgs; [procps systemd kubernetes])}:/run/current-system/sw/bin";
        ExecStart = "${pkgs.writeShellScriptBin "compute-workload-monitor" ''
          # Autonomous GPU Workload Monitor
          # Detects workload type and adjusts GPU profiles automatically
          # Manages mining pauses when AI/Gaming/K8s workloads detected

          set -euo pipefail

          LOG_FILE="${config.services.compute-workload-monitor.logFile}"
          MINING_SERVICES=("lolminer-nvidia" "xmrig")
          GAMING_PROCESSES=("steam\\.exe" "steamwebhelper" "steamapps" "Steam\\\\ Helper" "lutris" "heroic" "Lutris" "HeroicGamesLauncher" "wine(32|64)\\.exe" "proton")
          BUILD_PROCESSES=("nixos-rebuild" "colmena" "nix-build" "nix-daemon" "nix-store" "gcc" "clang" "cargo build" "make" "cmake" "ninja")

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
              # Priority: Gateway Signal (AI only) > Gaming > Kubernetes GPU > VRAM Pressure > Builds > Mining > Idle
              # AI workloads are detected ONLY via explicit gateway signal (no process-based detection)

              # Check for gateway signal (explicit AI workload notification)
              if check_gateway_signal; then
                  echo "ai"
                  return
              fi

              # Check for gaming
              for proc in "''${GAMING_PROCESSES[@]}"; do
                  if check_process_running "$proc"; then
                      echo "gaming"
                      return
                  fi
              done

              # Check for Kubernetes GPU workloads (Phase 1)
              if check_kubernetes_gpu_workload; then
                  echo "kubernetes-gpu"
                  return
              fi

              # Check for VRAM pressure (prevent miner from starting)
              if check_vram_pressure; then
                  echo "vram-pressure"
                  return
              fi

              # Check for build workloads using multiple detection methods (priority order)
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

              # Check for active mining
              for service in "''${MINING_SERVICES[@]}"; do
                  if systemctl is-active --quiet "$service"; then
                      # Mining is only active if no higher priority workload
                      echo "mining"
                      return
                  fi
              done

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
                  nexus)  echo "4" ;;   # 17% of 24 threads
                  sentry) echo "4" ;;   # 25% of 16 threads
                  *)      echo "4" ;;   # Conservative default
              esac
          }

          get_xmrig_idle_threads() {
              local host=$(get_hostname)
              case "$host" in
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

          pause_xmrig() {
              log "Pausing XMRig completely"
              systemctl stop xmrig
          }

          resume_xmrig() {
              local threads=$1
              log "Resuming XMRig with $threads threads"
              systemctl start xmrig
          }

          # VRAM pressure detection to prevent desktop freezes
          get_vram_threshold() {
              local gpu_id="$1"
              local gpu_name=$(get_gpu_name "$gpu_id")
              local host=$(get_hostname)

              # Per-GPU thresholds based on VRAM capacity and use case
              case "$gpu_name" in
                  *"3060"*|*"3050"*)
                      # Small GPUs (8GB): Allow mining when needed
                      # Miner needs 7GB, so 90% threshold = 7.2GB allowed
                      echo "90"
                      ;;
                  *"3090"*|*"3080"*)
                      # Large GPUs (24GB): Protect VRAM for AI/gaming
                      # 40% threshold = 9.6GB reserved for models
                      case "$host" in
                          forge)   echo "50" ;;  # Mining rig: more aggressive
                          *)       echo "40" ;;
                      esac
                      ;;
                      *"3070"*|*"3080"*)
                      # Medium-large GPUs (20GB+)
                      echo "45"
                      ;;
                      *)
                      # Conservative default for unknown GPUs
                      echo "40"
                      ;;
              esac
          }

          get_vram_usage_percent() {
              local gpu_id="$1"
              local vram_info=$(nvidia-smi -i "$gpu_id" --query-gpu=memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null)
              if [ -z "$vram_info" ]; then
                  echo "0"
                  return 1
              fi

              local used=$(echo "$vram_info" | cut -d',' -f1 | tr -d ' ')
              local total=$(echo "$vram_info" | cut -d',' -f2 | tr -d ' ')

              if [ "$total" -eq 0 ]; then
                  echo "0"
                  return 1
              fi

              local usage_percent=$((used * 100 / total))
              echo "$usage_percent"
          }

          check_vram_pressure() {
              local gpus=$(get_gpu_list)

              log "Checking VRAM pressure (per-GPU thresholds)..."

              for gpu_id in $gpus; do
                  local usage=$(get_vram_usage_percent "$gpu_id")
                  local gpu_name=$(get_gpu_name "$gpu_id")
                  local threshold
                  threshold=$(get_vram_threshold "$gpu_id")

                  log "  GPU $gpu_id ($gpu_name): ''${usage}% used (threshold: ''${threshold}%)"

                  if [ "$usage" -gt "$threshold" ]; then
                      log "  ⚠️  VRAM PRESSURE DETECTED on GPU $gpu_id: ''${usage}% > ''${threshold}%"
                      log "  Preventing miner start to avoid desktop freeze"
                      return 0  # Pressure detected (true)
                  fi
              done

              log "  ✓ VRAM usage acceptable across all GPUs"
              return 1  # No pressure (false)
          }

          get_max_vram_gpu() {
              local gpus=$(get_gpu_list)
              local max_usage=0
              local max_gpu=0

              for gpu_id in $gpus; do
                  local usage=$(get_vram_usage_percent "$gpu_id")
                  if [ "$usage" -gt "$max_usage" ]; then
                      max_usage=$usage
                      max_gpu=$gpu_id
                  fi
              done

              echo "$max_gpu:$max_usage"
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
              if systemctl is-active --quiet xmrig; then
                  log "Limiting xmrig to 50% CPU for Kubernetes workloads"
                  systemctl set-property xmrig.service CPUQuota="50%" --runtime
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
                          # 3060 Ti: Max performance
                          nvidia_safe nvidia-smi -i "$gpu_id" -pl 200
                          nvidia_safe nvidia-smi -i "$gpu_id" -lgc 2100
                          nvidia_safe nvidia-smi -i "$gpu_id" -lmc 7000
                          echo "  3060 Ti: 2100 MHz GPU, 7000 MHz mem, 200W limit"
                          ;;
                      *"3090"*)
                          # 3090: Aggressive GPU (liquid cooled), conservative VRAM
                          nvidia_safe nvidia-smi -i "$gpu_id" -pl 350
                          nvidia_safe nvidia-smi -i "$gpu_id" -lgc 2050
                          nvidia_safe nvidia-smi -i "$gpu_id" -lmc 7500
                          echo "  3090: 2050 MHz GPU (liquid-cooled), 7500 MHz mem, 350W limit"
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

              # STOP GPU mining completely to free VRAM (prevents desktop freeze)
              if systemctl is-active --quiet lolminer-nvidia; then
                  log "Stopping lolminer-nvidia to free VRAM for gaming"
                  systemctl stop lolminer-nvidia
              fi

              if systemctl is-active --quiet lolminer-amd; then
                  log "Stopping lolminer-amd to free VRAM for gaming"
                  systemctl stop lolminer-amd
              fi

              # Reduce CPU mining to 25% (free CPU for game logic)
              if systemctl is-active --quiet xmrig; then
                  log "Limiting xmrig to 25% CPU for gaming"
                  systemctl set-property xmrig.service CPUQuota="25%" --runtime
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
              if systemctl is-active --quiet xmrig; then
                  log "Keeping xmrig at 100% CPU (GPU is bottleneck for AI)"
                  systemctl set-property xmrig.service CPUQuota="100%" --runtime
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

              # Reduce GPU mining to 10% (builds may need GPU for CUDA/heavy workloads)
              if systemctl is-active --quiet lolminer-nvidia; then
                  log "Limiting lolminer-nvidia to 10% CPU for builds"
                  systemctl set-property lolminer-nvidia.service CPUQuota="10%" --runtime
              fi

              if systemctl is-active --quiet lolminer-amd; then
                  log "Limiting lolminer-amd to 10% CPU for builds"
                  systemctl set-property lolminer-amd.service CPUQuota="10%" --runtime
              fi

              # Reduce CPU mining to 10% (builds need maximum CPU)
              if systemctl is-active --quiet xmrig; then
                  log "Limiting xmrig to 10% CPU for builds"
                  systemctl set-property xmrig.service CPUQuota="10%" --runtime
              fi

              # Ensure nix-daemon gets high priority for builds
              if systemctl is-active --quiet nix-daemon; then
                  log "Setting nix-daemon to high CPU weight for builds"
                  systemctl set-property nix-daemon.service CPUWeight=2048 --runtime
              fi

              echo "BUILDS profile applied: Mode: 10% mining, builds get priority"
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
                          # 3060 Ti: Efficiency-focused
                          nvidia_safe nvidia-smi -i "$gpu_id" -pl 100
                          nvidia_safe nvidia-smi -i "$gpu_id" -lgc 1700
                          nvidia_safe nvidia-smi -i "$gpu_id" -lmc 5200
                          echo "  3060 Ti: 1700 MHz GPU, 5200 MHz mem, 100W limit"
                          ;;
                      *"3090"*)
                          # 3090: Efficiency with liquid cooling
                          nvidia_safe nvidia-smi -i "$gpu_id" -pl 270
                          nvidia_safe nvidia-smi -i "$gpu_id" -lgc 1750
                          nvidia_safe nvidia-smi -i "$gpu_id" -lmc 6500
                          echo "  3090: 1750 MHz GPU (liquid-cooled), 6500 MHz mem, 270W limit"
                          ;;
                      *)
                          # Default: Efficiency
                          nvidia_safe nvidia-smi -i "$gpu_id" -pl 200
                          nvidia_safe nvidia-smi -i "$gpu_id" -rgc
                          nvidia_safe nvidia-smi -i "$gpu_id" -rmc
                          echo "  $gpu_name: Default efficiency profile"
                          ;;
                  esac
              done

              echo "MINING profile applied: Mode: Efficiency-optimized"

              # Reset all mining to 100% CPU
              if systemctl is-active --quiet lolminer-nvidia; then
                  log "Resetting lolminer-nvidia to 100% CPU"
                  systemctl set-property lolminer-nvidia.service CPUQuota="100%" --runtime
              fi

              if systemctl is-active --quiet lolminer-amd; then
                  log "Resetting lolminer-amd to 100% CPU"
                  systemctl set-property lolminer-amd.service CPUQuota="100%" --runtime
              fi

              if systemctl is-active --quiet xmrig; then
                  local idle_threads=$(get_xmrig_idle_threads)
                  log "Resetting xmrig to 100% CPU ($idle_threads threads)"
                  systemctl set-property xmrig.service CPUQuota="100%" --runtime
                  reset_xmrig_threads "$idle_threads"
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

          # State tracking
          CURRENT_WORKLOAD="idle"
          CHECK_INTERVAL="${toString config.services.compute-workload-monitor.checkInterval}"

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

          while true; do
              new_workload=$(get_workload_type)

              if [ "$new_workload" != "$CURRENT_WORKLOAD" ]; then
                  log "Workload changed: $CURRENT_WORKLOAD -> $new_workload"
                  CURRENT_WORKLOAD="$new_workload"
                  apply_profile "$new_workload"
              fi

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

    # Runtime config directory for imperative threshold overrides
    systemd.tmpfiles.rules = [
      "d /run/compute-workload-monitor 0755 root root - -"
    ];
  };
}
