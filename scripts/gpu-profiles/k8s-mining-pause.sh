#!/usr/bin/env bash
# Kubernetes Mining Pause for GameMode
# Pauses mining pods when GameMode activates (gaming starts)
# Resumes mining pods when GameMode deactivates (gaming ends)

set -euo pipefail

MINING_DEPLOYMENT="gpu-miner-zephyr"
MINING_NAMESPACE="mining"
MINING_SERVICES=("lolminer-nvidia" "xmrig" "xmrig-flexible" "xmrig-proxy")
LOG_FILE="$HOME/.local/log/k8s-mining-pause.log"

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

pause_mining() {
    log "GameMode START: Pausing all mining workloads"

    # Stop host-based mining services
    for svc in "${MINING_SERVICES[@]}"; do
        if systemctl is-active --quiet "$svc"; then
            log "Stopping host service: $svc"
            if systemctl stop "$svc" >/dev/null 2>&1; then
                log "✓ Stopped $svc"
            else
                log "✗ Failed to stop $svc"
            fi
        else
            log "  $svc: not running (skipping)"
        fi
    done

    # Scale K8s deployment to 0
    if kubectl scale deployment "$MINING_DEPLOYMENT" -n "$MINING_NAMESPACE" --replicas=0 >/dev/null 2>&1; then
        log "✓ Scaled $MINING_DEPLOYMENT to 0 replicas"

        # Wait for pods to terminate
        local timeout=30
        local elapsed=0
        while [ $elapsed -lt $timeout ]; do
            local pod_count=$(kubectl get pods -n "$MINING_NAMESPACE" -l app=gpu-miner,host=zephyr --no-headers 2>/dev/null | wc -l)
            if [ "$pod_count" -eq 0 ]; then
                log "✓ All mining pods terminated"
                return 0
            fi
            sleep 2
            elapsed=$((elapsed + 2))
        done

        log "⚠ Warning: Pods still running after ${timeout}s timeout"
        return 1
    else
        log "✗ Failed to scale deployment"
        return 1
    fi
}

resume_mining() {
    log "GameMode END: Resuming all mining workloads"

    # Scale K8s deployment back to 1
    if kubectl scale deployment "$MINING_DEPLOYMENT" -n "$MINING_NAMESPACE" --replicas=1 >/dev/null 2>&1; then
        log "✓ Scaled $MINING_DEPLOYMENT to 1 replica"

        # Start host-based mining services
        for svc in "${MINING_SERVICES[@]}"; do
            if systemctl is-enabled --quiet "$svc" 2>/dev/null; then
                log "Starting host service: $svc"
                if systemctl start "$svc" >/dev/null 2>&1; then
                    log "✓ Started $svc"
                else
                    log "✗ Failed to start $svc"
                fi
            else
                log "  $svc: not enabled (skipping)"
            fi
        done
        log "✓ Scaled $MINING_DEPLOYMENT to 1 replica"

        # Wait for pod to be ready
        local timeout=60
        local elapsed=0
        while [ $elapsed -lt $timeout ]; do
            local ready=$(kubectl get pods -n "$MINING_NAMESPACE" -l app=gpu-miner,host=zephyr --no-headers 2>/dev/null | awk '{print $2}' | cut -d'/' -f1)
            if [ "$ready" = "1" ]; then
                log "✓ Mining pod is ready and running"
                return 0
            fi
            sleep 2
            elapsed=$((elapsed + 2))
        done

        log "⚠ Warning: Pod not ready after ${timeout}s timeout"
        return 1
    else
        log "✗ Failed to scale deployment"
        return 1
    fi
}

# Main: Check action from GameMode
ACTION="${1:-}"

case "$ACTION" in
    start)
        pause_mining
        ;;
    end)
        resume_mining
        ;;
    *)
        echo "Usage: $0 {start|end}"
        echo "  start  - Pause mining (called by GameMode when game starts)"
        echo "  end    - Resume mining (called by GameMode when game ends)"
        exit 1
        ;;
esac
