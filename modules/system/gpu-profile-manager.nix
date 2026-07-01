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
        procps
        kubernetes
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

          set -euo pipefail

          LOG_FILE="${config.services.gpu-profile-manager.logFile}"
          GAMING_STATE_FILE="${config.services.gpu-profile-manager.gamingStateFile}"
          PROFILE_REQUEST_FILE="${config.services.gpu-profile-manager.profileRequestFile}"
          CHECK_INTERVAL="${toString config.services.gpu-profile-manager.checkInterval}"

          # Power limits config (read by _load_power_config, NOT sourced directly)
          POWER_PROFILES_CONF="/etc/nvidia-power-profiles.conf"

          # Look up power limit for a profile + GPU name pattern
          # Falls back to nvidia-smi power.max_limit if no match
          # Uses associative array populated from the sourced config
          declare -A POWER_MAP=()
          _load_power_config() {
              if [[ ''${#POWER_MAP[@]} -eq 0 && -f "$POWER_PROFILES_CONF" ]]; then
                  while IFS='=' read -r key val; do
                      [[ -z "$key" || "$key" == \#* ]] && continue
                      POWER_MAP["$key"]="$val"
                  done < "$POWER_PROFILES_CONF"
              fi
          }

          get_power_limit() {
              local profile="$1"
              local gpu_name="$2"
              local gpu_id="$3"

              _load_power_config

              # Try matching GPU patterns from longest to shortest
              for pattern in 3090 3060 4060 4070 4080 4090 3080 3070; do
                  if [[ "$gpu_name" == *"$pattern"* ]]; then
                      local key="POWER_''${profile}_''${pattern}"
                      if [[ -n "''${POWER_MAP[$key]+x}" ]]; then
                          echo "''${POWER_MAP[$key]}"
                          return 0
                      fi
                  fi
              done

              # No match in config — query GPU max power limit
              nvidia-smi -i "$gpu_id" --query-gpu=power.max_limit --format=csv,noheader,nounits 2>/dev/null | tr -d '.' || echo "300"
          }

          log() {
              echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
          }

          get_hostname() {
              hostname
          }

          get_gpu_list() {
              nvidia-smi --query-gpu=index --format=csv,noheader,nounits 2>/dev/null || echo ""
          }

          get_gpu_name() {
              local gpu_id="$1"
              nvidia-smi -i "$gpu_id" --query-gpu=name --format=csv,noheader 2>/dev/null || echo "Unknown"
          }

          nvidia_safe() {
              "$@" 2>/dev/null || true
          }

          read_gaming_state() {
              if [[ -f "$GAMING_STATE_FILE" ]]; then
                  source "$GAMING_STATE_FILE"
                  echo "$GAMING_ACTIVE"
              else
                  echo "0"
              fi
          }

          read_profile_request() {
              if [[ -f "$PROFILE_REQUEST_FILE" ]]; then
                  cat "$PROFILE_REQUEST_FILE"
              else
                  echo ""
              fi
          }

          check_kubernetes_gpu_workload() {
              if ! command -v kubectl >/dev/null 2>&1; then
                  return 1
              fi

              if ! kubectl get nodes >/dev/null 2>&1; then
                  return 1
              fi

              local gpu_pods=$(kubectl get pods --all-namespaces \
                  -o jsonpath='{range .items[?(@.spec.containers[*].resources.limits.nvidia\.com/gpu)]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}' \
                  2>/dev/null || echo "")

              if [ -n "$gpu_pods" ]; then
                  local running_gpu_pods=$(echo "$gpu_pods" | while read -r pod; do
                      [ -z "$pod" ] && continue
                      local namespace=$(echo "$pod" | cut -d'/' -f1)

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

          detect_workload() {

              local requested_profile=$(read_profile_request)
              if [[ -n "$requested_profile" ]]; then
                  log "Using requested profile: $requested_profile"
                  echo "$requested_profile"
                  return
              fi

              local gaming_active=$(read_gaming_state)
              if [[ "$gaming_active" == "1" ]]; then
                  echo "gaming"
                  return
              fi

              # Local peakminer systemd units count as active mining workload.
              # When any peakminer-* process is running, lock the mining profile and
              # hand power/clock control to peakminer (or to the mining profile below
              # on hosts where peakminer powerLimit is null).
              if pgrep -x peakminer >/dev/null 2>&1; then
                  echo "mining"
                  return
              fi

              if check_kubernetes_gpu_workload; then
                  echo "kubernetes-gpu"
                  return
              fi

              echo "idle"
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
                          nvidia_safe nvidia-smi -i "$gpu_id" -lgc 1800
                          nvidia_safe nvidia-smi -i "$gpu_id" -lmc 6000
                          echo "  3060 Ti: Clock locks only (1800/6000 MHz), power limit unchanged"
                          ;;
                      *"3090"*)
                          local pw=$(get_power_limit gaming "$gpu_name" "$gpu_id")
                          nvidia_safe nvidia-smi -i "$gpu_id" -pl "$pw"
                          nvidia_safe nvidia-smi -i "$gpu_id" -lgc 2050
                          nvidia_safe nvidia-smi -i "$gpu_id" -lmc 7500
                          echo "  3090: 2050 MHz GPU (liquid-cooled), 7500 MHz mem, 350W limit (PRIMARY GAMING GPU)"
                          ;;
                      *"4060"*)
                          local pw=$(get_power_limit gaming "$gpu_name" "$gpu_id")
                          nvidia_safe nvidia-smi -i "$gpu_id" -pl "$pw"
                          nvidia_safe nvidia-smi -i "$gpu_id" -lgc 2100
                          nvidia_safe nvidia-smi -i "$gpu_id" -lmc 6800
                          echo "  4060 (Ada): 2100 MHz GPU, 6800 MHz mem, 110W limit"
                          ;;
                      *)
                          local pw=$(get_power_limit gaming "$gpu_name" "$gpu_id")
                          nvidia_safe nvidia-smi -i "$gpu_id" -pl "$pw"
                          nvidia_safe nvidia-smi -i "$gpu_id" -rgc
                          nvidia_safe nvidia-smi -i "$gpu_id" -rmc
                          echo "  $gpu_name: Default max performance profile (''${pw} W)"
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

              for gpu_id in $gpus; do
                  local gpu_name=$(get_gpu_name "$gpu_id")
                  echo "Configuring GPU $gpu_id ($gpu_name)..."

                  case "$gpu_name" in
                      *"3060"*)
                          local pw=$(get_power_limit kubernetes-gpu "$gpu_name" "$gpu_id")
                          nvidia_safe nvidia-smi -i "$gpu_id" -pl "$pw"
                          nvidia_safe nvidia-smi -i "$gpu_id" -lgc 1800
                          nvidia_safe nvidia-smi -i "$gpu_id" -lmc 6000
                          echo "  3060 Ti: 1800 MHz GPU, 6000 MHz mem, ''${pw}W limit"
                          ;;
                      *"3090"*)
                          local pw=$(get_power_limit kubernetes-gpu "$gpu_name" "$gpu_id")
                          nvidia_safe nvidia-smi -i "$gpu_id" -pl "$pw"
                          nvidia_safe nvidia-smi -i "$gpu_id" -lgc 1800
                          nvidia_safe nvidia-smi -i "$gpu_id" -lmc 6800
                          echo "  3090: 1800 MHz GPU (liquid-cooled), 6800 MHz mem, ''${pw}W limit"
                          ;;
                      *"4060"*)
                          local pw=$(get_power_limit kubernetes-gpu "$gpu_name" "$gpu_id")
                          nvidia_safe nvidia-smi -i "$gpu_id" -pl "$pw"
                          nvidia_safe nvidia-smi -i "$gpu_id" -lgc 1900
                          nvidia_safe nvidia-smi -i "$gpu_id" -lmc 6200
                          echo "  4060 (Ada): 1900 MHz GPU, 6200 MHz mem, ''${pw}W limit"
                          ;;
                      *)
                          local pw=$(get_power_limit kubernetes-gpu "$gpu_name" "$gpu_id")
                          nvidia_safe nvidia-smi -i "$gpu_id" -pl "$pw"
                          nvidia_safe nvidia-smi -i "$gpu_id" -rgc
                          nvidia_safe nvidia-smi -i "$gpu_id" -rmc
                          echo "  $gpu_name: Default balanced profile (''${pw} W)"
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
                          local pw=$(get_power_limit ai "$gpu_name" "$gpu_id")
                          nvidia_safe nvidia-smi -i "$gpu_id" -pl "$pw"
                          nvidia_safe nvidia-smi -i "$gpu_id" -lgc 1950
                          nvidia_safe nvidia-smi -i "$gpu_id" -lmc 6200
                          echo "  3060 Ti: 1950 MHz GPU, 6200 MHz mem, 110W limit"
                          ;;
                      *"3090"*)
                          local pw=$(get_power_limit ai "$gpu_name" "$gpu_id")
                          nvidia_safe nvidia-smi -i "$gpu_id" -pl "$pw"
                          nvidia_safe nvidia-smi -i "$gpu_id" -lgc 1900
                          nvidia_safe nvidia-smi -i "$gpu_id" -lmc 7000
                          echo "  3090: 1900 MHz GPU (liquid-cooled), 7000 MHz mem, ''${pw}W limit"
                          ;;
                      *"4060"*)
                          local pw=$(get_power_limit ai "$gpu_name" "$gpu_id")
                          nvidia_safe nvidia-smi -i "$gpu_id" -pl "$pw"
                          nvidia_safe nvidia-smi -i "$gpu_id" -lgc 2000
                          nvidia_safe nvidia-smi -i "$gpu_id" -lmc 6400
                          echo "  4060 (Ada): 2000 MHz GPU, 6400 MHz mem, ''${pw}W limit"
                          ;;
                      *)
                          local pw=$(get_power_limit kubernetes-gpu "$gpu_name" "$gpu_id")
                          nvidia_safe nvidia-smi -i "$gpu_id" -pl "$pw"
                          nvidia_safe nvidia-smi -i "$gpu_id" -rgc
                          nvidia_safe nvidia-smi -i "$gpu_id" -rmc
                          echo "  $gpu_name: Default balanced profile (''${pw} W)"
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

              for gpu_id in $gpus; do
                  local gpu_name=$(get_gpu_name "$gpu_id")

                  case "$gpu_name" in
                      *"3060"*)
                          local pw=$(get_power_limit builds "$gpu_name" "$gpu_id")
                          nvidia_safe nvidia-smi -i "$gpu_id" -pl "$pw"
                          ;;
                      *"3090"*)
                          local pw=$(get_power_limit builds "$gpu_name" "$gpu_id")
                          nvidia_safe nvidia-smi -i "$gpu_id" -pl "$pw"
                          ;;
                      *"4060"*)
                          local pw=$(get_power_limit builds "$gpu_name" "$gpu_id")
                          nvidia_safe nvidia-smi -i "$gpu_id" -pl "$pw"
                          ;;
                      *)
                          local pw=$(get_power_limit builds "$gpu_name" "$gpu_id")
                          nvidia_safe nvidia-smi -i "$gpu_id" -pl "$pw"
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
                          local pw=$(get_power_limit mining "$gpu_name" "$gpu_id")
                          nvidia_safe nvidia-smi -i "$gpu_id" -pl "$pw"
                          # No clock locks for 3060 Ti mining - power limit only
                          nvidia_safe nvidia-smi -i "$gpu_id" -rgc
                          nvidia_safe nvidia-smi -i "$gpu_id" -rmc
                          echo "  3060 Ti: Power limit ${pw}W only, clocks auto (mining-optimized)"
                          ;;
                      *"3090"*)
                          local pw=$(get_power_limit mining "$gpu_name" "$gpu_id")
                          nvidia_safe nvidia-smi -i "$gpu_id" -pl "$pw"
                          # No clock locks for 3090 mining - power limit only
                          nvidia_safe nvidia-smi -i "$gpu_id" -rgc
                          nvidia_safe nvidia-smi -i "$gpu_id" -rmc
                          echo "  3090: Power limit ${pw}W only, clocks auto (mining-optimized)"
                          ;;
                      *"4060"*)
                          local pw=$(get_power_limit mining "$gpu_name" "$gpu_id")
                          nvidia_safe nvidia-smi -i "$gpu_id" -pl "$pw"
                          nvidia_safe nvidia-smi -i "$gpu_id" -lgc 2000
                          nvidia_safe nvidia-smi -i "$gpu_id" -lmc 6550
                          echo "  4060 (Ada): 2000 MHz GPU (+200), 6550 MHz mem (+1150), ${pw}W limit (mining-optimized)"
                          ;;
                      *)
                          local pw=$(get_power_limit mining "$gpu_name" "$gpu_id")
                          nvidia_safe nvidia-smi -i "$gpu_id" -pl "$pw"
                          nvidia_safe nvidia-smi -i "$gpu_id" -rgc
                          nvidia_safe nvidia-smi -i "$gpu_id" -rmc
                          echo "  $gpu_name: Default efficiency profile (''${pw} W)"
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

                  case "$gpu_name" in
                      *"3060"*)
                          local pw=$(get_power_limit idle "$gpu_name" "$gpu_id")
                          nvidia_safe nvidia-smi -i "$gpu_id" -pl "$pw"
                          ;;
                      *"3090"*)
                          local pw=$(get_power_limit idle "$gpu_name" "$gpu_id")
                          nvidia_safe nvidia-smi -i "$gpu_id" -pl "$pw"
                          ;;
                      *"4060"*)
                          local pw=$(get_power_limit idle "$gpu_name" "$gpu_id")
                          nvidia_safe nvidia-smi -i "$gpu_id" -pl "$pw"
                          ;;
                      *)
                          local pw=$(get_power_limit idle "$gpu_name" "$gpu_id")
                          nvidia_safe nvidia-smi -i "$gpu_id" -pl "$pw"
                          ;;
                  esac

                  nvidia_safe nvidia-smi -i "$gpu_id" -rgc
                  nvidia_safe nvidia-smi -i "$gpu_id" -rmc

                  echo "  GPU $gpu_id: Reset to defaults (adaptive mode)"
              done

              echo "RESET to defaults applied: Mode: Adaptive (auto)"
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

          store_original_power_limits() {
              local gpus=$(get_gpu_list)
              local lock_file="/run/gpu-profile-manager/gpu_state.lock"

              (
                  flock -x 200
                  for gpu_id in $gpus; do
                      local current_limit=$(nvidia-smi -i "$gpu_id" --query-gpu=power.limit --format=csv,noheader,nounits 2>/dev/null | tr -d '[:space:]')
                      echo "$current_limit" > /run/gpu-profile-manager/gpu"$gpu_id"_original_power
                      log "Stored original power limit for GPU $gpu_id: $current_limit W"
                  done
              ) 200>"$lock_file"
          }

          restore_original_power_limits() {
              local gpus=$(get_gpu_list)
              local lock_file="/run/gpu-profile-manager/gpu_state.lock"

              (
                  flock -x 200
                  for gpu_id in $gpus; do
                      local stored_file="/run/gpu-profile-manager/gpu"$gpu_id"_original_power"
                      if [ -f "$stored_file" ]; then
                          local original_limit=$(cat "$stored_file")
                          log "Restoring GPU $gpu_id power limit to $original_limit W"
                          nvidia_safe nvidia-smi -i "$gpu_id" -pl "$original_limit"
                      fi
                  done
              ) 200>"$lock_file"
          }

          log "Starting GPU profile manager (check interval: ''${CHECK_INTERVAL}s)"
          log "Gaming state file: $GAMING_STATE_FILE"
          log "Profile request file: $PROFILE_REQUEST_FILE"

          mkdir -p /run/gpu-profile-manager

          log "Storing original GPU power limits for restoration..."
          store_original_power_limits

          CURRENT_WORKLOAD="idle"

          while true; do
              new_workload=$(detect_workload)

              if [ "$new_workload" != "$CURRENT_WORKLOAD" ]; then
                  log "Workload changed: $CURRENT_WORKLOAD -> $new_workload"

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

    systemd.tmpfiles.rules = [
      "d /run/gpu-profile-manager 0755 root root - -"
    ];
  };
}
