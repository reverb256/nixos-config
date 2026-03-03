#!/usr/bin/env bash
# PC+TV Mode with Minimal Latency (Tuned for Your Setup)
# Front: Desk speakers | Rear: TV speakers

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

MATISSE=75  # Desk speakers (front)
SAMSUNG=62  # TV (rear)

echo ""
log "═══ PC + TV MODE (Front + Rear) ═══"
echo ""

# Stop existing
pkill -f "audio-profile" 2>/dev/null || true
pkill pw-loopback 2>/dev/null || true
sleep 1

log "Setting up audio routing..."

# The key insight: TV is BEHIND you (6ft away)
# Sound takes ~6ms to travel that distance
# So TV speakers naturally have delay!

# Set Matisse as primary
wpctl set-default $MATISSE

# Create loopback with VERY SMALL latency compensation
# The TV speakers are behind you, so they naturally have delay
# We only need minimal compensation to account for digital processing
pw-loopback \
  --capture-props="node.target=$MATISSE audio.position=[FL FR]" \
  --playback-props="node.target=$SAMSUNG audio.position=[FL FR] latency.offset=1M" \
  &

echo $! > /tmp/audio-profile-front-rear.pid

sleep 2

log "✅ PC + TV Mode active!"
echo ""
echo "Front speakers (Matisse desk):  Primary output"
echo "Rear speakers (Samsung TV):     1ms delay"
echo ""
log "Why this works:"
echo "  • TV speakers are 6 feet behind you"
echo "  • Sound takes ~6ms to travel that distance naturally"
echo "  • We only add 1ms for digital processing on HDMI"
echo "  • Result: Front comes from desk, rear fills from behind"
echo ""
echo "  No corruption because latency is minimal!"
echo ""
echo "To stop: pkill pw-loopback"
echo ""
