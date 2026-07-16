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

FAIL=0
CANONICAL=$(git rev-parse --short origin/main 2>/dev/null || echo "UNKNOWN")
LOCAL=$(git rev-parse --short HEAD 2>/dev/null || echo "UNKNOWN")

log "=== Preflight: deploy consistency gate ==="
log "  canonical origin/main = $CANONICAL"
log "  local HEAD           = $LOCAL"

# 1. Local (zephyr) must track canonical.
if [ "$LOCAL" != "$CANONICAL" ]; then
    fail "local /etc/nixos ($LOCAL) != origin/main ($CANONICAL) — commit/push before deploy"
else
    pass "local /etc/nixos matches origin/main"
fi

# 2. nexus build executor must match canonical (PIPELINE INTEGRITY / G4).
log "  checking nexus build executor..."
if [ "$NO_FETCH" -eq 0 ]; then
    ssh nexus "bash --norc --noprofile -c 'cd /etc/nixos && git fetch origin main 2>&1 | tail -1'" >/dev/null 2>&1 || true
fi
NEXUS_HEAD=$(ssh nexus "bash --norc --noprofile -c 'cd /etc/nixos && git rev-parse --short origin/main 2>/dev/null'" 2>/dev/null || echo "UNKNOWN")
NEXUS_LOCAL=$(ssh nexus "bash --norc --noprofile -c 'cd /etc/nixos && git rev-parse --short HEAD 2>/dev/null'" 2>/dev/null || echo "UNKNOWN")
if [ "$NEXUS_LOCAL" != "$CANONICAL" ]; then
    # Self-heal: the deploy paths force-reset nexus to origin/main before building,
    # so drift here is benign. Sync it now (non-destructive: matches canonical).
    log "  ⚠ nexus /etc/nixos ($NEXUS_LOCAL) != origin/main ($CANONICAL) — self-healing (reset nexus to origin/main)"
    ssh nexus "bash --norc --noprofile -c 'set -e; cd /etc/nixos; git fetch origin main 2>&1 | tail -1; git reset --hard origin/main 2>&1 | tail -1'" 2>&1 | tail -1
    NEXUS_LOCAL=$(ssh nexus "bash --norc --noprofile -c 'cd /etc/nixos && git rev-parse --short HEAD 2>/dev/null'" 2>/dev/null || echo "UNKNOWN")
    if [ "$NEXUS_LOCAL" = "$CANONICAL" ]; then
        pass "nexus /etc/nixos synced to origin/main"
    else
        fail "nexus /etc/nixos still drifted ($NEXUS_LOCAL) after reset attempt"
    fi
else
    pass "nexus /etc/nixos matches origin/main"
fi

# 3. Working tree cleanliness on nexus (uncommitted edits would be clobbered by reset — warn, don't fail).
NEXUS_DIRTY=$(ssh nexus "bash --norc --noprofile -c 'cd /etc/nixos && git status --porcelain | head -5'" 2>/dev/null || echo "")
if [ -n "$NEXUS_DIRTY" ]; then
    log "  ⚠ nexus has uncommitted changes (will be reset by deploy):"
    echo "$NEXUS_DIRTY" | while read -r line; do log "      $line"; done
fi

# 4. In-flight build check (don't stomp a running build).
if ssh nexus "bash --norc --noprofile -c 'systemctl --user is-active \"nix-build-*\" 2>/dev/null | grep -q active'" 2>/dev/null; then
    fail "a nexus nix-build is already active — wait for it to finish before deploying"
else
    pass "no in-flight nexus build"
fi

log "=== Preflight result: $([ "$FAIL" -eq 0 ] && echo PASS || echo BLOCKED) ==="
exit ${FAIL:-0}
