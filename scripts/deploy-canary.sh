#!/usr/bin/env bash
# Canary / rolling deployment — issue #341
#
# Deploys hosts ONE AT A TIME in a safe order, probes post-switch health
# after each activation, auto-rolls-back on failure, and aborts the remaining
# hosts (fail-stop) so a bad switch can never cascade cluster-wide.
#
# Usage:
#   scripts/deploy-canary.sh                 # default safe order
#   scripts/deploy-canary.sh nexus forge     # custom order (safest-first)
#
# Default order (safest-first, per cluster topology):
#   1. nexus   — primary server/storage/AI gateway (canary #1)
#   2. forge   — GPU compute/mining (2x 4060)
#   3. sentry  — monitoring + Vulkan AI
#   4. zephyr  — workstation/control plane (LAST: local display risk)
#
# Post-switch probe per host: sshd active + uptime sanity + key services
# (per-host map, best-effort). On probe failure the host is rolled back with
# `nixos-rebuild --rollback switch` and the remaining hosts are NOT deployed.
set -euo pipefail

FLAKE="${FLAKE:-/etc/nixos}"
DISPATCHER="${FLAKE}/scripts/deploy/nexus-dispatch.sh"
CANARY_LOCK_FILE="${DEPLOY_CANARY_LOCK_FILE:-/tmp/nixos-canary-deploy.lock}"
CANARY_LOCK_DIR="${DEPLOY_CANARY_LOCK_DIR:-/tmp/nixos-canary-rollout.lock.d}"
CANARY_TOKEN="${CANARY_TOKEN:-$(date +%s)-$$}"
REMOTE_CANARY_LOCK_DIR="$CANARY_LOCK_DIR"
exec 9>"$CANARY_LOCK_FILE"
if ! flock -n 9; then
  echo "another canary rollout is already running (lock: $CANARY_LOCK_FILE)" >&2
  exit 75
fi
if ! mkdir "$CANARY_LOCK_DIR" 2>/dev/null; then
  echo "another canary rollout is already running (lock: $CANARY_LOCK_DIR)" >&2
  exit 75
fi
printf '%s\\n' "$CANARY_TOKEN" > "$CANARY_LOCK_DIR/owner"
CANARY_TOKEN_B64="$(printf '%s' "$CANARY_TOKEN" | base64 -w0)"
REMOTE_CANARY_LOCK_DIR_B64="$(printf '%s' "$REMOTE_CANARY_LOCK_DIR" | base64 -w0)"
if ! ssh nexus \
  env "CANARY_TOKEN_B64=$CANARY_TOKEN_B64" \
  "REMOTE_CANARY_LOCK_DIR_B64=$REMOTE_CANARY_LOCK_DIR_B64" \
  bash --norc --noprofile -s <<'REMOTE_CANARY_LOCK'
set -euo pipefail
d=$(printf '%s' "$REMOTE_CANARY_LOCK_DIR_B64" | base64 -d)
t=$(printf '%s' "$CANARY_TOKEN_B64" | base64 -d)
mkdir "$d"
trap 'rm -rf "$d"' EXIT
printf '%s\\n' "$t" > "$d/owner"
trap - EXIT
REMOTE_CANARY_LOCK
then
  rm -rf "$CANARY_LOCK_DIR"
  echo "unable to acquire the Nexus canary rollout lock" >&2
  exit 1
fi
cleanup_canary_lock() {
  if [ "$(cat "$CANARY_LOCK_DIR/owner" 2>/dev/null)" = "$CANARY_TOKEN" ]; then
    rm -rf "$CANARY_LOCK_DIR"
  fi
  ssh nexus \
    env "CANARY_TOKEN_B64=$CANARY_TOKEN_B64" \
    "REMOTE_CANARY_LOCK_DIR_B64=$REMOTE_CANARY_LOCK_DIR_B64" \
    bash --norc --noprofile -s <<'REMOTE_CANARY_CLEANUP' >/dev/null 2>&1 || true
set -euo pipefail
d=$(printf '%s' "$REMOTE_CANARY_LOCK_DIR_B64" | base64 -d)
t=$(printf '%s' "$CANARY_TOKEN_B64" | base64 -d)
if [ "$(cat "$d/owner" 2>/dev/null)" = "$t" ]; then
  rm -rf "$d"
fi
REMOTE_CANARY_CLEANUP
}
trap cleanup_canary_lock EXIT

# Per-host key services to probe after switch (best-effort; empty = sshd only).
# Add services here when a host gains critical infrastructure.
declare -A KEY_SERVICES=(
  [nexus]="caddy prometheus"
  [sentry]="prometheus grafana"
  [forge]=""
  [zephyr]=""
)

DEFAULT_ORDER=(nexus forge sentry zephyr)
if [ $# -gt 0 ]; then
  ORDER=("$@")
else
  ORDER=("${DEFAULT_ORDER[@]}")
fi

log() { echo "━━━ $* ━━━"; }

# probe_host <host> — returns 0 if sshd is up and key services are active.
probe_host() {
  local host="$1" svc
  local ssh_cmd="ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new"

  if ! $ssh_cmd "$host" "true" 2>/dev/null; then
    echo "  ✗ $host: SSH unreachable" >&2
    return 1
  fi
  if ! $ssh_cmd "$host" "systemctl is-active sshd" 2>/dev/null | grep -qx "active"; then
    echo "  ✗ $host: sshd not active" >&2
    return 1
  fi
  # Uptime sanity: refuse to pass during a post-boot load storm. Wait for the
  # activation storm to settle before judging (60s grace), then require load
  # below 24 (nexus is 12C — 24 covers even a doubled activation spike).
  local load
  sleep 60
  load=$($ssh_cmd "$host" "cat /proc/loadavg | cut -d' ' -f1" 2>/dev/null || echo 999)
  if awk -v l="$load" 'BEGIN{exit !(l < 24)}'; then
    echo "  ✓ $host: sshd up, load $load"
  else
    echo "  ✗ $host: load $load too high (possible boot storm)" >&2
    return 1
  fi
  for svc in ${KEY_SERVICES[$host]:-}; do
    if ! $ssh_cmd "$host" "systemctl is-active --quiet '$svc'" 2>/dev/null; then
      echo "  ✗ $host: service '$svc' not active" >&2
      return 1
    fi
  done
  return 0
}

# rollback_host <host> — nixos-rebuild rollback on the target.
rollback_host() {
  local host="$1"
  echo "  [rollback] $host → nixos-rebuild --rollback switch" >&2
  ssh -o BatchMode=yes -o ConnectTimeout=5 "$host" \
    "sudo nixos-rebuild --rollback switch" 2>&1 | tail -3 || \
    echo "  [rollback] FAILED for $host — manual intervention required" >&2
}

echo "Canary deployment lock acquired: $CANARY_LOCK_FILE"
echo "Canary deploy order: ${ORDER[*]}"
total=${#ORDER[@]}
i=0
for host in "${ORDER[@]}"; do
  i=$((i + 1))
  log "[$i/$total] Deploying $host"
  if ! CANARY_TOKEN="$CANARY_TOKEN" DEPLOY_CANARY_LOCK_DIR="$CANARY_LOCK_DIR" "$DISPATCHER" --sync --target "$host"; then
    echo "ERROR: deploy to $host FAILED — rolling back and aborting." >&2
    rollback_host "$host"
    exit 1
  fi
  echo "  probing post-switch health of $host..."
  if probe_host "$host"; then
    echo "  ✓ $host healthy — proceeding"
  else
    echo "ERROR: $host FAILED post-switch health probe — rolling back and aborting." >&2
    rollback_host "$host"
    echo "Aborting remaining hosts (fail-stop): ${ORDER[*]:$i}" >&2
    exit 1
  fi
done

log "Canary deploy complete: ${ORDER[*]}"
echo "Verify with: just health / just cluster-status"
