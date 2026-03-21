# Default Namespace Cleanup Plan

**Date**: 2026-03-21
**Purpose**: Move application workloads out of default namespace

---

## 🔍 Current State

**Pods in Default Namespace:**
1. `memory-monitor-29568605-whgrm` → Zephyr
2. `memory-monitor-29568610-jl7nb` → Zephyr
3. `memory-monitor-29568615-wf289` → Zephyr
4. `akash-export-cert-foreg` → Forge

**Problem**: Default namespace should only contain temporary/debugging pods, not production workloads.

---

## 📋 Cleanup Tasks

### 1. Memory Monitor (3 pods)

**Current Location**: `default` namespace
**Target Location**: `monitoring` namespace

**Why**: Memory monitoring is infrastructure/metrics, belongs with observability stack

**Action Required**:
```bash
# These are likely deployed via NixOS or Helm
# Find the deployment source:
kubectl get deployment memory-monitor -n default -o yaml

# Option A: If NixOS deployment, update hosts/*/configuration.nix
# Change namespace: "default" → "monitoring"

# Option B: If Helm deployment
helm upgrade memory-monitor <release> --namespace monitoring
```

**Status**: ⏳ Pending (API server recovering)

---

### 2. Akash Export Cert (1 pod)

**Current Location**: `default` namespace
**Target Location**: `akash-services` namespace

**Why**: Certificate export is part of Akash provider operations

**Action Required**:
```bash
# Find the DaemonSet source
kubectl get daemonset akash-export-cert -n default -o yaml

# Update namespace to akash-services
# Then redeploy
```

**Status**: ⏳ Pending (API server recovering)

---

## 🎯 Implementation Steps

1. **Identify Deployment Source**
   - Check if NixOS modules deploy these
   - Check if Helm charts deploy these
   - Check if manually created

2. **Update Configuration**
   - Update NixOS `modules/*/configuration.nix`
   - Update Helm values files
   - Update manual manifests

3. **Apply Changes**
   - `nixos-rebuild switch` on affected hosts
   - Verify pods restart in correct namespace

4. **Verify**
   ```bash
   kubectl get pods -n default  # Should be empty (except system pods)
   kubectl get pods -n monitoring | grep memory-monitor
   kubectl get pods -n akash-services | grep akash-export-cert
   ```

---

## 📊 Expected Outcome

**After Cleanup:**

| Namespace | Before | After |
|-----------|--------|-------|
| **default** | 4 pods | 0 pods ✅ |
| **monitoring** | 6 pods | 9 pods (+3 memory monitors) |
| **akash-services** | 10 pods | 11 pods (+1 export cert) |

---

## 🔍 Current Blocker

**API Server Status**: Temporarily unavailable (recovering from 8,500 pod deletion)

**Next Steps**:
1. Wait for API server to recover
2. Identify deployment source for each workload
3. Update configurations
4. Rebuild affected NixOS hosts

---

**Documentation**: `/etc/nixos/docs/kubernetes/default-namespace-cleanup-plan.md`
**Status**: ⏳ Pending API server recovery
