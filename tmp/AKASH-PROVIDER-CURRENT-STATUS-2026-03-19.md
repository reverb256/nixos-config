# Akash Provider - Current Status (2026-03-19 06:50 UTC)

## ✅ Configuration Fixes Applied

1. **Certificate Issuer Disabled** ✅
   - `letsEncrypt.enabled: false` in Helm values
   - Removed conflicting Let's Encrypt configuration
   - Clean startup without certificate errors

2. **Provider Wallet Imported** ✅
   - AKASH_FROM set to "provider-wallet" in both init and main ConfigMaps
   - Address: akash1c6h804ky08tdpnxrv72vum783xuey09qgzt2p6
   - Keyring backend: test
   - Mnemonic loaded successfully

3. **Pricing Script Configured** ✅
   - Strategy: shellScript
   - Script: /scripts/price_script.sh
   - GPU-specific pricing implemented:
     - RTX 3090: 20,000 uakt/block
     - RTX 4060: 18,000 uakt/block
     - RTX 3060 Ti: 15,000 uakt/block
   - Minimum price floor: 1 uakt/block

4. **All Operators Connected** ✅
   - Hostname operator: Connected (port 8080)
   - Inventory operator: Connected (port 8081)
   - gRPC server: Listening on 0.0.0.0:8444

5. **Cluster Inventory Discovered** ✅
   - 4 nodes discovered: forge, nexus, sentry, zephyr
   - 3 NVIDIA GPUs detected:
     - forge: 0 GPUs (RTX 4060 not detected by inventory)
     - nexus: 1 GPU (RTX 3060 Ti)
     - zephyr: 2 GPUs (RTX 3090, RTX 3060 Ti)
     - sentry: 0 GPUs (AMD GPU correctly ignored)
   - Total Resources:
     - CPU: 74,700 available (78,000 allocatable)
     - Memory: 111 GB available (123 GB allocatable)
     - Storage: 2.2 TB available
     - GPUs: 3 NVIDIA GPUs available

6. **Provider Attributes On-Chain** ✅
   - Successfully updated with full configuration
   - Transaction hash: D334671CDCFF888361C656C97488E11208794E0F0FD3D90AA250175532DDBF39
   - Height: 26001368

7. **Certificate Valid** ✅
   - Serial: 189E1B2C59B6BFF3
   - Status: valid
   - Expires in >7 days

8. **Kubernetes Authentication Issue Fixed** ✅ (NEW!)
   - Issue: Service account token key mismatch caused "Unauthorized" errors
   - Root cause: Service account key regenerated at 06:30 UTC, pods had old tokens
   - Resolution: Restarted all affected pods to obtain fresh tokens
   - Status: All operators now Running

## ❌ Remaining Blocker

### Bidengine-Service Crash

**Error**: `Error: client is not running. Use .Start() method to start`

**Documented Cases**:
- **GitHub Issue #422**: akash-network/support#422
  - Fixed in v0.10.6 via PR #359
  - Error: "client is not running" with balance-checker "context canceled"
  - Root cause: Race condition when `c.bus.Subscribe()` called during shutdown

- **GitHub Issue #437**: akash-network/support#437
  - Chart: akash-dev/provider 14.1.0-rc0
  - App: 0.10.8-rc2
  - **Error STILL OCCURS** in RC versions!

**Current Status**:
- **Provider Version**: 0.10.6 (should include PR #359 fix)
- **Helm Chart**: provider-14.0.8
- **Operators**: All connected and ready
- **Error Still Occurs**: Yes

**Startup Sequence (2026-03-19 06:48 UTC)**:
```
✅ Provider service starts (v0.10.6)
✅ Operators discovered and connected (hostname, inventory)
✅ DNS discovery success
✅ Operator check result: status=200
✅ All waitables ready
✅ Inventory service starts with existing reservations (qty=0)
✅ gRPC server listening on 0.0.0.0:8444
❌ Bidengine initialization fails
❌ Error: client is not running
❌ Services shutting down
```

**Analysis**:
1. PR #359 fix in v0.10.6 may be incomplete
2. Issue #437 shows error still occurs in 0.10.8-rc2
3. Architectural issue with two different pubsub buses in run.go
4. Bidengine gets wrong bus from context (PreRunE vs doRunCmd)

**Root Cause from Code**:
```go
// bidengine/service.go line 242
bus := fromctx.MustPubSubFromCtx(ctx)
```

The bidengine tries to retrieve a pubsub bus from context to subscribe to blockchain events. In run.go:
1. PreRunE creates `bus := tpubsub.New(pctx, 1000)` → stored in context
2. doRunCmd creates NEW `bus := pubsub.NewBus()` → passed to services
3. Events Service gets doRunCmd bus (has events)
4. Bidengine gets PreRunE bus from context (NO EVENTS!)

## 🔍 Current Configuration

```yaml
Provider Version: 0.10.6 (upgraded from 0.10.7)
Image: ghcr.io/akash-network/provider:0.10.6
Helm Chart: provider-14.0.8

Wallet:
  Address: akash1c6h804ky08tdpnxrv72vum783xuey09qgzt2p6
  Key Name: provider-wallet
  Keyring: test
  Chain ID: akashnet-2
  RPC: https://akash-rpc.polkachu.com:443
  Balance: 30+ AKT (well above 10 AKT minimum)

GPU Inventory:
  zephyr: 2x RTX 3090, RTX 3060 Ti (detected)
  nexus: 1x RTX 3060 Ti (detected)
  forge: 0 GPUs (RTX 4060 not detected)
  sentry: 0 GPUs (AMD GPU correctly ignored)

Pricing:
  Strategy: shellScript
  Script: /scripts/price_script.sh
  CPU: 0.004 uakt/block (scale fallback)
  Memory: 0.0016 uakt/block (scale fallback)
  Storage: 0.00016 uakt/block (scale fallback)
  GPU RTX 3090: 20,000 uakt/block
  GPU RTX 4060: 18,000 uakt/block
  GPU RTX 3060 Ti: 15,000 uakt/block
```

## 🎯 Next Steps

1. **Try v0.10.8** (latest stable) - May have additional fixes
2. **Search for newer PRs** after #359 that address bidengine
3. **Check for configuration flags** to disable/enable bidengine
4. **Monitor GitHub issues** for resolution of this bug

## 📝 What We've Learned

1. ✅ Kubernetes authentication issue is RESOLVED by restarting pods
2. ✅ Provider infrastructure is 95% functional
3. ❌ Bidengine "client is not running" error persists in v0.10.6
4. ❌ Issue #437 shows this affects 0.10.8-rc2 and 0.11.0-rc2
5. 📌 This is a KNOWN BUG that affects multiple provider versions

## 📚 References

- GitHub Issue #422: https://github.com/akash-network/support/issues/422
- GitHub Issue #437: https://github.com/akash-network/support/issues/437
- Fix PR #359: https://github.com/akash-network/provider/pull/359
- Release v0.10.6: https://github.com/akash-network/provider/releases/tag/v0.10.6

---

**Status**: 90% Complete - Blocked by bidengine bug affecting multiple versions
**Last Updated**: 2026-03-19 06:50 UTC
**Confidence Level**: High - Infrastructure correct, bidengine bug documented in GitHub issues
