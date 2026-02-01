#!/usr/bin/env bash
# Quick validation script for OpenClaw AIStor setup
# Verifies all components are properly configured

echo "=== OpenClaw AIStor Setup Validation ==="
echo ""

ERRORS=0

# Check 1: Verify configuration files exist
echo "Checking configuration files..."
[ -f "/etc/nixos/hosts/nexus/configuration.nix" ] && echo "✓ nexus configuration exists" || { echo "✗ nexus configuration missing"; ((ERRORS++)); }
[ -f "/etc/nixos/hosts/zephyr/configuration.nix" ] && echo "✓ zephyr configuration exists" || { echo "✗ zephyr configuration missing"; ((ERRORS++)); }
[ -f "/etc/nixos/modules/openclaw-storage.nix" ] && echo "✓ openclaw-storage module exists" || { echo "✗ openclaw-storage module missing"; ((ERRORS++)); }
[ -f "/etc/nixos/modules/openclaw-storage-mcp.py" ] && echo "✓ openclaw-storage-mcp.py exists" || { echo "✗ openclaw-storage-mcp.py missing"; ((ERRORS++)); }
echo ""

# Check 2: Verify scripts exist
echo "Checking scripts..."
[ -f "/etc/nixos/scripts/openclaw-aistor-workflows.py" ] && echo "✓ openclaw-aistor-workflows.py exists" || { echo "✗ Workflow script missing"; ((ERRORS++)); }
[ -f "/etc/nixos/scripts/setup-aistor-full-capabilities.sh" ] && echo "✓ setup-aistor-full-capabilities.sh exists" || { echo "✗ Setup script missing"; ((ERRORS++)); }
[ -f "/etc/nixos/scripts/test-openclaw-workflows.sh" ] && echo "✓ test-openclaw-workflows.sh exists" || { echo "✗ Test script missing"; ((ERRORS++)); }
echo ""

# Check 3: Verify secrets configuration
echo "Checking secrets configuration..."
[ -f "/etc/nixos/secrets/secrets.nix" ] && echo "✓ secrets.nix exists" || { echo "✗ secrets.nix missing"; ((ERRORS++)); }
[ -f "/etc/nixos/secrets/age-secrets.nix" ] && echo "✓ age-secrets.nix exists" || { echo "✗ age-secrets.nix missing"; ((ERRORS++)); }
if grep -q "minio-cache-credentials" /etc/nixos/secrets/secrets.nix 2>/dev/null; then
    echo "✓ minio-cache-credentials in secrets.nix"
else
    echo "✗ minio-cache-credentials not in secrets.nix"
    ((ERRORS++))
fi
if grep -q "minio-cache-credentials" /etc/nixos/secrets/age-secrets.nix 2>/dev/null; then
    echo "✓ minio-cache-credentials in age-secrets.nix"
else
    echo "✗ minio-cache-credentials not in age-secrets.nix"
    ((ERRORS++))
fi
echo ""

# Check 4: Check if minio-cache-credentials.age is encrypted
if [ -f "/etc/nixos/secrets/minio-cache-credentials.age" ]; then
    echo "✓ minio-cache-credentials.age exists (encrypted)"
else
    echo "⚠ minio-cache-credentials.age not found - needs encryption"
    echo "  Create: secrets/minio-cache-credentials.template -> encrypt with agenix"
fi
echo ""

# Check 5: Verify AIStor configuration in nexus
echo "Checking nexus AIStor configuration..."
if grep -q "services.minio.enable = true" /etc/nixos/hosts/nexus/configuration.nix 2>/dev/null; then
    echo "✓ MinIO enabled in nexus config"
else
    echo "✗ MinIO not enabled in nexus config"
    ((ERRORS++))
fi
if grep -q "listenAddress.*10.1.1.120:9000" /etc/nixos/hosts/nexus/configuration.nix 2>/dev/null; then
    echo "✓ MinIO listen address configured"
else
    echo "✗ MinIO listen address not configured"
    ((ERRORS++))
fi
echo ""

# Check 6: Verify zephyr cache configuration
echo "Checking zephyr cache configuration..."
if grep -q "services.nixos-minio-cache.enable = true" /etc/nixos/hosts/zephyr/configuration.nix 2>/dev/null; then
    echo "✓ MinIO cache enabled in zephyr config"
else
    echo "✗ MinIO cache not enabled in zephyr config"
    ((ERRORS++))
fi
if grep -q 'endpoint.*10.1.1.120:9000' /etc/nixos/hosts/zephyr/configuration.nix 2>/dev/null; then
    echo "✓ Cache endpoint configured"
else
    echo "✗ Cache endpoint not configured"
    ((ERRORS++))
fi
echo ""

# Check 7: Check documentation
echo "Checking documentation..."
[ -f "/etc/nixos/AISTOR-DEPLOY.md" ] && echo "✓ AISTOR-DEPLOY.md exists" || { echo "✗ Deployment guide missing"; ((ERRORS++)); }
if grep -q "OpenClaw" /etc/nixos/AGENTS.md 2>/dev/null; then
    echo "✓ AGENTS.md mentions OpenClaw"
else
    echo "⚠ AGENTS.md may need OpenClaw documentation"
fi
echo ""

# Summary
echo "=== Validation Summary ==="
if [ $ERRORS -eq 0 ]; then
    echo "✓ All critical components present and configured"
    echo ""
    echo "Next steps:"
    echo "  1. Encrypt credentials: agenix -e secrets/minio-cache-credentials.age"
    echo "  2. Deploy to nexus: just deploy-nexus"
    echo "  3. Setup buckets: ./scripts/setup-aistor-full-capabilities.sh"
    echo "  4. Deploy to zephyr: just deploy-zephyr"
    echo "  5. Run tests: ./scripts/test-openclaw-workflows.sh"
    exit 0
else
    echo "✗ $ERRORS validation errors found"
    echo "Please review the errors above and fix missing components"
    exit 1
fi
