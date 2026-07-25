#!/usr/bin/env bash
# Safe wrapper for nix flake checks with mandatory RAM verification

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLAKE_PATH="${1:-/etc/nixos}"

# Run mandatory RAM check
if ! "$SCRIPT_DIR/hermes-ram-check.sh"; then
    exit_code=$?
    if [ $exit_code -eq 1 ]; then
        echo ""
        echo "Operation aborted due to insufficient memory."
        echo "Please free up RAM before running flake checks."
        exit 1
    fi
    # exit_code 2 = warning, proceed anyway
fi

# Run the actual flake check
echo ""
echo "Running: nix flake check $FLAKE_PATH"
nix flake check "$FLAKE_PATH" "${@:2}"
