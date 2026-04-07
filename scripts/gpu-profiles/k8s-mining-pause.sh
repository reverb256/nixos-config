#!/usr/bin/env bash
# Kubernetes Mining Pause for GameMode
# Pauses mining pods when GameMode activates (gaming starts)
# Resumes mining pods when GameMode deactivates (gaming ends)

set -uo pipefail

MINING_DEPLOYMENT="gpu-miner-zephyr"
MINING_NAMESPACE="mining"
MINING_SERVICES=("lolminer-nvidia" "xmrig" "xmrig-flexible" "xmrig-proxy")
LOG_FILE="/var/log/gamemode-mining.log"

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE" 2>/dev/null
}

pause_mining() {
    log "GameMode START: Pausing all mining workloads"

    # Stop host-based mining services
    for svc in "${MINING_SERVICES[@]}"; do
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            log "Stopping host service: $svc"
            systemctl stop "$svc" 2>/dev/null && log "✓ Stopped $svc" || log "✗ Failed to stop $svc"
        else
            log "  $svc: not running (skipping)"
        fi
    done

    # Scale K8s deployment to 0 (skip if kubectl unavailable)
    if ! command -v kubectl &>/dev/null; then
        log "kubectl not available, skipping K8s scale down"
        return 0
    fi

    if kubectl scale deployment "$MINING_DEPLOYMENT" -n "$MINING_NAMESPACE" --replicas=0 >/dev/null 2>&1; then
        log "✓ Scaled $MINING_DEPLOYMENT to 0 replicas"
    else
        log "K8s scale down failed (cluster may be unavailable, this is OK on zephyr)"
    fi
    return 0
}

resume_mining() {
    log "GameMode END: Resuming all mining workloads"

    # Scale K8s deployment back to 1 (skip if kubectl unavailable)
    if ! command -v kubectl &>/dev/null; then
        log "kubectl not available, skipping K8s scale up"
    elif kubectl scale deployment "$MINING_DEPLOYMENT" -n "$MINING_NAMESPACE" --replicas=1 >/dev/null 2>&1; then
        log "✓ Scaled $MINING_DEPLOYMENT to 1 replica"
    else
        log "K8s scale up failed (cluster may be unavailable, this is OK on zephyr)"
    fi

    # Start host-based mining services
    for svc in "${MINING_SERVICES[@]}"; do
        if systemctl is-enabled --quiet "$svc" 2>/dev/null; then
            log "Starting host service: $svc"
            systemctl start "$svc" 2>/dev/null && log "✓ Started $svc" || log "✗ Failed to start $svc"
        fi
    done
    return 0
}

ACTION="${1:-}"
case "$ACTION" in
    start) pause_mining ;;
    end) resume_mining ;;
    *) echo "Usage: $0 {start|end}"; exit 1 ;;
esac
