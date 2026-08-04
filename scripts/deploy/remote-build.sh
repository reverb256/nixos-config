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
    # Only manage this helper's own tagged service. Never use a broad pkill:
    # another independently monitored build for the same target may be valid.
    ssh "$NEXUS" "systemctl --user stop ${SERVICE}.service 2>/dev/null; systemctl --user reset-failed ${SERVICE}.service 2>/dev/null; rm -f '$STORE_PATH_FILE' '$PID_FILE'; exit 0" 2>/dev/null || true
    rm -f "$STORE_PATH_FILE" "$PID_FILE"
}

# ── Step 2: Check if build already complete (scoped to THIS ref) ──
check_cached() {
    [ -f "$STORE_PATH_FILE" ] || return 1
    local cached
    cached=$(< "$STORE_PATH_FILE")
    [[ "$cached" == *"nixos-system-${TARGET}-"* ]] || return 1
    ssh "$NEXUS" "nix path-info '$cached' >/dev/null 2>&1" || return 1
    echo "$cached"
    return 0
}

# ── Step 3: Start build via systemd-run (detached, survives SSH drop) ──
start_build() {
    echo >&2 "  starting detached build on nexus (service: $SERVICE)..."
    cleanup_sentinels
    # Clear the remote sentinel too. A valid path from an earlier run must
    # never be accepted as the result of this build attempt.
    ssh "$NEXUS" "rm -f '$STORE_PATH_FILE' '$PID_FILE'" 2>/dev/null || true
    # Hold one Nexus-wide lock across source sync + evaluation/build. The
    # builder checkout is shared, so concurrent tags must not reset it under
    # another build. A busy lock makes this tagged service fail cleanly.
    # Transport options (http2=false, http-connections, connect-timeout,
    # download-attempts) are set declaratively in distributed-builds.nix and
    # picked up from /etc/nix/nix.conf — no need to duplicate them here.
    # (Removed 2026-08-04 audit: duplicate CLI flags; keep in sync if the
    # builder host has not yet been rebuilt with the declarative settings.)
    BUILD_COMMAND="set -e; cd /etc/nixos; git fetch origin \"${REF}\" >/dev/null 2>&1; git reset --hard \"${REF}\" >/dev/null 2>&1; nix build --no-link --fallback --print-out-paths .#nixosConfigurations.${TARGET}.config.system.build.toplevel > ${STORE_PATH_FILE} 2>/tmp/${TAG}-build-log"
    INNER="flock -n 9 -c $(printf '%q' \"$BUILD_COMMAND\") 9>/tmp/nixos-build-farm.lock"
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
            RESULT=$(ssh "$NEXUS" "systemctl --user show ${SERVICE}.service -p Result --value 2>/dev/null || echo failed")

            local OUT
            OUT=$(ssh "$NEXUS" "cat $STORE_PATH_FILE 2>/dev/null || echo ''")

            if [ "$RESULT" = "success" ] \
                && [[ "$OUT" == *"nixos-system-${TARGET}-"* ]] \
                && ssh "$NEXUS" "nix path-info '$OUT' >/dev/null 2>&1"; then
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
