#!/usr/bin/env bash
# auto-update-appimages.sh — Check and update Stability Matrix + LM Studio AppImage packages
# Runs as a systemd timer. Only rebuilds when versions change.
set -euo pipefail

NIXOS="/etc/nixos"
SM_FILE="$NIXOS/modules/services/stability-matrix.nix"
LM_FILE="$NIXOS/packages/lmstudio.nix"
LOG_TAG="appimage-updater"

log() { logger -t "$LOG_TAG" "$1"; echo "[$(date -Iseconds)] $1"; }

needs_rebuild=false
sm_updated=false
lm_updated=false
sm_ver=""
lm_ver=""

cd "$NIXOS"

# ── Stability Matrix (GitHub releases, fetchzip) ──
log "Checking Stability Matrix..."
current_sm=$(grep -oP 'version = "\K[^"]+' "$SM_FILE")
latest_sm=$(curl -sf https://api.github.com/repos/LykosAI/StabilityMatrix/releases/latest \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['tag_name'].lstrip('v'))" 2>/dev/null || true)

if [ -z "$latest_sm" ]; then
    log "SM: Failed to fetch latest version from GitHub API"
elif [ "$current_sm" = "$latest_sm" ]; then
    log "SM: Already on $current_sm"
else
    log "SM: $current_sm -> $latest_sm — fetching correct hash..."
    sed -i "s/version = \"${current_sm}\"/version = \"${latest_sm}\"/" "$SM_FILE"

    # fetchzip strips top-level dir — nix-prefetch-url --unpack doesn't match.
    # Build with empty hash to get the correct one from error output.
    url="https://github.com/LykosAI/StabilityMatrix/releases/download/v${latest_sm}/StabilityMatrix-linux-x64.zip"
    hash_output=$(nix-build --option builders '' --no-out-link -E "
      with import <nixpkgs> {};
      fetchzip { url = \"$url\"; sha256 = \"\"; }
    " 2>&1 || true)

    new_hash=$(echo "$hash_output" | grep -oP 'got:\s+sha256-[A-Za-z0-9+/=]+' | grep -oP 'sha256-[A-Za-z0-9+/=]+' || true)

    if [ -n "$new_hash" ]; then
        sed -i "s|sha256 = \"sha256-[^\"]*\"|sha256 = \"${new_hash}\"|" "$SM_FILE"
        sm_updated=true
        sm_ver="$latest_sm"
        needs_rebuild=true
        log "SM: Updated to $latest_sm ($new_hash)"
    else
        log "SM: Could not determine correct hash — reverting"
        git checkout -- "$SM_FILE"
    fi
fi

# ── LM Studio (CDN redirect, fetchurl) ──
log "Checking LM Studio..."
current_lm=$(grep -oP 'version = "\K[^"]+' "$LM_FILE")
latest_lm=$(curl -sIL "https://lmstudio.ai/download/latest/linux/x64" 2>/dev/null \
  | grep -i "^location:" | head -1 | grep -oP '\d+\.\d+\.\d+-\d+' || true)

if [ -z "$latest_lm" ]; then
    log "LM Studio: Failed to fetch latest version from CDN"
elif [ "$current_lm" = "$latest_lm" ]; then
    log "LM Studio: Already on $current_lm"
else
    log "LM Studio: $current_lm -> $latest_lm — fetching hash..."
    sed -i "s/version = \"${current_lm}\"/version = \"${latest_lm}\"/" "$LM_FILE"

    url="https://installers.lmstudio.ai/linux/x64/${latest_lm}/LM-Studio-${latest_lm}-x64.AppImage"
    nix_hash=$(nix-prefetch-url "$url" 2>/dev/null || true)

    if [ -n "$nix_hash" ]; then
        sri_hash=$(nix hash convert --hash-algo sha256 --to sri "$nix_hash")
        sed -i "s|sha256 = \"sha256-[^\"]*\"|sha256 = \"${sri_hash}\"|" "$LM_FILE"
        lm_updated=true
        lm_ver="$latest_lm"
        needs_rebuild=true
        log "LM Studio: Updated to $latest_lm ($sri_hash)"
    else
        log "LM Studio: Could not prefetch hash — reverting"
        git checkout -- "$LM_FILE"
    fi
fi

# ── Rebuild if anything changed ──
if [ "$needs_rebuild" = true ]; then
    commit_parts=()
    [ "$sm_updated" = true ] && commit_parts+=("SM $sm_ver")
    [ "$lm_updated" = true ] && commit_parts+=("LM Studio $lm_ver")
    commit_msg="auto-update: ${commit_parts[*]}"

    log "Committing and rebuilding: $commit_msg"
    git add "$SM_FILE" "$LM_FILE"
    git commit -m "$commit_msg"

    if nixos-rebuild switch --option builders '' 2>&1 | logger -t "$LOG_TAG"; then
        log "Rebuild succeeded"
    else
        log "Rebuild FAILED — check journalctl"
        exit 1
    fi
else
    log "No updates needed"
fi
