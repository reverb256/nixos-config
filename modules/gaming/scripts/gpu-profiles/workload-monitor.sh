#!/usr/bin/env bash
# Autonomous GPU Workload Monitor
# Detects workload type and adjusts GPU profiles automatically
# Manages mining pauses when AI/Gaming workloads detected

set -euo pipefail

LOG_FILE="/var/log/gpu-workload-monitor.log"
MINING_SERVICES=("lolminer-nvidia" "xmrig")
AI_PROCESSES=("lmstudio" "ollama" "python.*llm" "ai-inference-gateway")
GAMING_PROCESSES=("steam" "lutris" "heroic" "wine" "proton" "wine-preloader" "wine64" "wineserver")

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

check_process_running() {
    local process="$1"
    pgrep -f "$process" >/dev/null
}

check_gpu_utilization() {
    # Check if GPU utilization > 50% (active workload)
    local gpu_id="$1"
    local util=$(nvidia-smi -i "$gpu_id" --query-gpu=utilization.gpu --format=csv,noheader,nounits)
    [ "$util" -gt 50 ]
}

get_workload_type() {
    # Priority: Gaming > AI > Mining > Idle

    # Check for gaming
    for proc in "${GAMING_PROCESSES[@]}"; do
        if check_process_running "$proc"; then
            echo "gaming"
            return
        fi
    done

    # Check for AI workloads
    for proc in "${AI_PROCESSES[@]}"; do
        if check_process_running "$proc"; then
            echo "ai"
            return
        fi
    done

    # Check for active mining
    for service in "${MINING_SERVICES[@]}"; do
        if systemctl is-active --quiet "$service"; then
            # Mining is only active if no higher priority workload
            echo "mining"
            return
        fi
    done

    echo "idle"
}

apply_profile() {
    local profile="$1"
    log "Applying profile: $profile"

    case "$profile" in
        gaming)
            /etc/nixos/scripts/gpu-profiles/gaming.sh
            # Pause all mining if running
            for service in "${MINING_SERVICES[@]}"; do
                if systemctl is-active --quiet "$service"; then
                    log "Pausing $service for gaming"
                    systemctl stop "$service"
                fi
            done
            ;;
        ai)
            /etc/nixos/scripts/gpu-profiles/ai-inference.sh
            # Pause all mining if running
            for service in "${MINING_SERVICES[@]}"; do
                if systemctl is-active --quiet "$service"; then
                    log "Pausing $service for AI inference"
                    systemctl stop "$service"
                fi
            done
            ;;
        mining)
            /etc/nixos/scripts/gpu-profiles/mining.sh
            # Start mining services if not already running
            for service in "${MINING_SERVICES[@]}"; do
                if ! systemctl is-active --quiet "$service"; then
                    log "Starting $service (no other workloads detected)"
                    systemctl start "$service"
                fi
            done
            ;;
        idle)
            /etc/nixos/scripts/gpu-profiles/reset.sh
            # Don't auto-start mining, stay idle
            log "System idle, GPUs in adaptive mode"
            ;;
    esac
}

# State tracking
CURRENT_WORKLOAD="idle"
CHECK_INTERVAL=10  # Check every 10 seconds

log "Starting GPU workload monitor (check interval: ${CHECK_INTERVAL}s)"

while true; do
    new_workload=$(get_workload_type)

    if [ "$new_workload" != "$CURRENT_WORKLOAD" ]; then
        log "Workload changed: $CURRENT_WORKLOAD -> $new_workload"
        CURRENT_WORKLOAD="$new_workload"
        apply_profile "$new_workload"
    fi

    sleep "$CHECK_INTERVAL"
done
