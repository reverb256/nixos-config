#!/usr/bin/env bash
# Mission init script - idempotent, fast
set -euo pipefail

REPO_ROOT="/etc/nixos"

echo "[init] Checking repo state..."
cd "$REPO_ROOT" && git status --short | head -5

echo "[init] Checking Kubernetes access..."
kubectl get nodes --no-headers 2>&1 | head -3 || echo "[init] WARNING: kubectl not available"

echo "[init] Init complete"
