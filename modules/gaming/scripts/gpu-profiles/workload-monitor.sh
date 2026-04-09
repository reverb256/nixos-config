#!/usr/bin/env bash
# Autonomous GPU/CPU Workload Monitor
# Detects workload type and adjusts resource allocation automatically
# Manages mining via systemd CPUQuota for fine-grained control

set -euo pipefail

LOG_FILE="/var/log/gpu-workload-monitor.log"
MINING_SERVICES=("lolminer-nvidia" "lolminer-amd" "xmrig")
AI_PROCESSES=("lmstudio" "ollama" "python.*llm" "ai-inference-gateway")
GAMING_PROCESSES=("steam" "lutris" "heroic" "wine" "proton" "wine-preloader" "wine64" "wineserver")
BUILD_PROCESSES=("nixos-rebuild" "colmena" "nix-build" "gcc" "clang" "cargo build" "make" "cmake" "ninja")

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

check_process_running() {
    local process="$1"
    pgrep -f "$process" >/dev/null
}

get_hostname() {
    hostname
}

check_incoming_build_job() {
    # Detect distributed build jobs from coordinators via SSH
    # This catches when nix-daemon on worker receives build job from coordinator
    local coordinators=("zephyr" "nexus" "forge")
    local hostname=$(get_hostname)

    # Skip if we are the coordinator (we already detect nix-build directly)
    for coord in "${coordinators[@]}"; do
        if [ "$hostname" = "$coord" ]; then
            continue
        fi

        # Check for SSH connections from known coordinators
        if command -v ss >/dev/null 2>&1; then
            if ss -tnp 2>/dev/null | grep -q "ESTAB .*${coord}.*ssh"; then
                # Check if nix-daemon is using significant CPU (>30%)
                local nix_pid=$(pgrep -o nix-daemon | head -1)
                if [ -n "$nix_pid" ]; then
                    local nix_cpu=$(ps -p "$nix_pid" -o %cpu 2>/dev/null | tail -1)
                    if [ -n "$nix_cpu" ] && [ "$nix_cpu" != "%CPU" ]; then
                        # Remove decimal point for comparison (e.g., "45.2" -> "45")
                        local nix_cpu_int=${nix_cpu%.*}
                        if [ "$nix_cpu_int" -gt 30 ] 2>/dev/null; then
                            log "Detected incoming build from $coord (nix-daemon CPU: ${nix_cpu}%)"
                            return 0
                        fi
                    fi
                fi
            fi
        fi
    done

    return 1
}

get_workload_type() {
    # Priority: Gaming > AI > Builds > Mining > Idle

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

    # Check for build processes
    for proc in "${BUILD_PROCESSES[@]}"; do
        if check_process_running "$proc"; then
            echo "builds"
            return
        fi
    done

    # Check for incoming distributed build jobs (worker detection)
    if check_incoming_build_job; then
        echo "builds"
        return
    fi

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
            # Pause GPU mining, reduce CPU mining via CPUQuota
            for service in "${MINING_SERVICES[@]}"; do
                if systemctl is-active --quiet "$service"; then
                    if [[ "$service" == *"lolminer"* ]]; then
                        log "Limiting $service to 0% CPU for gaming"
                        systemctl set-property ${service}.service CPUQuota="0%" --runtime
                    else
                        # xmrig: 25% CPU for gaming
                        log "Limiting $service to 25% CPU for gaming"
                        systemctl set-property ${service}.service CPUQuota="25%" --runtime
                    fi
                fi
            done
            ;;
        ai)
            /etc/nixos/scripts/gpu-profiles/ai-inference.sh
            # Pause GPU mining, keep CPU mining at 100%
            for service in "${MINING_SERVICES[@]}"; do
                if systemctl is-active --quiet "$service"; then
                    if [[ "$service" == *"lolminer"* ]]; then
                        log "Limiting $service to 0% CPU for AI"
                        systemctl set-property ${service}.service CPUQuota="0%" --runtime
                    else
                        # xmrig: 100% CPU (GPU is bottleneck)
                        log "Keeping $service at 100% CPU for AI (GPU is bottleneck)"
                        systemctl set-property ${service}.service CPUQuota="100%" --runtime
                    fi
                fi
            done
            ;;
        builds)
            # Reduce all mining to 10%, give builds priority
            for service in "${MINING_SERVICES[@]}"; do
                if systemctl is-active --quiet "$service"; then
                    log "Limiting $service to 10% CPU for builds"
                    systemctl set-property ${service}.service CPUQuota="10%" --runtime
                fi
            done

            # Give nix-daemon high priority
            if systemctl is-active --quiet nix-daemon; then
                log "Setting nix-daemon to high CPU weight for builds"
                systemctl set-property nix-daemon.service CPUWeight=2048 --runtime
            fi
            ;;
        mining)
            /etc/nixos/scripts/gpu-profiles/mining.sh
            # Reset all mining to 100% CPU
            for service in "${MINING_SERVICES[@]}"; do
                if systemctl is-active --quiet "$service"; then
                    log "Resetting $service to 100% CPU for mining"
                    systemctl set-property ${service}.service CPUQuota="100%" --runtime
                fi
            done

            # Start mining services if not running
            for service in lolminer-nvidia lolminer-amd; do
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

log "Starting GPU/CPU workload monitor (check interval: ${CHECK_INTERVAL}s)"

while true; do
    new_workload=$(get_workload_type)

    if [ "$new_workload" != "$CURRENT_WORKLOAD" ]; then
        log "Workload changed: $CURRENT_WORKLOAD -> $new_workload"
        CURRENT_WORKLOAD="$new_workload"
        apply_profile "$new_workload"
    fi

    sleep "$CHECK_INTERVAL"
done

