# Kubernetes GPU Support - Complete Guide

**Last Updated:** 2026-03-15
**Status:** ✅ All 7 GPUs Operational

## Overview

The Kubernetes cluster has full GPU support across all nodes with mixed vendor support:
- **NVIDIA CUDA**: 5 GPUs (Zephyr: 2, Nexus: 1, Forge: 2)
- **AMD ROCm**: 2 GPUs (Forge: 2, Sentry: 1)

## Cluster GPU Inventory

| Node   | NVIDIA GPUs      | AMD GPUs         | Total | Device Plugin    |
|--------|------------------|------------------|-------|------------------|
| Zephyr | RTX 3060 Ti      | -                | 1     | nvidia-device-plugin |
|        | RTX 3090         | -                | 1     | nvidia-device-plugin |
| Nexus  | RTX 3060 Ti      | -                | 1     | nvidia-device-plugin |
| Forge  | RTX 4060 x2      | RX 5700 XT x2    | 4     | nvidia + amd plugins |
| Sentry | -                | RX 5600 XT       | 1     | amd-device-plugin |
| **Total** | **5**         | **3**            | **8** | |

## Device Plugins

### NVIDIA Device Plugin
- **Repository:** https://github.com/NVIDIA/k8s-device-plugin
- **Resource Type:** `nvidia.com/gpu`
- **Node Selector:** `accelerator=nvidia-gpu`
- **DaemonSet:** 3 pods (Zephyr, Nexus, Forge)
- **Status:** ✅ Running

### AMD Device Plugin
- **Repository:** https://github.com/RadeonOpenCompute/k8s-device-plugin
- **Resource Type:** `amd.com/gpu`
- **Node Selector:** `gpu=amd`
- **DaemonSet:** 2 pods (Forge, Sentry)
- **Status:** ✅ Running
- **Note:** Requires privileged mode for `/dev/kfd` access

## Quick Start

### Verify GPU Registration

```bash
# Check GPU capacity per node
kubectl get nodes -o json | jq -r '.items[] | "\(.metadata.name): nvidia.com/gpu=\(.status.capacity["nvidia.com/gpu"] // "null") amd.com/gpu=\(.status.capacity["amd.com/gpu"] // "null")"'

# Expected output:
# forge: nvidia.com/gpu=2 amd.com/gpu=2
# nexus: nvidia.com/gpu=1 amd.com/gpu=null
# sentry: nvidia.com/gpu=null amd.com/gpu=1
# zephyr: nvidia.com/gpu=2 amd.com/gpu=null
```

### Test NVIDIA GPU

```bash
# Quick device visibility test
kubectl run nvidia-test --image=ubuntu:22.04 --restart=Never --overrides='
{
  "spec": {
    "nodeSelector": {"accelerator": "nvidia-gpu"},
    "containers": [{
      "name": "test",
      "image": "ubuntu:22.04",
      "command": ["sh", "-c", "ls -la /dev/nvidia*"],
      "resources": {"limits": {"nvidia.com/gpu": 1}}
    }]
  }
}'

# Clean up
kubectl delete pod nvidia-test
```

### Test AMD GPU

```bash
# Note: AMD requires privileged mode
kubectl run amd-test --image=rocm/dev-ubuntu-22.04:6.2 --restart=Never --overrides='
{
  "spec": {
    "nodeSelector": {"gpu": "amd"},
    "containers": [{
      "name": "test",
      "image": "rocm/dev-ubuntu-22.04:6.2",
      "command": ["rocm-smi"],
      "resources": {"limits": {"amd.com/gpu": 1}},
      "securityContext": {"privileged": true}
    }]
  }
}'

# Clean up
kubectl delete pod amd-test
```

## Scheduling Patterns

### 1. NVIDIA-Only Workload

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: cuda-workload
spec:
  nodeSelector:
    accelerator: nvidia-gpu
  containers:
  - name: worker
    image: nvidia/cuda:12.1.0-runtime
    resources:
      limits:
        nvidia.com/gpu: 1
```

### 2. AMD-Only Workload

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: rocm-workload
spec:
  nodeSelector:
    gpu: amd
  containers:
  - name: worker
    image: rocm/dev-ubuntu-22.04:6.2
    command: ["your-rocm-app"]
    resources:
      limits:
        amd.com/gpu: 1
    securityContext:
      privileged: true  # Required for AMD GPU access
```

### 3. Multi-GPU on Forge

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: multi-gpu-forge
spec:
  nodeSelector:
    kubernetes.io/hostname: forge  # Pin to Forge
  containers:
  - name: worker
    image: nvidia/cuda:12.1.0-runtime
    resources:
      limits:
        nvidia.com/gpu: 2  # Both RTX 4060s
```

### 4. Flexible Vendor Selection

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: flexible-gpu
spec:
  affinity:
    nodeAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        preference:
          matchExpressions:
          - key: accelerator
            operator: In
            values: [nvidia-gpu]
  containers:
  - name: worker
    image: your-image
    resources:
      limits:
        nvidia.com/gpu: 1  # Will try NVIDIA first
```

### 5. DaemonSet on All GPU Nodes

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: gpu-monitor
spec:
  selector:
    matchLabels:
      app: gpu-monitor
  template:
    metadata:
      labels:
        app: gpu-monitor
    spec:
      # OR logic - run on either GPU type
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: accelerator
                operator: In
                values: [nvidia-gpu]
            - matchExpressions:
              - key: gpu
                operator: In
                values: [amd]
      containers:
      - name: monitor
        image: your-monitor-image
        resources:
          limits:
            nvidia.com/gpu: 1
```

## Node Labels

For GPU scheduling to work correctly, ensure nodes have proper labels:

```bash
# NVIDIA nodes (auto-applied by device plugin)
kubectl label node zephyr accelerator=nvidia-gpu
kubectl label node nexus accelerator=nvidia-gpu
kubectl label node forge accelerator=nvidia-gpu

# AMD nodes (manual label)
kubectl label node forge gpu=amd
kubectl label node sentry gpu=amd
```

## Resource Requests

### NVIDIA CUDA
```yaml
resources:
  limits:
    nvidia.com/gpu: 1  # Integer number of GPUs
  requests:
    cpu: "2"
    memory: "4Gi"
```

### AMD ROCm
```yaml
resources:
  limits:
    amd.com/gpu: 1  # Integer number of GPUs
  requests:
    cpu: "2"
    memory: "4Gi"
```

## GPU Sharing (Time-Slicing)

NVIDIA supports GPU sharing via time-slicing configuration. This is configured in the device plugin config map.

For MIG (Multi-Instance GPU) support on A100/H100, see NVIDIA documentation.

## Troubleshooting

### GPUs Not Showing Up

```bash
# Check device plugin pods
kubectl get pods -n kube-system | grep gpu

# Check node capacity
kubectl describe node <node-name> | grep -i gpu

# Check device plugin logs
kubectl logs -n kube-system nvidia-device-plugin-daemonset-xxxxx
kubectl logs -n kube-system amd-gpu-device-plugin-daemonset-xxxxx
```

### AMD GPU Permission Errors

AMD GPUs require privileged access:
```yaml
securityContext:
  privileged: true
```

Also ensure kube-apiserver has `--allow-privileged=true`.

### Pod Stuck in ContainerCreating

Common causes:
1. Wrong image architecture (ensure amd64)
2. GPU driver issues on node
3. Device plugin not running on target node

## Example Manifests

See `/etc/nixos/kubernetes-manifests/gpu/` for:
- `gpu-test-nvidia.yaml` - NVIDIA GPU test
- `gpu-test-amd.yaml` - AMD GPU test
- `gpu-scheduling-examples.yaml` - Comprehensive scheduling patterns

## References

- [NVIDIA Device Plugin](https://github.com/NVIDIA/k8s-device-plugin)
- [AMD Device Plugin](https://github.com/RadeonOpenCompute/k8s-device-plugin)
- [Kubernetes Device Plugins](https://kubernetes.io/docs/concepts/extend-kubernetes/compute-storage-net/device-plugins/)
- [ROCm Documentation](https://rocm.docs.amd.com/)
