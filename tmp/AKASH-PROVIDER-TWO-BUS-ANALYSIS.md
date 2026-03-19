# Akash Provider - Two-Bus Architecture Bug Analysis

## Executive Summary

**Status**: BLOCKED by known code bug affecting multiple provider versions
**Impact**: Provider crashes after successful startup with "client is not running" error
**Affected Versions**: v0.10.5 through v0.11.0-rc2
**Successfully Running**: 72% of providers (43/60) run v0.10.7 - workaround exists!

## Root Cause: Two-Bus Architecture Bug

### The Problem (Code Level)

In `cmd/provider-services/cmd/run.go`:

```go
// Line 277 - PreRunE phase
bus := tpubsub.New(pctx, 1000)  // Creates github.com/troian/pubsub bus
fromctx.CmdSetContextValue(cmd, fromctx.CtxKeyPubSub, bus)

// Line 561 - doRunCmd phase
bus := pubsub.NewBus()  // Creates pkg.akt.dev/go/util/pubsub bus
defer bus.Close()
```

### Two Different PubSub Packages

| Package | Path | Usage |
|---------|------|-------|
| `tpubsub` | `github.com/troian/pubsub` | External library, stored in context |
| `pubsub` | `pkg.akt.dev/go/util/pubsub` | Akash internal, passed to services |

### Failure Mode

1. **PreRunE** creates `tpubsub` bus → stores in context
2. **doRunCmd** creates NEW `pubsub` bus → passes to services
3. **Events Service** gets `pubsub` bus from parameter (has events)
4. **Bidengine/Manifest/Cluster** call `fromctx.MustPubSubFromCtx()` → get `tpubsub` bus (NO EVENTS!)
5. **Balance Checker** subscribes to wrong bus → `context canceled`
6. **Cascade shutdown** → "client is not running" error

## Startup Sequence Analysis

### Working Startup (Expected)
```
✅ Provider service starts
✅ Operators discovered and connected
✅ DNS discovery success
✅ gRPC listening on 0.0.0.0:8444
✅ Bidengine starts receiving orders
✅ Provider stays running
```

### Our Startup (Actual)
```
✅ Provider service starts (v0.10.6)
✅ Operators discovered and connected
✅ DNS discovery success
✅ Operator check result: status=200
✅ All waitables ready
✅ Inventory service starts with existing reservations (qty=0)
✅ gRPC listening on 0.0.0.0:8444
❌ Balance-checker receives shutdown request err="context canceled"
❌ Services shutting down
❌ Error: client is not running. Use .Start() method to start
```

## GitHub Issues Status

| Issue | Title | Status | Version |
|-------|-------|--------|---------|
| #422 | Provider crash: "client is not running" | **OPEN** | v0.10.5 |
| #437 | Provider crashing after startup | **CLOSED** | v0.10.8-rc2 |

### PR #359 "Fix" (Merged 2026-01-27)

**What it fixed**: Added error handling for `c.bus.Subscribe()` to prevent nil pointer dereference

**What it DIDN'T fix**: The two-bus architecture problem - services still get wrong bus from context

**Why v0.10.6+ still has the bug**: PR #359 only prevents crash, doesn't fix root cause

## Why 72% of Providers Work (v0.10.7)

### Hypothesis 1: Different Deployment Method
- Some providers may NOT use Helm
- Direct `provider-services run` may avoid two-bus issue
- Different command path might not create duplicate buses

### Hypothesis 2: Configuration-Based Workaround
- Environment variable that disables affected services
- Helm value that bypasses the problematic code path
- Flag to use single-bus mode

### Hypothesis 3: Timing-Based Race Condition
- Bug only triggers under certain timing conditions
- Faster/slower startup might avoid the race
- Resource availability affects timing

### Hypothesis 4: Different Go Version/Build
- Official images vs custom builds
- Different compiler optimizations affect behavior

## Investigation Path

1. ✅ Confirmed two-bus architecture bug exists in code
2. ✅ Confirmed PR #359 doesn't fix root cause
3. ✅ Confirmed 43 providers successfully run v0.10.7
4. ❓ Need to identify what makes successful providers different

## Next Steps

### Option 1: Try v0.10.8 (Latest Stable)
```bash
helm upgrade akash-provider akash/provider -n akash-services \
  --set image.tag=0.10.8 \
  --reuse-values
```

### Option 2: Investigate Successful Providers
- Query Console API for working provider configurations
- Compare Helm values with successful providers
- Contact provider operators for their configurations

### Option 3: Try Manual Deployment
- Skip Helm chart
- Run `provider-services run` directly
- See if manual startup avoids the bug

### Option 4: Disable Affected Services
- Find flag to disable balance-checker
- Find flag to disable bidengine (not ideal, but diagnostic)
- Run provider without services that crash

## Current Configuration

```yaml
Provider Version: 0.10.6
Helm Chart: provider-14.0.8
Image: ghcr.io/akash-network/provider:0.10.6

Wallet:
  Address: akash1c6h804ky08tdpnxrv72vum783xuey09qgzt2p6
  Balance: 30+ AKT (well above minimum)

Operators: All connected and ready
Inventory: 4 nodes, 3 GPUs detected
Certificate: Valid
```

## Key Files

- `cmd/provider-services/cmd/run.go`: Two-bus creation
- `provider/balance_checker.go`: First service to fail
- `bidengine/service.go`: Gets wrong bus from context
- `manifest/service.go`: Terminates, triggering cascade

## References

- GitHub Issue #422: https://github.com/akash-network/support/issues/422
- GitHub Issue #437: https://github.com/akash-network/support/issues/437
- Fix PR #359: https://github.com/akash-network/provider/pull/359
- Console API: https://console-api.akash.network/v1/

---

**Last Updated**: 2026-03-19 09:00 UTC
**Confidence**: High - Code analysis confirms two-bus architecture bug
**Recommendation**: Try v0.10.8 or investigate successful provider configurations
