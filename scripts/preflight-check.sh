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
# forge IS included in this gate. The old exclusion (03fb6022) claimed its
# SSH was broken by a world-writable systemd-ssh-proxy store include; that
# service is no longer configured anywhere in the repo, forge's sshd passes
# `sshd -t`, and SSH from zephyr works (verified 2026-08-19, #715).
# Uses sequential SSH checks so a failed self-heal is reported clearly.
log "  checking remote hosts..."
HOSTS="nexus sentry forge"

for HOST in $HOSTS; do
  REMOTE_HEAD=$(ssh "$HOST" "bash --norc --noprofile -c 'cd /etc/nixos && git rev-parse HEAD 2>/dev/null'" 2>/dev/null || echo "UNKNOWN")
  if [ "$REMOTE_HEAD" != "$CANONICAL" ]; then
    log "  ⚠ $HOST ($REMOTE_HEAD) != origin/main ($CANONICAL) — self-healing"
    # Hosts use `central` (nexus git server) as their fetch remote, not
    # `origin` — `git fetch origin` fails silently and `git reset --hard
    # origin/main` resets to a stale ref (observed 2026-08-20). Try origin
    # first, fall back to central (simple, avoids nested-quote hell that
    # broke `git remote | grep` under the fish login shell).
    REMOTE="origin"
    if ! ssh "$HOST" "bash --norc --noprofile -c 'cd /etc/nixos && git rev-parse --verify origin/main >/dev/null 2>&1'" 2>/dev/null; then
      REMOTE="central"
    fi
    # SELF-HEAL: colmena apply (running as root) can leave root-owned objects
    # in /etc/nixos/.git, breaking the NEXT fetch with "insufficient
    # permission ... unpack-objects failed" (observed on nexus/sentry/forge
    # 2026-08-20). Normalize ownership before fetching.
    ssh "$HOST" "sudo chown -R j_kro:users /etc/nixos/.git 2>/dev/null || true" 2>/dev/null
    ssh "$HOST" "bash --norc --noprofile -c 'cd /etc/nixos && git fetch $REMOTE main 2>&1 | tail -1 && git reset --hard $REMOTE/main 2>&1 | tail -1'" 2>&1 | tail -1
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
BUILD_TYPES=("colmena" "deploy" "nix-build" "nix-copy" "nixos-rebuild" "switch-to-configuration")
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
    # SELF-HEAL: a lingering \`colmena apply\` from a failed/wedged deploy never
    # finishes on its own — it blocks every future deploy (observed 2026-08-20:
    # a 26-min colmena apply + its nix-eval child after an OOM-killed NSS
    # build). A REAL nix-daemon worker (active compile) is left alone; a
    # wedged colmena/nixos-rebuild is killed so the next deploy can proceed.
    if echo "$DETECTED" | grep -q "colmena\|deploy\|nixos-rebuild\|switch-to-configuration"; then
        log "  ⚠ stale deploy process on nexus:$DETECTED — killing (failed/wedged deploys never self-clean)"
        ssh nexus "bash --norc --noprofile -c 'pgrep -x colmena 2>/dev/null | xargs -r kill -9; pgrep -x deploy 2>/dev/null | xargs -r kill -9; pgrep -f "deploy-rs" 2>/dev/null | xargs -r kill -9; pgrep -f "colmenaHive" 2>/dev/null | xargs -r kill -9; pgrep -x nixos-rebuild 2>/dev/null | xargs -r kill -9; pgrep -x switch-to-configuration 2>/dev/null | xargs -r kill -9; sleep 1; echo KILLED'" 2>&1 | tail -1
        pass "stale deploy process killed"
    else
        fail "in-flight build processes on nexus:$DETECTED — wait for them to finish before deploying"
    fi
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
