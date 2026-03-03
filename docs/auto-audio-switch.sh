#!/usr/bin/env bash
# Auto-Switch Audio Mode Based on Running Programs
# Run this in background, it monitors and switches automatically

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $1"; }
warn() { echo -e "${YELLOW}[$(date +'%H:%M:%S')]${NC} $1"; }

# Program → Audio Mode mappings
# Format: "program_name:mode"
# Modes: pc, tv, both
declare -A PROGRAM_MODES=(
  # PC/Desktop apps → PC mode
  ["discord"]="pc"
  ["spotify"]="pc"
  ["chromium"]="pc"
  ["firefox"]="pc"
  ["code"]="pc"
  ["kate"]="pc"
  ["konsole"]="pc"
  ["alacritty"]="pc"

  # TV/Game apps → TV mode
  ["steam"]="tv"
  ["luttis"]="tv"
  ["heroic"]="tv"
  ["mame"]="tv"
  ["retroarch"]="tv"

  # Add your own here!
)

# Current mode
CURRENT_MODE=""

# Helper to switch mode
switch_mode() {
  local new_mode="$1"

  if [[ "$CURRENT_MODE" != "$new_mode" ]]; then
    log "Auto-switching to $new_mode mode"
    /etc/nixos/docs/audio-profiles.sh "$new_mode" > /dev/null 2>&1
    CURRENT_MODE="$new_mode"
  fi
}

# Get active window's program name
get_active_program() {
  # Try to get active window using hyprctl or qdbus or xprop
  if command -v hyprctl &> /dev/null; then
    hyprctl activewindow | grep -oP 'class: \K\w+' | tr '[:upper:]' '[:lower:]'
  elif command -v qdbus &> /dev/null; then
    qdbus org.kde.KWin /KWin activeWindow | grep -oP 'class: \K.*' | head -1 | tr '[:upper:]' '[:lower:]'
  elif command -v xprop &> /dev/null; then
    xprop -id "$(xprop -root | grep '_NET_ACTIVE_WINDOW' | cut -d' ' -f5)" | grep 'WM_CLASS' | cut -d'"' -f2 | tr '[:upper:]' '[:lower:]'
  else
    echo ""
  fi
}

# Check if a program is running (not just focused)
is_running() {
  local program="$1"
  pgrep -fi "$program" > /dev/null
}

log "Starting auto-audio-switch daemon..."
log "Monitoring for programs: ${!PROGRAM_MODES[@]}"
log "Press Ctrl+C to stop"
echo ""

# Main loop - check every 2 seconds
while true; do
  # Check TV/game programs first (higher priority)
  for program in "${!PROGRAM_MODES[@]}"; do
    mode="${PROGRAM_MODES[$program]}"

    if [[ "$mode" == "tv" ]] && is_running "$program"; then
      switch_mode "tv"
      sleep 3
      continue 2
    fi
  done

  # Then check PC programs
  for program in "${!PROGRAM_MODES[@]}"; do
    mode="${PROGRAM_MODES[$program]}"

    if [[ "$mode" == "pc" ]] && is_running "$program"; then
      # But make sure no TV programs are running
      tv_running=false
      for tv_prog in "${!PROGRAM_MODES[@]}"; do
        if [[ "${PROGRAM_MODES[$tv_prog]}" == "tv" ]] && is_running "$tv_prog"; then
          tv_running=true
          break
        fi
      done

      if [[ "$tv_running" == "false" ]]; then
        switch_mode "pc"
      fi
      sleep 3
      continue 2
    fi
  done

  sleep 2
done
