#!/usr/bin/env bash
#
# dualsense-deadzone-wrapper.sh - Wrapper script for DualSense deadzone configuration
# Called by udev when controller is connected
#
# Usage: dualsense-deadzone-wrapper.sh /dev/input/eventX
#

set -euo pipefail

# Logging
LOG_FILE="/var/log/dualsense-deadzone.log"
TOOL="/run/current-system/sw/bin/set-evdev-deadzone"

# Device node from udev (%k)
DEVICE_NODE="$1"

# Validate input
if [[ -z "$DEVICE_NODE" ]]; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Error: No device node provided" >> "$LOG_FILE"
  exit 1
fi

# Full device path
DEVICE_PATH="/dev/input/${DEVICE_NODE}"

# Check if device exists
if [[ ! -e "$DEVICE_PATH" ]]; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Error: Device $DEVICE_PATH does not exist" >> "$LOG_FILE"
  exit 1
fi

# Check if tool exists
if [[ ! -x "$TOOL" ]]; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Error: Tool $TOOL not found or not executable" >> "$LOG_FILE"
  exit 1
fi

# Apply deadzone
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Applying deadzone to $DEVICE_PATH" >> "$LOG_FILE"

if "$TOOL" "$DEVICE_PATH" 0:10000 1:10000 3:10000 4:10000 >> "$LOG_FILE" 2>&1; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ Successfully applied deadzone to $DEVICE_PATH" >> "$LOG_FILE"
  exit 0
else
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ❌ Failed to apply deadzone to $DEVICE_PATH (exit code: $?)" >> "$LOG_FILE"
  exit 1
fi
