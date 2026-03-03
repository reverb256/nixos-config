#!/usr/bin/env bash
# Simple Auto-Switcher - Easy to Configure
# Edit the MAPPINGS section below to add your programs

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date +'%H:%M:%S')] AUTO-SWITCH:${NC} $1"; }

# ═══════════════════════════════════════════════════════════════
#  EDIT THIS SECTION - Add your programs here
# ═══════════════════════════════════════════════════════════════

# When these programs run → switch to TV mode
TV_PROGRAMS="
  steam
  lutris
  heroic
  retroarch
  mame
"

# When these programs run → switch to PC mode
PC_PROGRAMS="
  discord
  spotify
  chromium
  firefox
  code
  kate
"

# ═══════════════════════════════════════════════════════════════

CURRENT_MODE=""

switch_to() {
  local mode="$1"
  if [[ "$CURRENT_MODE" != "$mode" ]]; then
    log "Switching to $mode mode"
    /etc/nixos/docs/audio-profiles.sh "$mode" > /dev/null 2>&1
    CURRENT_MODE="$mode"
  fi
}

is_running() {
  pgrep -fi "$1" > /dev/null
}

log "Auto-switcher started (edit this file to add programs)"
log "Press Ctrl+C to stop"
echo ""

while true; do
  # Check TV programs (higher priority)
  for prog in $TV_PROGRAMS; do
    if is_running "$prog"; then
      switch_to "tv"
      sleep 5
      continue 2
    fi
  done

  # Check PC programs
  for prog in $PC_PROGRAMS; do
    if is_running "$prog"; then
      switch_to "pc"
      sleep 5
      continue 2
    fi
  done

  sleep 2
done
