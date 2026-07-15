#!/usr/bin/env bash
# remote-build.sh — Idempotent detached build on nexus via systemd-run
#
# Uses systemd-run to run the build as a transient user service on nexus,
# surviving SSH disconnection. Polls via systemctl for completion.
#
# Usage:  remote-build.sh <target-host> <build-tag>
#   target-host  = flake host attribute (e.g. 'zephyr')
#   build-tag    = unique tag for sentinel files (e.g. 'zephyr-switch')
#
# Output: prints store path on stdout, exit 0
#         prints error messages on stderr, exit 1

set -euo pipefail

TARGET="${1:?Usage: remote-build.sh <target-host> <build-tag>}"
TAG="${2:?Usage: remote-build.sh <target-host> <build-tag>}"
NEXUS="nexus"

SERVICE="nix-build-${TAG}"
STORE_PATH_FILE="/tmp/${TAG}-store-path"
PID_FILE="/tmp/${TAG}-pid"

# ── Step 1: Kill orphaned builds ──
cleanup_orphans() {
    # Kill by stored PID if exists
    [ -f "$PID_FILE" ] && { kill "$(cat "$PID_FILE")" 2>/dev/null || true; }
    # Stop any leftover systemd service with this tag
    ssh "$NEXUS" "systemctl --user stop ${SERVICE}.service 2>/dev/null; systemctl --user reset-failed ${SERVICE}.service 2>/dev/null; exit 0" 2>/dev/null || true
    # Kill old nix processes for this target
    ssh "$NEXUS" "pkill -f 'nix.*realise.*${TARGET}' 2>/dev/null; pkill -f 'nix.*build.*${TARGET}' 2>/dev/null; exit 0" 2>/dev/null || true
    rm -f "$STORE_PATH_FILE" "$PID_FILE"
}

# ── Step 2: Check if build already complete ──
check_cached() {
    [ -f "$STORE_PATH_FILE" ] || return 1
    local cached
    cached=$(< "$STORE_PATH_FILE")
    ssh "$NEXUS" "nix path-info '$cached' >/dev/null 2>&1" || return 1
    echo "$cached"
    return 0
}

# ── Step 3: Start build via systemd-run (detached, survives SSH drop) ──
start_build() {
    echo "  starting detached build on nexus (service: $SERVICE)..."
    cleanup_sentinels
    # systemd-run --user --no-block starts the service and returns immediately.
    # The service runs: nix build ... with output captured.
    ssh "$NEXUS" "systemd-run --user --unit=${SERVICE} --no-block --same-dir --working-directory=/etc/nixos -- \
      bash -c 'nix build --no-link --print-out-paths .#nixosConfigurations.${TARGET}.config.system.build.toplevel > ${STORE_PATH_FILE} 2>/tmp/${TAG}-build-log'"
}

# ── Step 4: Poll for completion ──
poll_build() {
    echo -n "  building"
    local START
    START=$(date +%s)
    local ACTIVE

    while true; do
        ACTIVE=$(ssh "$NEXUS" "systemctl --user is-active ${SERVICE}.service 2>/dev/null || echo inactive")
        
        if [ "$ACTIVE" != "active" ]; then
            # Let files flush
            sleep 2
            
            # Check result
            local RESULT
            RESULT=$(ssh "$NEXUS" "systemctl --user is-failed ${SERVICE}.service 2>/dev/null || echo inactive")
            
            local OUT
            OUT=$(ssh "$NEXUS" "cat $STORE_PATH_FILE 2>/dev/null || echo ''")
            
            if [ -n "$OUT" ] && ssh "$NEXUS" "nix path-info '$OUT' >/dev/null 2>&1"; then
                local ELAPSED
                ELAPSED=$(( $(date +%s) - START ))
                echo " done (${ELAPSED}s)"
                echo "$OUT" > "$STORE_PATH_FILE"
                echo "$OUT"
                return 0
            else
                echo ""
                if [ "$RESULT" = "failed" ]; then
                    echo "Build failed for $TARGET (service failed). Last log lines:" >&2
                else
                    echo "Build failed for $TARGET. Last log lines:" >&2
                fi
                ssh "$NEXUS" "tail -10 /tmp/${TAG}-build-log 2>/dev/null" >&2 || echo "  (no log)" >&2
                return 1
            fi
        fi
        
        # Progress every 30s
        local ELAPSED
        ELAPSED=$(( $(date +%s) - START ))
        if [ $(( ELAPSED % 30 )) -eq 0 ] && [ "$ELAPSED" -gt 0 ]; then
            # Show progress from log
            local PROGRESS
            PROGRESS=$(ssh "$NEXUS" "tail -5 /tmp/${TAG}-build-log 2>/dev/null | grep -oE 'copying path.*from.*|building.*|[0-9]+%|checked.*|error.*' | tail -1 || echo ''")
            [ -n "$PROGRESS" ] && echo " [$PROGRESS]"
        fi
        echo -n "."
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
    echo "  build already complete: $CACHED" >&2
    echo "$CACHED"
    exit 0
fi

start_build
if ! poll_build; then
    exit 1
fi
