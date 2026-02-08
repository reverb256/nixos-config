#!/usr/bin/env bash
# Comprehensive Cluster Verification Script
# Tests distributed builds, colmena, and  node readiness

set -e

echo "🚀 Comprehensive Cluster Verification"
echo "====================================="

echo ""
echo "1️⃣  Testing  Services..."
if pgrep -f -gateway >/dev/null 2>&1; then
    echo "   ✅  gateway is running"
    echo "   🌐 Access at: http://localhost:18789"
else
    echo "   ⚠️   gateway is not running"
    echo "   🔧 Start with: systemctl --user start -gateway"
fi

echo ""
echo "2️⃣  Testing  Node Status..."
if command -v  >/dev/null 2>&1; then
    echo "   ✅  CLI is available"
    echo "   📋 Node status:"
     nodes status 2>/dev/null | head -10 || echo "   (nodes not yet configured)"
else
    echo "   ⚠️   CLI is not available"
fi

echo ""
echo "3️⃣  Testing Colmena Configuration..."
if [ -f colmena.nix ]; then
    echo "   ✅ Colmena configuration exists"
    echo "   📋 Available nodes:"
    nix eval .#nodes --apply 'builtins.attrNames' --impure --experimental-features 'nix-command flakes' 2>/dev/null || echo "   (colmena not configured)"
else
    echo "   ⚠️  Colmena configuration not found"
fi

echo ""
echo "4️⃣  Testing Distributed Builds..."
echo "   🏗️  Build machines configuration:"
nix show-config 2>/dev/null | grep -i build || echo "   (no build config visible)"

echo ""
echo "5️⃣  Testing SSH Connectivity to Cluster Nodes..."
for node in nexus forge sentry; do
    if ping -c 1 -W 2 $node >/dev/null 2>&1; then
        echo "   ✅ $node - reachable"
    else
        echo "   ❌ $node - unreachable"
    fi
done

echo ""
echo "6️⃣  Testing GitHub Actions Readiness..."
if [ -d .github/workflows ]; then
    echo "   ✅ GitHub Actions workflows are configured"
    echo "   📁 Workflow files:"
    ls -la .github/workflows/
else
    echo "   ⚠️  GitHub Actions workflows not found"
fi

echo ""
echo "7️⃣  Testing System Status..."
echo "   🖥️  Hostname: $(hostname)"
echo "   ⏰ Uptime: $(uptime)"
echo "   🔋 Mining status:"
if systemctl --user is-active lolminer-nvidia >/dev/null 2>&1; then
    echo "      ✅ lolminer-nvidia is running"
else
    echo "      ⚠️  lolminer-nvidia is not running"
fi

echo ""
echo "8️⃣  Testing Repository State..."
echo "   📦 Git status:"
git status --porcelain

echo ""
echo "📋 Summary of Ready Components:"
echo "   -  Gateway: $(if pgrep -f -gateway >/dev/null 2>&1; then echo "✅"; else echo "❌"; fi)"
echo "   -  CLI: $(if command -v  >/dev/null 2>&1; then echo "✅"; else echo "❌"; fi)"
echo "   - Distributed Builds: $(if [ -f ~/.ssh/id_nixbuild ]; then echo "✅"; else echo "❌"; fi)"
echo "   - Colmena Config: $(if [ -f colmena.nix ]; then echo "✅"; else echo "❌"; fi)"
echo "   - GitHub Actions: $(if [ -d .github/workflows ]; then echo "✅"; else echo "❌"; fi)"
echo "   - Cluster Connectivity: $(if ping -c 1 -W 1 nexus >/dev/null 2>&1; then echo "✅"; else echo "❌"; fi)"

echo ""
echo "🎉 Verification Complete!"
echo ""
echo "Next steps:"
echo "1. If distributed builds aren't working, run: sudo nixos-rebuild switch"
echo "2. To deploy to cluster: colmena apply --on-change build"
echo "3. To test  nodes:  nodes status"
echo "4. Push changes to GitHub to activate CI/CD"