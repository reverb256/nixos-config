#!/usr/bin/env bash

echo "=== VRChat Debug Script ==="
echo "Date: $(date)"
echo ""

echo "=== System Information ==="
echo "Kernel: $(uname -r)"
echo "NVIDIA Driver: $(nvidia-smi --query-gpu=driver_version --format=csv,noheader,nounits 2>/dev/null || echo 'Could not query')"
echo "Graphics: $(glxinfo | grep "OpenGL renderer string" | head -n 1)"
echo ""

echo "=== Wayland Session Info ==="
echo "Session Type: $XDG_SESSION_TYPE"
echo "WAYLAND_DISPLAY: $WAYLAND_DISPLAY"
echo "QT_QPA_PLATFORM: $QT_QPA_PLATFORM"
echo ""

echo "=== NVIDIA Variables ==="
echo "__NV_PRIME_RENDER_OFFLOAD: $__NV_PRIME_RENDER_OFFLOAD"
echo "__GLX_VENDOR_LIBRARY_NAME: $__GLX_VENDOR_LIBRARY_NAME"
echo "__GL_SYNC_TO_VBLANK: $__GL_SYNC_TO_VBLANK"
echo ""

echo "=== OpenXR Runtime ==="
if [ -f "$HOME/.config/openxr/1/active_runtime.json" ]; then
    echo "Active OpenXR runtime:"
    cat "$HOME/.config/openxr/1/active_runtime.json"
else
    echo "Active OpenXR runtime file not found"
fi
echo ""

echo "=== Steam Environment ==="
echo "STEAM_RUNTIME: $STEAM_RUNTIME"
echo "PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES: $PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES"
echo ""

echo "=== VRChat Proton Log Location ==="
if [ -d "$HOME/.local/share/Steam/steamapps/compatdata" ]; then
    echo "Compatible data directories:"
    ls -la "$HOME/.local/share/Steam/steamapps/compatdata" | grep -E "[0-9]+"
else
    echo "Steam compatdata directory not found"
fi
echo ""

echo "=== Monado Service Status ==="
systemctl --user status monado
echo ""

echo "=== Relevant Running Processes ==="
ps aux | grep -E "(wivrn|monado|steam|vrchat)" | grep -v grep
echo ""

echo "=== End Debug Script ==="