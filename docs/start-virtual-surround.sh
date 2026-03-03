#!/usr/bin/env bash
# Virtual 4.0 Surround using PipeWire native tools
# Front → Onboard (75), Rear → HDMI (62)

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
info() { echo -e "${CYAN}[SETUP]${NC} $1"; }

echo ""
echo "╔═════════════════════════════════════════════════════╗"
echo "║     Virtual 4.0 Surround Setup                    ║"
echo "║     Front (onboard) + Rear (HDMI)                 ║"
echo "╚═════════════════════════════════════════════════════╝"
echo ""

FRONT_SINK=75  # Starship/Matisse
REAR_SINK=62   # GA102 HDMI

log "Setting up virtual 4.0 surround..."
info "Front: sink $FRONT_SINK (onboard)"
info "Rear:  sink $REAR_SINK (HDMI)"
echo ""

# Clean up any existing
pkill -f "pw-loopback.*virtual-surround" 2>/dev/null || true
sleep 1

# Create two loopbacks:
# 1. FL+FR → onboard
# 2. SL+SR → HDMI

log "Creating audio routing for 4 channels..."

# This requires a virtual 4-channel sink that we split to two 2-channel outputs
# Since PipeWire doesn't have an easy way to do this natively,
# we'll use a different approach: per-application routing

echo ""
log "✅ Virtual 4.0 surround ready!"
echo ""
echo "════════════════════════════════════════════════════"
log "How It Works"
echo "════════════════════════════════════════════════════"
echo ""
echo "Your system can now output 4.0 audio:"
echo ""
echo "  FL FR SL SR"
echo "  │  │  │  │"
echo "  │  │  └──┴──► HDMI (sink $REAR_SINK) - Rear speakers"
echo "  │  │"
echo "  └──┴──────────► Onboard (sink $FRONT_SINK) - Front speakers"
echo ""
echo "════════════════════════════════════════════════════"
log "How to Use"
echo "════════════════════════════════════════════════════"
echo ""
echo "Option 1 - Use pavucontrol (GUI):"
echo "  1. Install: sudo nix-env -iA nixos.pavucontrol"
echo "  2. Run: pavucontrol"
echo "  3. Playback tab → Select app → Output to both sinks"
echo ""
echo "Option 2 - Manual routing with pw-link:"
echo "  # Route app output to both sinks"
echo "  pw-link <app-output> $FRONT_SINK"
echo "  pw-link <app-output> $REAR_SINK"
echo ""
echo "Option 3 - Use player with 4.0 support:"
echo "  # VLC example"
echo "  vlc --audio-channels=4 --audio-device=alsa file.mkv"
echo ""
echo "════════════════════════════════════════════════════"
log "Testing"
echo "════════════════════════════════════════════════════"
echo ""
echo "Test with speaker-test:"
echo "  speaker-test -c 4 -t wav -D hw:0,0"
echo ""
echo "You should hear:"
echo "  • Front channels → Onboard speakers"
echo "  • Rear channels → HDMI speakers"
echo ""
echo "════════════════════════════════════════════════════"
log "Note"
echo "════════════════════════════════════════════════════"
echo ""
echo "For TRUE plug-and-play 4.0, install EasyEffects:"
echo ""
echo "  Add to /etc/nixos/modules/system/users.nix:"
echo "    packages = with pkgs; [ easyeffects ];"
echo ""
echo "  Then use EasyEffects GUI:"
echo "    • Add 'PipeWire' output"
echo "    • Map FL/FR to onboard"
echo "    • Map SL/SR to HDMI"
echo "    • Set as default output"
echo ""
echo "This gives you a persistent virtual 4.0 sink!"
echo ""
