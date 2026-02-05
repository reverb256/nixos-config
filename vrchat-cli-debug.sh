#!/usr/bin/env bash

echo "=== VRChat CLI Debug Script ==="
echo "Date: $(date)"
echo ""

echo "=== Checking if Steam is running ==="
if pgrep -x "steam" > /dev/null; then
    echo "✓ Steam is running"
    STEAM_PID=$(pgrep -x steam | head -n 1)
    echo "Steam PID: $STEAM_PID"
else
    echo "⚠ Steam is not running"
    echo "Please start Steam before running this script"
    exit 1
fi
echo ""

echo "=== Environment Variables ==="
echo "PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES: $PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES"
echo "WINE_FULLSCREEN_FAKE_CAPTURE: $WINE_FULLSCREEN_FAKE_CAPTURE"
echo "XDG_SESSION_TYPE: $XDG_SESSION_TYPE"
echo "__NV_PRIME_RENDER_OFFLOAD: $__NV_PRIME_RENDER_OFFLOAD"
echo "__GLX_VENDOR_LIBRARY_NAME: $__GLX_VENDOR_LIBRARY_NAME"
echo ""

echo "=== Checking for VRChat installation ==="
VRCHAT_PATH="$HOME/.local/share/Steam/steamapps/common/VRChat"
if [ -d "$VRCHAT_PATH" ]; then
    echo "✓ VRChat directory found: $VRCHAT_PATH"
    ls -la "$VRCHAT_PATH" | head -20
else
    echo "⚠ VRChat directory not found: $VRCHAT_PATH"
    # Look for VRChat in compatdata if installed but not extracted
    if [ -d "$HOME/.local/share/Steam/steamapps/compatdata/438100" ]; then
        echo "✓ VRChat data directory exists: $HOME/.local/share/Steam/steamapps/compatdata/438100"
    else
        echo "⚠ VRChat data directory not found"
    fi
fi
echo ""

echo "=== Checking Proton compatibility tool setup ==="
COMPAT_PATH="$HOME/.local/share/Steam/steamapps/compatdata/438100"
if [ -d "$COMPAT_PATH" ]; then
    echo "✓ Compat directory exists: $COMPAT_PATH"
    echo "Contents:"
    ls -la "$COMPAT_PATH" | head -10
else
    echo "⚠ Compat directory does not exist yet: $COMPAT_PATH"
    echo "VRChat may not have been launched successfully yet to create this directory"
fi
echo ""

echo "=== Attempting to launch VRChat via Steam CLI ==="
echo "This will try to launch VRChat with verbose output..."
echo "VRChat App ID: 438100"
echo ""

# Set environment variables for this launch
export PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES=1
export WINE_FULLSCREEN_FAKE_CAPTURE=1

# Try to launch VRChat via Steam command line
echo "Executing: steam -applaunch 438100 -console"
echo "-----------------------------"
echo "VRChat output begins:"
steam -applaunch 438100 -console 2>&1
echo ""
echo "-----------------------------"
echo "VRChat output ends"
echo ""

echo "=== Checking for recent Steam logs ==="
STEAM_LOGS="$HOME/.local/share/Steam/logs"
if [ -d "$STEAM_LOGS" ]; then
    echo "Recent Steam log files:"
    ls -lat "$STEAM_LOGS" | head -10
    
    echo ""
    echo "Last 50 lines of console log:"
    tail -n 50 "$STEAM_LOGS/console*.log" 2>/dev/null | tail -n 50 || echo "No console log found"
else
    echo "Steam logs directory not found: $STEAM_LOGS"
fi
echo ""

echo "=== SystemD user services status ==="
systemctl --user status monado.service 2>/dev/null || echo "Monado service not loaded"
systemctl --user status wivrn 2>/dev/null || echo "WiVRn service not loaded (may be normal if not using VR headset)"
echo ""

echo "=== Checking for Wine/Proton processes ==="
ps aux | grep -E "(wine|proton|vrchat)" | grep -v grep | head -10
echo ""

echo "=== VRChat CLI Debug Script Complete ==="