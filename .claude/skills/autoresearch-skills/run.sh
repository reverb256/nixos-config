#!/usr/bin/env bash
# Autoresearch runner - enters nix-shell and executes autoresearch

set -euo pipefail

cd "$(dirname "$0")"

# Check if zai-api-key is deployed (Z.AI API key from agenix)
if [[ ! -f "/run/agenix/zai-api-key" ]]; then
    echo "❌ Error: Z.AI API key not found at /run/agenix/zai-api-key"
    echo ""
    echo "Required configuration:"
    echo "  1. Enable aiServices in your host's agenix-secrets-registry"
    echo "  2. Run 'just switch' to deploy the zai-api-key secret"
    echo ""
    echo "Example:"
    echo "  cd /etc/nixos"
    echo "  # Edit hosts/<hostname>/configuration.nix:"
    echo "  # services.agenix-secrets-registry.aiServices = true;"
    echo "  just switch"
    exit 1
fi

# Enter nix-shell and run autoresearch with passed arguments
exec nix-shell --run "python3 autoresearch.py $*"
