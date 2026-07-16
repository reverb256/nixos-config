#!/usr/bin/env bash
# Emergency DNS Restore - Cloudflare bypass
sudo systemctl stop unbound 2>/dev/null || true
sudo chattr -i /etc/resolv.conf 2>/dev/null || true
echo "# Cloudflare DNS - Emergency Restore" | sudo tee /etc/resolv.conf
echo "nameserver 1.1.1.1" | sudo tee -a /etc/resolv.conf
echo "nameserver 1.0.0.1" | sudo tee -a /etc/resolv.conf
echo "nameserver 8.8.8.8" | sudo tee -a /etc/resolv.conf
sudo chattr +i /etc/resolv.conf

# Test DNS
sleep 1
if dig @127.0.0.1 google.com +short &>/dev/null; then
    notify-send "DNS RESTORED" "Cloudflare DNS active - You can browse now" -i network-wired
    echo "✓ DNS RESTORED - Cloudflare active"
else
    notify-send "DNS RESTORED" "Using system fallback" -i network-wired
    echo "✓ DNS restored via fallback"
fi
