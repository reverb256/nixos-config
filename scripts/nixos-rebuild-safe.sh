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

# Pause XMRig via HTTP API (faster than systemctl stop)
pause_xmrig() {
  if systemctl is-active --quiet xmrig.service; then
    if xmrig_api_available; then
      local token
      token="$(get_xmrig_token)"
      echo "  ⏸️  Pausing XMRig via API..."
      # Use JSON-RPC pause method
      curl -sf -X POST "http://${XMRIG_API_HOST}:${XMRIG_API_PORT}/json_rpc" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -d '{"id":1,"jsonrpc":"2.0","method":"pause"}' >/dev/null 2>&1
      echo "  ✅ XMRig paused"
      return 0
    else
      # Fallback to systemctl if API unavailable
      echo "  Stopping XMRig service (API unavailable)..."
      systemctl stop xmrig.service
      echo "  ✅ XMRig stopped"
      return 0
    fi
  fi
  return 1
}

# Resume XMRig via HTTP API (faster than systemctl start)
resume_xmrig() {
  if systemctl is-active --quiet xmrig.service; then
    if xmrig_api_available; then
      local token
      token="$(get_xmrig_token)"
      echo "  ▶️  Resuming XMRig via API..."
      # Use JSON-RPC resume method
      curl -sf -X POST "http://${XMRIG_API_HOST}:${XMRIG_API_PORT}/json_rpc" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -d '{"id":1,"jsonrpc":"2.0","method":"resume"}' >/dev/null 2>&1
      echo "  ✅ XMRig resumed"
      return 0
    fi
  else
    # Service not running, start it
    echo "  Starting XMRig service..."
    systemctl start xmrig.service 2>/dev/null || true
    sleep 2
    if systemctl is-active --quiet xmrig.service; then
      echo "  ✅ XMRig started"
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

# Function to pause mining services
stop_mining() {
  echo "🛑 Pausing mining services for build..."
  local paused=0

  # Pause XMRig
  pause_xmrig && paused=$((paused + 1))

  # Stop lolMiner (no API available, use systemctl)
  stop_lolminer && paused=$((paused + 1))

  if [ $paused -eq 0 ]; then
    echo "  No active mining services found"
  fi
  echo "✅ Mining paused"
}

# Function to resume mining services
start_mining() {
  echo "▶️  Resuming mining services..."
  local resumed=0

  # Resume XMRig
  resume_xmrig && resumed=$((resumed + 1))

  # Start lolMiner
  start_lolminer && resumed=$((resumed + 1))

  if [ $resumed -eq 0 ]; then
    echo "  All mining services already running"
  fi
  echo "✅ Mining resumed"
}

# Trap to ensure mining restarts even on failure
trap start_mining EXIT

# Check for stuck nix processes before building
# NOTE: DO NOT use pkill - it can kill the Plasma session
# Only warn if processes exist, let user handle manually
echo "🔍 Checking for stuck nix processes..."
STUCK_PROCS=$(pgrep -f "nixos-rebuild|nix-build" || true)
if [ -n "$STUCK_PROCS" ]; then
  echo "⚠️  Found stuck nix processes (will not auto-kill to avoid breaking session):"
  ps -p $STUCK_PROCS -o pid,cmd 2>/dev/null || true
  echo "💡 Run manually if needed: sudo pkill -9 -f 'nixos-rebuild|nix-build'"
  echo "⏸️  Waiting 5 seconds for locks to clear..."
  sleep 5
fi

# Stop mining before build
stop_mining

# Run the actual nixos-rebuild command
# Note: --accept-flake-config allows nix to read git repo owned by another user
# when running with sudo. This is safe for single-user systems.
# --print-build-logs shows full build output
# --keep-going shows all errors instead of stopping at first
# -v shows verbose output for debugging
echo "🔨 Building: nixos-rebuild $*"
echo "💡 If build hangs, press Ctrl+C and check: sudo lsof | grep nix"
nixos-rebuild --accept-flake-config -v --print-build-logs "$@"
BUILD_STATUS=$?

if [ $BUILD_STATUS -ne 0 ]; then
  echo "❌ Build failed (exit code: $BUILD_STATUS)"
  exit $BUILD_STATUS
fi

echo "✅ Build completed successfully"
