#!/usr/bin/env bash
# Check cluster uptime and report SLA status
# Usage: ./check-cluster-uptime.sh

set -euo pipefail

REPORT_DIR="/var/log/cluster-sla"
mkdir -p "$REPORT_DIR"
REPORT_FILE="$REPORT_DIR/uptime-$(date +%Y%m%d-%H%M%S).log"

HOSTS=(zephyr nexus forge sentry)
CURRENT_HOST=$(hostname)

{
    echo "=== Cluster Uptime Report - $(date) ==="
    echo ""
    echo "Checking ${#HOSTS[@]} hosts: ${HOSTS[*]}"
    echo ""

    for host in "${HOSTS[@]}"; do
        echo "[$host]"

        # Check host connectivity
        if [ "$host" = "$CURRENT_HOST" ]; then
            HOST_STATUS="Online"
        elif ping -c 1 -W 2 "$host.local" >/dev/null 2>&1; then
            HOST_STATUS="Online"
        else
            HOST_STATUS="OFFLINE"
            echo "  Status: $HOST_STATUS"
            echo "  Severity: CRITICAL - SLA BREACH"
            continue
        fi

        echo "  Status: $HOST_STATUS"

        # Check services on this host
        if [ "$host" = "$CURRENT_HOST" ]; then
            # Local check
            FAILED_UNITS=$(systemctl list-units --failed --no-legend --plain 2>/dev/null | head -5)
        else
            # Remote check via SSH
            FAILED_UNITS=$(ssh "$host.local" 'systemctl list-units --failed --no-legend --plain' 2>/dev/null | head -5 || echo "")
        fi

        if [ -n "$FAILED_UNITS" ]; then
            echo "  Failed services:"
            echo "$FAILED_UNITS" | while read -r unit; do
                echo "    - $unit"
            done
        else
            echo "  Services: All OK"
        fi

        echo ""
    done

    echo "=== Summary ==="
    echo "Report saved to: $REPORT_FILE"

} | tee "$REPORT_FILE"

# Also write to ongoing log for SLA calculations
ln -sf "$REPORT_FILE" "$REPORT_DIR/uptime-latest.log"
