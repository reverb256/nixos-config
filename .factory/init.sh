#!/usr/bin/env bash
# Mission init script - idempotent
set -euo pipefail

REPO_ROOT="/etc/nixos"
GATEWAY_DIR="$REPO_ROOT/modules/services/ai-inference/ai_inference_gateway"

echo "[init] Checking ZAI API key availability..."
if [ -f /run/agenix/zai-api-key ]; then
  echo "[init] ZAI API key available at /run/agenix/zai-api-key"
else
  echo "[init] WARNING: ZAI API key not decrypted. Some features may not work."
fi

echo "[init] Checking gateway test environment..."
if [ -f "$GATEWAY_DIR/shell.nix" ]; then
  echo "[init] Gateway shell.nix found"
else
  echo "[init] WARNING: Gateway shell.nix not found"
fi

echo "[init] Checking git status..."
cd "$REPO_ROOT" && git status --short | head -5

echo "[init] Init complete"
