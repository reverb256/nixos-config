# GPU Profiles Module (Pure Actuator)
# Reads gaming state + profile requests + AI signals
# Applies nvidia-smi GPU profiles via gw_apply_* functions
# Manages mining services (stop during gaming/AI, restart with VRAM check)
# Stores and restores original power limits
#
# Responsibilities:
#   - Read gaming state from gaming-detection
#   - Read profile requests from mining-coordinator
#   - Check AI signal file
#   - Check K8s GPU workloads
#   - Check VRAM pressure
#   - Apply appropriate GPU profile via gw_apply_* functions
#   - Manage lolminer mining service (pause/resume with VRAM check)
#   - Store and restore original power limits
#
# Does NOT:
#   - Detect gaming (gaming-detection.nix handles this)
#   - Detect builds via PSI (mining-coordinator.nix handles this)
#   - Write profile requests (mining-coordinator.nix handles this)
#
# Workload Priority (highest to lowest):
#   profile_request > AI > gaming > k8s-gpu > vram-pressure > mining > idle
{ config, lib, pkgs, ... }:

let
  cfg = config.services.gpu-workload.gpu-profiles;
in {
  options.services.gpu-workload.gpu-profiles = {
    enable = lib.mkEnableOption "GPU workload profile actuator (pure actuator)";

    checkInterval = lib.mkOption {
      type = lib.types.int;
      default = 10;
      description = "Workload detection and profile check interval in seconds";
    };

    logFile = lib.mkOption {
      type = lib.types.str;
      default = "/var/log/gpu-workload-gpu-profiles.log";
      description = "Path to the gpu-profiles log file";
    };

    gamingStateFile = lib.mkOption {
      type = lib.types.str;
      default = "/run/gpu-workload/gaming_state";
      description = "Path to gaming state file from gaming-detection service";
    };

    profileRequestFile = lib.mkOption {
      type = lib.types.str;
      default = "/run/gpu-workload/profile_request";
      description = "Path to profile request file from mining-coordinator service";
    };

    aiSignalFile = lib.mkOption {
      type = lib.types.str;
      default = "/run/gpu-workload/ai_active";
      description = "Path to AI signal file (presence indicates active AI workload)";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.gpu-workload-gpu-profiles = {
      description = "GPU Workload Profile Actuator (Pure Actuator)";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network.target"
        "gpu-workload-gaming-detection.service"
        "gpu-workload-mining-coordinator.service"
      ];

      path = with pkgs; [
        procps    # pgrep
        kubernetes # kubectl for K8s GPU workload detection
        gnugrep   # grep
        coreutils # echo, cat, mkdir, date, etc.
        systemd   # systemctl for mining service management
      ];

      serviceConfig = {
        Type = "simple";
        Environment = "PATH=${lib.makeBinPath (with pkgs; [ procps kubernetes gnugrep coreutils systemd ])}:/run/current-system/sw/bin";
        ExecStart = lib.getExe (pkgs.writeShellScriptBin "gpu-workload-gpu-profiles" ''
          # GPU Workload Profile Actuator (Pure Actuator)
          # Reads gaming state + profile requests + AI signals
          # Applies nvidia-smi GPU profiles via gw_apply_* functions
          # Manages mining services (stop during gaming/AI, restart with VRAM check)
          #
          # Workload Priority (highest to lowest):
          #   profile_request > AI > gaming > k8s-gpu > vram-pressure > mining > idle

          set -euo pipefail

          # Source shared library (provides gw_* functions)
          . "$(command -v gpu-workload-lib)"

          # Configuration from NixOS options
          STATE_DIR="/run/gpu-workload"
          GAMING_STATE_FILE="${cfg.gamingStateFile}"
          PROFILE_REQUEST_FILE="${cfg.profileRequestFile}"
          AI_SIGNAL_FILE="${cfg.aiSignalFile}"
          CHECK_INTERVAL="${toString cfg.checkInterval}"

          # Mining services to manage
          MINING_SERVICES=("lolminer-nvidia" "lolminer-amd")

          # ============================================================================
          # WORKLOAD DETECTION
          # ============================================================================

          # Detect current workload based on all signals
          # Priority: profile_request > AI > gaming > k8s-gpu > vram-pressure > mining > idle
          detect_workload() {
              # 1. Profile request (highest priority - set by mining-coordinator)
              if [[ -f "$PROFILE_REQUEST_FILE" ]]; then
                  local requested_profile
                  requested_profile=$(cat "$PROFILE_REQUEST_FILE" 2>/dev/null || echo "")
                  if [[ -n "$requested_profile" ]]; then
                      # Map profile_request values to workload types
                      case "$requested_profile" in
                          gaming|ai|builds|k8s-gpu|mining|idle)
                              gw_log "Using requested profile: $requested_profile"
                              echo "$requested_profile"
                              return
                              ;;
                          *)
                              gw_log "Unknown profile request: '$requested_profile' - ignoring"
                              ;;
                      esac
                  fi
              fi

              # 2. AI signal file (explicit AI workload notification)
              if [[ -f "$AI_SIGNAL_FILE" ]]; then
                  gw_log "AI signal file detected: $AI_SIGNAL_FILE"
                  echo "ai"
                  return
              fi

              # 3. Gaming state (from gaming-detection service)
              if [[ -f "$GAMING_STATE_FILE" ]]; then
                  source "$GAMING_STATE_FILE"
                  if [[ "$GAMING_ACTIVE" == "1" ]]; then
                      gw_log "Gaming active (method=$DETECTION_METHOD)"
                      echo "gaming"
                      return
                  fi
              fi

              # 4. Kubernetes GPU workloads
              if gw_check_kubernetes_gpu_workload; then
                  echo "kubernetes-gpu"
                  return
              fi

              # 5. VRAM pressure (>90% on any GPU)
              if gw_check_vram_pressure; then
                  echo "vram-pressure"
                  return
              fi

              # 6. Mining active
              for service in "''${MINING_SERVICES[@]}"; do
                  if systemctl is-active --quiet "$service" 2>/dev/null; then
                      echo "mining"
                      return
                  fi
              done

              # 7. Idle (lowest priority - fallback)
              echo "idle"
          }

          # ============================================================================
          # MINING SERVICE MANAGEMENT
          # ============================================================================

          # Stop all GPU mining services
          stop_mining() {
              local reason="$1"
              for service in "''${MINING_SERVICES[@]}"; do
                  if systemctl is-active --quiet "$service" 2>/dev/null; then
                      gw_log "Stopping $service ($reason)"
                      systemctl stop "$service"
                  fi
              done
          }

          # Start mining services (with VRAM pressure check)
          start_mining() {
              # Check VRAM pressure before starting any miner
              if gw_check_vram_pressure; then
                  gw_log "VRAM pressure detected (>90%) - blocking miner restart"
                  return 1
              fi

              for service in "''${MINING_SERVICES[@]}"; do
                  if ! systemctl is-active --quiet "$service" 2>/dev/null; then
                      gw_log "Starting $service (no VRAM pressure)"
                      systemctl start "$service"
                  fi
              done
              return 0
          }

          # ============================================================================
          # PROFILE APPLICATION
          # ============================================================================

          # Apply the appropriate GPU profile based on workload type
          apply_profile() {
              local workload="$1"
              gw_log "Applying profile for workload: $workload"

              case "$workload" in
                  gaming)
                      stop_mining "gaming detected"
                      gw_apply_gaming_profile
                      ;;
                  ai)
                      stop_mining "AI workload detected"
                      gw_apply_ai_profile
                      ;;
                  kubernetes-gpu)
                      stop_mining "K8s GPU workload detected"
                      gw_apply_kubernetes_gpu_profile
                      ;;
                  vram-pressure)
                      stop_mining "VRAM pressure"
                      gw_apply_vram_pressure_profile
                      ;;
                  builds)
                      gw_apply_builds_profile
                      ;;
                  mining)
                      gw_apply_mining_profile
                      start_mining
                      ;;
                  idle)
                      gw_apply_idle_profile
                      ;;
                  *)
                      gw_log "Unknown workload type: $workload"
                      ;;
              esac
          }

          # ============================================================================
          # POWER LIMIT MANAGEMENT
          # ============================================================================

          # Check if we need to restore power limits on workload transition
          # Restores when transitioning FROM a high-power profile TO mining/idle
          should_restore_power_limits() {
              local old_workload="$1"
              local new_workload="$2"

              case "$old_workload" in
                  gaming|ai|kubernetes-gpu|builds|vram-pressure)
                      case "$new_workload" in
                          mining|idle)
                              return 0  # Should restore
                              ;;
                      esac
                  ;;
              esac
              return 1  # Should not restore
          }

          # ============================================================================
          # MAIN LOOP
          # ============================================================================
          gw_log "Starting gpu-profiles actuator service"
          gw_log "  Check interval: $CHECK_INTERVAL"
          gw_log "  Gaming state file: $GAMING_STATE_FILE"
          gw_log "  Profile request file: $PROFILE_REQUEST_FILE"
          gw_log "  AI signal file: $AI_SIGNAL_FILE"

          # Ensure state directory exists
          mkdir -p "$STATE_DIR"

          # Store original power limits on startup (before any profile changes)
          gw_log "Storing original GPU power limits for restoration..."
          gw_store_original_power_limits "$STATE_DIR"

          # State tracking
          CURRENT_WORKLOAD="idle"

          while true; do
              # Detect current workload (priority: profile_request > AI > gaming > k8s-gpu > vram-pressure > mining > idle)
              new_workload=$(detect_workload)

              # Apply profile on workload transition
              if [[ "$new_workload" != "$CURRENT_WORKLOAD" ]]; then
                  gw_log "Workload transition: $CURRENT_WORKLOAD -> $new_workload"

                  # Restore original power limits when leaving high-power profiles
                  if should_restore_power_limits "$CURRENT_WORKLOAD" "$new_workload"; then
                      gw_log "Restoring original power limits after $CURRENT_WORKLOAD workload"
                      gw_restore_original_power_limits "$STATE_DIR"
                  fi

                  CURRENT_WORKLOAD="$new_workload"
                  apply_profile "$new_workload"
              fi

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
    ];
  };
}
