#!/usr/bin/env bash
# remote-build.sh — Idempotent detached build on nexus via systemd-run
#
# PIPELINE INTEGRITY (why this script exists in this shape):
#   nexus is ONLY a build executor. The authoritative source is zephyr's
#   /etc/nixos (which tracks origin/main). Historically the build ran against
#   nexus's LOCAL /etc/nixos checkout, which could drift (uncommitted edits,
#   stale origin/main ref) and silently produce a toplevel that did NOT match
#   the source of truth. To eliminate that class of bug, this script
#   force-syncs nexus's /etc/nixos to the requested ref (default origin/main)
#   BEFORE building. The artifact always reflects the canonical commit.
#
# Usage:  remote-build.sh <target-host> <build-tag> [ref=origin/main]
#   target-host  = flake host attribute (e.g. 'zephyr')
#   build-tag    = unique tag for sentinel files (e.g. 'zephyr-switch')
#   ref          = git ref to build from (default origin/main). nexus is
#                  force-synced to this ref before building.
#
# Output: prints store path on stdout, exit 0
#         prints error messages on stderr, exit 1

set -euo pipefail

TARGET="${1:?Usage: remote-build.sh <target-host> <build-tag> [ref]}"
TAG="${2:?Usage: remote-build.sh <target-host> <build-tag> [ref]}"
REF="${3:-origin/main}"
NEXUS="nexus"

# Sanitize ref for safe use in filenames (slashes/colons -> dashes)
REF_SLUG=$(echo "$REF" | tr '/:' '--')

SERVICE="nix-build-${TAG}"
STORE_PATH_FILE="/tmp/${TAG}-${REF_SLUG}-store-path"
PID_FILE="/tmp/${TAG}-${REF_SLUG}-pid"

# ── Step 1: Kill orphaned builds ──
cleanup_orphans() {
    [ -f "$PID_FILE" ] && { kill "$(cat "$PID_FILE")" 2>/dev/null || true; }
    ssh "$NEXUS" "systemctl --user stop ${SERVICE}.service 2>/dev/null; systemctl --user reset-failed ${SERVICE}.service 2>/dev/null; exit 0" 2>/dev/null || true
    ssh "$NEXUS" "pkill -f 'nix.*realise.*${TARGET}' 2>/dev/null; pkill -f 'nix.*build.*${TARGET}' 2>/dev/null; exit 0" 2>/dev/null || true
    rm -f "$STORE_PATH_FILE" "$PID_FILE"
}

# ── Step 2: Check if build already complete (scoped to THIS ref) ──
check_cached() {
    [ -f "$STORE_PATH_FILE" ] || return 1
    local cached
    cached=$(< "$STORE_PATH_FILE")
    ssh "$NEXUS" "nix path-info '$cached' >/dev/null 2>&1" || return 1
    echo "$cached"
    return 0
}

# ── Step 2b: Force-sync nexus /etc/nixos to the build ref (PIPELINE INTEGRITY) ──
# nexus is a build cache only; never trust its local edits. Pull the canonical
# ref and hard-reset to it so the build can't reflect drift.
sync_builder() {
    echo >&2 "  syncing nexus /etc/nixos -> $REF (builder must match source of truth)..."
    ssh "$NEXUS" "bash --norc --noprofile -c 'set -e; cd /etc/nixos; git fetch origin \"$REF\" 2>&1 | tail -1; git reset --hard \"$REF\" 2>&1 | tail -2; echo \"  nexus /etc/nixos now at \$(git rev-parse --short HEAD)\"'"
}

# ── Step 3: Start build via systemd-run (detached, survives SSH drop) ──
start_build() {
    echo >&2 "  starting detached build on nexus (service: $SERVICE)..."
    cleanup_sentinels
    sync_builder
    # Build the toplevel for TARGET from the (now synced) nexus checkout.
    # INNER is expanded locally so $REF/$TARGET/$STORE_PATH_FILE/$TAG are concrete.
    INNER="git -C /etc/nixos reset --hard ${REF} >/dev/null 2>&1; nix build --no-link --print-out-paths .#nixosConfigurations.${TARGET}.config.system.build.toplevel > ${STORE_PATH_FILE} 2>/tmp/${TAG}-build-log"
    ssh "$NEXUS" "systemd-run --user --unit=${SERVICE} --no-block --same-dir --working-directory=/etc/nixos -- bash -c $(printf '%q' "$INNER")"
}

# ── Step 4: Poll for completion ──
poll_build() {
    echo -n >&2 "  building"
    local START
    START=$(date +%s)
    local ACTIVE

    while true; do
        ACTIVE=$(ssh "$NEXUS" "systemctl --user is-active ${SERVICE}.service 2>/dev/null || echo inactive")

        if [ "$ACTIVE" != "active" ]; then
            sleep 2

            local RESULT
            RESULT=$(ssh "$NEXUS" "systemctl --user is-failed ${SERVICE}.service 2>/dev/null || echo inactive")

            local OUT
            OUT=$(ssh "$NEXUS" "cat $STORE_PATH_FILE 2>/dev/null || echo ''")

            if [ -n "$OUT" ] && ssh "$NEXUS" "nix path-info '$OUT' >/dev/null 2>&1"; then
                local ELAPSED
                ELAPSED=$(( $(date +%s) - START ))
                echo >&2 " done (${ELAPSED}s)"
                echo "$OUT" > "$STORE_PATH_FILE"
                echo "$OUT"
                return 0
            else
                echo >&2 ""
                if [ "$RESULT" = "failed" ]; then
                    echo "Build failed for $TARGET (service failed). Last log lines:" >&2
                else
                    echo "Build failed for $TARGET. Last log lines:" >&2
                fi
                ssh "$NEXUS" "tail -10 /tmp/${TAG}-build-log 2>/dev/null" >&2 || echo "  (no log)" >&2
                return 1
            fi
        fi

        local ELAPSED
        ELAPSED=$(( $(date +%s) - START ))
        if [ $(( ELAPSED % 30 )) -eq 0 ] && [ "$ELAPSED" -gt 0 ]; then
            local PROGRESS
            PROGRESS=$(ssh "$NEXUS" "tail -5 /tmp/${TAG}-build-log 2>/dev/null | grep -oE 'copying path.*from.*|building.*|[0-9]+%|checked.*|error.*' | tail -1 || echo ''")
            [ -n "$PROGRESS" ] && echo >&2 " [$PROGRESS]"
        fi
        echo -n >&2 "."
        sleep 5
    done
}

# ── Step 5: Cleanup ──
cleanup_sentinels() {
    rm -f "$STORE_PATH_FILE" "$PID_FILE"
}

# ── Main ──
cleanup_orphans

if CACHED=$(check_cached); then
    echo "  build already complete for $REF: $CACHED" >&2
    echo "$CACHED"
    exit 0
fi

start_build
if ! poll_build; then
    exit 1
fi
