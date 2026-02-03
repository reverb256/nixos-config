#!/usr/bin/env bash

set -e

echo "=== WiVRn + Lighthouse Setup Verification ==="
echo

echo "1. Checking WiVRn service..."
if systemctl --user is-active wivrn >/dev/null 2>&1; then
    echo "   ✅ WiVRn service is running"
else
    echo "   ❌ WiVRn service is not running"
    echo "   Run: systemctl --user start wivrn"
fi

echo
echo "2. Checking firewall configuration..."
for port in 9757 5353 9947 27036 27031; do
    if firewall-cmd --list-ports 2>/dev/null | grep -q ":$port/"; then
        echo "   ✅ Port $port is open"
    else
        echo "   ⚠️  Port $port may not be open"
    fi
done

echo
echo "3. Checking required packages..."
required_packages=("wivrn" "motoc" "steam-run" "avahi")
for pkg in "${required_packages[@]}"; do
    if command -v "$pkg" >/dev/null 2>&1; then
        echo "   ✅ $pkg is installed"
    else
        echo "   ❌ $pkg is not installed"
    fi
done

echo
echo "4. Checking environment variables..."
env_vars=("STEAMVR_LHR" "WIVRN_LH_SUPPORT" "WIVRN_STEAMVR_ENABLED")
for var in "${env_vars[@]}"; do
    if [ -n "${!var}" ]; then
        echo "   ✅ $var=${!var}"
    else
        echo "   ⚠️  $var is not set"
    fi
done

echo
echo "5. Checking VR devices..."
echo "   USB devices:"
lsusb | grep -E "(28de:210[12]|2833:0181|1234:5678)" || echo "   No VR devices detected"

echo
echo "6. Usage Instructions:"
echo
echo "   To use WiVRn with Lighthouse tracking:"
echo "   1. Power on your lighthouse base stations"
echo "   2. Power on your Tundra trackers and connect to base stations"
echo "   3. Start WiVRn dashboard on your PC"
echo "   4. Launch WiVRn client on your Quest Pro"
echo "   5. Connect to your PC via Wi-Fi or USB"
echo
echo "   To calibrate tracking:"
echo "   Run: motoc monitor"
echo "   Run: motoc calibrate"
echo
echo "   For troubleshooting:"
echo "   - Check base station line-of-sight"
echo "   - Ensure trackers are powered and synced"
echo "   - Verify firewall ports are open"
echo "   - Check USB permissions for devices"
echo

echo "=== Setup Complete ==="