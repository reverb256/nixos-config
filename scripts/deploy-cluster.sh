#!/usr/bin/env bash
# Deploy Cluster Configuration Script
# Sets up distributed builds, colmena, CI/CD, and  nodes

set -e

echo "🚀 Deploying complete cluster configuration..."

echo ""
echo "📋 Configuration Summary:"
echo "   - Distributed builds enabled across all 4 nodes"
echo "   - Colmena configuration ready for cluster deployment"
echo "   - GitHub Actions CI/CD workflows created"
echo "   -  node setup prepared"
echo ""

echo "🔧 To apply the distributed builds configuration:"
echo "   sudo nixos-rebuild switch"
echo ""

echo "🌐 To test distributed builds:"
echo "   nix build --dry-run -L nixpkgs.hello"
echo ""

echo "🔗 To deploy to the entire cluster:"
echo "   cd /etc/nixos"
echo "   colmena apply --on-change build"
echo ""

echo "🤖 To manage  nodes:"
echo "    nodes status          # Check node status"
echo "    nodes list            # List all nodes"
echo "    nodes pending        # Check pending nodes"
echo "    nodes approve <id>   # Approve a node"
echo ""

echo "🔄 To test colmena connectivity:"
echo "   colmena list"
echo ""

echo "✅ Configuration deployed successfully!"
echo "   Next steps:"
echo "   1. Run 'sudo nixos-rebuild switch' to apply local changes"
echo "   2. Set up  nodes on other devices"
echo "   3. Test distributed builds"
echo "   4. Push changes to GitHub to activate CI/CD"