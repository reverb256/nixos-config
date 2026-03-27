# Calico Typha Health Fix - 2026-03-27

## Problem Summary
**Critical**: Typha health endpoint unresponsive, causing CNI installation failures on 3/4 nodes.

## Root Cause Chain
1. **Typha health probes failing** - Port 9098 not responding to HTTP GET
2. **Typha pods NotReady** - Even with 30s timeout
3. **calico-node can't discover Typha** - k8s-poll thread reports "numTyphas=0"
4. **install-cni init container failing** - Restart loops on nexus/forge/sentry
5. **CNI broken** - Only zephyr has working calico-node
6. **DNS failures** - CoreDNS pods can't communicate

## Current State
- ✅ Zephyr: calico-node Running (CNI working)
- ❌ Nexus: calico-node Init:Error
- ❌ Forge: calico-node Init:Error
- ❌ Sentry: calico-node Init:CrashLoopBackOff
- ⚠️  CoreDNS: 1/2 pods running (on zephyr only)
- ✅ 7/7 miner pods Running but with limited connectivity

## Attempted Fixes
1. ✅ Increased Typha probe timeout: 10s → 30s
2. ✅ Changed health host: localhost → 127.0.0.1
3. ❌ Health endpoint still timing out

## Root Cause (Deep Analysis)
Typha health server starts but doesn't respond to HTTP requests. The k8s-poll thread can't discover Typha pods via Kubernetes API, reporting "numTyphas=0".

**Possible causes**:
- Health server starting but not binding properly
- Container namespace isolation blocking localhost
- TLS certificate issues preventing HTTPS
- Resource constraints (CPU/memory)

## Recommended Solutions

### Option 1: Disable Typha (Quick Fix)
```bash
kubectl patch Installation default --type=json -p='[
  {"op": "replace", "path": "/spec/calicoNetwork/typhaMetricsPort", "value": null}
]' -n tigera-operator
```
**Impact**: Removes Typha scaling, calico-node connects directly to API server.

### Option 2: Force Restart Calico
```bash
kubectl delete pod -n calico-system -l k8s-app=calico-node
kubectl delete pod -n calico-system -l k8s-app=calico-typha
```
**Impact**: Temporary disruption, may resolve transient issues.

### Option 3: Check Resource Limits
```bash
kubectl describe node zephyr | grep -A 5 "Allocated resources"
kubectl top pod -n calico-system
```
**Impact**: Identify if resource starvation is causing health endpoint failures.

### Option 4: Manual Health Check
```bash
# From inside Typha container
kubectl exec -n calico-system calico-typha-<pod> -- curl -v http://127.0.0.1:9098/readiness
```
**Impact**: Directly test if health endpoint works inside container.

## Next Steps
1. **IMMEDIATE**: Try Option 2 (force restart)
2. **If fails**: Try Option 1 (disable Typha)
3. **Monitor**: Verify calico-node becomes Ready on all nodes
4. **Test**: DNS resolution from pods
5. **Document**: Update this file with resolution

## References
- Calico Typha docs: https://docs.projectcalico.org/architecture/#typha
- Health check configuration: https://docs.projectcalico.org/maintenance/monitor/
- Incident timeline: See session logs for full debugging path

**Created**: 2026-03-27 16:05 UTC
**Status**: IN_PROGRESS
**Owner**: j_kro
