#!/usr/bin/env bash
# Test Distributed Builds Script
# Verifies that distributed builds are configured correctly across the cluster

set -e

echo "🧪 Testing distributed builds configuration..."

echo ""
echo "🔍 Checking SSH connectivity to cluster nodes..."
for node in nexus forge sentry; do
    echo "  Testing $node..."
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no $node "hostname" >/dev/null 2>&1; then
        echo "    ✅ $node is reachable"
    else
        echo "    ❌ $node is not reachable - check SSH configuration"
    fi
done

echo ""
echo "📋 Checking nix build machines configuration..."
if command -v nix &> /dev/null; then
    echo "  Nix is installed"
    echo "  Build machines configured:"
    nix show-config | grep build-machi || echo "  No build machines found in config"
else
    echo "  ❌ Nix is not in PATH"
fi

echo ""
echo "🔧 Testing distributed builds setup..."
# Check if the nixbuild user exists on remote nodes
for node in nexus forge sentry; do
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no $node "id nixbuild" >/dev/null 2>&1; then
        echo "    ✅ nixbuild user exists on $node"
    else
        echo "    ⚠️  nixbuild user does not exist on $node"
    fi
done

echo ""
echo "🌐 Testing SSH key access..."
if [ -f ~/.ssh/id_nixbuild ]; then
    echo "  ✅ SSH key for distributed builds exists"
    echo "  Public key:"
    cat ~/.ssh/id_nixbuild.pub 2>/dev/null || echo "  (not found)"
else
    echo "  ❌ SSH key for distributed builds does not exist"
    echo "     Expected: ~/.ssh/id_nixbuild"
fi

echo ""
echo "🎯 To test actual distributed builds:"
echo "  nix build --dry-run -L nixpkgs.hello"
echo "  nix build --max-jobs 8 -L nixpkgs.hello  # Should distribute across nodes"
echo ""

echo "✅ Distributed builds test completed!"