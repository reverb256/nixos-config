#!/usr/bin/env bash
# Gaming Detection Deployment Script

set -euo pipefail

echo "=== Gaming Detection Deployment ==="
echo ""

# Pre-deployment checks
echo "Step 1: Validating configuration..."
nix flake check

echo "Step 2: Deploying to all compute nodes..."
just deploy

echo "Step 3: Verifying services..."
for host in zephyr nexus forge; do
  echo "Checking $host..."
  ssh $host "systemctl is-active compute-workload-monitor" || echo "WARNING: compute-workload-monitor not active on $host"
  ssh $host "systemctl is-active lolminer-nvidia" || echo "WARNING: lolminer-nvidia not active on $host"
done

echo "Step 4: Verifying GameMode..."
for host in zephyr nexus forge; do
  echo "Checking $host..."
  ssh $host "which gamemoded" || echo "WARNING: GameMode not found on $host"
done

echo ""
echo "=== Deployment Complete ==="
echo "Next: Run integration tests per docs/testing/gamemode-integration-test.md"
