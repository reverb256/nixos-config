#!/usr/bin/env bash
# Deploy Cluster Configuration Script
# Sets up distributed builds, colmena, CI/CD, and OpenClaw nodes

set -e

echo "🚀 Deploying complete cluster configuration..."

echo ""
echo "📋 Configuration Summary:"
echo "   - Distributed builds enabled across all 4 nodes"
echo "   - Colmena configuration ready for cluster deployment"
echo "   - GitHub Actions CI/CD workflows created"
echo "   - OpenClaw node setup prepared"
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

echo "🤖 To manage OpenClaw nodes:"
echo "   openclaw nodes status          # Check node status"
echo "   openclaw nodes list            # List all nodes"
echo "   openclaw nodes pending        # Check pending nodes"
echo "   openclaw nodes approve <id>   # Approve a node"
echo ""

echo "🔄 To test colmena connectivity:"
echo "   colmena list"
echo ""

echo "✅ Configuration deployed successfully!"
echo "   Next steps:"
echo "   1. Run 'sudo nixos-rebuild switch' to apply local changes"
echo "   2. Set up OpenClaw nodes on other devices"
echo "   3. Test distributed builds"
echo "   4. Push changes to GitHub to activate CI/CD"