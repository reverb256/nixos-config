#!/usr/bin/env bash
# Graceful Kubernetes Restart Script
# Prevents cascading failures during CRI-O restarts
# Usage: sudo ./scripts/graceful-k8s-restart.sh

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $*"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $*"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    error "This script must be run as root (use sudo)"
    exit 1
fi

log "=== Graceful Kubernetes Restart Sequence ==="

# 1. Stop control plane (reverse dependency order)
log "Stopping control plane services (reverse dependency order)..."

if systemctl is-active --quiet kube-controller-manager; then
    log "Stopping kube-controller-manager..."
    systemctl stop kube-controller-manager
else
    warn "kube-controller-manager not active, skipping"
fi

if systemctl is-active --quiet kube-scheduler; then
    log "Stopping kube-scheduler..."
    systemctl stop kube-scheduler
else
    warn "kube-scheduler not active, skipping"
fi

if systemctl is-active --quiet kube-apiserver; then
    log "Stopping kube-apiserver..."
    systemctl stop kube-apiserver
else
    warn "kube-apiserver not active, skipping"
fi

if systemctl is-active --quiet kubelet; then
    log "Stopping kubelet..."
    systemctl stop kubelet
else
    warn "kubelet not active, skipping"
fi

# 2. Restart CRI-O
log "Restarting CRI-O..."
systemctl restart crio

# 3. Wait for CRI-O readiness
log "Waiting for CRI-O to be ready..."
timeout=60
while [ $timeout -gt 0 ]; do
    if /run/current-system/sw/bin/crictl info >/dev/null 2>&1; then
        log "CRI-O is ready ✓"
        break
    fi
    sleep 1
    ((timeout--))
done

if [ $timeout -eq 0 ]; then
    error "CRI-O failed to become ready after 60 seconds"
    exit 1
fi

# 4. Start kubelet
log "Starting kubelet..."
systemctl start kubelet

# 5. Wait briefly for kubelet to start
log "Waiting briefly for kubelet to start..."
sleep 5

# Check kubelet is responding (not fully registered, just running)
if /run/current-system/sw/bin/curl -f -s http://localhost:10248/healthz >/dev/null 2>&1; then
    log "Kubelet is responding ✓"
elif pgrep -f "kubelet.*--hostname-override=zephyr" >/dev/null 2>&1; then
    log "Kubelet process is running ✓"
else
    error "Kubelet failed to start"
    exit 1
fi

# 6. Start control plane (dependency order)
log "Starting control plane services (dependency order)..."

log "Starting kube-apiserver..."
systemctl start kube-apiserver

# Wait a bit for API server to stabilize
sleep 5

log "Starting kube-scheduler..."
systemctl start kube-scheduler

log "Starting kube-controller-manager..."
systemctl start kube-controller-manager

# 7. Verify cluster health
log "Waiting for API server to fully initialize..."
sleep 30

# Retry kubectl commands if API server isn't ready yet
log "Verifying cluster health..."
retry_count=0
max_retries=5

while [ $retry_count -lt $max_retries ]; do
    if kubectl get nodes >/dev/null 2>&1; then
        log "Cluster nodes:"
        kubectl get nodes

        log ""
        log "System pods:"
        kubectl get pods -n kube-system | head -20
        break
    else
        ((retry_count++))
        if [ $retry_count -lt $max_retries ]; then
            log "API server not ready yet, retrying ($retry_count/$max_retries)..."
            sleep 10
        else
            error "API server still not ready after $max_retries retries"
        fi
    fi
done

# 8. Final health check
log ""
log "=== Final Health Check ==="

# Check all control plane services
control_plane_services=("kube-apiserver" "kube-scheduler" "kube-controller-manager" "kubelet" "crio")
all_healthy=true

for service in "${control_plane_services[@]}"; do
    if systemctl is-active --quiet "$service.service"; then
        log "✓ $service.service is healthy"
    else
        error "✗ $service.service is NOT healthy"
        all_healthy=false
    fi
done

# Check cluster connectivity
if kubectl get nodes >/dev/null 2>&1; then
    log "✓ Cluster connectivity verified"
else
    error "✗ Cluster connectivity NOT verified"
    all_healthy=false
fi

if [ "$all_healthy" = true ]; then
    log ""
    log "=== Graceful Restart Complete ==="
    log "All services healthy ✓"
    exit 0
else
    error ""
    error "=== Graceful Restart Failed ==="
    error "Some services are not healthy"
    exit 1
fi
