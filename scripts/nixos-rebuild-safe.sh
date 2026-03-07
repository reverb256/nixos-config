#!/usr/bin/env bash
# nixos-rebuild-safe.sh - Build with automatic mining pause
#
# Automatically stops mining services before build and restarts after.
# Uses API health checks where available (xmrig), systemctl for control.
# Usage: sudo nixos-rebuild-safe.sh switch --flake /etc/nixos#zephyr

set -euo pipefail

# XMRig HTTP API configuration
XMRIG_API_HOST="${XMRIG_API_HOST:-127.0.0.1}"
XMRIG_API_PORT="${XMRIG_API_PORT:-8081}"
XMRIG_TOKEN_FILE="${XMRIG_TOKEN_FILE:-/run/agenix/xmrig-api-token}"

# Read XMRig API token from file
get_xmrig_token() {
  if [ -r "$XMRIG_TOKEN_FILE" ]; then
    cat "$XMRIG_TOKEN_FILE"
  else
    echo ""
  fi
}

# Check if XMRig API is responsive (health check)
xmrig_api_available() {
  local token
  token="$(get_xmrig_token)"
  [ -n "$token" ] || return 1

  # Try to get summary - XMRig API uses /1/summary path format
  # and requires Bearer token authentication
  curl -sf "http://${XMRIG_API_HOST}:${XMRIG_API_PORT}/1/summary" \
    -H "Authorization: Bearer $token" \
    >/dev/null 2>&1
}

# Stop XMRig service via systemctl
stop_xmrig() {
  if systemctl is-active --quiet xmrig.service; then
    # Optional: health check before stopping
    if xmrig_api_available; then
      echo "  📡 XMRig API healthy - stopping service..."
    else
      echo "  Stopping XMRig service..."
    fi
    systemctl stop xmrig.service
    echo "  ✅ XMRig stopped"
    return 0
  fi
  return 1
}

# Start XMRig service via systemctl
start_xmrig() {
  if ! systemctl is-active --quiet xmrig.service; then
    echo "  Starting XMRig service..."
    systemctl start xmrig.service 2>/dev/null || true

    # Wait briefly and verify
    sleep 2
    if systemctl is-active --quiet xmrig.service; then
      # Verify API is responsive if token is available
      if xmrig_api_available; then
        echo "  ✅ XMRig started (API verified)"
      else
        echo "  ✅ XMRig started"
      fi
      return 0
    fi
  fi
  return 1
}

# Stop lolMiner services via systemctl
stop_lolminer() {
  local stopped=0
  for unit in lolminer-nvidia.service lolminer-amd.service; do
    if systemctl list-unit-files | grep -q "^${unit}"; then
      if systemctl is-active --quiet "$unit"; then
        systemctl stop "$unit"
        echo "  Stopped: $unit"
        stopped=$((stopped + 1))
      fi
    fi
  done
  return $stopped
}

# Start lolMiner services via systemctl
start_lolminer() {
  local started=0
  for unit in lolminer-nvidia.service lolminer-amd.service; do
    if systemctl list-unit-files | grep -q "^${unit}"; then
      if ! systemctl is-active --quiet "$unit"; then
        systemctl start "$unit" 2>/dev/null || true
        if systemctl is-active --quiet "$unit"; then
          echo "  Started: $unit"
          started=$((started + 1))
        fi
      fi
    fi
  done
  return $started
}

# Function to check and stop mining services
stop_mining() {
  echo "🛑 Stopping mining services for build..."
  local stopped=0

  # Stop XMRig
  stop_xmrig && stopped=$((stopped + 1))

  # Stop lolMiner
  stop_lolminer && stopped=$((stopped + 1))

  if [ $stopped -eq 0 ]; then
    echo "  No active mining services found"
  fi
  echo "✅ Mining paused"
}

# Function to restart mining services
start_mining() {
  echo "▶️  Restarting mining services..."
  local started=0

  # Start XMRig
  start_xmrig && started=$((started + 1))

  # Start lolMiner
  start_lolminer && started=$((started + 1))

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
