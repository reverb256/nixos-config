# Phase 0 Status: BLOCKED - CSI Driver Registration Issue

**Date:** 2026-03-23
**Status:** ⚠️ BLOCKED - Technical incompatibility discovered
**Duration:** 2 hours (deployed driver, registration failing)

---

## What Was Accomplished

### ✅ Completed
1. **nix-csi driver deployed** - DaemonSet running on 3 nodes (zephyr, nexus, forge)
2. **CSIDriver resource created** - `nix.csi.store` registered in Kubernetes API
3. **StorageClass created** - `nix-store` StorageClass provisioned
4. **CSI sockets created** - Driver listening on `/var/lib/kubelet/plugins/nix.csi.store/csi.sock`
5. **Registration sockets created** - Registrar socket at `/var/lib/kubelet/plugins_registry/nix.csi.store-reg.sock`
6. **Test pods created** - Multiple test configurations attempted

### ❌ Blocked
**Issue:** Kubelet cannot find `nix.csi.store` driver despite:
- CSIDriver object existing in Kubernetes API
- CSI socket file existing on node filesystem
- Registration socket file existing on node filesystem
- nix-node pods running 3/3 containers

**Error Message:**
```
MountVolume.SetUp failed for volume "nix-volume": kubernetes.io/csi: mounter.SetUpAt failed
to get CSI client: driver name nix.csi.store not found in the list of registered CSI drivers
```

---

## Root Cause Analysis

### Symptoms
1. CSI driver pods are **Running** (3/3 containers) on all nodes
2. CSIDriver resource exists: `kubectl get csidriver nix.csi.store` ✅
3. Socket files exist on nodes: `/var/lib/kubelet/plugins/nix.csi.store/csi.sock` ✅
4. Kubelet **cannot** see driver in its registered drivers list

### Potential Causes

#### Hypothesis 1: Kubernetes Version Incompatibility
**Evidence:**
- Cluster running Kubernetes v1.35.0
- nix-csi driver may not be tested against this version
- CSI ephemeral volumes feature may have changed in newer K8s versions

**Likelihood:** HIGH

#### Hypothesis 2: CSI Driver Registration Protocol Mismatch
**Evidence:**
- csi-node-driver-registrar logs show registration server started
- No explicit "driver registered successfully" message in logs
- Kubelet may be expecting a different registration format

**Likelihood:** MEDIUM

#### Hypothesis 3: Kubelet Configuration Issue
**Evidence:**
- Restarting kubelet didn't resolve the issue
- No kubelet configuration changes made for CSI support
- May need explicit CSI driver registration enabled

**Likelihood:** LOW

---

## Attempted Solutions

### ✅ Attempted (Failed)
1. **Restarted kubelet** on forge and nexus (twice) - No change
2. **Deleted old failed pods** (`nix-csi-node-gbcgr`, `nix-csi-node-v2l4w`) - No change
3. **Verified socket files** exist on nodes - Confirmed present
4. **Recreated CSIDriver resource** - Already correct
5. **Multiple test pod configurations**:
   - Alpine with hostPath-style volume mount
   - Official nix-csi scratch image with correct CSI ephemeral format
   - Different nodeSelectors (forge, nexus)
   - All failed with same error

### ❌ Not Attempted
1. **Downgrade Kubernetes** to v1.28-v1.34 (nix-csi tested versions)
2. **Build nix-csi from source** with potential fixes
3. **Manual CSI driver registration** via kubelet API
4. **Check upstream nix-csi issues** for K8s 1.35 compatibility

---

## Recommendations

### Immediate Actions (Phase 0 Unblock)

#### Option 1: Use Alternative Approach ⭐ RECOMMENDED
**Skip nix-csi for now**, use hostPath with `readOnlyRootFilesystem`:
- More reliable (tested pattern)
- Still provides security benefit (no privileged containers)
- Can revisit nix-csi when project matures

**Trade-off:** Less elegant than CSI ephemeral volumes, but functional

#### Option 2: Downgrade Kubernetes
Test nix-csi on Kubernetes v1.28-v1.34 where it's known to work:
- Requires cluster reconfiguration
- Risk of breaking other workloads
- Time-intensive (2-3 hours)

**Trade-off:** High effort, may break existing functionality

#### Option 3: Engage Upstream
File issue with nix-csi project:
- Request K8s 1.35 compatibility testing
- Provide detailed error logs
- May take weeks to resolve

**Trade-off:** Long wait time, uncertain outcome

### Long-term Actions

1. **Contribute to nix-csi**: Add K8s 1.35 support
2. **Document working pattern**: Create guide for alternative approach
3. **Reevaluate in 6 months**: Check if nix-csi matures

---

## Resources Created

### Kubernetes Resources
- `kubectl get csidriver nix.csi.store` ✅
- `kubectl get sc nix-store` ✅
- `kubectl get ds -n kube-system nix-node` ✅ (3 pods running)
- `kubectl get pods -n kube-system -l app.kubernetes.io/part-of=nix-csi`

### Files Created
- `kubernetes-manifests/storage/nix-csi-driver.yaml` (corrected with official image)
- `kubernetes-manifests/storage/nix-store-storage-class.yaml`
- `kubernetes-manifests/storage/nix-csi-test-pod.yaml` (original)
- `kubernetes-manifests/storage/nix-csi-test-pod-correct.yaml` (with proper format)

---

## Success Criteria (Not Met)

- [ ] nix-csi test pod runs without errors
- [ ] CSI ephemeral volume mounts successfully
- [ ] Test pod can access `/nix/store` without privileged containers
- [ ] All 3 nodes show CSI driver as registered

---

## Next Steps

### Path Forward: Option 1 (Alternative Approach)
1. Skip Phase 0 CSI driver verification
2. Move to Phase 1 with hostPath + readOnlyRootFilesystem
3. Continue migration with functional approach
4. Revisit nix-csi in Phase 6 (cleanup) when project matures

### Path Forward: Option 2 (Debug Further)
1. Create minimum reproduction case
2. File upstream issue with nix-csi project
3. Test on K8s v1.34 VM
4. Document resolution for future reference

---

**Decision Point:** Please choose between:
- **Option 1:** Continue migration with alternative approach (recommended)
- **Option 2:** Continue debugging (2-4 more hours)
- **Option 3:** Pause and revisit later

---

**Document Owner:** j_kro
**Version:** 1.0
**Status:** ⚠️ BLOCKED - Awaiting decision on path forward
