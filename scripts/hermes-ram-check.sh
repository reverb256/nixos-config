#!/usr/bin/env bash
# Mandatory RAM check for Hermes operations on Zephyr
# Prevents OOM crashes by enforcing memory limits

set -euo pipefail

log() { echo "[$(date +%H:%M:%S)] $*"; }
die() { log "ERROR: $*"; exit 1; }

# Configuration
MIN_FREE_RAM_MB=2048        # Minimum 2GB free RAM required
MIN_AVAILABLE_RAM_MB=4096   # Minimum 4GB available (including cache)
CRITICAL_FREE_RAM_MB=1024   # Critical threshold - kill operations if below

# Get current memory stats (handle different free output formats)
FREE_RAM_MB=$(free -m | awk '/^Mem:/ {print $7}' | grep -E '^[0-9]+$' || echo "0")
AVAILABLE_RAM_MB=$(free -m | awk '/^Mem:/ {print $8}' | grep -E '^[0-9]+$' || echo "0")
SWAP_USED_MB=$(free -m | awk '/^Swap:/ {print $3}' | grep -E '^[0-9]+$' || echo "0")

# Fallback if available column doesn't exist
if [ -z "$AVAILABLE_RAM_MB" ] || [ "$AVAILABLE_RAM_MB" = "0" ]; then
    AVAILABLE_RAM_MB=$(free -m | awk '/^Mem:/ {print $7}')
fi

log "=== Hermes Pre-flight RAM Check ==="
log "Free RAM: ${FREE_RAM_MB}MB (minimum: ${MIN_FREE_RAM_MB}MB)"
log "Available RAM: ${AVAILABLE_RAM_MB}MB (minimum: ${MIN_AVAILABLE_RAM_MB}MB)"
log "Swap Used: ${SWAP_USED_MB}MB"
log ""

# Critical check - abort immediately
if [ "$FREE_RAM_MB" -lt "$CRITICAL_FREE_RAM_MB" ]; then
    log "❌ CRITICAL: Free RAM (${FREE_RAM_MB}MB) below critical threshold (${CRITICAL_FREE_RAM_MB}MB)"
    log "   Action: Aborting operation to prevent system instability"
    log ""
    log "Recommended actions:"
    log "   1. Kill unnecessary processes: ps aux --sort=-%mem | head -10"
    log "   2. Scale down K8s deployments: kubectl scale deployment --all -n ai-inference --replicas=0"
    log "   3. Clear caches: sudo sync && echo 3 | sudo tee /proc/sys/vm/drop_caches"
    exit 1
fi

# Warning check - proceed with caution
if [ "$FREE_RAM_MB" -lt "$MIN_FREE_RAM_MB" ] || [ "$AVAILABLE_RAM_MB" -lt "$MIN_AVAILABLE_RAM_MB" ]; then
    log "⚠️  WARNING: Low memory conditions detected"
    log "   Free RAM: ${FREE_RAM_MB}MB < ${MIN_FREE_RAM_MB}MB required"
    log "   Available RAM: ${AVAILABLE_RAM_MB}MB < ${MIN_AVAILABLE_RAM_MB}MB required"
    log ""
    log "   Proceeding with operation, but OOM risk is HIGH!"
    log "   Consider scaling down services first."
    log ""
    exit 2
fi

log "✅ RAM check passed - sufficient memory for operations"
exit 0
