#!/usr/bin/env bash
# preflight-check.sh — Pre-deploy consistency gate for the NixOS cluster.
#
# Verifies the build executor (nexus) and the source-of-truth host (zephyr)
# agree on the canonical commit BEFORE any build/activate happens. This is the
# G4 gate: it blocks a deploy that would otherwise build drifted bytes from a
# stale nexus /etc/nixos checkout.
#
# Usage:  preflight-check.sh [--no-fetch]
#   --no-fetch   Skip the git fetch (use cached remote refs)
#
# Exit: 0 if safe to deploy, 1 if a drift/consistency problem was found.

set -uo pipefail

FLAKE="${FLAKE:-/etc/nixos}"
NO_FETCH=0
[[ "${1:-}" == "--no-fetch" ]] && NO_FETCH=1

log() { echo "[preflight $(date +%H:%M:%S)] $*" >&2; }
pass() { log "  ✓ $*"; }
fail() { log "  ✗ $*"; FAIL=1; }

cd "$FLAKE" || { echo "cannot cd to $FLAKE" >&2; exit 1; }

if [ "$NO_FETCH" -eq 0 ]; then
    git fetch origin main >&2 || {
        echo "cannot refresh origin/main; use --no-fetch only with an intentional cached ref" >&2
        exit 1
    }
fi

FAIL=0
CANONICAL=$(git rev-parse origin/main 2>/dev/null || echo "UNKNOWN")
LOCAL=$(git rev-parse HEAD 2>/dev/null || echo "UNKNOWN")

log "=== Preflight: deploy consistency gate ==="
log "  canonical origin/main = $CANONICAL"
log "  local HEAD           = $LOCAL"

# 1. Local (zephyr) must track canonical.
if [ "$LOCAL" != "$CANONICAL" ]; then
    fail "local /etc/nixos ($LOCAL) != origin/main ($CANONICAL) — commit/push before deploy"
else
    pass "local /etc/nixos matches origin/main"
fi

# 2-4. All remote hosts must match canonical.
# NOTE: forge is intentionally excluded from this gate.
# - forge: its SSH is broken by the world-writable systemd-ssh-proxy store
#   include (OpenSSH secure_permission rejects mode 1777; chmod is impossible
#   on the immutable Nix store). Fix = systemd-ssh-proxy.enable=false in
#   forge config. Forge is a GPU miner (not a builder) and not in the zephyr
#   deploy closure, so excluding it here is safe for zephyr deploys.
# Uses sequential SSH checks so a failed self-heal is reported clearly.
log "  checking remote hosts..."
HOSTS="nexus sentry"

for HOST in $HOSTS; do
  REMOTE_HEAD=$(ssh "$HOST" "bash --norc --noprofile -c 'cd /etc/nixos && git rev-parse HEAD 2>/dev/null'" 2>/dev/null || echo "UNKNOWN")
  if [ "$REMOTE_HEAD" != "$CANONICAL" ]; then
    log "  ⚠ $HOST ($REMOTE_HEAD) != origin/main ($CANONICAL) — self-healing"
    ssh "$HOST" "bash --norc --noprofile -c 'cd /etc/nixos && git fetch origin main 2>&1 | tail -1 && git reset --hard origin/main 2>&1 | tail -1'" 2>&1 | tail -1
    REMOTE_HEAD=$(ssh "$HOST" "bash --norc --noprofile -c 'cd /etc/nixos && git rev-parse HEAD 2>/dev/null'" 2>/dev/null || echo "UNKNOWN")
    if [ "$REMOTE_HEAD" = "$CANONICAL" ]; then
      pass "$HOST synced"
    else
      fail "$HOST still drifted ($REMOTE_HEAD)"
    fi
  else
    pass "$HOST matches origin/main"
  fi
done
# 4. In-flight build check — detect build types that indicate a DEPLOY or long build.
#    nix-instantiate is EXCLUDED because it's a short-lived helper that spawns during
#    any nix operation (including preflight itself) — counting it causes self-blocking.
BUILD_TYPES=("colmena" "nix-build" "nix-copy" "nixos-rebuild" "switch-to-configuration")
DETECTED=""
for btype in "${BUILD_TYPES[@]}"; do
    PIDS=$(ssh nexus "pgrep -x '$btype' 2>/dev/null | wc -l" 2>/dev/null)
    if [[ "${PIDS:-0}" -gt 0 ]]; then
        DETECTED="$DETECTED $btype($PIDS)"
    fi
done
# 4a. nix-daemon worker children (REAL compile/sign workers)
DAEMON_WORKERS=$(ssh nexus "D_PID=\$(pgrep -x nix-daemon | head -1); if [ -n "\$D_PID" ]; then pgrep -P "\$D_PID" 2>/dev/null | wc -l; else echo 0; fi" 2>/dev/null)
if [[ "${DAEMON_WORKERS:-0}" -gt 0 ]]; then
    DETECTED="$DETECTED nix-daemon-workers($DAEMON_WORKERS)"
fi
if [[ -n "$DETECTED" ]]; then
    fail "in-flight build processes on nexus:$DETECTED — wait for them to finish before deploying"
else
    pass "no in-flight builds on nexus (incl. nix-daemon workers)"
fi

# 4b. Nexus nix-daemon health check
NEXUS_DAEMON=$(ssh nexus "systemctl show nix-daemon --property=MainPID --value 2>/dev/null" 2>/dev/null)
if [[ -z "${NEXUS_DAEMON:-}" || "$NEXUS_DAEMON" == "0" ]]; then
    fail "nix-daemon not running on nexus — builds will fail"
else
    pass "nix-daemon running on nexus (pid $NEXUS_DAEMON)"
fi

# 4c. Nexus store DB lock check — a lingering daemon can hold the SQLite lock
LOCK_CHECK=$(ssh nexus "timeout 10 nix eval --raw nixpkgs#hello.outPath 2>&1" 2>/dev/null)
if echo "$LOCK_CHECK" | grep -qi "busy\|locked\|database is locked"; then
    fail "nexus store DB is locked — a lingering daemon holds /nix/var/nix/db/db.sqlite; run: ssh nexus 'sudo pkill -9 -f nix-daemon'"
else
    pass "nexus store DB not locked"
fi

log "=== Preflight result: $([ "$FAIL" -eq 0 ] && echo PASS || echo BLOCKED) ==="
exit ${FAIL:-0}
