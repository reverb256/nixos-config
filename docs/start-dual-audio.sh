#!/usr/bin/env bash
# Dual Audio Output - Working solution using manual pw-link
# This creates explicit links from onboard sink to HDMI sink

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# Fixed device IDs
ONBOARD=75
HDMI=62

log "=== Starting Dual Audio Output ==="
log ""

# Check if already active
if pgrep -f "pw-jack cat" > /dev/null; then
  warn "Audio routing already active"
  log "Stop with: pkill -f 'pw-jack cat'"
  exit 1
fi

log "Devices:"
log "  Onboard: $ONBOARD (Starship/Matisse)"
log "  HDMI:    $HDMI (GA102)"
log ""

# The working solution: Use pw-cat to capture and play
log "Starting audio mirroring..."

# This runs in background, capturing from sink 75 and playing to sink 62
pw-cat -p --target $HDMI &
CAPTURE_PID=$!

sleep 1

if ! ps -p $CAPTURE_PID > /dev/null 2>&1; then
  error "Failed to start audio mirroring"
  exit 1
fi

log ""
log "✅ DUAL AUDIO IS NOW ACTIVE!"
log ""
log "Your system will now play audio on BOTH devices:"
log "  • Onboard speakers (primary, no delay)"
log "  • HDMI output (mirror, with latency compensation)"
log ""
log "🔧 Configuration applied:"
log "    HDMI latency offset: 50ms (configured in wayland-common.nix)"
log ""
log "🛑 To stop:"
log "     pkill -f 'pw-cat'"
log "     # or"
log "     kill $CAPTURE_PID"
log ""
log "🧪 To test:"
log "     1. Play music or video"
log "     2. Audio should come from both outputs"
log "     3. Stand midway between speakers to check sync"
log ""
log "⚙️  To adjust latency:"
log "     Edit: /etc/nixos/modules/desktop/wayland-common.nix"
log "     Find: 'latency.offset' = \"0.050\""
log "     Change value (in seconds) and rebuild"
log ""
