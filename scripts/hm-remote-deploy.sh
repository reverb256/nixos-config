#!/usr/bin/env bash
# Remote half of `just hm-deploy`: runs on the TARGET host, fed via stdin
# (`ssh host "GEN=<store-path> bash -s" < scripts/hm-remote-deploy.sh`).
#
# Sets the home-manager profile to $GEN and activates it. Standalone HM
# activation aborts when a managed file collides with a differing plain file;
# this helper backs those up to <file>.pre-hm-backup and retries — the same
# collision handling as `home-manager switch -b backup`, minus the flake fetch
# (remote hosts cannot reach the private home-manager-config repo, which is
# why deployment goes through nix-copy-closure + direct activation).
set -euo pipefail

[ -n "${GEN:-}" ] || { echo "hm-remote-deploy: GEN env required" >&2; exit 2; }
[ -d "$GEN" ] || { echo "hm-remote-deploy: $GEN missing on this host (run nix-copy-closure first)" >&2; exit 2; }

nix-env -p "$HOME/.local/state/nix/profiles/home-manager" --set "$GEN"

LOG=$(mktemp)
trap 'rm -f "$LOG"' EXIT
if ! "$GEN/activate" >"$LOG" 2>&1; then
    if grep -qE "would be clobbered|in the way" "$LOG"; then
        echo ">> backing up conflicting files and re-activating" >&2
        grep -E "would be clobbered|in the way" "$LOG" \
            | grep -v "will be skipped since they are the same" \
            | grep -oE "'[^']+'" | tr -d "'" | sort -u \
            | while read -r f; do
                [ -e "$f" ] && mv "$f" "$f.pre-hm-backup" && echo "  backed up: $f" >&2
            done
        "$GEN/activate"
    else
        cat "$LOG" >&2
        exit 1
    fi
fi
echo ">> activated: $(readlink "$HOME/.local/state/nix/profiles/home-manager")"
