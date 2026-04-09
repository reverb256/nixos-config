#!/usr/bin/env bash
# Cluster Storage Verification Script
# Ensures all configured storage is properly mounted across all nodes

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

# Function to check a node's storage
check_node_storage() {
    local node=$1
    local expected_mounts="${2:-}"  # Default to empty if not provided

    log "Checking storage on $node..."

    # Try to mount filesystems if they're not mounted
    ssh "$node" "sudo mount -a 2>&1" || true

    # Get actual mounts
    local actual_mounts=$(ssh "$node" "df -h | grep -E '^/dev' | awk '{print \$6}' | sort | tr '\n' ' '")

    log "$node mounts: $actual_mounts"

    # Check for critical mount points
    if [[ "$node" == "nexus" ]]; then
        # Nexus should have /data/* mounts
        local data_mounts=$(ssh "$node" "df -h | grep '/data' | wc -l")
        if [[ "$data_mounts" -ge 5 ]]; then
            log "✓ Nexus: All /data mounts active ($data_mounts mounts found)"
        else
            error "✗ Nexus: Missing /data mounts (only $data_mounts found, expected 5+)"
            return 1
        fi

        # Check for /var/lib/containers
        if ssh "$node" "df -h | grep -q '/var/lib/containers'"; then
            log "✓ Nexus: /var/lib/containers mounted"
        else
            warn "✗ Nexus: /var/lib/containers not mounted"
        fi
    fi

    if [[ "$node" == "sentry" ]]; then
        # Sentry should have /storage
        if ssh "$node" "df -h | grep -q '/storage'"; then
            log "✓ Sentry: /storage mounted"
        else
            error "✗ Sentry: /storage not mounted"
            return 1
        fi
    fi

    if [[ "$node" == "zephyr" ]]; then
        # Zephyr should have /data
        if df -h | grep -q '/data'; then
            log "✓ Zephyr: /data mounted"
        else
            error "✗ Zephyr: /data not mounted"
            return 1
        fi
    fi

    return 0
}

# Function to get storage summary
get_storage_summary() {
    log "=== Cluster Storage Summary ==="

    for node in zephyr nexus forge sentry; do
        echo ""
        echo "Node: $node"
        ssh "$node" "df -h | grep '^/dev' | sort"
    done
}

# Main execution
main() {
    log "Starting cluster storage verification..."

    local failed=0

    # Check each node
    for node in zephyr nexus forge sentry; do
        if ! check_node_storage "$node"; then
            failed=1
        fi
    done

    echo ""
    get_storage_summary

    if [[ $failed -eq 0 ]]; then
        log "✓ All cluster storage verified successfully!"
        return 0
    else
        error "✗ Some storage verification checks failed"
        return 1
    fi
}

# Run main function
main "$@"
