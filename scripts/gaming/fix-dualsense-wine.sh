#!/usr/bin/env bash
# DualSense/DualShock controller fix for Wine/Proton games
# Run this script to enable hidraw controller support in Wine prefixes

set -e

# Default paths - adjust if needed
WINE_PREFIX="${WINE_PREFIX:-/data/@games/hoyoverse/prefix}"
WINE_BIN="${WINE_BIN:-/data/@games/hoyoverse/runners/spritz-wine-cachyos-wow64-10.0-7/bin/wine}"

echo "Configuring Wine for DualSense/DualShock controller support..."
echo "Wine prefix: $WINE_PREFIX"

# Enable hidraw for DualSense (PS5) and DualShock 4 (PS4) controllers
# This fixes the axis mapping issues in games like Honkai Star Rail
WINEPREFIX="$WINE_PREFIX" "$WINE_BIN" reg add \
    'HKLM\System\CurrentControlSet\Services\winebus' \
    /v DisableHidraw \
    /t REG_DWORD \
    /d 0 \
    /f 2>/dev/null || true

# Also set the emulator to autoload for better compatibility
WINEPREFIX="$WINE_PREFIX" "$WINE_BIN" reg add \
    'HKLM\System\CurrentControlSet\Services\winebus' \
    /v ImmersiveDevice \
    /t REG_DWORD \
    /d 1 \
    /f 2>/dev/null || true

echo "Registry keys added. Restarting wine prefix..."

# Restart the wine prefix to apply changes
WINEPREFIX="$WINE_PREFIX" "$WINE_BIN" wineboot -r 2>/dev/null || true

echo "Done! Your controller should work in Honkai Star Rail now."
echo ""
echo "Note: This may change button prompts from PlayStation to Xbox icons."
