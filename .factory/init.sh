#!/usr/bin/env bash
# Mission init script - idempotent
set -euo pipefail

REPO_ROOT="/etc/nixos"

echo "[init] Checking flake validity..."
cd "$REPO_ROOT" && nix flake check --no-build 2>&1 | tail -3

echo "[init] Checking Kubernetes access..."
kubectl get nodes --no-headers 2>&1 | head -5

echo "[init] Checking git status..."
cd "$REPO_ROOT" && git status --short | head -5

echo "[init] Init complete"
