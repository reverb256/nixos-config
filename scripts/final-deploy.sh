#!/usr/bin/env bash
set -euo pipefail

echo "🚀 Starting deployment of Zephyr configuration with Plasma Desktop..."
echo "🔧 This may take a while, but will use configured binary caches"
echo ""

if [ "$EUID" -ne 0 ]; then
    echo "❌ Please run as root or with sudo"
    exit 1
fi

echo "📝 The following components will be deployed:"
echo "   - KDE Plasma 6 desktop environment"
echo "   - SDDM display manager with Wayland support" 
echo "   - Auto-login for user 'j_kro'"
echo "   - NVIDIA RTX 3090 drivers properly configured"
echo "   - Gaming optimizations and VR support"
echo "   - Mining services (configurable)"
echo ""

echo "⚡ Running: nixos-rebuild switch --flake .#zephyr"
echo "🔄 This may take several minutes depending on cache hits..."
echo ""

cd /etc/nixos
nixos-rebuild switch --flake .#zephyr --impure

echo ""
echo "🎉 Deployment completed successfully!"
echo ""
echo "💡 Next steps:"
echo "   1. Reboot the system: sudo reboot"
echo "   2. After reboot, SDDM should auto-login user 'j_kro'"
echo "   3. Plasma 6 should start on Wayland"
echo "   4. Desktop environment should be fully functional"
echo ""