#!/usr/bin/env bash
# Pre-flight check for NixOS deployments.
# Run before nixos-rebuild to prevent resource contention from concurrent builds.
# Exits with code 0 if safe to proceed, 1 if blocked.
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
HOSTS=("zephyr" "nexus" "forge" "sentry")

echo "=== NixOS Deploy Pre-Flight ==="

BLOCKED=0

# 1. Check local nixos-rebuild processes
LOCAL_BUILDS=$(ps aux | grep -E '[n]ixos-rebuild' | wc -l)
if [ "$LOCAL_BUILDS" -gt 0 ]; then
    echo -e "${RED}❌ $LOCAL_BUILDS nixos-rebuild process(es) already running locally${NC}"
    ps aux | grep -E '[n]ixos-rebuild' | head -5
    BLOCKED=1
fi

# 2. Check local nix-daemon load
NIX_LOADS=$(ps aux | grep -E '[n]ix-build|[n]ix-daemon' | wc -l)
echo "   $NIX_LOADS nix build/daemon processes running"

# 3. Check rebuild locks on remote hosts
for host in "${HOSTS[@]}"; do
    if ssh -o ConnectTimeout=3 -o BatchMode=yes "$host" "test -f /run/nixos/switch-to-configuration.lock" 2>/dev/null; then
        echo -e "${RED}❌ switch-to-configuration lock active on $host${NC}"
        BLOCKED=1
    else
        echo -e "${GREEN}✓${NC} No lock on $host"
    fi
done

# 4. Check for stale .lock files in /run/nixos/ locally
if [ -f /run/nixos/switch-to-configuration.lock ]; then
    LOCK_PID=$(cat /run/nixos/switch-to-configuration.lock 2>/dev/null || echo "unknown")
    if [ "$LOCK_PID" != "unknown" ] && kill -0 "$LOCK_PID" 2>/dev/null; then
        echo -e "${RED}❌ Local switch-to-configuration lock held by PID $LOCK_PID${NC}"
        BLOCKED=1
    else
        echo -e "${YELLOW}⚠️ Stale local lock found (PID $LOCK_PID dead) — removing${NC}"
        rm -f /run/nixos/switch-to-configuration.lock
    fi
fi

echo ""
if [ "$BLOCKED" -eq 1 ]; then
    echo -e "${RED}❌ BLOCKED: Fix conflicts above before deploying${NC}"
    echo "   Wait for existing builds to complete, then retry."
    exit 1
fi

echo -e "${GREEN}✓ All clear — safe to deploy${NC}"
exit 0
