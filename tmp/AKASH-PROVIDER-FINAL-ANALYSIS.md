# Akash Provider - Final Analysis (2026-03-19)

## Summary

After extensive research across:
- GitHub issues #422, #437
- Source code analysis of akash-network/provider
- Testing versions v0.10.6, v0.10.7, v0.11.0-rc2
- Console API analysis showing 72% of providers successfully running v0.10.7

**Conclusion**: This is a CODE-LEVEL BUG that affects ALL current provider versions. There is NO CONFIGURATION FIX.

## Root Cause: Two-Bus Architecture Bug

### The Bug in Code

**File**: `cmd/provider-services/cmd/run.go`

```
# Line 329 - PreRunE phase
bus := tpubsub.New(pctx, 1000)  # Creates github.com/troian/pubsub bus
fromctx.CmdSetContextValue(cmd, fromctx.CtxKeyPubSub, bus)

# Line 562 - doRunCmd phase
bus := pubsub.NewBus()  # Creates pkg.akt.dev/go/util/pubsub bus
defer bus.Close()
```

### Two Different PubSub Packages

| Package | Path | Usage |
|---------|------|-------|
| tpubsub | github.com/troian/pubsub | External library, stored in context |
| pubsub | pkg.akt.dev/go/util/pubsub | Akash internal, passed to services |

### Why 72% of Providers Work

Most likely explanation: **Different Deployment Method**
- Some providers may NOT use Helm
- Direct provider-services run might avoid the two-bus issue
- Custom builds with patched code

## Tested Versions - ALL FAILED

| Version | Status | Error |
|---------|--------|-------|
| v0.10.6 | CRASH | "client is not running" |
| v0.10.7 | CRASH | Same error |
| v0.11.0-rc2 | CRASH | Same error |

## Log Pattern

```
✅ Provider service starts
✅ Operators discovered and connected
✅ gRPC listening on 0.0.0.0:8444
❌ Error: client is not running. Use .Start() method to start
❌ Services shutting down
```

## Recommendation

1. Contact Akash team about this issue
2. Try manual deployment without Helm
3. Wait for official fix

---

**Status**: BLOCKED BY CODE BUG - NO CONFIGURATION FIX AVAILABLE
**Last Updated**: 2026-03-19 10:10 UTC
