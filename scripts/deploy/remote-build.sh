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
    # Materialize a small remote script instead of nesting shell quoting inside
    # systemd-run. The old `printf %q` + `bash -c` chain was re-parsed by SSH
    # and systemd, collapsing spaces (`set-e;cd/...`) and handing the command
    # to the user's fish shell as one invalid token.
    local FETCH_REF
    FETCH_REF="${REF#origin/}"
    local REMOTE_SCRIPT
    REMOTE_SCRIPT=$(cat <<EOF
#!/usr/bin/env bash
set -euo pipefail
exec 9>/tmp/nixos-build-farm.lock
flock -n 9 || { echo "build farm lock is busy" >&2; exit 75; }
cd /etc/nixos
# colmena apply-local --sudo evaluates the flake as root and can create
# root-owned files in the flake dir (flake.lock, .git objects), which breaks
# the NEXT build/fetch (insufficient permission). Normalize before fetching.
REPO_OWNER="$(stat -c %U .)"
REPO_GROUP="$(stat -c %G .)"
if [[ -n "$REPO_OWNER" ]] && [[ "$(find . -not -user "$REPO_OWNER" 2>/dev/null | head -1)" ]]; then
  sudo chown -R "$REPO_OWNER":"$REPO_GROUP" . 2>/dev/null || true
fi
git fetch origin $(printf '%q' "$FETCH_REF") >/dev/null 2>&1
git reset --hard FETCH_HEAD >/dev/null 2>&1
nix build --no-link --fallback --option http2 false --option http-connections 16 --option connect-timeout 10 --option download-attempts 10 --print-out-paths .#nixosConfigurations.${TARGET}.config.system.build.toplevel >$(printf '%q' "$STORE_PATH_FILE") 2>$(printf '%q' "/tmp/${TAG}-build-log")
EOF
    )
    local REMOTE_SCRIPT_FILE="/tmp/${SERVICE}.sh"
    local PAYLOAD
    PAYLOAD=$(printf '%s' "$REMOTE_SCRIPT" | base64 -w0)
    ssh "$NEXUS" "printf '%s' '$PAYLOAD' | base64 -d > '$REMOTE_SCRIPT_FILE' && chmod 700 '$REMOTE_SCRIPT_FILE' && systemd-run --user --unit='${SERVICE}' --no-block --same-dir --working-directory=/etc/nixos /run/current-system/sw/bin/bash '$REMOTE_SCRIPT_FILE'"
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
