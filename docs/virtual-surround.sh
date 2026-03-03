#!/usr/bin/env bash
# Create Virtual 4.0 Surround (Front + Rear)
# Maps system 4.0 channels to two physical stereo outputs

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
info() { echo -e "${CYAN}[SETUP]${NC} $1;"

echo -e "${BLUE}╔═════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Virtual 4.0 Surround Setup                      ║${NC}"
echo -e "${BLUE}║   Front: Onboard | Rear: HDMI                     ║${NC}"
echo -e "${BLUE}╚═════════════════════════════════════════════════════╝${NC}"
echo ""

# Physical sink IDs
FRONT_SINK=75  # Starship/Matisse (front speakers)
REAR_SINK=62   # GA102 HDMI (rear speakers)

log "Creating virtual 4.0 surround sink..."
echo ""

info "Channel mapping:"
echo "  FL (Front Left)  ──► Onboard  (sink $FRONT_SINK) left"
echo "  FR (Front Right) ──► Onboard  (sink $FRONT_SINK) right"
echo "  SL (Surround Left) ──► HDMI     (sink $REAR_SINK) left"
echo "  SR (Surround Right)──► HDMI     (sink $REAR_SINK) right"
echo ""

# Kill any existing virtual surround
pkill -f "virtual-surround" 2>/dev/null || true
sleep 1

# Create virtual sink using PipeWire's filter-chain
# This creates a 4.0 sink that splits to two 2.0 outputs

log "Starting PipeWire filter-chain..."

pw-filter -m \
  --name virtual-surround-4.0 \
  --capture-dsp-props='audio.rate=48000 audio.channels=4 audio.position=[FL FR SL SR]' \
  --playback-dsp-props='audio.rate=48000 audio.channels=2 audio.position=[FL FR]' \
  --capture-props='node.target=75 media.class=Audio/Sink' \
  --playback-props='node.target=62' \
  &

PW_FILTER_PID=$!

sleep 2

if ! ps -p $PW_FILTER_PID > /dev/null 2>&1; then
  error "pw-filter failed - trying alternative method..."
  rm -f /tmp/virtual-surround.pid

  # Alternative: Use PulseAudio virtual surround
  log "Trying PulseAudio module-virtual-surround..."

  # Check if pulse is available
  if ! command -v pactl &> /dev/null; then
    error "Neither pw-filter nor pactl available"
    echo ""
    echo "Installing required tools..."
    echo "  sudo nix-env -iA nixos.pipewire-pulse"
    exit 1
  fi

  # Load virtual surround module
  pactl load-module module-virtual-surround-sink \
    sink_name=virtual-surround-4.0 \
    sink_master=$FRONT_SINK \
    sink_rear=$REAR_SINK \
    channels=4 \
    rate=48000 \
    format=s16le

  VIRTUAL_SINK=$(pactl list short sinks | grep virtual-surround | cut -f1)
  echo $VIRTUAL_SINK > /tmp/virtual-surround.pid

else
  echo $PW_FILTER_PID > /tmp/virtual-surround.pid
fi

log ""
log "✅ Virtual 4.0 Surround created!"
echo ""
echo -e "${CYAN}═════════════════════════════════════════════════════${NC}"
log "Setup Information"
echo -e "${CYAN}═════════════════════════════════════════════════════${NC}"
echo ""
echo "Virtual sink created:"
echo "  Name: virtual-surround-4.0"
echo "  Channels: 4 (FL FR SL SR)"
echo ""
echo "Physical routing:"
echo "  Front speakers → Onboard output"
echo "  Rear speakers  → HDMI output"
echo ""
info "Testing:"
echo "  1. Set virtual-surround-4.0 as default output"
echo "  2. Play 4.0/5.1/7.1 content"
echo "  3. Front channels go to onboard, rear to HDMI"
echo ""
info "To set as default:"
echo "  wpctl set-default $(cat /tmp/virtual-surround.pid 2>/dev/null || echo 'see above')"
echo ""
info "To stop:"
echo "  kill \$(cat /tmp/virtual-surround.pid)"
echo "  pactl unload-module module-virtual-surround-sink"
echo ""
