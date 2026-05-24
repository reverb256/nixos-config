#!/usr/bin/env bash
set -euo pipefail

echo "Checking for contradictory claims..."

if grep -q "systemd.*llama-server" docs/LIVE/*.md docs/ARCHIVE/*.md 2>/dev/null && grep -q "K8s.*llama-server" docs/LIVE/*.md; then
  echo "CONTRADICTION: llama-server deployment model (systemd vs K8s)"
  exit 1
fi

echo "No major contradictions detected."
exit 0
