# YuniKorn Priority Preemption Analysis

**Date:** 2026-03-21
**Status:** Preemption not working - Using manual scaling workaround

## Problem Summary

YuniKorn priority preemption (`gaming-high` priority 1000 vs `mining-low` priority 100) is not functioning correctly. High-priority placeholder pods remain in `Pending` state indefinitely while lower-priority mining pods continue running.

## Root Cause Analysis

### 1. ResourceQuota Blocking (RESOLVED)
**Issue:** Original ResourceQuota blocked pods before scheduler preemption could occur.
- ResourceQuota validation happens at **admission time** (API server)
- YuniKorn preemption happens at **scheduling time** (scheduler)
- GPU quota of 6 prevented new pods from being admitted

**Fix:** Removed GPU limits from ResourceQuota, keeping only CPU/memory limits.
```yaml
# File: 30-resourcequota-fix.yaml
# ResourceQuota no longer tracks GPU resources - YuniKorn manages them
```

### 2. YuniKorn Reservation Timeout (ONGOING)
**Issue:** YuniKorn creates a reservation but never converts it to an allocation.

**Log Pattern:**
```
INFO allocation ask is reserved {"node": "forge", ...}
... (40 seconds later) ...
INFO Task state transition: Scheduling → Completed
INFO terminationType: STOPPED_BY_RM
```

**Analysis:** The scheduler reserves the GPU resources but fails to actually preempt the lower-priority pods within the reservation timeout window.

### 3. Malformed GPU Configuration (IDENTIFIED)
**Issue:** Helm values contain malformed GPU resource specification:
```yaml
nvidia:              # WRONG - should be nvidia.com/gpu
  com/gpu: 4
nvidia.com/gpu: "2"  # Conflicting entry
```

### 4. Extended Resource Handling
GPU resources are Kubernetes extended resources. YuniKorn's preemption logic may not properly handle:
- Preempting GPU-allocated pods
- Cross-device preemption (preempting pod on GPU 0 to free GPU 0-2)

## Current Configuration

### Priority Classes
| Class | Priority | Used By |
|-------|----------|---------|
| gaming-high | 1000 | gaming-placeholder |
| mining-low | 100 | gpu-miner-forge-nvidia-* |

### Queue Placement
Both pods are in the same queue: `root.mining`
```yaml
yunikorn.yunikorn.io/queue-name: root.mining
```

### YuniKorn Preemption Settings
```yaml
policy:
  preemption:
    enable: true
    considerPriority: true
    preemptOthers: true
```

## Workaround Implementation

The current working solution uses **manual pod scaling** in `compute-workload-monitor`:

```bash
# When gaming detected:
scale_gaming_placeholder() {
    local gaming_active=$1
    local replicas=0
    if [[ "$gaming_active" == "1" ]]; then
        replicas=1
        # Manually scale down NVIDIA mining pods
        kubectl scale deployment gpu-miner-forge-nvidia-0 gpu-miner-forge-nvidia-1 \
            -n mining --replicas=0
    fi
    kubectl scale deployment gaming-placeholder -n mining --replicas=$replicas
}

scale_nvidia_miners() {
    local scale_up=$1
    if [[ "$scale_up" == "1" ]]; then
        kubectl scale deployment gpu-miner-forge-nvidia-0 gpu-miner-forge-nvidia-1 \
            -n mining --replicas=1
    fi
}
```

## Next Steps

### Option A: Fix YuniKorn Configuration (Recommended)
1. Fix malformed GPU configuration in Helm values
2. Investigate YuniKorn preemption logs for GPU-specific issues
3. Consider upgrading to latest YuniKorn version (1.9.0+)

### Option B: Use Volcano Scheduler
Volcano has better support for:
- Gang scheduling
- GPU resource preemption
- Queue-based fair scheduling

### Option C: Custom Preemption Controller
Build a simple controller that:
- Monitors ConfigMap for gaming state
- Directly scales down mining deployments when gaming active
- Scales back up when gaming ends

## Files Modified

1. `/etc/nixos/kubernetes-manifests/scheduling/gaming/30-resourcequota-fix.yaml`
   - Removed GPU limits from ResourceQuota

2. `/etc/nixos/modules/system/compute-workload-monitor.nix`
   - Added manual scaling functions for NVIDIA miners

## Testing

To test preemption after fixes:
```bash
# Scale up gaming placeholder
kubectl scale deployment gaming-placeholder -n mining --replicas=1

# Watch for preemption
kubectl get pods -n mining -w

# Check YuniKorn logs
kubectl logs -n yunikorn deployment/yunikorn-scheduler --container=yunikorn-scheduler-k8s -f
```

## References

- [YuniKorn Preemption Documentation](https://yunikorn.apache.org/docs/user_guide/preemption/)
- [Kubernetes Extended Resources](https://kubernetes.io/docs/concepts/scheduling-eviction/manage-resources/#extended-resources)
- [GPU Scheduling with YuniKorn](https://yunikorn.apache.org/docs/design/device_scheduling/)
