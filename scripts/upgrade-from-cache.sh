#!/bin/bash
# upgrade-from-cache.sh - Deploy using cached binaries from build server
# Inspired by https://www.nijho.lt/post/nixos-cache/
#
# Usage: ./upgrade-from-cache.sh [hostname]
# Defaults to current hostname if not specified

set -euo pipefail

# Configuration
CACHE_HOST="${CACHE_HOST:-zephyr.tigris-ule.ts.net}"
CACHE_PORT="${CACHE_PORT:-50000}"
REV_DIR="${REV_DIR:-/var/lib/nix-auto-build}"
FLAKE_PATH="${FLAKE_PATH:-/etc/nixos}"

# Get hostname
HOSTNAME="${1:-$(hostname)}"

echo "[nix-cache] Deploying $HOSTNAME from cache server $CACHE_HOST"

# Get .rev file from shared nixos-share (Zephyr shares /etc/nixos with all nodes)
if [[ -f "$FLAKE_PATH/$HOSTNAME.rev" ]]; then
  REV_FILE="$FLAKE_PATH/$HOSTNAME.rev"
  echo "[nix-cache] Using shared .rev file: $REV_FILE"
elif [[ -f "$REV_DIR/$HOSTNAME.rev" ]]; then
  REV_FILE="$REV_DIR/$HOSTNAME.rev"
else
  echo "[nix-cache] No cached revision found, building locally..."
  REV_FILE=""
fi

# Read nixpkgs revision if available
if [[ -f "$REV_FILE" ]]; then
  NIXPKGS_REV=$(cat "$REV_FILE")
  echo "[nix-cache] Using nixpkgs revision: ${NIXPKGS_REV:0:8} ($NIXPKGS_REV)"

  # Deploy with cached binaries
  sudo nixos-rebuild switch \
    --flake "$FLAKE_PATH#$HOSTNAME" \
    --override-input nixpkgs "github:NixOS/nixpkgs/$NIXPKGS_REV" \
    --print-build-logs \
    --keep-going
else
  echo "[nix-cache] No cached revision found, building locally..."
  sudo nixos-rebuild switch \
    --flake "$FLAKE_PATH#$HOSTNAME" \
    --print-build-logs \
    --keep-going
fi

# Clean up temp file
if [[ "${REV_FILE:-/tmp/}" == "/tmp/"* ]]; then
  rm -f "$REV_FILE"
fi

echo "[nix-cache] Deployment complete!"
