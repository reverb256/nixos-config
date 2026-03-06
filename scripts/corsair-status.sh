#!/usr/bin/env bash
# Corsair AIO Cooler Status
# Shows pump speed, liquid temperature, and fan status for Corsair AIO coolers

echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║              Corsair Device Status                                ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

# Color codes
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

if ! command -v liquidctl &> /dev/null; then
    echo -e "${RED}Error: liquidctl not found!${NC}"
    echo "Install with: nix-shell -p liquidctl"
    exit 1
fi

# Check if OpenRGB is running and stop it temporarily
OPENRGB_RUNNING=false
if systemctl is-active --quiet openrgb 2>/dev/null; then
    echo -e "${YELLOW}Stopping OpenRGB service temporarily...${NC}"
    sudo systemctl stop openrgb
    OPENRGB_RUNNING=true
    sleep 1
fi

echo -e "${CYAN}Scanning for Corsair devices...${NC}"
echo ""

# List all Corsair devices
liquidctl list

echo ""
echo -e "${CYAN}=== AIO Cooler Status ===${NC}"
echo ""

# Get device status
if liquidctl status &>/dev/null; then
    liquidctl status
else
    echo "No AIO devices found or not supported"
    echo ""
    echo "Supported devices:"
    echo "  - Corsair H115i RGB Platinum"
    echo "  - Corsair H100i RGB Platinum"
    echo "  - Corsair H100i Pro XT"
    echo ""
fi

echo ""
echo -e "${CYAN}=== Pump Speed ===${NC}"

# Try to get pump info from hwmon if available
for hwmon in /sys/class/hwmon/hwmon*; do
    name=$(cat "$hwmon/name" 2>/dev/null)
    case "$name" in
        *corsair*|*hydro*|*h100i*|*h115i*)
            echo "Found Corsair device: $name"
            for fan in "$hwmon"/fan*_input; do
                if [ -f "$fan" ]; then
                    rpm=$(cat "$fan")
                    label=$(echo "$fan" | sed 's/_input//' | sed "s|$hwmon/||")
                    echo "  $label: $rpm RPM"
                fi
            done
            ;;
    esac
done

# Restart OpenRGB if it was running
if [ "$OPENRGB_RUNNING" = true ]; then
    echo ""
    echo -e "${CYAN}Restarting OpenRGB service...${NC}"
    sudo systemctl start openrgb
    echo ""
fi

echo ""
echo -e "${CYAN}=== Commands ===${NC}"
echo "  liquidctl list           - List all supported devices"
echo "  liquidctl status         - Show device status"
echo "  liquidctl initialize     - Initialize devices"
echo "  corsair-rgb              - Start OpenRGB GUI"
echo "  corsair-rgb-server       - Start OpenRGB server"
echo "  aio-status               - Show this status"
echo ""
echo "For RGB control, use: corsair-rgb"
