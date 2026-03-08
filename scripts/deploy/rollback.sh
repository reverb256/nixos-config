#!/usr/bin/env bash
set -euo pipefail

HOST="${1:-$(hostname -s)}"
GENERATION="${2:-}"

if [ -z "$GENERATION" ]; then
    echo "Available generations:"
    sudo nixos-rebuild list-generations --profile /nix/var/nix/profiles/system | grep -E "^\s+[0-9]+" | tail -5
    echo ""
    echo "Usage: $0 [host] [generation-number]"
    exit 1
fi

if [ "$HOST" = "$(hostname -s)" ]; then
    echo "Rolling back local system to generation $GENERATION..."
    sudo nixos-rebuild switch --profile /nix/var/nix/profiles/system --switch-generation "$GENERATION"
else
    echo "Rolling back $HOST to generation $GENERATION..."
    ssh "$HOST" "sudo nixos-rebuild switch --profile /nix/var/nix/profiles/system --switch-generation $GENERATION"
fi

echo "✓ Rollback complete"
