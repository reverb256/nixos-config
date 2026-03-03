#!/usr/bin/env bash
# Audio Profile Switcher
# Switch between PC mode and TV mode speaker configurations

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
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# Device IDs
MATISSE=75  # Under desk, in front
SAMSUNG=62  # TV, behind

show_usage() {
  echo ""
  echo "╔═════════════════════════════════════════════════════╗"
  echo "║     Audio Profile Switcher                         ║"
  echo "╚═════════════════════════════════════════════════════╝"
  echo ""
  echo "Usage: $0 <profile>"
  echo ""
  echo "Profiles:"
  echo ""
  echo "  pc          PC Mode (at desk)"
  echo "              ┌─────────────────────────────────────┐"
  echo "              │  Matisse (under desk) = FRONT       │"
  echo "              │  Samsung TV (behind)    = REAR       │"
  echo "              └─────────────────────────────────────┘"
  echo ""
  echo "  tv          TV Mode (gaming on TV)"
  echo "              ┌─────────────────────────────────────┐"
  echo "              │  Samsung TV           = FRONT       │"
  echo "              │  Matisse              = OFF         │"
  echo "              └─────────────────────────────────────┘"
  echo ""
  echo "  tv+rear     TV Mode with rear fill"
  echo "              ┌─────────────────────────────────────┐"
  echo "              │  Samsung TV           = FRONT       │"
  echo "              │  Matisse              = REAR (quiet) │"
  echo "              └─────────────────────────────────────┘"
  echo ""
  echo "  status      Show current audio routing"
  echo "  test        Test current profile"
  echo ""
  echo "Examples:"
  echo "  $0 pc       # Switch to PC/desk mode"
  echo "  $0 tv       # Switch to TV/gaming mode"
  echo "  $0 status   # Show what's active"
  echo ""
}

set_pc_mode() {
  echo ""
  log "═══ Switching to PC MODE ═══"
  echo ""
  log "Front: Matisse (under desk)"
  log "Rear:  Samsung TV (behind)"
  echo ""

  # Set Matisse as default (front speakers)
  wpctl set-default $MATISSE

  # Create loopback for rear speakers (Samsung TV)
  # Capture from Matisse, play to Samsung with delay
  pkill -f "audio-profile-pc" 2>/dev/null || true

  pw-loopback \
    --capture-props="node.target=$MATISSE audio.position=[FL FR]" \
    --playback-props="node.target=$SAMSUNG audio.position=[FL FR] latency.offset=50M" \
    &

  echo $! > /tmp/audio-profile-pc.pid

  log "✅ PC Mode active!"
  echo ""
  echo "Front speakers (Matisse):  Primary output"
  echo "Rear speakers (Samsung):   Ambient fill (50ms delay)"
  echo ""
  info "Perfect for desktop gaming, work, music"
  echo ""
}

set_tv_mode() {
  echo ""
  log "═══ Switching to TV MODE ═══"
  echo ""
  log "Front: Samsung TV"
  log "Rear:  (disabled)"
  echo ""

  # Kill any PC mode loopback
  pkill -f "audio-profile-pc" 2>/dev/null || true
  pkill pw-loopback 2>/dev/null || true
  sleep 1

  # Set Samsung TV as default
  wpctl set-default $SAMSUNG

  log "✅ TV Mode active!"
  echo ""
  echo "All audio → Samsung TV"
  echo ""
  info "Perfect for console gaming on TV, movies"
  echo ""
}

set_tv_rear_mode() {
  echo ""
  log "═══ Switching to TV+REAR MODE ═══"
  echo ""
  log "Front: Samsung TV"
  log "Rear:  Matisse (lower volume)"
  echo ""

  # Kill existing
  pkill -f "audio-profile-pc" 2>/dev/null || true
  pkill pw-loopback 2>/dev/null || true
  sleep 1

  # Set Samsung as primary
  wpctl set-default $SAMSUNG

  # Add rear fill from Matisse at lower volume
  pw-loopback \
    --capture-props="node.target=$SAMSUNG audio.position=[FL FR]" \
    --playback-props="node.target=$MATISSE audio.position=[FL FR] channelmix.volume=0.3 latency.offset=20M" \
    &

  echo $! > /tmp/audio-profile-tv-rear.pid

  log "✅ TV+Rear Mode active!"
  echo ""
  echo "Front (Samsung TV):  Primary output (100%)"
  echo "Rear (Matisse):      Ambient fill (30%, 20ms delay)"
  echo ""
  info "Great for immersive gaming on TV with desk speakers as rear"
  echo ""
}

show_status() {
  echo ""
  log "═══ Current Audio Status ═══"
  echo ""

  DEFAULT=$(wpctl status | grep "*" -A 1 | grep -oP '\d+(?=\.)' | head -1)

  if [[ "$DEFAULT" == "$MATISSE" ]]; then
    echo -e "${GREEN}Mode: PC MODE${NC}"
    echo "  Default: Matisse (desk speakers)"
    echo "  Rear:    Samsung TV (via loopback)"
  elif [[ "$DEFAULT" == "$SAMSUNG" ]]; then
    echo -e "${MAGENTA}Mode: TV MODE${NC}"
    echo "  Default: Samsung TV"
    echo "  Rear:    $(pgrep -f 'audio-profile-tv-rear' > /dev/null && echo 'Matisse (enabled)' || echo 'Matisse (disabled)')"
  else
    echo -e "${YELLOW}Mode: UNKNOWN${NC}"
    echo "  Default: Sink $DEFAULT"
  fi

  echo ""
  echo "Devices:"
  echo "  Matisse (desk):  sink $MATISSE"
  echo "  Samsung (TV):    sink $SAMSUNG"
  echo ""

  if pgrep -f "audio-profile-pc" > /dev/null; then
    log "PC mode loopback running (PID: $(cat /tmp/audio-profile-pc.pid 2>/dev/null || echo 'unknown'))"
  elif pgrep -f "audio-profile-tv-rear" > /dev/null; then
    log "TV+Rear mode loopback running (PID: $(cat /tmp/audio-profile-tv-rear.pid 2>/dev/null || echo 'unknown'))"
  fi
  echo ""
}

test_current_profile() {
  echo ""
  log "═══ Testing Current Profile ═══"
  echo ""
  log "Playing test tone..."
  echo ""

  # Play test sound on default sink
  if command -v speaker-test &> /dev/null; then
    speaker-test -t sine -f 440 -l 1 &
    TEST_PID=$!
    sleep 2
    kill $TEST_PID 2>/dev/null || true
  elif command -v pw-play &> /dev/null; then
    # Try to play a system sound
    pw-play /usr/share/sounds/freedesktop/stereo/complete.oga 2>/dev/null || {
      warn "No test sound available"
      return 1
    }
  else
    warn "No audio test tools available"
    return 1
  fi

  log "✅ Test complete!"
  echo ""
  info "Did you hear audio from the expected speakers?"
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
  tv+rear|tv-rear)
    set_tv_rear_mode
    ;;
  status)
    show_status
    ;;
  test)
    test_current_profile
    ;;
  *)
    show_usage
    exit 1
    ;;
esac
