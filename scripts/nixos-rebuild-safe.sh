#!/usr/bin/env bash
# nixos-rebuild-safe.sh - Build with automatic mining pause
#
# Automatically stops mining services before build and restarts after.
# Usage: sudo nixos-rebuild-safe.sh switch --flake /etc/nixos#zephyr

set -euo pipefail

MINING_SERVICES=(
  "xmrig.service"
  "xmrig@*.service"
  "lolminer*.service"
)

# Function to check and stop mining services
stop_mining() {
  echo "🛑 Stopping mining services for build..."
  local stopped=0
  for svc in "${MINING_SERVICES[@]}"; do
    # Expand glob patterns to actual service names
    for unit in $(systemctl list-unit-files --all --no-legend | grep -E "^${svc//\./\\.}" | awk '{print $1}'); do
      if systemctl is-active --quiet "$unit"; then
        systemctl stop "$unit"
        echo "  Stopped: $unit"
        stopped=$((stopped + 1))
      fi
    done
  done
  if [ $stopped -eq 0 ]; then
    echo "  No active mining services found"
  fi
  echo "✅ Mining paused"
}

# Function to restart mining services
start_mining() {
  echo "▶️  Restarting mining services..."
  local started=0
  for svc in "${MINING_SERVICES[@]}"; do
    # Expand glob patterns to actual service names
    for unit in $(systemctl list-unit-files --all --no-legend | grep -E "^${svc//\./\\.}" | awk '{print $1}'); do
      # Only start if not already running
      if ! systemctl is-active --quiet "$unit"; then
        systemctl start "$unit" 2>/dev/null || true
        if systemctl is-active --quiet "$unit"; then
          echo "  Started: $unit"
          started=$((started + 1))
        fi
      fi
    done
  done
  if [ $started -eq 0 ]; then
    echo "  All mining services already running"
  fi
  echo "✅ Mining resumed"
}

# Trap to ensure mining restarts even on failure
trap start_mining EXIT

# Stop mining before build
stop_mining

# Run the actual nixos-rebuild command
# Note: --accept-flake-config allows nix to read git repo owned by another user
# when running with sudo. This is safe for single-user systems.
echo "🔨 Building: nixos-rebuild $*"
nixos-rebuild --accept-flake-config "$@"
BUILD_STATUS=$?

if [ $BUILD_STATUS -ne 0 ]; then
  echo "❌ Build failed (exit code: $BUILD_STATUS)"
  exit $BUILD_STATUS
fi

echo "✅ Build completed successfully"
