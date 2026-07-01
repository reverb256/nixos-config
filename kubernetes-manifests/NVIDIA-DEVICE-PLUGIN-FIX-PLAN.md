# NVIDIA Device Plugin Fix Plan
**Date**: 2026-03-26
**Priority**: CRITICAL (all GPU workloads blocked)
**Status**: Ready to Execute

---

## Problem Summary

### Primary Issue: GPU Device Plugin Not Registering
- **Impact**: 11 pods stuck in `OutOfnvidia.com/gpu` state
- **Root Cause**: Device plugin DaemonSet mounts wrong kubelet directory
- **Technical Details**:
  - DaemonSet mounts host `/var/lib/kubernetes` → container `/var/lib/kubelet`
  - Kubelet creates device plugin sockets at host `/var/lib/kubelet/device-plugins/`
  - Plugin looks for socket at container `/var/lib/kubelet/device-plugins/kubelet.sock`
  - **Result**: Plugin connects to empty directory, not kubelet's actual socket

### Secondary Issues
1. **Missing ConfigMap**: `ai-inference/kube-root-ca.crt` not found (blocking pod startup)

---

## Fix Plan

### Phase 1: Fix NVIDIA Device Plugin (CRITICAL)

#### Step 1: Locate Current DaemonSet
```bash
kubectl get ds -n kube-system nvidia-device-plugin-daemonset -o yaml > /tmp/nvidia-device-plugin-backup.yaml
```

#### Step 2: Update Volume Mount
**File**: `kubernetes-manifests/scheduling/nvidia-device-plugin-daemonset.yaml`

**Change**:
```yaml
# BEFORE (WRONG):
spec:
  template:
    spec:
      volumes:
      - name: kubelet-root
        hostPath:
          path: /var/lib/kubernetes  # ❌ Wrong directory

# AFTER (CORRECT):
spec:
  template:
    spec:
      volumes:
      - name: kubelet-root
        hostPath:
          path: /var/lib/kubelet  # ✅ Actual kubelet working directory
```

#### Step 3: Apply Fixed DaemonSet
```bash
kubectl apply -f kubernetes-manifests/scheduling/nvidia-device-plugin-daemonset.yaml
```

#### Step 4: Verify Plugin Registration
```bash
# Check plugin pods are running
kubectl get pods -n kube-system -l name=nvidia-device-plugin-ds

# Verify sockets exist
ssh zephyr 'sudo ls -la /var/lib/kubelet/device-plugins/'
ssh nexus 'sudo ls -la /var/lib/kubelet/device-plugins/'

# Check GPU resources registered
kubectl describe node zephyr | grep nvidia.com/gpu
kubectl describe node nexus | grep nvidia.com/gpu
```

**Expected Result**: `nvidia.com/gpu: 2` on zephyr, `nvidia.com/gpu: 1` on nexus

---

### Phase 2: Verify GPU Pod Scheduling

#### Step 1: Check Existing Pods
```bash
# View stuck GPU pods
kubectl get pods -A | grep OutOfnvidia.com/gpu
```

#### Step 2: Monitor Pod Recovery
```bash
# Watch pods transition from OutOfnvidia.com/gpu to Running
kubectl get pods -A -w | grep llama
```

**Expected Result**: Pods should automatically schedule once GPUs are registered

---

### Phase 3: Fix kube-root-ca.crt ConfigMap

#### Investigation
```bash
# Check if ConfigMap exists in kube-system (default location)
kubectl get cm -n kube-system kube-root-ca.crt

# Check if namespace has this ConfigMap
kubectl get cm -n ai-inference

# Check api-server logs for errors
ssh zephyr 'sudo journalctl -u kube-apiserver --since "10 minutes ago" | grep -i configmap'
```

#### Likely Fix
This ConfigMap is auto-created by Kubernetes. If missing, likely due to:
1. API server issue (should resolve after GPU fix reduces load)
2. Namespace corruption (recreate namespace)

**Commands to investigate**:
```bash
# Check namespace status
kubectl get ns ai-inference -o yaml

# If ConfigMap missing, check api-server controller
ssh zephyr 'sudo journalctl -u kube-apiserver --since "1 hour ago" | grep -i "kube-root-ca"'
```

---

## Execution Order

**CRITICAL**: Execute in this order:
1. ✅ **Phase 1**: Fix device plugin (unblocks all GPU workloads)
2. ✅ **Phase 2**: Verify GPU scheduling (confirms fix works)
3. ⏸️ **Phase 3**: Fix ConfigMap (may auto-resolve after Phase 1)

---

## Rollback Plan

If Phase 1 causes issues:
```bash
# Restore original DaemonSet
kubectl apply -f /tmp/nvidia-device-plugin-backup.yaml

# Restart kubelet to clear state
ssh zephyr 'sudo systemctl restart kubelet'
ssh nexus 'sudo systemctl restart kubelet'
```

---

## Success Criteria

- [ ] Device plugin creates socket at `/var/lib/kubelet/device-plugins/nvidia-gpu.sock`
- [ ] Node capacity shows `nvidia.com/gpu: 2` (zephyr) and `nvidia.com/gpu: 1` (nexus)
- [ ] All llama pods transition to `Running` state
- [ ] No `OutOfnvidia.com/gpu` pods in cluster
- [ ] kube-root-ca.crt ConfigMap exists

---

## Time Estimate
- **Phase 1**: 5 minutes (apply DaemonSet, verify)
- **Phase 2**: 10 minutes (wait for pod scheduling)
- **Phase 3**: 10 minutes (investigation, may auto-resolve)

**Total**: ~25 minutes if all goes smoothly

---

## Related Files
- **DaemonSet**: `kubernetes-manifests/scheduling/nvidia-device-plugin-daemonset.yaml`
- **Backup**: `/tmp/nvidia-device-plugin-backup.yaml` (created during Step 1)
- **NixOS Config**: `modules/services/kubernetes.nix` (kubelet configuration reference)
