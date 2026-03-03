#!/usr/bin/env bash
# Setup True 4.0 Front+Rear with EasyEffects
# Front: Desk speakers | Rear: TV speakers

set -euo pipefail

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $1"; }

echo ""
echo "╔═════════════════════════════════════════════════════╗"
echo "║     4.0 Front+Rear Setup                          ║"
echo "╚═════════════════════════════════════════════════════╝"
echo ""

# Stop any existing loopbacks
pkill pw-loopback 2>/dev/null || true
pkill easyeffects 2>/dev/null || true
sleep 1

# Check if EasyEffects is installed
if ! command -v easyeffects &> /dev/null; then
  log "EasyEffects not installed yet!"
  echo ""
  echo "Installing..."
  echo "  It's already in your packages, just need to rebuild:"
  echo "  sudo nixos-rebuild switch"
  echo ""
  exit 1
fi

log "Starting EasyEffects..."
easyeffects &

sleep 3

log "════════════════════════════════════════════════════"
log "MANUAL SETUP IN EasyEffects"
log "════════════════════════════════════════════════════"
echo ""
echo "EasyEffects window should now be open."
echo ""
echo "1. Click 'Presets' (left panel)"
echo "2. Click 'Add preset' → Name it '4.0 Front+Rear'"
echo ""
echo "3. Go to 'Plugins' section (left panel)"
echo ""
echo "4. Add these plugins in order:"
echo ""
echo "   a) Stereo Tools → Enable"
echo "      - Mode: 'Stereo to 4.0 upmix'"
echo "      - This creates rear channels from stereo"
echo ""
echo "   b) Channel Mapper → Enable"
echo "      - Set output device: Matisse (desk speakers)"
echo "      - Map FL,FR to front output"
echo ""
echo "   c) Add second Channel Mapper"
echo "      - Set output device: Samsung TV"
echo "      - Map SL,SR to rear output"
echo ""
echo "5. Set '4.0 Front+Rear' as default output in system audio"
echo ""
log "════════════════════════════════════════════════════"
log "Alternative: Simpler Method"
log "════════════════════════════════════════════════════"
echo ""
echo "For now, you can use the simple mirror (both outputs same audio):"
echo ""
echo "  Primary: Desk speakers (front)"
echo "  Mirror:  TV (behind you - same audio)"
echo ""
echo "This is what's currently active. The TV will play"
echo "the same audio as desk speakers (no front/rear separation)."
echo ""
echo "For true front/rear positioning, you need EasyEffects config above."
echo ""
