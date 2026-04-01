# GPU Workload Shared Library
# Provides the gpu-workload-lib shell script with all shared gw_* functions
# Used by: gaming-detection, gpu-profiles, mining-coordinator
#
# Usage in service scripts:
#   . "$(command -v gpu-workload-lib)"
#
# This sources all gw_* functions into the calling script's environment.
{ config, lib, pkgs, ... }:

let
  cfg = config.services.gpu-workload.shared;
in {
  options.services.gpu-workload.shared = {
    enable = lib.mkEnableOption "GPU workload shared library (gpu-workload-lib package)";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      (pkgs.writeShellScriptBin "gpu-workload-lib" ''
        # GPU Workload Shared Library
        # All shared shell functions for gpu-workload modules
        # Usage: . "$(command -v gpu-workload-lib)"
        set -euo pipefail

        # ============================================================================
        # LOGGING
        # ============================================================================
        gw_log() {
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >&2
        }

        # ============================================================================
        # HOSTNAME HELPER
        # ============================================================================
        gw_get_hostname() {
            hostname
        }

        # ============================================================================
        # GAMING DETECTION
        # ============================================================================

        # Detect gaming using GameMode daemon (primary detection method)
        # Returns: 1 if gaming active, 0 if not, 2 if unavailable (use GPU fallback)
        gw_detect_gaming_gamemode() {
            # Check if gamemoded is available
            if ! command -v gamemoded &>/dev/null; then
                gw_log "GameMode not installed - will use GPU fallback"
                return 2  # Special code for "not available"
            fi

            # Query GameMode state as the user (GameMode runs in user session)
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
                gw_log "GameMode: Gaming detected"
                return 1  # Gaming active
            elif [[ "$gaming_output" == *"inactive"* ]]; then
                gw_log "GameMode: No gaming detected"
                return 0  # No gaming
            else
                gw_log "GameMode: Daemon not responding (output: '$gaming_output') - will use GPU fallback"
                return 2  # Unavailable
            fi
        }

        # Detect gaming by analyzing GPU utilization patterns (fallback)
        # Returns: 1 if gaming pattern detected, 0 if mining/other pattern
        gw_detect_gpu_pattern() {
            # Need NVIDIA GPU
            if ! command -v nvidia-smi &>/dev/null; then
                gw_log "No NVIDIA GPU available - assume no gaming"
                return 0
            fi

            # Get current GPU utilization (check ALL GPUs, use MAX for gaming detection)
            local current_util
            current_util=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null | awk '{print $1}' | sort -rn | head -1)

            if [[ -z "$current_util" ]]; then
                gw_log "Failed to query GPU utilization - assume no gaming"
                return 0
            fi

            # Read previous utilization from state file (if exists)
            local prev_util=""
            local util_history_file="/run/gpu-workload/gpu-util-history"
            if [[ -f "$util_history_file" ]]; then
                source "$util_history_file"
                prev_util="$LAST_GPU_UTIL"
            fi

            # Save current utilization
            echo "LAST_GPU_UTIL=$current_util" > "$util_history_file"

            # If we don't have history, can't detect pattern yet
            if [[ -z "$prev_util" ]]; then
                gw_log "No GPU utilization history - assume no gaming"
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
                gw_log "GPU pattern: Gaming detected (util=$current_util%, variance=$util_diff%)"
                return 1
            else
                gw_log "GPU pattern: No gaming (util=$current_util%, variance=$util_diff%)"
                return 0
            fi
        }

        # Unified gaming detection (GameMode primary, GPU fallback)
        # Returns: exit code 1 if gaming detected, 0 if not
        #          echoes detection method to stdout ("gamemode", "gpu_fallback", "none")
        gw_detect_gaming() {
            # Try GameMode first (authoritative)
            gw_detect_gaming_gamemode
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
                    gw_log "GameMode unavailable, using GPU pattern detection"
                    gw_detect_gpu_pattern
                    local gpu_result=$?
                    if [[ "$gpu_result" == "1" ]]; then
                        echo "gpu_fallback"
                    else
                        echo "none"
                    fi
                    return $gpu_result
                    ;;
                *)
                    gw_log "Unexpected GameMode result: $gamemode_result"
                    echo "none"
                    return 0
                    ;;
            esac
        }

        # ============================================================================
        # GPU HELPERS
        # ============================================================================

        # Get list of NVIDIA GPU indices
        gw_get_gpu_list() {
            nvidia-smi --query-gpu=index --format=csv,noheader,nounits 2>/dev/null || echo ""
        }

        # Get GPU name by index
        gw_get_gpu_name() {
            local gpu_id="$1"
            nvidia-smi -i "$gpu_id" --query-gpu=name --format=csv,noheader 2>/dev/null || echo "Unknown"
        }

        # Safely execute nvidia-smi command (suppress errors)
        gw_nvidia_safe() {
            "$@" 2>/dev/null || true
        }

        # Get VRAM usage percentage for a specific GPU
        # Arguments: $1 = gpu_id
        # Outputs: percentage (integer)
        gw_get_vram_usage_percent() {
            local gpu_id="$1"
            local vram_info
            vram_info=$(nvidia-smi -i "$gpu_id" --query-gpu=memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null)

            if [[ -z "$vram_info" ]]; then
                echo "0"
                return
            fi

            local used
            used=$(echo "$vram_info" | cut -d',' -f1 | tr -d '[:space:]')
            local total
            total=$(echo "$vram_info" | cut -d',' -f2 | tr -d '[:space:]')

            if [[ -z "$used" ]] || [[ -z "$total" ]] || [[ "$total" -eq 0 ]]; then
                echo "0"
                return
            fi

            local percent=$(( (used * 100) / total ))
            echo "$percent"
        }

        # Check if any GPU has VRAM pressure (>90% usage)
        # Returns: 0 if pressure detected, 1 if OK
        gw_check_vram_pressure() {
            local gpus
            gpus=$(gw_get_gpu_list)

            if [[ -z "$gpus" ]]; then
                return 1
            fi

            for gpu_id in $gpus; do
                local usage
                usage=$(gw_get_vram_usage_percent "$gpu_id")
                if [[ "$usage" -gt 90 ]]; then
                    gw_log "VRAM pressure on GPU $gpu_id: ''${usage}%"
                    return 0
                fi
            done

            return 1
        }

        # ============================================================================
        # STATE MANAGEMENT
        # ============================================================================

        # Read gaming state from file
        # Sets: GAMING_ACTIVE, DETECTION_METHOD, HYSTERESIS_COUNT, PAUSE_COUNT, LAST_UPDATE
        gw_read_gaming_state() {
            local state_file="''${1:-/run/gpu-workload/gaming_state}"

            if [[ -f "$state_file" ]]; then
                source "$state_file"
            else
                # Default state
                GAMING_ACTIVE=0
                DETECTION_METHOD="none"
                HYSTERESIS_COUNT=0
                PAUSE_COUNT=0
                LAST_UPDATE=""
            fi
        }

        # Write gaming state to file
        gw_write_gaming_state() {
            local gaming_active="$1"    # 0 or 1
            local detection_method="$2" # "gamemode" or "gpu_fallback" or "none"
            local hysteresis_count="$3" # countdown before resume (0-N)
            local pause_count="$4"      # total number of pauses

            local state_dir="/run/gpu-workload"
            local state_file="$state_dir/gaming_state"

            mkdir -p "$state_dir"
            {
                echo "GAMING_ACTIVE=$gaming_active"
                echo "DETECTION_METHOD=$detection_method"
                echo "HYSTERESIS_COUNT=$hysteresis_count"
                echo "PAUSE_COUNT=$pause_count"
                echo "LAST_UPDATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
            } > "$state_file"
        }

        # Export gaming state to Prometheus via node_exporter textfile collector
        gw_export_gaming_metric() {
            local gaming_active="$1"    # 0 or 1
            local detection_method="$2" # "gamemode" or "gpu_fallback" or "none"

            local hostname
            hostname=$(gw_get_hostname)

            local metric_dir="/var/lib/node_exporter/textfile_collector"
            local metric_file="$metric_dir/gaming.prom"

            # Ensure directory exists
            if [[ ! -d "$metric_dir" ]]; then
                mkdir -p "$metric_dir" || {
                    gw_log "Failed to create node_exporter directory: $metric_dir"
                    return 1
                }
            fi

            # Write metric (with help and type for Prometheus)
            {
                echo "# HELP gpu_workload_gaming_active Whether a game is currently running (1=yes, 0=no)"
                echo "# TYPE gpu_workload_gaming_active gauge"
                echo "gpu_workload_gaming_active{host=\"$hostname\",detection_method=\"$detection_method\"} $gaming_active"
            } > "$metric_file"

            gw_log "Exported gaming metric: gaming_active=$gaming_active (method=$detection_method)"
        }

        # ============================================================================
        # GPU PROFILES
        # ============================================================================

        # Apply gaming GPU profile (maximum performance)
        gw_apply_gaming_profile() {
            gw_log "=== Applying GPU GAMING profile ==="

            local gpus
            gpus=$(gw_get_gpu_list)
            local gpu_count
            gpu_count=$(echo "$gpus" | wc -l)

            if [[ "$gpu_count" -eq 0 ]]; then
                gw_log "WARNING: No NVIDIA GPUs detected"
                return 0
            fi

            gw_log "Detected $gpu_count GPU(s) for gaming profile"

            for gpu_id in $gpus; do
                local gpu_name
                gpu_name=$(gw_get_gpu_name "$gpu_id")
                gw_log "Configuring GPU $gpu_id ($gpu_name)..."

                case "$gpu_name" in
                    *"3060"*)
                        # 3060 Ti: Skip power limit changes (tight power budget, not primary gaming GPU)
                        # Keep clock locks for stability but don't touch power limit
                        gw_nvidia_safe nvidia-smi -i "$gpu_id" -lgc 1800
                        gw_nvidia_safe nvidia-smi -i "$gpu_id" -lmc 6000
                        gw_log "  3060 Ti: Clock locks only (1800/6000 MHz), power limit unchanged"
                        ;;
                    *"3090"*)
                        # 3090: Primary gaming GPU - max performance (liquid cooled)
                        gw_nvidia_safe nvidia-smi -i "$gpu_id" -pl 350
                        gw_nvidia_safe nvidia-smi -i "$gpu_id" -lgc 2050
                        gw_nvidia_safe nvidia-smi -i "$gpu_id" -lmc 7500
                        gw_log "  3090: 2050 MHz GPU (liquid-cooled), 7500 MHz mem, 350W limit (PRIMARY GAMING GPU)"
                        ;;
                    *)
                        # Default: Max performance
                        gw_nvidia_safe nvidia-smi -i "$gpu_id" -pl 250
                        gw_nvidia_safe nvidia-smi -i "$gpu_id" -rgc
                        gw_nvidia_safe nvidia-smi -i "$gpu_id" -rmc
                        gw_log "  $gpu_name: Default max performance profile"
                        ;;
                esac
            done

            gw_log "GAMING profile applied: Mode: Maximum performance"
        }

        # Apply mining GPU profile (efficiency-optimized)
        gw_apply_mining_profile() {
            gw_log "=== Applying GPU MINING profile ==="

            local gpus
            gpus=$(gw_get_gpu_list)
            local gpu_count
            gpu_count=$(echo "$gpus" | wc -l)

            if [[ "$gpu_count" -eq 0 ]]; then
                gw_log "WARNING: No NVIDIA GPUs detected"
                return 0
            fi

            gw_log "Detected $gpu_count GPU(s) for mining profile"

            for gpu_id in $gpus; do
                local gpu_name
                gpu_name=$(gw_get_gpu_name "$gpu_id")
                gw_log "Configuring GPU $gpu_id ($gpu_name)..."

                case "$gpu_name" in
                    *"3060"*)
                        # 3060 Ti: Reset to mining power limits
                        gw_nvidia_safe nvidia-smi -i "$gpu_id" -pl 130
                        gw_nvidia_safe nvidia-smi -i "$gpu_id" -lgc 1700
                        gw_nvidia_safe nvidia-smi -i "$gpu_id" -lmc 5200
                        gw_log "  3060 Ti: 1700 MHz GPU, 5200 MHz mem (130W limit mining-optimized)"
                        ;;
                    *"3090"*)
                        # 3090: Reset to mining power limits
                        gw_nvidia_safe nvidia-smi -i "$gpu_id" -pl 250
                        gw_nvidia_safe nvidia-smi -i "$gpu_id" -lgc 1750
                        gw_nvidia_safe nvidia-smi -i "$gpu_id" -lmc 6500
                        gw_log "  3090: 1750 MHz GPU (liquid-cooled), 6500 MHz mem (250W limit mining-optimized)"
                        ;;
                    *)
                        # Default: Don't override power limits, let mining module manage
                        gw_nvidia_safe nvidia-smi -i "$gpu_id" -rgc
                        gw_nvidia_safe nvidia-smi -i "$gpu_id" -rmc
                        gw_log "  $gpu_name: Default efficiency profile (power limit from mining module)"
                        ;;
                esac
            done

            gw_log "MINING profile applied: Mode: Efficiency-optimized"
        }

        # Apply AI inference GPU profile (balanced performance with thermal safety)
        gw_apply_ai_profile() {
            gw_log "=== Applying GPU AI INFERENCE profile ==="

            local gpus
            gpus=$(gw_get_gpu_list)
            local gpu_count
            gpu_count=$(echo "$gpus" | wc -l)

            if [[ "$gpu_count" -eq 0 ]]; then
                gw_log "WARNING: No NVIDIA GPUs detected"
                return 0
            fi

            gw_log "Detected $gpu_count GPU(s) for AI inference profile"

            for gpu_id in $gpus; do
                local gpu_name
                gpu_name=$(gw_get_gpu_name "$gpu_id")
                gw_log "Configuring GPU $gpu_id ($gpu_name)..."

                case "$gpu_name" in
                    *"3060"*)
                        # 3060 Ti: Balanced
                        gw_nvidia_safe nvidia-smi -i "$gpu_id" -pl 110
                        gw_nvidia_safe nvidia-smi -i "$gpu_id" -lgc 1950
                        gw_nvidia_safe nvidia-smi -i "$gpu_id" -lmc 6200
                        gw_log "  3060 Ti: 1950 MHz GPU, 6200 MHz mem, 110W limit"
                        ;;
                    *"3090"*)
                        # 3090: Liquid cooled, can push harder
                        gw_nvidia_safe nvidia-smi -i "$gpu_id" -pl 300
                        gw_nvidia_safe nvidia-smi -i "$gpu_id" -lgc 1900
                        gw_nvidia_safe nvidia-smi -i "$gpu_id" -lmc 7000
                        gw_log "  3090: 1900 MHz GPU (liquid-cooled), 7000 MHz mem, 300W limit"
                        ;;
                    *)
                        # Default: Balanced
                        gw_nvidia_safe nvidia-smi -i "$gpu_id" -pl 200
                        gw_nvidia_safe nvidia-smi -i "$gpu_id" -rgc
                        gw_nvidia_safe nvidia-smi -i "$gpu_id" -rmc
                        gw_log "  $gpu_name: Default balanced profile"
                        ;;
                esac
            done

            gw_log "AI INFERENCE profile applied: Mode: Balanced performance with thermal safety"
        }

        # Apply Kubernetes GPU workload profile (balanced for containerized workloads)
        gw_apply_kubernetes_gpu_profile() {
            gw_log "=== Applying GPU KUBERNETES GPU WORKLOAD profile ==="

            local gpus
            gpus=$(gw_get_gpu_list)
            local gpu_count
            gpu_count=$(echo "$gpus" | wc -l)

            if [[ "$gpu_count" -eq 0 ]]; then
                gw_log "WARNING: No NVIDIA GPUs detected"
                return 0
            fi

            gw_log "Detected $gpu_count GPU(s) for Kubernetes GPU workload profile"

            # Set GPUs to balanced mode for K8s workloads
            for gpu_id in $gpus; do
                local gpu_name
                gpu_name=$(gw_get_gpu_name "$gpu_id")
                gw_log "Configuring GPU $gpu_id ($gpu_name)..."

                case "$gpu_name" in
                    *"3060"*)
                        # 3060 Ti: Balanced for K8s
                        gw_nvidia_safe nvidia-smi -i "$gpu_id" -pl 150
                        gw_nvidia_safe nvidia-smi -i "$gpu_id" -lgc 1800
                        gw_nvidia_safe nvidia-smi -i "$gpu_id" -lmc 6000
                        gw_log "  3060 Ti: 1800 MHz GPU, 6000 MHz mem, 150W limit"
                        ;;
                    *"3090"*)
                        # 3090: Balanced for K8s (liquid cooled)
                        gw_nvidia_safe nvidia-smi -i "$gpu_id" -pl 280
                        gw_nvidia_safe nvidia-smi -i "$gpu_id" -lgc 1800
                        gw_nvidia_safe nvidia-smi -i "$gpu_id" -lmc 6800
                        gw_log "  3090: 1800 MHz GPU (liquid-cooled), 6800 MHz mem, 280W limit"
                        ;;
                    *)
                        # Default: Balanced
                        gw_nvidia_safe nvidia-smi -i "$gpu_id" -pl 200
                        gw_nvidia_safe nvidia-smi -i "$gpu_id" -rgc
                        gw_nvidia_safe nvidia-smi -i "$gpu_id" -rmc
                        gw_log "  $gpu_name: Default balanced profile"
                        ;;
                esac
            done

            gw_log "KUBERNETES GPU profile applied: Mode: Balanced for containerized workloads"
        }

        # Apply builds GPU profile (reduce mining for build workloads)
        gw_apply_builds_profile() {
            gw_log "=== Applying GPU/CPU BUILDS profile ==="

            local gpus
            gpus=$(gw_get_gpu_list)
            local gpu_count
            gpu_count=$(echo "$gpus" | wc -l)

            if [[ "$gpu_count" -eq 0 ]]; then
                gw_log "WARNING: No NVIDIA GPUs detected"
            else
                gw_log "Detected $gpu_count GPU(s) for builds profile"
            fi

            # Reduce GPU mining on nexus due to heat issues
            local host
            host=$(gw_get_hostname)
            if [[ "$host" == "nexus" ]]; then
                if systemctl is-active --quiet lolminer-nvidia 2>/dev/null; then
                    gw_log "Limiting lolminer-nvidia to 10% CPU for builds (nexus heat management)"
                    systemctl set-property lolminer-nvidia.service CPUQuota="10%" --runtime 2>/dev/null || true
                fi
                if systemctl is-active --quiet lolminer-amd 2>/dev/null; then
                    gw_log "Limiting lolminer-amd to 10% CPU for builds (nexus heat management)"
                    systemctl set-property lolminer-amd.service CPUQuota="10%" --runtime 2>/dev/null || true
                fi
            else
                gw_log "Build detected on $host - allowing GPU mining to continue (no heat issues)"
            fi

            # Ensure nix-daemon gets high priority for builds
            if systemctl is-active --quiet nix-daemon 2>/dev/null; then
                gw_log "Setting nix-daemon to high CPU weight for builds"
                systemctl set-property nix-daemon.service CPUWeight=2048 --runtime 2>/dev/null || true
            fi

            gw_log "BUILDS profile applied: builds get priority"
        }

        # Apply idle/default GPU profile (reset to adaptive mode)
        gw_apply_idle_profile() {
            gw_log "=== Resetting GPUs to DEFAULT/AUTO profile ==="

            local gpus
            gpus=$(gw_get_gpu_list)
            local gpu_count
            gpu_count=$(echo "$gpus" | wc -l)

            if [[ "$gpu_count" -eq 0 ]]; then
                gw_log "WARNING: No NVIDIA GPUs detected"
                return 0
            fi

            gw_log "Detected $gpu_count GPU(s), resetting to defaults"

            for gpu_id in $gpus; do
                local gpu_name
                gpu_name=$(gw_get_gpu_name "$gpu_id")
                gw_log "Resetting GPU $gpu_id ($gpu_name)..."

                # Reset power limits based on GPU model
                case "$gpu_name" in
                    *"3060"*)
                        gw_nvidia_safe nvidia-smi -i "$gpu_id" -pl 200
                        ;;
                    *"3090"*)
                        gw_nvidia_safe nvidia-smi -i "$gpu_id" -pl 350
                        ;;
                    *)
                        # Try to get max power limit
                        local max_power
                        max_power=$(nvidia-smi -i "$gpu_id" --query-gpu=power.max_limit --format=csv,noheader,nounits 2>/dev/null | tr -d '.' || echo "300")
                        gw_nvidia_safe nvidia-smi -i "$gpu_id" -pl "''${max_power%.*}"
                        ;;
                esac

                # Reset locked clocks
                gw_nvidia_safe nvidia-smi -i "$gpu_id" -rgc
                gw_nvidia_safe nvidia-smi -i "$gpu_id" -rmc

                gw_log "  GPU $gpu_id: Reset to defaults (adaptive mode)"
            done

            gw_log "RESET to defaults applied: Mode: Adaptive (auto)"
        }

        # Apply VRAM pressure profile (stop miners, wait for VRAM to free)
        gw_apply_vram_pressure_profile() {
            gw_log "=== Applying GPU VRAM PRESSURE profile ==="

            local gpus
            gpus=$(gw_get_gpu_list)
            local gpu_count
            gpu_count=$(echo "$gpus" | wc -l)

            if [[ "$gpu_count" -eq 0 ]]; then
                gw_log "WARNING: No NVIDIA GPUs detected"
                return 0
            fi

            gw_log "Detected VRAM pressure - preventing miner start to avoid freeze"

            # Get detailed VRAM info
            for gpu_id in $gpus; do
                local gpu_name
                gpu_name=$(gw_get_gpu_name "$gpu_id")
                local usage
                usage=$(gw_get_vram_usage_percent "$gpu_id")
                local vram_info
                vram_info=$(nvidia-smi -i "$gpu_id" --query-gpu=memory.used,memory.total --format=csv,noheader,nounits)

                local used
                used=$(echo "$vram_info" | cut -d',' -f1)
                local total
                total=$(echo "$vram_info" | cut -d',' -f2)

                gw_log "GPU $gpu_id ($gpu_name): ''${used}MB / ''${total}MB (''${usage}%)"
            done

            # Ensure GPU miners are completely stopped
            if systemctl is-active --quiet lolminer-nvidia 2>/dev/null; then
                gw_log "Stopping lolminer-nvidia due to VRAM pressure"
                systemctl stop lolminer-nvidia
            fi

            if systemctl is-active --quiet lolminer-amd 2>/dev/null; then
                gw_log "Stopping lolminer-amd due to VRAM pressure"
                systemctl stop lolminer-amd
            fi

            # Set GPUs to balanced mode (not max, not idle)
            for gpu_id in $gpus; do
                local gpu_name
                gpu_name=$(gw_get_gpu_name "$gpu_id")

                case "$gpu_name" in
                    *"3060"*)
                        gw_nvidia_safe nvidia-smi -i "$gpu_id" -pl 150
                        ;;
                    *"3090"*)
                        gw_nvidia_safe nvidia-smi -i "$gpu_id" -pl 250
                        ;;
                    *)
                        gw_nvidia_safe nvidia-smi -i "$gpu_id" -pl 200
                        ;;
                esac
            done

            gw_log "VRAM PRESSURE profile applied: Miners stopped, waiting for VRAM to free"
        }

        # ============================================================================
        # POWER LIMIT BACKUP
        # ============================================================================

        # Store original power limits for all GPUs (for later restoration)
        gw_store_original_power_limits() {
            local state_dir="''${1:-/run/gpu-workload}"
            local gpus
            gpus=$(gw_get_gpu_list)

            mkdir -p "$state_dir"

            for gpu_id in $gpus; do
                local current_limit
                current_limit=$(nvidia-smi -i "$gpu_id" --query-gpu=power.limit --format=csv,noheader,nounits 2>/dev/null | tr -d '[:space:]')
                echo "$current_limit" > "$state_dir/gpu''${gpu_id}_original_power"
                gw_log "Stored original power limit for GPU $gpu_id: $current_limit W"
            done
        }

        # Restore original power limits from saved state
        gw_restore_original_power_limits() {
            local state_dir="''${1:-/run/gpu-workload}"
            local gpus
            gpus=$(gw_get_gpu_list)

            for gpu_id in $gpus; do
                local stored_file="$state_dir/gpu''${gpu_id}_original_power"
                if [[ -f "$stored_file" ]]; then
                    local original_limit
                    original_limit=$(cat "$stored_file")
                    gw_log "Restoring GPU $gpu_id power limit to $original_limit W"
                    gw_nvidia_safe nvidia-smi -i "$gpu_id" -pl "$original_limit"
                fi
            done
        }

        # ============================================================================
        # PSI HELPERS
        # ============================================================================

        # Load PSI threshold with fallback chain:
        # 1. Environment variables (set by systemd from NixOS config)
        # 2. Runtime config file: /run/gpu-workload/thresholds.conf
        # 3. Declarative config: /etc/gpu-workload/thresholds.conf
        # 4. Built-in defaults (fallback)
        gw_load_psi_threshold() {
            local var_name="$1"
            local default_value="$2"
            local value=""

            # Check environment first (set by systemd from NixOS config)
            if [[ -n "''${!var_name+x}" ]]; then
                value="''${!var_name}"
            fi

            # Check runtime override file (imperative changes)
            if [[ -z "$value" ]] && [[ -f /run/gpu-workload/thresholds.conf ]]; then
                value=$(grep "^''${var_name}=" /run/gpu-workload/thresholds.conf 2>/dev/null | cut -d'=' -f2)
            fi

            # Check declarative config file (NixOS generated)
            if [[ -z "$value" ]] && [[ -f /etc/gpu-workload/thresholds.conf ]]; then
                value=$(grep "^''${var_name}=" /etc/gpu-workload/thresholds.conf 2>/dev/null | cut -d'=' -f2)
            fi

            # Use default if not found
            if [[ -z "$value" ]]; then
                value="$default_value"
            fi

            echo "$value"
        }

        # Parse PSI "some avg10" value from a /proc/pressure/* line
        # Arguments: $1 = psi_line (e.g., "some avg10=1.19 avg60=1.15 avg300=0.95 total=16120473")
        # Outputs: the avg10 float value, or empty string on failure
        gw_parse_psi_avg10() {
            local psi_line="$1"
            echo "$psi_line" | awk '{
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
            }'
        }

        # Parse PSI "full avg10" value from a /proc/pressure/* line
        # Arguments: $1 = psi_line (e.g., "some avg10=... full avg10=0.50 avg60=...")
        # Outputs: the full avg10 float value, or empty string on failure
        gw_parse_psi_full_avg10() {
            local psi_line="$1"
            echo "$psi_line" | awk '{
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
            }'
        }

        # ============================================================================
        # KUBERNETES GPU DETECTION
        # ============================================================================

        # Check for running Kubernetes GPU workloads across all namespaces
        # Returns: 0 if GPU pods found and running, 1 if no GPU workloads
        gw_check_kubernetes_gpu_workload() {
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
            local gpu_pods
            gpu_pods=$(kubectl get pods --all-namespaces \
                -o jsonpath='{range .items[?(@.spec.containers[*].resources.limits.nvidia\.com/gpu)]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}' \
                2>/dev/null || echo "")

            if [[ -n "$gpu_pods" ]]; then
                # Filter out non-running pods
                local running_gpu_pods
                running_gpu_pods=$(echo "$gpu_pods" | while read -r pod; do
                    [[ -z "$pod" ]] && continue
                    local namespace
                    namespace=$(echo "$pod" | cut -d'/' -f1)
                    local name
                    name=$(echo "$pod" | cut -d'/' -f2)

                    if kubectl get pod "$name" -n "$namespace" -o jsonpath='{.status.phase}' 2>/dev/null | grep -q "Running"; then
                        echo "$pod"
                    fi
                done)

                if [[ -n "$running_gpu_pods" ]]; then
                    gw_log "Kubernetes GPU workload detected: $running_gpu_pods"
                    return 0
                fi
            fi

            return 1
        }
      '')
    ];
  };
}
