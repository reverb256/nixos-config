#!/bin/bash
# Cluster Mining Verification Script
# Run this to verify all mining services are using Kryptex pools correctly

echo "🔍 Verifying mining configuration across cluster..."

hosts=("zephyr" "nexus" "forge" "sentry")
expected_wallets=("krxXVNVMM7.zephyr" "krxXVNVMM7.nexus" "krxXVNVMM7.forge" "krxXVNVMM7.sentry")

for i in "${!hosts[@]}"; do
    host="${hosts[$i]}"
    expected_wallet="${expected_wallets[$i]}"

    echo ""
    echo "📊 Checking $host..."

    # Check if mining services are running
    mining_status=$(ssh j_kro@$host "systemctl is-active lolminer-nvidia xmrig 2>/dev/null || echo 'not running'")

    if [[ $mining_status == *"active"* ]]; then
        echo "✅ Mining services: RUNNING"

        # Check wallet configuration
        wallet_config=$(ssh j_kro@$host "grep '$expected_wallet' /etc/nixos/hosts/$host/configuration.nix 2>/dev/null || echo 'wallet not found'")

        if [[ $wallet_config == *"$expected_wallet"* ]]; then
            echo "✅ Wallet: $expected_wallet (CORRECT)"
        else
            echo "❌ Wallet: INCORRECT or MISSING"
            echo "   Expected: $expected_wallet"
        fi

        # Check pool configuration
        pool_config=$(ssh j_kro@$host "grep 'kryptex' /etc/nixos/hosts/$host/configuration.nix 2>/dev/null || echo 'pool not configured'")

        if [[ $pool_config == *"kryptex"* ]]; then
            echo "✅ Pool: KRYPTEX (CORRECT)"
        else
            echo "❌ Pool: NON-KRYPTEX POOLS FOUND"
        fi

    else
        echo "❌ Mining services: NOT RUNNING"
    fi
done

echo ""
echo "🎯 Mining verification complete!"
echo "💡 All services should show: RUNNING + CORRECT wallet + KRYPTEX pool"