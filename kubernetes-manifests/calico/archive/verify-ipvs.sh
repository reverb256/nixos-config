#!/usr/bin/env bash
# IPVS Verification Script
# Verifies IPVS is properly configured on Kubernetes cluster
#
# Usage: ./verify-ipvs.sh

set -euo pipefail

echo "=========================================="
echo "IPVS Verification Script"
echo "=========================================="
echo

# Step 1: Check IPVS kernel modules
echo "Step 1: Checking IPVS kernel modules..."
echo "----------------------------------------"
if lsmod | grep -E '^ip_vs ' > /dev/null; then
    echo "✅ IPVS modules loaded:"
    lsmod | grep ip_vs
else
    echo "❌ IPVS modules NOT loaded"
    echo "Expected modules: ip_vs, ip_vs_rr, ip_vs_wrr, ip_vs_sh"
    exit 1
fi
echo

# Step 2: Check IPVS stats
echo "Step 2: Checking IPVS stats..."
echo "----------------------------------------"
if command -v ipvsadm &> /dev/null; then
    if ipvsadm -Ln &> /dev/null; then
        echo "✅ IPVS is active:"
        ipvsadm -Ln
    else
        echo "⚠️  IPVS modules loaded but no virtual servers configured yet"
        echo "This is normal before kube-proxy starts using IPVS"
    fi
else
    echo "❌ ipvsadm not found - install with: nix-shell -p ipvsadm"
    exit 1
fi
echo

# Step 3: Check kube-proxy mode
echo "Step 3: Checking kube-proxy mode..."
echo "----------------------------------------"
KUBE_PROXY_POD=$(kubectl get pods -n kube-system -l k8s-app=kube-proxy -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$KUBE_PROXY_POD" ]; then
    echo "✅ kube-proxy pod found: $KUBE_PROXY_POD"
    if kubectl logs -n kube-system "$KUBE_PROXY_POD" 2>/dev/null | grep -q "Using ipvs Proxier"; then
        echo "✅ kube-proxy is using IPVS mode"
        echo "Recent logs:"
        kubectl logs -n kube-system "$KUBE_PROXY_POD" --tail=5 2>/dev/null | grep -i ipvs || true
    else
        echo "❌ kube-proxy NOT using IPVS mode (still using iptables)"
        echo "Check: kubectl logs -n kube-system $KUBE_PROXY_POD"
    fi
else
    echo "❌ kube-proxy pod not found"
fi
echo

# Step 4: Check ipvsadm availability
echo "Step 4: Checking ipvsadm installation..."
echo "----------------------------------------"
if command -v ipvsadm &> /dev/null; then
    IPVSADM_VERSION=$(ipvsadm -v 2>&1 | head -1)
    echo "✅ ipvsadm installed: $IPVSADM_VERSION"
else
    echo "❌ ipvsadm not found in PATH"
    echo "Install: nix-shell -p ipvsadm"
fi
echo

# Step 5: Summary
echo "=========================================="
echo "IPVS Verification Summary"
echo "=========================================="
echo
echo "Next steps:"
echo "1. If IPVS modules not loaded: Reboot or run: modprobe ip_vs ip_vs_rr ip_vs_wrr ip_vs_sh"
echo "2. If kube-proxy not using IPVS: Restart kube-proxy pods"
echo "3. Monitor IPVS performance: ipvsadm -Ln --rate"
echo
echo "Documentation:"
echo "- IPVS: https://kernel.org/doc/Documentation/networking/ipvs-sysctl.txt"
echo "- kube-proxy IPVS: https://kubernetes.io/docs/tasks/administer-cluster/kube-proxy/"
echo
