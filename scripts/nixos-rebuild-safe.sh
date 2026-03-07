#!/usr/bin/env bash
# nixos-rebuild-safe.sh - Build with automatic mining pause
#
# Automatically stops mining services before build and restarts after.
# Usage: sudo nixos-rebuild-safe.sh switch --flake .#zephyr

set -euo pipefail

MINING_SERVICES=(
  "xmrig@*"
  "lolminer-*"
)

# Function to check and stop mining services
stop_mining() {
  echo "🛑 Stopping mining services for build..."
  for svc in "${MINING_SERVICES[@]}"; do
    systemctl stop "$svc" 2>/dev/null || true
  done
  echo "✅ Mining paused"
}

# Function to restart mining services
start_mining() {
  echo "▶️  Restarting mining services..."
  for svc in "${MINING_SERVICES[@]}"; do
    # Find actual services matching the pattern
    systemctl list-units --all | grep -E "$svc" | \
      awk '{print $1}' | while read -r unit; do
      systemctl start "$unit" 2>/dev/null || true
    done
  done
  echo "✅ Mining resumed"
}

# Trap to ensure mining restarts even on failure
trap start_mining EXIT

# Stop mining before build
stop_mining

# Run the actual nixos-rebuild command
echo "🔨 Building: nixos-rebuild $*"
sudo nixos-rebuild "$@"
BUILD_STATUS=$?

if [ $BUILD_STATUS -ne 0 ]; then
  echo "❌ Build failed (exit code: $BUILD_STATUS)"
  exit $BUILD_STATUS
fi

echo "✅ Build completed successfully"
