#!/usr/bin/env bash
# CI Monitor — periodic health/monitoring check for the cluster.
# Designed to run on sentry (or any node). Posts results as kanban task
# with type=monitor.
#
# Usage: scripts/ci-monitor.sh [--host HOST] [--board BOARD]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/../kanban_helper.sh" ]; then
  source "$SCRIPT_DIR/../kanban_helper.sh"
elif [ -f "/home/j_kro/Projects/site-agency/scripts/kanban_helper.sh" ]; then
  source "/home/j_kro/Projects/site-agency/scripts/kanban_helper.sh"
else
  # Fallback: define minimal inline wrapper with remote-hermes fallback
  _HK_CMD="hermes kanban"
  command -v hermes &>/dev/null || _HK_CMD="ssh -o ConnectTimeout=5 -o BatchMode=yes j_kro@zephyr hermes kanban"
  kanban_post() {
    local t="$1" title="$2"; shift 2
    $_HK_CMD create "[${t}] ${title}" --body "$*" --json --skill "type:${t}" --skill "source:ci-monitor" 2>/dev/null || echo "mock-${t}-$RANDOM"
  }
  kanban_close() { $_HK_CMD complete "$1" 2>/dev/null || true; }
  kanban_block() { $_HK_CMD block "$1" "$2" 2>/dev/null || true; }
fi

# ── Config ──
HOST="${1:-sentry}"
BOARD="${2:-}"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
HOSTNAME=$(hostname -s 2>/dev/null || echo "$HOST")
TMPDIR=$(mktemp -d)

cleanup() { rm -rf "$TMPDIR"; }
trap cleanup EXIT

echo "=== CI Monitor ($HOSTNAME @ $TIMESTAMP) ==="

# ── Checks ──
issues=""

# Check 1: System load / memory
loadavg=$(cat /proc/loadavg 2>/dev/null | awk '{print $1,$2,$3}' || echo "N/A")
mem_avail=$(free -m 2>/dev/null | awk '/Mem:/{printf "%.0f%%", $7/$2 * 100}' || echo "N/A")

issues+="- Load: $loadavg
- Memory available: $mem_avail
"

# Check 2: Disk usage
df_output=$(df -h / /nix /var/lib 2>/dev/null | awk 'NR>1{printf "- %s: %s used of %s (%s)\n", $6, $3, $2, $5}' || echo "N/A")
issues+="$df_output"

# Check 3: Systemd services (only if running interactively or on real host)
if command -v systemctl &>/dev/null; then
  failed_units=$(systemctl list-units --state=failed --no-legend 2>/dev/null | wc -l || echo 0)
  issues+="- Failed systemd units: $failed_units
"
fi

# Check 4: K3s node status (if kubectl is available)
if command -v kubectl &>/dev/null; then
  node_status=$(kubectl get nodes --no-headers 2>/dev/null | awk '{print $2}' | sort | uniq -c | tr '\n' ' ')
  issues+="- Node statuses: $node_status
"
fi

# ── Determine overall status ──
if echo "$issues" | grep -qi "out of memory\|disk full\|fail\|unreachable\|NotReady"; then
  status="warning"
elif [ "$(echo "$failed_units" 2>/dev/null || echo 0)" -gt 0 ]; then
  status="warning"
else
  status="ok"
fi

body="## CI Monitor Report

**Host:** $HOSTNAME
**Time:** $TIMESTAMP
**Status:** $status

### Details

$issues"

echo ""
echo "Status: $status"
echo "$issues"

# ── Post kanban task ──
kanban_post "monitor" "CI Monitor: $HOSTNAME — $status" \
  --body "$body" \
  --urgency "$([ "$status" = "ok" ] && echo "low" || echo "normal")" \
  --labels "type:monitor,source:ci-monitor,host:${HOSTNAME},status:${status}" || {
  echo "⚠️  Failed to post kanban monitor event"
}

echo ""
echo "✅ Monitor cycle complete"
