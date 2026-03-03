#!/usr/bin/env bash
# Audio Profile Switcher - FIXED VERSION
# No latency compensation to avoid corruption

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# Device IDs
MATISSE=67  # Under desk, in front
SAMSUNG=51  # TV, behind

show_usage() {
  echo ""
  echo "╔═════════════════════════════════════════════════════╗"
  echo "║     Audio Profile Switcher (Safe Mode)            ║"
  echo "╚═════════════════════════════════════════════════════╝"
  echo ""
  echo "Usage: $0 <profile>"
  echo ""
  echo "Profiles:"
  echo "  pc          PC Mode (desk speakers only, no corruption)"
  echo "  tv          TV Mode (TV only)"
  echo "  pc+tv       PC + TV (both, no latency - may have echo)"
  echo "  status      Show current status"
  echo ""
  echo "NOTE: Latency compensation disabled to prevent corruption"
  echo "      Use pc+tv at your own risk (may hear echo)"
  echo ""
}

set_pc_mode() {
  echo ""
  log "═══ PC MODE (Desk Only) ═══"
  echo ""

  # Kill any loopbacks
  pkill -f "audio-profile" 2>/dev/null || true
  pkill pw-loopback 2>/dev/null || true
  sleep 1

  # Set Matisse as default
  wpctl set-default $MATISSE

  log "✅ PC Mode active!"
  echo ""
  echo "Audio → Matisse desk speakers ONLY"
  echo "No loopback (no corruption risk)"
  echo ""
}

set_tv_mode() {
  echo ""
  log "═══ TV MODE ═══"
  echo ""

  # Kill any loopbacks
  pkill -f "audio-profile" 2>/dev/null || true
  pkill pw-loopback 2>/dev/null || true
  sleep 1

  # Set Samsung as default
  wpctl set-default $SAMSUNG

  log "✅ TV Mode active!"
  echo ""
  echo "Audio → Samsung TV ONLY"
  echo ""
}

set_pc_tv_mode() {
  echo ""
  log "═══ PC + TV MODE (No Latency Comp) ═══"
  echo ""
  warn "⚠️  This may cause echo (no delay compensation)"
  echo ""

  # Kill existing
  pkill -f "audio-profile" 2>/dev/null || true
  pkill pw-loopback 2>/dev/null || true
  sleep 1

  # Set Matisse as primary
  wpctl set-default $MATISSE

  # Simple loopback with NO latency compensation
  pw-loopback \
    --capture-props="node.target=$MATISSE audio.position=[FL FR]" \
    --playback-props="node.target=$SAMSUNG audio.position=[FL FR]" \
    &

  echo $! > /tmp/audio-profile-simple.pid

  log "✅ PC + TV Mode active!"
  echo ""
  echo "Primary: Matisse desk speakers"
  echo "Mirror:  Samsung TV (no delay - may echo)"
  echo ""
  warn "If you hear corruption or echo, switch back to 'pc' or 'tv' mode"
  echo ""
}

show_status() {
  echo ""
  log "═══ Current Status ═══"
  echo ""

  DEFAULT=$(wpctl status | grep "*" -A 1 | grep -oP '\d+(?=\.)' | head -1)

  echo "Default sink: $DEFAULT"
  echo ""

  if [[ "$DEFAULT" == "$MATISSE" ]]; then
    if pgrep -f "audio-profile-simple" > /dev/null; then
      echo -e "${CYAN}Mode: PC + TV (simple mirror)${NC}"
      echo "  Primary: Matisse (desk)"
      echo "  Mirror:  Samsung TV"
      echo ""
      warn "⚠️  No latency compensation - echo possible"
    else
      echo -e "${GREEN}Mode: PC Only${NC}"
      echo "  Output: Matisse desk speakers"
    fi
  elif [[ "$DEFAULT" == "$SAMSUNG" ]]; then
    echo -e "${MAGENTA}Mode: TV Only${NC}"
    echo "  Output: Samsung TV"
  fi
  echo ""

  if pgrep pw-loopback > /dev/null; then
    echo "Loopback processes: $(pgrep pw-loopback | wc -l)"
  fi
  echo ""
}

# Main
case "${1:-}" in
  pc)
    set_pc_mode
    ;;
  tv)
    set_tv_mode
    ;;
  pc+tv|both)
    set_pc_tv_mode
    ;;
  status)
    show_status
    ;;
  *)
    show_usage
    exit 1
    ;;
esac
