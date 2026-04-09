#!/usr/bin/env bash
#
# TP-Link Switch Verification Script
# Verifies all switches are accessible before VLAN configuration
#
# Usage: bash scripts/verify-switches.sh

# Exit on error, but allow command failures to be handled
set -o pipefail

# Switch configurations (CORRECTED IPs 2026-03-10)
declare -A SWITCHES
SWITCHES[sw1-modem]="10.1.1.90"
SWITCHES[sw2-nexus]="10.1.1.95"
SWITCHES[sw3-upstairs]="10.1.1.12"
SWITCHES[sw4-zephyr]="10.1.1.104"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "═══════════════════════════════════════════════════════════"
echo "  TP-Link Switch Accessibility Verification"
echo "═══════════════════════════════════════════════════════════"
echo ""

# Track results
declare -i PASSED=0
declare -i FAILED=0
declare -a FAILED_SWITCHES=()

for switch in sw1-modem sw2-nexus sw3-upstairs sw4-zephyr; do
    ip="${SWITCHES[$switch]}"

    echo -n "Testing $switch ($ip)... "

    # Test 1: Ping
    if ping -c 1 -W 2 "$ip" &>/dev/null; then
        echo -ne "${GREEN}✓ Ping${NC} "

        # Test 2: Port 80 open (web interface)
        if timeout 2 bash -c "echo > /dev/tcp/$ip/80" 2>/dev/null; then
            echo -e "${GREEN}✓ Port 80${NC} ${GREEN}✓${NC}"
            ((PASSED++))
        else
            echo -e "${GREEN}✓ Ping${NC} ${RED}✗ Port 80 (web interface not accessible)${NC}"
            ((FAILED++))
            FAILED_SWITCHES+=("$switch (Port 80)")
        fi
    else
        echo -e "${RED}✗ Ping (host unreachable)${NC}"
        ((FAILED++))
        FAILED_SWITCHES+=("$switch (ping)")
    fi
done

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  Summary"
echo "═══════════════════════════════════════════════════════════"
echo -e "  Passed: ${GREEN}$PASSED${NC}/4"
echo -e "  Failed: ${RED}$FAILED${NC}/4"

if [ $FAILED -gt 0 ]; then
    echo ""
    echo -e "${YELLOW}⚠ Failed switches:${NC}"
    for failed in "${FAILED_SWITCHES[@]}"; do
        echo "    - $failed"
    done
    echo ""
    echo -e "${RED}✗ Verification failed. Please check:${NC}"
    echo "    1. Switches are powered on"
    echo "    2. Network cables are connected"
    echo "    3. Switch management IPs are correct"
    echo "    4. No firewall rules blocking access"
    echo ""
    echo "Before running VLAN configuration:"
    echo "  1. Physically verify each switch"
    echo "  2. Check switch port link lights"
    echo "  3. Verify IP addresses in switch web UI"
    exit 1
else
    echo ""
    echo -e "${GREEN}✓ All switches accessible!${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Test login credentials to each switch"
    echo "  2. Take screenshots of current configurations"
    echo "  3. Run: python3 scripts/tplink-configure-vlans.py --verify"
    exit 0
fi
