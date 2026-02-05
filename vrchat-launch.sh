#!/usr/bin/env bash

# VRChat launch script for debugging
echo "Starting VRChat with debugging..."

# Set required environment variables
export PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES=1
export WINE_FULLSCREEN_FAKE_CAPTURE=1
export DXVK_HUD=1

# Create log directory if it doesn't exist
LOG_DIR="$HOME/vrchat_logs"
mkdir -p "$LOG_DIR"

# Launch VRChat with logging
echo "Environment variables:"
env | grep -E "(OPENXR|PRESSURE|WINE|DXVK|STEAM)" | sort

echo "Launching VRChat..."
"$@"

echo "VRChat exited with code $?"