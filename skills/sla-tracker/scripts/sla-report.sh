#!/usr/bin/env bash
# Generate SLA compliance report from uptime logs
# Usage: ./sla-report.sh [days]

set -euo pipefail

REPORT_DIR="${1:-/var/log/cluster-sla}"
REPORT_PERIOD=${2:-30}

echo "=== SLA Compliance Report (Last $REPORT_PERIOD days) ==="
echo ""

# Find logs in the period
LOG_FILES=$(find "$REPORT_DIR" -name "uptime-*.log" -mtime -$REPORT_PERIOD 2>/dev/null | sort)

if [ -z "$LOG_FILES" ]; then
    echo "No uptime logs found for the last $REPORT_PERIOD days"
    echo "Log directory: $REPORT_DIR"
    exit 1
fi

# Count total checks and incidents
TOTAL_CHECKS=$(grep -c "^\[" $LOG_FILES 2>/dev/null || echo "0")
TOTAL_HOSTS=$(grep -c "^\[" $LOG_FILES 2>/dev/null || echo "0")

# Count incidents by type
OFFLINE_COUNT=$(grep -c "OFFLINE" $LOG_FILES 2>/dev/null || echo "0")
FAILED_SERVICE_COUNT=$(grep -c "Failed services:" $LOG_FILES 2>/dev/null || echo "0")

# Calculate uptime
AVAILABLE_CHECKS=$((TOTAL_HOSTS - OFFLINE_COUNT))
if [ "$TOTAL_HOSTS" -gt 0 ]; then
    UPTIME_PCT=$(echo "scale=2; $AVAILABLE_CHECKS * 100 / $TOTAL_HOSTS" | bc)
else
    UPTIME_PCT="0.00"
fi

echo "Overall Metrics:"
echo "  Total host checks: $TOTAL_HOSTS"
echo "  Available checks: $AVAILABLE_CHECKS"
echo "  Offline incidents: $OFFLINE_COUNT"
echo "  Failed service incidents: $FAILED_SERVICE_COUNT"
echo "  Overall Uptime: ${UPTIME_PCT}%"
echo ""

# SLA Status
SLA_9990="99.90"
SLA_9950="99.50"
SLA_9900="99.00"

echo "SLA Compliance:"

if (( $(echo "$UPTIME_PCT >= $SLA_9990" | bc -l) )); then
    echo "  ✓ 99.9% SLA (Three Nines) - COMPLIANT"
elif (( $(echo "$UPTIME_PCT >= $SLA_9950" | bc -l) )); then
    echo "  ✓ 99.5% SLA - COMPLIANT"
elif (( $(echo "$UPTIME_PCT >= $SLA_9900" | bc -l) )); then
    echo "  ✓ 99.0% SLA (Two Nines) - COMPLIANT"
else
    echo "  ✗ SLA BREACH - Below 99.0% uptime"
fi

echo ""

# Per-host breakdown
echo "Per-Host Breakdown:"
for host in zephyr nexus forge sentry; do
    HOST_CHECKS=$(grep "^\[$host\]" $LOG_FILES | wc -l)
    HOST_OFFLINE=$(grep "^\[$host\]" $LOG_FILES | grep -c "OFFLINE" || echo "0")

    if [ "$HOST_CHECKS" -gt 0 ]; then
        HOST_UPTIME=$(echo "scale=2; ($HOST_CHECKS - $HOST_OFFLINE) * 100 / $HOST_CHECKS" | bc)
        printf "  %-10s: %6s%% (%d incidents)\n" "$host" "$HOST_UPTIME" "$HOST_OFFLINE"
    else
        printf "  %-10s: No data\n" "$host"
    fi
done

echo ""
echo "Recommendations:"
if (( $(echo "$UPTIME_PCT < 99" | bc -l) )); then
    echo "  - Investigate frequent offline incidents"
    echo "  - Consider implementing redundancy"
    echo "  - Review network connectivity"
elif [ "$OFFLINE_COUNT" -gt 0 ]; then
    echo "  - Review causes of offline incidents"
    echo "  - Consider automated failover"
else
    echo "  - Cluster is performing well"
fi
