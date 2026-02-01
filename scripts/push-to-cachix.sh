#!/usr/bin/env bash
set -e

RESULT="${1:-./result}"
CACHE_NAME="reverb-os"
TOKEN_FILE="/run/agenix/cachix-token"

if [ ! -d "$RESULT" ]; then
    echo "Error: $RESULT not found. Build something first with 'nix build .#<package>'"
    exit 1
fi

if [ ! -f "$TOKEN_FILE" ]; then
    echo "Error: Cachix token not available at $TOKEN_FILE"
    echo "Make sure agenix secrets are loaded"
    exit 1
fi

echo "Pushing $RESULT to cachix $CACHE_NAME..."

CACHIX_TOKEN=$(cat "$TOKEN_FILE")

nix-shell -p cachix --run "
  echo '$CACHIX_TOKEN' | cachix authtoken --stdin
  cachix push $CACHE_NAME $RESULT
"

echo "✓ Successfully pushed to https://$CACHE_NAME.cachix.org"
