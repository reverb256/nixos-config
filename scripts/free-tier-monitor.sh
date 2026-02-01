#!/usr/bin/env bash
set -e

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

echo "=== NixOS Free Tier Usage Monitor ==="
echo "Date: $(date)"
echo ""

echo "📦 Nix Store Usage:"
STORE_SIZE=$(nix path-info -S /run/current-system 2>/dev/null | awk '{print $1}' || echo "0")
echo "  Current system closure: $STORE_SIZE"
TOTAL_STORE=$(du -sh /nix/store 2>/dev/null | awk '{print $1}' || echo "Unknown")
echo "  Total store size: $TOTAL_STORE"
echo ""

echo "🔄 Garnix Cache:"
if grep -q "cache.garnix.io" /etc/nix/nix.conf 2>/dev/null; then
    echo "  ✓ Configured (https://garnix.io/dashboard)"
else
    echo "  ⚠ Not configured"
fi
echo ""

echo "🔨 Build Generations:"
if [ -d /nix/var/nix/profiles/system ]; then
    GENERATION_COUNT=$(ls -1 /nix/var/nix/profiles/system-* 2>/dev/null | wc -l)
    echo "  Count: $GENERATION_COUNT"
    
    if [ $GENERATION_COUNT -gt 50 ]; then
        echo -e "  ${YELLOW}⚠ Warning: High generation count${NC}"
        echo "  Run: sudo nix-collect-garbage --delete-older-than 30d"
    fi
fi
echo ""

echo "💾 Disk Space:"
DISK_USAGE=$(df -h /nix | tail -1 | awk '{print $5}' | sed 's/%//')
if [ "$DISK_USAGE" -gt 80 ]; then
    echo -e "  ${RED}⚠ CRITICAL: ${DISK_USAGE}% usage${NC}"
    echo "  Run: sudo nix-collect-garbage -d"
elif [ "$DISK_USAGE" -gt 60 ]; then
    echo -e "  ${YELLOW}⚠ Warning: ${DISK_USAGE}% usage${NC}"
else
    echo -e "  ${GREEN}✓ OK: ${DISK_USAGE}% usage${NC}"
fi
echo ""

echo "=== Actions ==="
echo "Weekly: sudo nix-collect-garbage"
echo "Monthly: nix-store --optimise"
echo "Check: https://garnix.io/dashboard"
