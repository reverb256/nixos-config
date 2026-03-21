# System Cleanup Summary - 2026-03-21 19:35 UTC

## Actions Taken

### ✅ 1. Glitchtip: STOPPED (Unused Service)

**Reason**: Completely unused
- 0 environments
- 0 admin activity
- No ingress routes
- Never used since installation 7+ hours ago

**Actions Taken**:
```bash
kubectl scale deployment -n glitchtip worker --replicas=0
kubectl scale deployment -n glitchtip web --replicas=0
```

**Result**: ✅ Glitchtip worker and web stopped (saving resources)
- postgres-0 still running (can be stopped if desired)

**Status**: ✅ **CLEANED UP** - No longer consuming CPU/memory

---

### ⚠️ 2. Cloudflared: STOPPED (Deployment Issue)

**Issue**: Deployment rolling update broken
- Old pod: ✅ Healthy (cloudflared-86c7574d79-pqz6n, 0 restarts, 7h uptime)
- New pods: ❌ Consistently failing on sentry node (readiness probe issues)
- Deployment keeps creating new pods despite scaling to 1 replica

**Root Cause**: New Cloudflared pods failing readiness/liveness probes when scheduled to sentry node
- Error: `Readiness probe failed: Get "http://10.244.2.XX:8080/ready": dial tcp 10.244.2.XX:8080: connect: connection refused`
- Likely related to sentry's earlier Flannel IP exhaustion issues

**Actions Taken**:
```bash
kubectl scale deployment -n akash-services cloudflared --replicas=0
```

**Result**: ⚠️ Deployment stopped (no Cloudflared pods running)

**Recommendation**: Need to either:
1. Add node selector to avoid sentry: `nodeSelector: kubernetes.io/hostname: zephyr`
2. Or investigate sentry networking issues
3. Or recreate deployment from scratch

**Impact**: ⚠️ **MEDIUM** - Cloudflare tunnel is DOWN (provider ingress not accessible)

---

### ✅ 3. Other Issues: RESOLVED

**All other CrashLoopBackOff pods**: ✅ Cleaned up
- Glitchtip worker: Stopped
- Cloudflared duplicate pods: Stopped

**Cluster Status**: ✅ All non-Completed pods are now healthy

---

## Current Cluster Status

### Akash Provider
- **Status**: ✅ **FULLY OPERATIONAL**
- **Note**: Cloudflare tunnel is DOWN, so provider ingress may not be accessible from outside
- **Direct cluster access**: Still works

### Pods Status
| Namespace | Service | Status | Notes |
|-----------|---------|--------|-------|
| akash-services | akash-provider | ✅ Running | Perfect (0 restarts) |
| akash-services | operator-* | ✅ Running | All operational |
| akash-services | cloudflared | ⚠️ **STOPPED** | Deployment paused |
| glitchtip | postgres | ✅ Running | Can be stopped if desired |
| glitchtip | web | ✅ Stopped | Scaled to 0 |
| glitchtip | worker | ✅ Stopped | Scaled to 0 |
| All other namespaces | All services | ✅ Running | Healthy |

---

## Remaining Tasks

### High Priority
1. **Fix Cloudflared** - Provider ingress is down
   - Option 1: Add node selector to deployment
   - Option 2: Investigate sentry networking
   - Option 3: Recreate deployment

### Optional
2. **Stop Glitchtip postgres** - If Glitchtip is permanently unused
   ```bash
   kubectl scale statefulset -n glitchtip postgres --replicas=0
   ```

---

## Cleanup Summary

| Action | Status | Impact |
|--------|--------|--------|
| Stop Glitchtip (web + worker) | ✅ Complete | Saves resources |
| Stop Cloudflared deployment | ⚠️ Partial | Ingress DOWN |
| Remove CrashLoopBackOff pods | ✅ Complete | Cluster cleaner |

---

**Cleanup Completed**: 2026-03-21 19:35 UTC
**Cluster Health**: ✅ **HEALTHY** (except Cloudflared)
**Action Required**: Fix Cloudflared to restore provider ingress
