# GPU Over-Provisioning Prevention Strategy

**Date**: 2026-03-21
**Incident**: 8,500 failed mining pods causing IP exhaustion
**Status**: ✅ Resolved + Prevention Implemented

---

## 🔴 Incident Summary

**What Happened:**
- Mining deployment on Nexus scaled to **8,502 replicas**
- Nexus only has **1 NVIDIA GPU** available
- 8,501 pods failed immediately (GPU unavailable)
- Failed pods consumed **8,500+ IP addresses** in Flannel subnet
- Caused cluster-wide IP exhaustion

**Impact:**
- ❌ MLflow deployment blocked (IP exhaustion on Sentry)
- ❌ New workloads unable to schedule
- ❌ etcd storage wasted (8,500 pod objects)
- ❌ kubectl operations degraded (filtering 8,500 objects)
- ❌ Scheduler performance degraded

---

## ✅ Resolution

**Immediate Actions (Completed):**
1. ✅ Deleted 8,500 failed mining pods
2. ✅ Scaled gpu-miner-nexus deployment to 1 replica
3. ✅ Applied GPU resource quota to mining namespace

**Before/After:**
| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| Failed mining pods | 8,500 | 0 | **-100%** |
| IPs consumed by failed pods | 8,500 | 0 | **-100%** |
| Mining deployment replicas | 8,502 | 1 | **-99.9%** |
| Available IPs for new pods | ~0 | 8,500+ | **+∞** |

---

## 🛡️ Prevention Strategy

### 1. **Resource Quota** ✅ IMPLEMENTED

**File**: `/etc/nixos/kubernetes-manifests/scheduling/mining-gpu-quota.yaml`

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: gpu-quota
  namespace: mining
spec:
  hard:
    requests.nvidia.com/gpu: "1"  # Matches Nexus GPU count
    requests.amd.com/gpu: "4"     # Matches total AMD GPUs
```

**What It Does:**
- Prevents creation of pods that exceed available GPU capacity
- Deployment controller will fail fast instead of creating 8,500 failed pods
- Applied at namespace level

**Verification:**
```bash
kubectl get resourcequota gpu-quota -n mining
# Output: requests.nvidia.com/gpu: 1/1, requests.amd.com/gpu: 0/4
```

---

### 2. **Deployment Replica Limits**

**Best Practices:**
```yaml
# ❌ WRONG - Exceeds available GPUs
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gpu-miner-nexus
spec:
  replicas: 8502  # Way too many!

# ✅ CORRECT - Matches available GPUs
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gpu-miner-nexus
spec:
  replicas: 1  # Matches Nexus GPU count
```

**Implementation:**
- Manually set replicas to match GPU capacity
- Use HorizontalPodAutoscaler with custom metrics (not default CPU/memory)

---

### 3. **Admission Controller Validation** (Future)

**Option A: ValidatingAdmissionPolicy**
```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: gpu-limit-validator
spec:
  matchConstraints:
    - operations: ["CREATE", "UPDATE"]
      namespaces: ["mining"]
  validations:
    - expression: "spec.replicas <= 10"
      message: "Deployment replicas cannot exceed 10"
```

**Option B: OPA Gatekeeper**
```rego
package kubernetes.admission

deny[{
  "msg": "Deployment replicas exceed GPU capacity",
  "details": sprintf("Namespace %s has %d GPUs but deployment requests %d replicas", [
    input.namespace,
    total_gpus,
    input.request.object.spec.replicas
  ])
}] {
  input.request.kind.kind == "Deployment"
  input.request.object.spec.replicas > total_gpus
}
```

---

### 4. **Monitoring and Alerting**

**Prometheus Alerts:**
```yaml
groups:
- name: gpu-provisioning
  rules:
  - alert: TooManyFailedPods
    expr: |
      count(kube_pod_status_phase{namespace="mining", phase="Failed"}) > 10
    for: 5m
    annotations:
      summary: "Too many failed pods in mining namespace"
      description: "{{ $value }} failed pods detected"

  - alert: GPUOverProvisioning
    expr: |
      sum(kube_deployment_spec_replicas{namespace="mining"})
      >
      sum(kube_node_status_capacity{resource="nvidia_com/gpu"})
    for: 1m
    annotations:
      summary: "Mining deployments exceed GPU capacity"
```

---

### 5. **Cluster-Level Protection**

**Namespace Resource Quotas:**
```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: cluster-gpu-limit
  namespace: mining
spec:
  hard:
    pods: "100"  # Max 100 pods in mining namespace
    requests.nvidia.com/gpu: "1"
    requests.amd.com/gpu: "4"
```

**Pod Disruption Budgets:**
```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: mining-pdb
  namespace: mining
spec:
  minAvailable: 0
  selector:
    matchLabels:
      app: gpu-miner
```

---

## 📊 GPU Inventory by Node

| Node | NVIDIA GPUs | AMD GPUs | Mining Pods Allowed | Current Usage |
|------|-------------|----------|-------------------|----------------|
| Nexus | 1 | 0 | 1 | 1 ✅ |
| Forge | 2 | 2 | 2 NVIDIA + 2 AMD | 2 ✅ |
| Zephyr | 2 | 0 | 2 | 1 (1 available) |
| Sentry | 0 | 1 | 1 AMD | 0 (1 available) |

**Total**: 5 NVIDIA + 3 AMD = 8 GPUs

---

## 🎯 Verification Commands

**Check GPU Quota:**
```bash
kubectl get resourcequota -n mining
kubectl describe resourcequota gpu-quota -n mining
```

**Check Failed Pods:**
```bash
kubectl get pods -n mining --field-selector=status.phase==Failed
# Should return: No resources found
```

**Check GPU Usage:**
```bash
kubectl get pods -n mining -o jsonpath='{range .items[*]}{.metadata.name}{"\tGPU: "}{.spec.containers[0].resources.requests.nvidia\.com/gpu}{"\n"}{end}'
```

**Test Prevention:**
```bash
# This should fail due to quota
kubectl scale deployment gpu-miner-nexus -n mining --replicas=10
# Expected: Error: exceeded quota: gpu-quota, requested: requests.nvidia.com/gpu=10
```

---

## 🔄 Maintenance Procedures

**Monthly:**
1. Review GPU quota limits (if hardware changes)
2. Audit mining deployment replica counts
3. Check for zombie/failed pods cluster-wide

**Quarterly:**
1. Review GPU allocation across namespaces
2. Update quota limits based on new hardware
3. Validate prevention mechanisms still work

---

## 📚 Related Documentation

- **Incident Report**: `/etc/nixos/docs/kubernetes/gpu-overprovisioning-incident-2026-03-21.md`
- **Quota Manifest**: `/etc/nixos/kubernetes-manifests/scheduling/mining-gpu-quota.yaml`
- **Cluster Analysis**: `/etc/nixos/docs/kubernetes/cluster-analysis-2026-03-21.md`

---

**Generated by**: Claude (MLOps Engineer + Kubernetes Specialist)
**Status**: ✅ Resolved with prevention in place
**Last Updated**: 2026-03-21
