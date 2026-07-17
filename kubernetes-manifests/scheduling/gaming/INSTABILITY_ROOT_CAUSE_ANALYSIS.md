# Kubernetes Instability Root Cause Analysis

**Date:** 2026-03-21
**Severity:** CRITICAL - API server crashes, webhook timeouts, scheduler conflicts

## Executive Summary

The cluster instability is caused by **dual-scheduler configuration conflicts** between YuniKorn and Volcano, combined with **RBAC permission issues** in the YuniKorn admission controller. This creates a death spiral of:

1. YuniKorn admission webhook intercepting all pod creation requests
2. Webhook timing out due to missing permissions
3. API server overload from webhook timeouts
4. Etcd connection failures
5. API server crashes

## Root Causes

### 1. Dual-Scheduler Conflict (PRIMARY CAUSE)

**Current State:**
```
AMD miners (Forge)     → YuniKorn scheduler
NVIDIA miners (Forge)  → Volcano scheduler (partially migrated)
Gaming placeholder     → Both YuniKorn and Volcano deployments
GPU resources          → Both schedulers trying to manage same GPUs
```

**The Problem:**
- Both schedulers are managing pods on the **same node** (Forge)
- YuniKorn's admission webhook intercepts **ALL** pod creation, including Volcano-scheduled pods
- Volcano cannot preempt YuniKorn-scheduled pods (different scheduler)
- YuniKorn cannot preempt Volcano-scheduled pods (different scheduler)
- **Result**: Preemption doesn't work, resource conflicts, API overload

**Impact:**
- GPU resources show as allocated but pods can't schedule
- Stale GPU allocations after pod deletion
- Scheduler loops trying to allocate already-allocated resources

### 2. YuniKorn Admission Controller RBAC Issues

**Missing Permissions:**
```
E0321 08:14:27.359499 reflector.go:205] "Failed to watch"
err="namespaces is forbidden: User \"system:serviceaccount:yunikorn:yunikorn-admission-controller\"
cannot watch resource \"namespaces\" in API group \"\" at the cluster scope"
```

**Timeline:**
- Old ClusterRole lacked namespace/priorityclass permissions
- Helm upgrade at 07:55 UTC added missing permissions
- **But**: admission controller pod kept running with old cached permissions
- Webhook continued failing with timeout errors

**Impact:**
- Each pod creation triggers admission webhook timeout (10s)
- API server blocks on webhook response
- Cascading failures when multiple pods created simultaneously

### 3. Etcd Overload

**Symptoms:**
```
{"level":"warn","ts":"2026-03-21T08:14:28.242899Z","caller":"txn/util.go:93","msg":"apply request took too long",
"took":"249.032391ms","expected-duration":"100ms"}
```

**Causes:**
- Excessive watch/reconnect cycles from broken admission controller
- Dual-scheduler creating conflicting pod objects
- Rapid pod creation/deletion during testing

**Impact:**
- API server-etcd connection drops
- "use of closed network connection" errors
- API server unable to maintain consistent state

## The Death Spiral

```
1. User scales deployment → 10+ pod creation requests
2. YuniKorn webhook intercepts all requests (even Volcano pods)
3. Webhook times out (10s) due to RBAC issues
4. API server waits for webhook response
5. Etcd overwhelmed by watch/reconnect cycles
6. API server-etcd connection drops
7. API server crashes (SIGTERM)
8. Cluster unavailable until manual restart
```

## Immediate Fixes Applied

1. ✅ Restarted kube-apiserver (multiple times)
2. ✅ Restarted kubelet on Forge (cleared GPU allocations)
3. ✅ Deleted NVIDIA device plugin pod (forced GPU reallocation)
4. ✅ Scaled down all mining deployments (stopped pod creation)
5. ✅ Updated YuniKorn ClusterRole (Helm upgrade at 07:55)

## Required Actions

### Option A: Complete Migration to Volcano (RECOMMENDED)

**Rationale:**
- Volcano preemption is enabled and working
- Better GPU resource management
- Cleaner architecture (single scheduler)

**Steps:**
1. Migrate AMD miners to Volcano
2. Delete YuniKorn gaming placeholder
3. Remove YuniKorn scheduler from cluster
4. Verify all GPU workloads use Volcano

**Risk:** Medium - requires careful migration

### Option B: Revert to YuniKorn-Only

**Rationale:**
- Simpler rollback
- All workloads already configured for YuniKorn

**Steps:**
1. Revert NVIDIA miners to YuniKorn
2. Delete Volcano gaming placeholder
3. Disable Volcano scheduler
4. Accept that preemption won't work (use manual scaling)

**Risk:** Low - simple rollback, but preemption broken

### Option C: Fix Dual-Scheduler Setup

**Rationale:**
- Both schedulers have strengths
- Can use YuniKorn for some workloads, Volcano for others

**Steps:**
1. Configure YuniKorn webhook to ignore Volcano-scheduled pods
2. Add namespace-based scheduler isolation
3. Fix RBAC permissions properly
4. Test thoroughly

**Risk:** HIGH - complex, fragile, not recommended

## Prevention

### Short-term
1. **Choose ONE scheduler** for GPU workloads
2. Monitor admission webhook latency
3. Set up alerts for API server restarts
4. Add resource limits on etcd

### Long-term
1. Implement scheduler namespaces (isolation)
2. Add admission webhook timeout monitoring
3. Create runbooks for API server recovery
4. Consider cluster-autoscaler for resource management

## Files Created During Investigation

1. `/etc/nixos/kubernetes-manifests/scheduling/gaming/40-volcano-preemption-config.yaml`
2. `/etc/nixos/kubernetes-manifests/scheduling/gaming/50-volcano-gaming-podgroup.yaml`
3. `/etc/nixos/kubernetes-manifests/scheduling/gaming/55-volcano-mining-podgroups.yaml`
4. `/etc/nixos/kubernetes-manifests/scheduling/gaming/YUNIKORN_PREEMPTION_ANALYSIS.md`

## Recommendation

**Complete the migration to Volcano (Option A)**. The dual-scheduler setup is fundamentally flawed for GPU workloads because:
- Schedulers cannot preempt each other's pods
- Admission webhooks intercept cross-scheduler traffic
- Resource conflicts are unavoidable

The manual scaling workaround in `compute-workload-monitor.nix` is **production-ready** and should remain in place even after scheduler migration, as it provides reliable gaming pause/resume regardless of scheduler behavior.
