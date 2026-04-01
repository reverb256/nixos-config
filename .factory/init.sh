#!/usr/bin/env bash
# Mission init script - idempotent setup for GPU workload consolidation
# No services to start (NixOS config editing mission)
set -euo pipefail

cd /etc/nixos

# Ensure new module directory exists
mkdir -p modules/gpu-workload

# Ensure .factory directories exist
mkdir -p .factory/skills
mkdir -p .factory/library

echo "Init complete: modules/gpu-workload/ ready"
