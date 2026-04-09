#!/usr/bin/env bash
set -euo pipefail

HOSTS="zephyr nexus forge sentry"

echo "=== Cluster Health Check ==="
echo ""

for host in $HOSTS; do
    if [ "$host" = "$(hostname -s)" ]; then
        echo "[$host] Local:"
        systemctl is-active ai-inference-gateway >/dev/null 2>&1 && echo "  ✓ AI Gateway" || echo "  ✗ AI Gateway"
        curl -f http://127.0.0.1:8080/health >/dev/null 2>&1 && echo "  ✓ HTTP health" || echo "  ✗ HTTP health"
    else
        echo "[$host] Remote:"
        if ssh -o ConnectTimeout=2 "$host" true >/dev/null 2>&1; then
            ssh "$host" "systemctl is-active ai-inference-gateway" >/dev/null 2>&1 && echo "  ✓ AI Gateway" || echo "  ✗ AI Gateway"
        else
            echo "  ✗ Host unreachable"
        fi
    fi
    echo ""
done
