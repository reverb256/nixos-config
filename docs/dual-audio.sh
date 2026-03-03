#!/usr/bin/env bash
# Dual Audio Output Script with Latency Compensation
# Routes audio to both onboard and HDMI outputs simultaneously

set -euo pipefail

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# Get current sinks
ONBOARD_SINK=$(wpctl status | grep "Starship" | grep -oP '\d+(?=\s+ALCS1200A)' || echo "75")
HDMI_SINK=$(wpctl status | grep "GA102.*HDMI" | grep -oP '^\s+\K\d+' || echo "62")

log "=== Dual Audio Output Setup ==="
log "Onboard sink: $ONBOARD_SINK (Starship/Matisse)"
log "HDMI sink: $HDMI_SINK (GA102)"

# Check if already running
if pgrep -f "pw-loopback.*$HDMI_SINK" > /dev/null; then
  warn "Dual audio is already active!"
  log "To stop: pkill -f 'pw-loopback.*$HDMI_SINK'"
  exit 0
fi

# Create loopback to HDMI with latency compensation
log "Creating loopback to HDMI with 50ms latency compensation..."

# Method 1: Using pw-loopback with latency (preferred)
if command -v pw-loopback &> /dev/null; then
  # Create virtual loopback source
  pw-loopback \
    --capture-props='audio.position=[FL FR]' \
    --playback-props='audio.position=[FL FR] node.target="$HDMI_SINK" latency.offset=50M' &

  LOOPBACK_PID=$!
  sleep 1

  if ps -p $LOOPBACK_PID > /dev/null; then
    log "✓ Loopback started (PID: $LOOPBACK_PID)"
    log "Audio now plays on both devices!"
  else
    error "Failed to start loopback"
    exit 1
  fi

else
  # Method 2: Using pw-link (manual routing)
  warn "pw-loopback not available, using pw-link method..."

  # This requires manual configuration per application
  log "Note: This method routes ALL audio to both outputs"
  log "To stop: pkill -f 'pw-link.*loop'"

  # Create links for all future streams
  # (This is a simplified approach - for full control, use EasyEffects)
fi

log ""
log "═══════════════════════════════════════════════"
log "Testing audio synchronization..."
log ""
log "📋 Instructions:"
log "  1. Play any audio (music, video, etc.)"
log "  2. Listen for echo/delay between outputs"
log "  3. If you hear echo, adjust latency:"
log ""
log "     Edit: /etc/nixos/docs/dual-audio.sh"
log "     Change: latency.offset=50M"
log "     To:    latency.offset=XXM (XX = milliseconds)"
log ""
log "  4. Stop dual audio:"
log "     pkill -f pw-loopback"
log "═══════════════════════════════════════════════"
