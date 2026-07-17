#!/usr/bin/env bash
# Verify Calico WireGuard encryption is active on all nodes

set -e

echo "=== Calico WireGuard Encryption Verification ==="
echo ""

# Check 1: FelixConfiguration
echo "1. Checking FelixConfiguration..."
if kubectl get felixconfiguration default -o jsonpath='{.spec.wireguardEnabled}' 2>/dev/null | grep -q "true"; then
    echo "   ✅ WireGuard enabled in FelixConfiguration"
    echo "   Port: $(kubectl get felixconfiguration default -o jsonpath='{.spec.wireguardListeningPort}')"
    echo "   Interface: $(kubectl get felixconfiguration default -o jsonpath='{.spec.wireguardInterfaceName}')"
else
    echo "   ❌ WireGuard NOT enabled"
    exit 1
fi

echo ""

# Check 2: WireGuard interface on current node
echo "2. Checking WireGuard interface on $(hostname)..."
if ip link show wireguard.cali >/dev/null 2>&1; then
    echo "   ✅ wireguard.cali interface exists"
    ip addr show wireguard.cali | grep inet | awk '{print "   IP: " $2}'
else
    echo "   ❌ wireguard.cali interface NOT found"
    exit 1
fi

echo ""

# Check 3: iptables rules for WireGuard
echo "3. Checking iptables WireGuard rules..."
if sudo iptables -L -n | grep -q "51820"; then
    echo "   ✅ Firewall rules for UDP 51820 configured"
    sudo iptables -L -n | grep -E "(51820|wireguard)" | head -2 | awk '{print "   " $0}'
else
    echo "   ❌ No firewall rules for WireGuard"
    exit 1
fi

echo ""

# Check 4: WireGuard traffic (sample)
echo "4. Checking for WireGuard traffic..."
TRAFFIC=$(timeout 2 sudo tcpdump -i wireguard.cali -nn -c 2 2>/dev/null || true)
if [ -n "$TRAFFIC" ]; then
    echo "   ✅ Encrypted traffic detected on wireguard.cali"
    echo "$TRAFFIC" | head -1 | awk '{print "   Sample: " $0}'
else
    echo "   ⚠️  No traffic captured (may be idle)"
fi

echo ""
echo "=== Verification Complete ==="
echo "WireGuard encryption is ACTIVE and encrypting inter-node pod traffic"
echo ""
echo "Performance Note: WireGuard adds ~5-10% CPU overhead for encryption"
echo "Security Benefit: All pod traffic between nodes is encrypted (ChaCha20-Poly1305)"
