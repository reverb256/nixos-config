#!/usr/bin/env bash
# PC+TV Mode - Clean, No Corruption
# Both outputs locked to 48kHz, same buffer

set -euo pipefail

GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $1"; }

MATISSE=67  # Desk
SAMSUNG=51  # TV

echo ""
log "═══ PC + TV MODE (Clean Setup) ═══"
echo ""

pkill pw-loopback 2>/dev/null || true
sleep 1

log "Configuring for no corruption..."
log "• Locking both outputs to 48000 Hz"
log "• Using larger buffer for stability"
log "• No latency compensation (natural delay from distance)"

# Set Matisse as primary
wpctl set-default $MATISSE

# Create loopback with locked sample rate
pw-loopback \
  --capture-props="node.target=$MATISSE audio.rate=48000 audio.position=[FL FR]" \
  --playback-props="node.target=$SAMSUNG audio.rate=48000 audio.position=[FL FR] node.latency=2048/48000" \
  &

echo $! > /tmp/audio-pc-tv-clean.pid

sleep 2

log "✅ Clean PC+TV mode active!"
echo ""
echo "Both outputs locked to 48kHz with larger buffer"
echo "This should eliminate corruption!"
echo ""
log "Test it:"
echo "  • Play music - should sound clean on both"
echo "  • TV speakers are rear (naturally delayed by distance)"
echo "  • Desk speakers are front"
echo ""
echo "Still hearing corruption on TV?"
echo "  → The Samsung TV's audio processing might be the issue"
echo "  → Try TV audio settings: Turn off 'Auto Volume', 'Dolby', etc."
echo ""
echo "To stop: pkill pw-loopback"
echo ""
