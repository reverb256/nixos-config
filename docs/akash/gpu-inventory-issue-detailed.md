# Akash Provider GPU Inventory Issue - Detailed Analysis

## Problem Statement

The Akash provider incorrectly reports **6 NVIDIA GPUs** when only **5 NVIDIA GPUs** exist in the cluster.

### Root Cause

**Sentry node has an AMD GPU that's being counted as a NVIDIA GPU:**

```
Sentry Node Resources:
  amd.com/gpu: 1    ✅ (AMD GPU present)
  nvidia.com/gpu: 0 ❌ (No NVIDIA GPU)

Provider Inventory Shows:
  Sentry: gpu: 1    ❌ (Incorrect - counting AMD GPU)
  Total: 6 GPUs     ❌ (Should be 5 NVIDIA GPUs)
```

### Why This Happens

The Akash `operator-inventory` service (v0.10.7) aggregates **all GPU types** (`nvidia.com/gpu` + `amd.com/gpu`) into a single `gpu` count without distinguishing vendors.

## Actual GPU Inventory

| Node | NVIDIA GPUs | AMD GPUs | Total | Akash Count | Status |
|------|------------|----------|-------|-------------|--------|
| **Forge** | 2× RTX 4060 | 2× AMD | 4 | 2 NVIDIA only | ✅ Correct |
| **Nexus** | 1× RTX 3090 | 0 | 1 | 1 NVIDIA | ✅ Correct |
| **Sentry** | 0 | 1× AMD | 1 | **1 NVIDIA** | ❌ **Incorrect** |
| **Zephyr** | 2× RTX 3090 | 0 | 2 | 2 NVIDIA | ✅ Correct |
| **Total** | **5 NVIDIA** | **3 AMD** | **8** | **6 GPUs** | ❌ **Should be 5** |

## Attempted Solutions

### 1. Node Label: `akash.network/capabilities.gpu.exclude=true`
**Result:** ❌ Did not work
```bash
kubectl label node sentry akash.network/capabilities.gpu.exclude=true
```
The inventory service ignored this label.

### 2. ConfigMap: `exclude.node_gpu: [sentry]`
**Result:** ❌ Did not work (field may not be implemented)
```yaml
exclude:
  nodes: []
  node_storage: []
  node_gpu:
  - sentry
```
The inventory service still showed Sentry with 1 GPU.

### 3. ConfigMap: `exclude.nodes: [sentry]`
**Result:** ⚠️ Partially worked (excluded entire node)
```yaml
exclude:
  nodes:
  - sentry
  node_storage: []
```

**Provider Inventory After:**
```json
{
  "total_allocatable": {
    "cpu": 62000,     // Down from 78000 (-16000 Sentry CPUs)
    "gpu": 5,         // ✅ Correct!
    "memory": 92326301696  // Down from 123114618880 (-30GB Sentry RAM)
  }
}
```

**Problem:** Entire Sentry node excluded, not just its GPU:
- Lost 16 CPUs from inventory
- Lost 30GB RAM from inventory
- Lost 220GB storage from inventory
- Sentry's AMD GPU correctly excluded ✅

### 4. Node Label: `akash.network/capabilities.gpu.count=0`
**Result:** ⚠️ Same as #3 - excluded entire node

## Current Status

### GPU Count: ✅ FIXED (5 GPUs)
- Provider now correctly reports 5 NVIDIA GPUs
- Forge: 2 GPUs ✅
- Nexus: 1 GPU ✅
- Zephyr: 2 GPUs ✅
- Sentry: Excluded from inventory

### Resource Trade-off

| Resource | Before | After | Lost |
|----------|--------|-------|------|
| **GPUs** | 6 (1 incorrect) | 5 (all correct) | 0 GPUs ✅ |
| **CPUs** | 78,000 | 62,000 | 16,000 (Sentry) |
| **Memory** | 123GB | 92GB | 31GB (Sentry) |
| **Storage** | 2.2TB | 2.0TB | 220GB (Sentry) |

**Impact:** Sentry's CPU, memory, and storage are no longer available for Akash leases.

## Why This Limitation Exists

The Akash provider's `operator-inventory` service has **no granular GPU filtering**:

1. **No GPU vendor filtering:** Can't exclude only `amd.com/gpu` while keeping `nvidia.com/gpu`
2. **No per-resource-type exclusion:** Can't exclude GPU while keeping CPU/memory/storage
3. **Node-level exclusion only:** The `exclude.nodes` list excludes the **entire node**, not specific resources

### Inventory Service Behavior

```go
// Simplified logic of operator-inventory
for node in cluster {
    gpuCount = node.resources.nvidia_gpu + node.resources.amd_gpu
    inventory.add(node, cpu, gpuCount, memory, storage)
}
```

The service aggregates all GPU types without vendor distinction.

## Ideal Solution (Not Currently Possible)

What we WANT:
```yaml
exclude:
  nodes: []
  resources:
    sentry:
      - amd.com/gpu  # Exclude only AMD GPU
```

What we HAVE:
```yaml
exclude:
  nodes: []           # No resource-level exclusion
  # Can only exclude entire nodes
```

## Workaround Options

### Option 1: Accept Current State (RECOMMENDED)
**Pros:**
- ✅ GPU count is correct (5 NVIDIA GPUs)
- ✅ Provider won't bid on impossible GPU leases
- ✅ No manual intervention needed

**Cons:**
- ❌ Sentry's 16 CPUs unavailable for Akash
- ❌ Sentry's 31GB RAM unavailable for Akash
- ❌ Sentry's 220GB storage unavailable for Akash

**Verdict:** Best option for GPU-heavy workloads

### Option 2: Revert to Incorrect GPU Count
**Pros:**
- ✅ All 78 CPUs available for leases
- ✅ All 123GB RAM available for leases
- ✅ All storage available for leases

**Cons:**
- ❌ Provider shows 6 GPUs (incorrect)
- ❌ May bid on leases requiring 6 NVIDIA GPUs
- ❌ Lease deployment will fail when only 5 NVIDIA GPUs exist

**Verdict:** Dangerous - could cause bid failures

### Option 3: Upgrade Akash Provider
Check if newer versions support GPU vendor filtering:

```bash
# Monitor for updates
kubectl get deployment -n akash-services operator-inventory -o jsonpath='{.spec.template.spec.containers[0].image}'
# Current: ghcr.io/akash-network/provider:0.10.7
```

### Option 4: Submit Feature Request
Request from Akash Network:
- GPU vendor filtering (exclude `amd.com/gpu` only)
- Per-resource-type exclusion (exclude GPU but keep CPU)
- Proper AMD GPU support (separate GPU type in inventory)

## Verification

### Check Current GPU Count
```bash
kubectl logs -n akash-services akash-provider-akash-provider-fixed-0 --tail=5 | \
  grep -o '"total_allocatable":{[^}]*}' | tail -1
```

Expected output:
```json
{"cpu":62000,"gpu":5,"memory":92326301696,"storage_ephemeral":2004727789117}
```

### Check Node Inventory
```bash
kubectl logs -n akash-services akash-provider-akash-provider-fixed-0 --tail=5 | \
  grep -A 50 '"nodes":' | grep '"name"'
```

Expected: Only `forge`, `nexus`, `zephyr` (no `sentry`)

### Check Sentry Node Resources
```bash
kubectl describe node sentry | grep -A 2 "amd.com\|nvidia.com"
```

Expected:
```
amd.com/gpu  1
nvidia.com/gpu  0
```

## To Revert (If Needed)

If you want to restore Sentry to the inventory (with incorrect GPU count):

```bash
# Remove node exclusion from ConfigMap
kubectl patch configmap -n akash-services operator-inventory --type merge -p '{
  "data":{"config.yaml":"version: v1\ncluster_storage:\n  - default\n  - beta2\n  - beta3\n  - ram\nexclude:\n  nodes: []\n  node_storage: []\n"}
}'

# Restart inventory service
kubectl rollout restart deployment -n akash-services operator-inventory

# Restart provider to clear cache
kubectl rollout restart statefulset -n akash-services akash-provider-akash-provider-fixed

# Wait and verify (will show 6 GPUs again)
sleep 30
kubectl logs -n akash-services akash-provider-akash-provider-fixed-0 --tail=5 | \
  grep -o '"total_allocatable":{[^}]*}' | tail -1
```

## Summary

| Aspect | Status |
|--------|--------|
| **GPU Count** | ✅ Fixed (5 NVIDIA GPUs) |
| **Sentry GPU** | ✅ Excluded (AMD not counted) |
| **Sentry CPU** | ❌ Excluded (16 CPUs lost) |
| **Sentry RAM** | ❌ Excluded (31GB lost) |
| **Sentry Storage** | ❌ Excluded (220GB lost) |
| **Root Cause** | Akash provider lacks GPU vendor filtering |
| **Recommended** | Keep current state (Option 1) |

## Next Steps

1. **Monitor** provider behavior with 5 GPUs
2. **Check** if provider can successfully deploy GPU leases
3. **Submit** feature request to Akash Network for GPU vendor filtering
4. **Watch** for provider updates that add AMD GPU support

---

**Created:** 2026-03-21
**Status:** ⚠️ Workaround Active (Sentry node excluded)
**Provider Version:** 0.10.7
**Issue:** Akash Network operator-inventory lacks granular GPU filtering
