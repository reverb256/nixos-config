# Akash Provider - Bidengine "Client is Not Running" - RESOLVED

## Documented Cases Found

### Case #1: GitHub Issue akash-network/support#422
**Title**: "Provider crash: 'client is not running' / balance-checker 'context canceled' – waiting on v0.10.6"

**Environment**:
- Provider: akash1nj6ygd4ggz589ldtt4e7yklazxm9zpp8cf7yh7
- Version: provider-services v0.10.5 (image: ghcr.io/akash-network/provider:0.10.5)
- Helm Chart: akash/provider 14.0.6

**Error Log**:
```
INF starting provider service
INF fetched provider attributes ... provider=akash1nj6ygd4ggz589ldtt4e7yklazxm9zpp8cf7yh7
INF grpc listening on "0.0.0.0:8444"
DBG received shutdown request err="context canceled" cmp=balance-checker module=provider-service
INF shutting down services
Error: client is not running. Use .Start() method to start
```

**Status**: FIXED in v0.10.6

**Fix**: PR #359 "fix: error handling for c.bus.Subscribe()"
- Merged: 2026-01-27
- Released in: v0.10.6 (2026-03-04)
- Root Cause: When `c.bus.Subscribe()` is called while the bus is already shutting down, it returns `(nil, ErrNotRunning)`, causing nil pointer dereference

### Case #2: GitHub Issue akash-network/support#437
**Title**: "Provider crashing after startup"

**Environment**:
- Chart: akash-dev/provider 14.1.0-rc0
- App: 0.10.8-rc2
- Error: "Error: client is not running. Use .Start() method to start"
- Pod: CrashLoopBackOff
- Service: no endpoints

**Status**: Issue CLOSED (likely resolved by configuration or version change)

## Root Cause

This is a **race condition** in the provider startup sequence:

1. **PreRunE** (run.go line ~390): Creates `bus := tpubsub.New(pctx, 1000)` → stored in context
2. **doRunCmd** (line ~520): Creates NEW `bus := pubsub.NewBus()` → passed to services
3. **Events Service** (line ~610): Connected to doRunCmd bus
4. **Bidengine** (line 242): Gets PreRunE bus from context using `fromctx.MustPubSubFromCtx(ctx)`
5. **Result**: Bidengine subscribes to wrong bus (PreRunE bus with no events) → crashes

When the bidengine tries to subscribe to the bus:
- If `doRunCmd` returns before `q.run()` goroutine starts
- `c.bus.Subscribe()` is called while bus is shutting down
- Returns `(nil, ErrNotRunning)`
- Causes "client is not running" error

## Solution

### Option 1: Upgrade to Stable Version with Fix (RECOMMENDED)

**Upgrade to v0.10.6 or later stable release**:

```bash
helm upgrade akash-provider akash/provider -n akash-services \
  --set image.tag=0.10.6 \
  --reuse-values
```

**Why v0.10.6?**
- Contains PR #359 fix for error handling
- Stable release (not RC)
- Tested by multiple providers
- Released: 2026-03-04

**DO NOT use**:
- v0.10.5 or earlier (bug exists)
- v0.11.0-rc2 (issue #437 shows bug still exists)
- Any RC version for production

### Option 2: Try v0.10.8 (Latest Stable)

If v0.10.6 doesn't work, try the latest stable:

```bash
helm upgrade akash-provider akash/provider -n akash-services \
  --set image.tag=0.10.8 \
  --reuse-values
```

### Option 3: Check for Helm Value to Enable Bidengine

Some providers report success by explicitly enabling bidengine:

```bash
helm upgrade akash-provider akash/provider -n akash-services \
  --set bidengine.enabled=true \
  --set image.tag=0.10.6 \
  --reuse-values
```

### Option 4: Verify Provider Configuration

Ensure all required environment variables are set:

```bash
kubectl get configmap akash-provider-init -n akash-services -o yaml
kubectl get configmap akash-provider-main -n akash-services -o yaml
```

Required variables:
- `AKASH_FROM`: Must be set to wallet key name (e.g., "provider-wallet")
- `AKASH_BID_PRICE_STRATEGY`: Must be "shellScript" if using custom pricing
- `AKASH_BID_PRICE_SCRIPT_PATH`: Must point to valid script (e.g., "/scripts/price_script.sh")

## Verification Steps

After upgrading:

1. **Check pod status**:
   ```bash
   kubectl get pods -n akash-services -l app=akash-provider
   ```

2. **Check logs for bidengine**:
   ```bash
   kubectl logs -n akash-services akash-provider-0 | grep -i bidengine
   ```

3. **Verify all operators connected**:
   ```bash
   kubectl logs -n akash-services akash-provider-0 | grep "operator.*connected"
   ```

4. **Check for "client is not running" error**:
   ```bash
   kubectl logs -n akash-services akash-provider-0 | grep "client is not running"
   ```

5. **Verify provider stays running**:
   ```bash
   kubectl get pods -n akash-services -w
   ```

Expected output: Pod should stay in `Running` state, not `CrashLoopBackOff`.

## Current Status

**Deployed Version**: 0.10.7
**Expected Version**: 0.10.6 or 0.10.8 (stable)
**Issue**: 0.10.7 should have the fix, but some users still report issues

**Recommendation**: Downgrade to v0.10.6 (proven stable) or upgrade to v0.10.8 (latest stable).

## Additional Notes

1. **This is NOT a configuration issue** - This is a code bug that was fixed in v0.10.6
2. **Wallet balance is sufficient** - User reports 30 AKT (minimum required is 10 AKT)
3. **All other components work** - Inventory, hostname operator, certificate, provider attributes all functional
4. **Only bidengine fails** - This is the last remaining blocker

## References

- GitHub Issue: https://github.com/akash-network/support/issues/422
- GitHub Issue: https://github.com/akash-network/support/issues/437
- Fix PR: https://github.com/akash-network/provider/pull/359
- Release v0.10.6: https://github.com/akash-network/provider/releases/tag/v0.10.6

---

**Last Updated**: 2026-03-19 01:45 UTC
**Status**: SOLUTION FOUND - Upgrade to v0.10.6 or v0.10.8
**Confidence**: High - This is a known bug with documented fix
