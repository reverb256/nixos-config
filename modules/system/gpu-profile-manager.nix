# GPU Profile Manager Module
# Host-level GPU power management via nvidia-smi
# Reads gaming state and workload requests to apply appropriate GPU profiles
# NO service control - K8s Volcano handles mining pause/resume
{
  config,
  pkgs,
  lib,
  ...
}: {
  options.services.gpu-profile-manager = {
    enable = lib.mkEnableOption "GPU profile manager for workload-based power management";

    checkInterval = lib.mkOption {
      type = lib.types.int;
      default = 10;
      description = "Check interval in seconds";
    };

    logFile = lib.mkOption {
      type = lib.types.str;
      default = "/var/log/gpu-profile-manager.log";
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
      description = "Path to profile request file from mining-coordinator service";
    };
  };

  config = lib.mkIf config.services.gpu-profile-manager.enable {
    systemd.services.gpu-profile-manager = {
      description = "GPU Profile Manager - Workload-based GPU power management";
      wantedBy = ["multi-user.target"];
      after = [
        "network.target"
        "gaming-detection.service"
        "mining-coordinator.service"
      ];
      path = with pkgs; [
        procps # pgrep
        kubernetes # kubectl for K8s GPU workload detection
        gnugrep
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
              coreutils
            ]
          )
        }:/run/current-system/sw/bin";
        ExecStart = "${pkgs.writeShellScriptBin "gpu-profile-manager" ''
          # GPU Profile Manager
          # Applies GPU power profiles based on detected workload
          # Reads gaming state from gaming-detection service
          # Reads profile requests from mining-coordinator service
          # NO service control - only nvidia-smi commands

          set -euo pipefail

          LOG_FILE="${config.services.gpu-profile-manager.logFile}"
          GAMING_STATE_FILE="${config.services.gpu-profile-manager.gamingStateFile}"
          PROFILE_REQUEST_FILE="${config.services.gpu-profile-manager.profileRequestFile}"
          CHECK_INTERVAL="${toString config.services.gpu-profile-manager.checkInterval}"

          # Logging function
          log() {
              echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
          }

          # Get hostname
          get_hostname() {
              hostname
          }

          # ============================================================================
          # GPU HELPER FUNCTIONS
          # ============================================================================
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

          # ============================================================================
          # WORKLOAD DETECTION
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

          # Read profile request from mining-coordinator service
          read_profile_request() {
              if [[ -f "$PROFILE_REQUEST_FILE" ]]; then
                  cat "$PROFILE_REQUEST_FILE"
              else
                  echo ""  # No request
              fi
          }

          # Check for Kubernetes GPU workloads (excluding mining namespace)
          check_kubernetes_gpu_workload() {
              # Check if kubectl is available and cluster is accessible
              if ! command -v kubectl >/dev/null 2>&1; then
                  return 1
              fi

              # Check if we can connect to the cluster
              if ! kubectl get nodes >/dev/null 2>&1; then
                  return 1
              fi

              # Check for GPU pods across all namespaces EXCEPT mining
              # Look for pods with nvidia.com/gpu resource requests
              local gpu_pods=$(kubectl get pods --all-namespaces \
                  -o jsonpath='{range .items[?(@.spec.containers[*].resources.limits.nvidia\.com/gpu)]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}' \
                  2>/dev/null || echo "")

              if [ -n "$gpu_pods" ]; then
                  # Filter out mining namespace and non-running pods
                  local running_gpu_pods=$(echo "$gpu_pods" | while read -r pod; do
                      [ -z "$pod" ] && continue
                      local namespace=$(echo "$pod" | cut -d'/' -f1)

                      # Skip mining namespace (mining pods are managed by Volcano preemption)
                      if [[ "$namespace" == "mining" ]]; then
                          continue
                      fi

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

          # Detect current workload based on all signals
          detect_workload() {
              # Priority: Profile Request > Gaming > K8s GPU > Idle

              # Check for explicit profile request (highest priority)
              local requested_profile=$(read_profile_request)
              if [[ -n "$requested_profile" ]]; then
                  log "Using requested profile: $requested_profile"
                  echo "$requested_profile"
                  return
              fi

              # Check gaming state (from gaming-detection service)
              local gaming_active=$(read_gaming_state)
              if [[ "$gaming_active" == "1" ]]; then
                  echo "gaming"
                  return
              fi

              # Check for Kubernetes GPU workloads
              if check_kubernetes_gpu_workload; then
                  echo "kubernetes-gpu"
                  return
              fi

              # Default: idle
              echo "idle"
          }

          # ============================================================================
          # GPU PROFILES
          # ============================================================================
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
          }

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
          }

          apply_builds_profile() {
              echo "=== Applying GPU/CPU BUILDS profile ==="

              local gpus=$(get_gpu_list)
              local gpu_count=$(echo "$gpus" | wc -l)

              if [ "$gpu_count" -eq 0 ]; then
                  echo "WARNING: No NVIDIA GPUs detected"
              else
                  echo "Detected $gpu_count GPU(s) for builds profile"
              fi

              # GPU profiles for builds (balanced, not max)
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

              echo "BUILDS profile applied: Mode: Balanced for CUDA/heavy workloads"
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
                          # 3060 Ti: Reset to mining power limits
                          nvidia_safe nvidia-smi -i "$gpu_id" -pl 130
                          nvidia_safe nvidia-smi -i "$gpu_id" -lgc 1700
                          nvidia_safe nvidia-smi -i "$gpu_id" -lmc 5200
                          echo "  3060 Ti: 1700 MHz GPU, 5200 MHz mem (130W limit (mining-optimized)"
                          ;;
                      *"3090"*)
                          # 3090: Reset to mining power limits
                          nvidia_safe nvidia-smi -i "$gpu_id" -pl 250
                          nvidia_safe nvidia-smi -i "$gpu_id" -lgc 1750
                          nvidia_safe nvidia-smi -i "$gpu_id" -lmc 6500
                          echo "  3090: 1750 MHz GPU (liquid-cooled), 6500 MHz mem (250W limit (mining-optimized)"
                          ;;
                      *)
                          # Default: Don't override power limits, let mining module manage
                          nvidia_safe nvidia-smi -i "$gpu_id" -rgc
                          nvidia_safe nvidia-smi -i "$gpu_id" -rmc
                          echo "  $gpu_name: Default efficiency profile (power limit from mining module)"
                          ;;
                  esac
              done

              echo "MINING profile applied: Mode: Efficiency-optimized"
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

          # ============================================================================
          # PROFILE APPLICATION
          # ============================================================================
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
                  echo "$current_limit" > /run/gpu-profile-manager/gpu"$gpu_id"_original_power
                  log "Stored original power limit for GPU $gpu_id: $current_limit W"
              done
          }

          restore_original_power_limits() {
              local gpus=$(get_gpu_list)
              for gpu_id in $gpus; do
                  local stored_file="/run/gpu-profile-manager/gpu"$gpu_id"_original_power"
                  if [ -f "$stored_file" ]; then
                      local original_limit=$(cat "$stored_file")
                      log "Restoring GPU $gpu_id power limit to $original_limit W"
                      nvidia_safe nvidia-smi -i "$gpu_id" -pl "$original_limit"
                  fi
              done
          }

          # ============================================================================
          # MAIN LOOP
          # ============================================================================
          log "Starting GPU profile manager (check interval: ''${CHECK_INTERVAL}s)"
          log "Gaming state file: $GAMING_STATE_FILE"
          log "Profile request file: $PROFILE_REQUEST_FILE"

          # Create state directory
          mkdir -p /run/gpu-profile-manager

          # Store original power limits on first run
          log "Storing original GPU power limits for restoration..."
          store_original_power_limits

          # State tracking
          CURRENT_WORKLOAD="idle"

          while true; do
              new_workload=$(detect_workload)

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

              sleep "$CHECK_INTERVAL"
          done
        ''}/bin/gpu-profile-manager";

        Restart = "on-failure";
        RestartSec = "10s";
      };
    };

    # Runtime state directory
    systemd.tmpfiles.rules = [
      "d /run/gpu-profile-manager 0755 root root - -"
    ];
  };
}
