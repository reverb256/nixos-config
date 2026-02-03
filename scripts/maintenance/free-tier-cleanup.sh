#!/usr/bin/env bash
set -e

sudo nix-collect-garbage --delete-older-than 30d
sudo nix-store --optimise

if command -v home-manager &> /dev/null; then
    home-manager generations | tail -n +10 | while read -r line; do
        gen=$(echo "$line" | awk '{print $1}')
        if [ -n "$gen" ]; then
            nix-env --delete-generations "$gen" 2>/dev/null || true
        fi
    done
fi

echo "$(date): Cleanup completed"
