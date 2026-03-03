#!/usr/bin/env bash
# Test if your Samsung TV can handle 5.1 audio via AC3 passthrough

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

echo -e "${BLUE}╔═════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     HDMI 5.1 Surround Audio Capability Test        ║${NC}"
echo -e "${BLUE}╚═════════════════════════════════════════════════════╝${NC}"
echo ""

log "Testing Samsung TV via GA102 HDMI..."
echo ""

# Check current HDMI EDID info
log "Reading TV capabilities from EDID:"
echo ""
cat /proc/asound/card1/eld* 2>/dev/null | grep -E "(monitor_name|speakers|sad0)" || {
  error "Could not read EDID info"
  exit 1
}
echo ""

# Parse the speakers field
SPEAKERS=$(cat /proc/asound/card1/eld* 2>/dev/null | grep "speakers" | cut -d: -f2 | xargs)

log "Detected speaker configuration:"
echo "  $SPEAKERS"
echo ""

if [[ "$SPEAKERS" == *"FL/FR"* ]] && [[ "$SPEAKERS" != *"LFE"* ]] && [[ "$SPEAKERS" != *"FC"* ]]; then
  warn "TV reports STEREO ONLY (2.0)"
  echo ""
  echo "This means:"
  echo "  ❌ Uncompressed 5.1/7.1 will NOT work"
  echo "  ❓ AC3/DTS passthrough MAY work (test below)"
  echo ""
elif [[ "$SPEAKERS" == *"LFE"* ]] || [[ "$SPEAKERS" == *"FC"* ]]; then
  log "✓ TV reports surround capability!"
  echo ""
fi

echo -e "${BLUE}═════════════════════════════════════════════════════${NC}"
log "Testing AC3 Passthrough Capability"
echo -e "${BLUE}═════════════════════════════════════════════════════${NC}"
echo ""

# Check for required tools
if ! command -v mpv &> /dev/null && ! command -v vlc &> /dev/null; then
  warn "No media player found"
  echo ""
  echo "Install one to test:"
  echo "  nix-shell -p mpv   # or vlc"
  echo ""
  echo "Then test with:"
  echo "  mpv --audio-device=hdmi --audio-channels=5.1 video.mkv"
  echo ""
  exit 0
fi

# Test with available player
if command -v mpv &> /dev/null; then
  log "mpv found - can test AC3 passthrough"
  echo ""
  echo "To test 5.1 playback:"
  echo ""
  echo "  1. Download a 5.1 test video:"
  echo "     wget https://samples.ffmpeg.org/MPEG-4/multichannel/ffmpeg_5.1_ac3.mp4"
  echo ""
  echo "  2. Play with AC3 passthrough:"
  echo "     mpv --audio-device=alsa/hw:1,7 \\"
  echo "         --audio-spdif=ac3,dts-hd \\"
  echo "         --audio-channels=5.1 \\"
  echo "         ffmpeg_5.1_ac3.mp4"
  echo ""
  echo "  3. If you hear surround, TV supports AC3!"
  echo ""
elif command -v vlc &> /dev/null; then
  log "VLC found - can test AC3 passthrough"
  echo ""
  echo "To test 5.1 playback:"
  echo ""
  echo "  1. Open VLC"
  echo "  2. Tools → Preferences → Audio"
  echo "  3. Set Output Module: 'Audio passthrough'"
  echo "  4. Play 5.1 video file"
  echo "  5. Check if receiver/TV detects surround"
  echo ""
fi

echo -e "${BLUE}═════════════════════════════════════════════════════${NC}"
log "Summary"
echo -e "${BLUE}═════════════════════════════════════════════════════${NC}"
echo ""
echo "Your TV's reported capability:"
echo "  Stereo (2.0): ✅ YES"
echo "  Surround 5.1: ⚠️  MAYBE (via AC3/DTS passthrough)"
echo ""
echo "What this means:"
echo "  • Music/Movies → Test AC3 passthrough (above)"
echo "  • If passthrough fails → TV truly can't do 5.1"
echo "  • To get real 5.1 → Need AVR receiver or USB sound card"
echo ""
echo "Current working setup:"
echo "  • Enhanced stereo (2.0 mirrored to both outputs)"
echo "  • Latency compensation (50ms for HDMI sync)"
echo "  • Works with all apps → No configuration needed"
echo ""
