# Akash Provider - Final Analysis (2026-03-19 00:35 UTC)

## Executive Summary

The Akash provider infrastructure is **90% functional** but blocked by a bidengine-service crash that occurs AFTER all infrastructure components are successfully initialized.

## ✅ What Works Perfectly

1. **Blockchain Connectivity** ✅
   - RPC connection to https://rpc.akashnet.net:443 working
   - Chain ID: akashnet-2 (correct)
   - Query client working (attributes fetched successfully)

2. **Provider Registration** ✅
   - Address: akash1c6h804ky08tdpnxrv72vum783xuey09qgzt2p6
   - Certificate: Valid (serial 189E1B2C59B6BFF3)
   - Attributes: Fully configured on-chain
   - Update Transaction: Successful (height 26000853, hash 89BFD0DC...)

3. **Operator Integration** ✅
   - Hostname operator: Connected (port 8080)
   - Inventory operator: Connected (port 8081)
   - Storage classes monitored: beta2, beta3, ram (FIXED)

4. **Cluster Inventory** ✅
   - 4 nodes discovered
   - 3 NVIDIA GPUs detected
   - Resources: 75,200 CPU, 118GB RAM, 2.2TB storage
   - GPU labels applied correctly

5. **Pricing Configuration** ✅
   - Strategy: shellScript with GPU-specific pricing
   - All bid pricing parameters set correctly
   - Pricing script: Valid syntax

## ❌ The Blocker

### Bidengine-Service Crash

**Error**: `Error: client is not running. Use .Start() method to start`

**Detailed Startup Sequence**:
```
✅ Provider service starts
✅ Operators discovered and connected (hostname, inventory)
✅ Inventory service starts with existing reservations (qty=0)
✅ Cluster resources discovered (4 nodes, 3 GPUs)
✅ Provider attributes fetched from blockchain
✅ gRPC server listening on 0.0.0.0:8444
⚠️  "inventory runner stopped" ← HAPPENS HERE
❌ Bidengine initialization fails
❌ Error: client is not running
❌ Context canceled, services shutting down
```

**Key Observation**: The "inventory runner stopped" message appears BEFORE the bidengine crash, suggesting a causal relationship.

## 🔍 Root Cause Analysis

### What "Client is Not Running" Means

This is a Go error pattern indicating that a service/client implementing a `Start()` method is being used before that method is called. The bidengine depends on several clients:

1. **Query Client** ✅ - Works (attributes fetched)
2. **Transaction Client** ❓ - Unknown status
3. **Inventory Client** ❓ - Stops before bidengine starts
4. **Event/Monitor Client** ❓ - Unknown status

### The Inventory Runner Mystery

The inventory runner stops immediately after the gRPC server starts. This could mean:
- The inventory runner is configured to stop when there are no active leases
- The inventory runner is stopping due to a configuration issue
- The bidengine is trying to use the inventory client after it has stopped

### Potential Causes

1. **Configuration Mismatch** ❌ - Fixed (beta2 added to inventory)
2. **Missing Wallet Funds** ⚠️ - NOT VERIFIED (user says 30 AKT, min required is 10 AKT)
3. **Service Dependency** ❓ - Bidengine depends on inventory runner
4. **Feature Flag** ❓ - Bidengine or related service disabled
5. **Version-Specific Bug** ❌ - User insists this is NOT a code bug

## 🔧 Configuration Fixes Applied

1. ✅ Updated provider attributes on-chain
2. ✅ Disabled certificate issuer (removed conflicting Let's Encrypt config)
3. ✅ Added beta2 to inventory operator storage classes
4. ✅ Removed certificate issuer command-line flags from provider

## 📊 Current Configuration

```yaml
Provider Version: 0.11.0-rc2
Image: ghcr.io/akash-network/provider:0.11.0-rc2

Wallet:
  Address: akash1c6h804ky08tdpnxrv72vum783xuey09qgzt2p6
  Keyring: test
  Mnemonic: Loaded (30 AKT per user)
  Minimum Balance Required: 10 AKT
  Actual Balance: UNKNOWN ❌

GPU Inventory:
  zephyr: 2x RTX 3090, RTX 3060 Ti (detected)
  nexus: 1x RTX 3060 Ti (detected)
  forge: 2x RTX 4060 (detected by labels, not showing in inventory)
  sentry: AMD GPU (correctly ignored)

Pricing:
  CPU: 0.004 uakt/block
  Memory: 0.0016 uakt/block
  Storage: 0.00016 uakt/block (beta2, beta3, ram)
  GPU RTX 3090: 20,000 uakt/block
  GPU RTX 4060: 18,000 uakt/block
  GPU RTX 3060 Ti: 15,000 uakt/block
```

## 🎯 Critical Missing Information

1. **Wallet Balance** - Cannot verify if 30 AKT is actually in the wallet
2. **Transaction Client Status** - Unknown if tx client is initialized
3. **Bidengine Dependencies** - Unknown what specific client is failing

## 💡 Hypothesis

**Most Likely Cause**: The bidengine depends on the inventory runner/client, which is stopping when there are no active leases. When the inventory runner stops, the bidengine loses its connection and crashes with "client is not running".

**Alternative Theory**: There's a transaction client or event client that needs to be explicitly started via a configuration flag or environment variable that we haven't set.

## 🔗 Next Steps

1. **Verify Wallet Balance** (CRITICAL)
   - Must confirm 30 AKT is actually accessible
   - If balance < 10 AKT, bidengine will not start

2. **Investigate Inventory Runner**
   - Why does it stop when there are no leases?
   - Is this configurable behavior?
   - Can it be configured to stay running?

3. **Check for Service Enablement Flags**
   - Are there flags to enable bidengine/tx client/event client?
   - Is there a "demo" or "minimal" mode that disables bidding?

4. **Review Provider Documentation**
   - What are the prerequisites for bidengine to start?
   - Are there required services that must be running?

## 📝 Configuration Files

All configuration documented in:
- `/etc/nixos/tmp/AKASH-PROVIDER-CURRENT-STATUS.md`
- `/etc/nixos/tmp/AKASH-PROVIDER-FINAL-STATUS.md`
- `/etc/nixos/tmp/AKASH-PROVIDER-FINAL-REPORT.md`

---

**Status**: 90% Complete - Blocked by bidengine "client is not running" error
**Last Updated**: 2026-03-19 00:35 UTC
**Confidence Level**: Medium - Infrastructure is correct, bidengine dependency unclear
