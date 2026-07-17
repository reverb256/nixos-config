# Zephyr RAM Protection Policy

**Created:** 2026-03-24
**Status:** Active
**Purpose:** Prevent OOM crashes on Zephyr control plane node

## Problem

Zephyr (31GB RAM) runs the Kubernetes control plane components (kube-apiserver, etcd, kube-scheduler, kube-controller-manager) plus AI workloads and gaming. This leaves minimal headroom for additional workloads, causing frequent OOM (Out of Memory) conditions.

## Solution: Node Taint

Zephyr has a `ram-constrained=true:NoSchedule` taint applied to prevent non-critical workloads from scheduling.

```bash
kubectl describe node zephyr | grep Taints
```

Expected output:
```
Taints:             ram-constrained=true:NoSchedule
```

## Workload Scheduling Policy

### Allowed Workloads on Zephyr

Only workloads with the `ram-constrained` toleration can schedule to Zephyr:

1. **Infrastructure** (automatically tolerates control-plane taint)
   - kube-apiserver
   - etcd
   - kube-scheduler
   - kube-controller-manager
   - Calico CNI components (calico-node, tigera-operator)
   - CoreDNS
   - CNI plugins (nvidia-device-plugin, amd-gpu-device-plugin)

2. **Mining** (explicit ram-constrained toleration)
   - xmrig-zephyr (CPU mining)
   - gpu-miner-zephyr (GPU mining - currently disabled due to GPU device health issue)

### Default Scheduling Target

**ALL other workloads MUST schedule to Nexus (46GB RAM)** by default.

Use `nodeSelector` or `nodeAffinity` to enforce this:

```yaml
spec:
  template:
    spec:
      nodeName: nexus  # Force scheduling to nexus
      # OR use affinity:
      nodeAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
          - matchExpressions:
            - key: kubernetes.io/hostname
              operator: In
              values:
              - nexus
```

## Adding ram-constrained Tolation

To add a new workload to Zephyr, add the toleration to your deployment YAML:

```yaml
spec:
  template:
    spec:
      tolerations:
        - key: ram-constrained
          operator: Equal
          value: "true"
          effect: NoSchedule
```

### Example: Mining Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gpu-miner-zephyr
  namespace: mining
spec:
  template:
    spec:
      nodeName: zephyr
      tolerations:
        - key: node-role.kubernetes.io/control-plane
          operator: Exists
          effect: NoSchedule
        - key: workstation
          operator: Equal
          value: "true"
          effect: NoSchedule
        - key: interactive
          operator: Equal
          value: "true"
          effect: NoExecute
        - key: ram-constrained  # REQUIRED for Zephyr scheduling
          operator: Equal
          value: "true"
          effect: NoSchedule
```

## Verification

To verify a workload has the toleration applied:

```bash
# Check deployment
kubectl get deployment <name> -n <namespace> -o yaml | grep -A 5 ram-constrained

# Check live pod
kubectl get pod <pod-name> -n <namespace> -o jsonpath='{.spec.tolerations}' | jq '.[] | select(.key=="ram-constrained")'
```

## Known Issues

### gpu-miner-zephyr Pod Explosion

**Status:** Scaled to 0 replicas (disabled)

**Issue:** gpu-miner-zephyr deployment creates hundreds of failed pods with `UnexpectedAdmissionError`.

**Root Cause:** GPU device health issue - "Allocate failed due to no healthy devices present; cannot allocate unhealthy devices nvidia.com/gpu"

**Impact:** Not related to ram-constrained toleration (toleration is correctly applied).

**Resolution:** Pending GPU device health investigation. xmrig-zephyr (CPU mining) continues to run successfully.

## Related Documentation

- [CLAUDE.md - Critical Safety Rules](/etc/nixos/CLAUDE.md) - Workload scheduling constraints
- [AGENTS.md - Workload Scheduling](/etc/nixos/AGENTS.md) - ZEPHYR OOM PREVENTION section
- [STATUS.md](/etc/nixos/STATUS.md) - Real-time cluster health
- [docs/kubernetes/PREVENT_POD_EXPLOSION.md](/etc/nixos/docs/kubernetes/PREVENT_POD_EXPLOSION.md) - Pod explosion prevention

## Changes

**2026-03-24:**
- Applied ram-constrained toleration to xmrig-zephyr and gpu-miner-zephyr
- Verified xmrig-zephyr running successfully with toleration
- Disabled gpu-miner-zephyr (GPU device health issue, unrelated to tolerations)
- Created documentation
