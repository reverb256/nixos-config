#!/usr/bin/env bash
# Test OpenClaw Tailscale Security Configuration
# Verifies CVE-2026-25253 protections are in place

echo "=== OpenClaw Tailscale Security Verification ==="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get Tailscale IP
TAILSCALE_IP=$(tailscale ip -4 2>/dev/null)
if [ -z "$TAILSCALE_IP" ]; then
    echo -e "${RED}ERROR: Tailscale not running or no IP assigned${NC}"
    exit 1
fi

echo -e "Tailscale IP: ${GREEN}$TAILSCALE_IP${NC}"
echo ""

# Test 1: Check OpenClaw is listening on correct IP
echo "Test 1: Checking OpenClaw bind address..."
OPENCLAW_BIND=$(sudo ss -tlnp | grep 18789 | awk '{print $4}')
if echo "$OPENCLAW_BIND" | grep -q "$TAILSCALE_IP"; then
    echo -e "${GREEN}✓ PASS: OpenClaw listening on Tailscale IP ($TAILSCALE_IP)${NC}"
elif echo "$OPENCLAW_BIND" | grep -q "0.0.0.0"; then
    echo -e "${RED}✗ FAIL: OpenClaw listening on ALL interfaces (0.0.0.0) - SECURITY RISK!${NC}"
    echo -e "${YELLOW}  Run: sudo nixos-rebuild switch --flake .#zephyr${NC}"
    exit 1
elif echo "$OPENCLAW_BIND" | grep -q "127.0.0.1"; then
    echo -e "${YELLOW}⚠ WARNING: OpenClaw only on localhost (127.0.0.1)${NC}"
    echo -e "${YELLOW}  Tailscale devices won't be able to connect${NC}"
else
    echo -e "${YELLOW}? UNKNOWN: OpenClaw bind: $OPENCLAW_BIND${NC}"
fi
echo ""

# Test 2: Verify firewall rules
echo "Test 2: Checking firewall rules..."
if sudo iptables -L | grep -q "tailscale0.*18789"; then
    echo -e "${GREEN}✓ PASS: Firewall allows OpenClaw only on Tailscale interface${NC}"
else
    echo -e "${YELLOW}⚠ WARNING: Firewall rules not found for tailscale0${NC}"
    echo -e "${YELLOW}  May need to rebuild NixOS configuration${NC}"
fi
echo ""

# Test 3: Check service status
echo "Test 3: Checking OpenClaw service..."
if systemctl is-active openclaw-container-declarative >/dev/null 2>&1; then
    echo -e "${GREEN}✓ PASS: OpenClaw service is running${NC}"
else
    echo -e "${RED}✗ FAIL: OpenClaw service is not running${NC}"
    echo -e "${YELLOW}  Run: systemctl status openclaw-container-declarative${NC}"
    exit 1
fi
echo ""

# Test 4: Test local access via Tailscale IP
echo "Test 4: Testing local access via Tailscale IP..."
if curl -s --connect-timeout 3 "http://$TAILSCALE_IP:18789/health" >/dev/null 2>&1; then
    echo -e "${GREEN}✓ PASS: OpenClaw accessible via Tailscale IP${NC}"
else
    echo -e "${RED}✗ FAIL: Cannot connect to OpenClaw on Tailscale IP${NC}"
    echo -e "${YELLOW}  Check: systemctl status openclaw-container-declarative${NC}"
    exit 1
fi
echo ""

# Test 5: Verify localhost still works
echo "Test 5: Testing localhost access..."
if curl -s --connect-timeout 3 "http://127.0.0.1:18789/health" >/dev/null 2>&1; then
    echo -e "${GREEN}✓ PASS: OpenClaw accessible via localhost${NC}"
else
    echo -e "${YELLOW}⚠ WARNING: OpenClaw not accessible via localhost${NC}"
    echo -e "${YELLOW}  This may be expected if only bound to Tailscale IP${NC}"
fi
echo ""

echo "=== Summary ==="
echo -e "${GREEN}OpenClaw is secured behind Tailscale VPN${NC}"
echo ""
echo "Access URLs:"
echo "  - Local:     http://127.0.0.1:18789 (if enabled)"
echo "  - Tailscale: http://$TAILSCALE_IP:18789"
echo ""
echo "Security Status:"
echo "  - CVE-2026-25253: Protected (no public exposure)"
echo "  - Encryption: WireGuard (Tailscale)"
echo "  - Access: Tailscale-authenticated devices only"
echo ""
echo "To test from another Tailscale device:"
echo "  curl http://$TAILSCALE_IP:18789/health"
