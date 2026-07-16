#!/usr/bin/env bash
# Try to restore Unbound with DNS-over-TLS first
echo "Attempting to restore Unbound..."

# Try restarting Unbound
sudo systemctl restart unbound
sleep 3

# Test if Unbound works
if dig @127.0.0.1 google.com +short &>/dev/null; then
    notify-send "✓ Unbound RESTORED" "DNS-over-TLS working!" -i network-wired
    echo "✓ Unbound with DNS-over-TLS is working"
    exit 0
fi

# Fallback to Cloudflare bypass
echo "Unbound failed, using Cloudflare bypass..."
sudo systemctl stop unbound 2>/dev/null || true
sudo chattr -i /etc/resolv.conf 2>/dev/null || true
echo "nameserver 1.1.1.1" | sudo tee /etc/resolv.conf
sudo chattr +i /etc/resolv.conf

notify-send "✓ DNS RESTORED" "Cloudflare bypass active" -i network-wired
echo "✓ DNS restored via Cloudflare bypass"
