# AMD GPU Coexistence: Mining + Kubernetes AI Workloads

## Overview

This cluster supports **coexisting GPU workloads** on AMD GPUs:
- **Mining**: Via systemd services (lolMiner)
- **AI/Inference**: Via Kubernetes (ROCm workloads)

Both can coexist, but you need to manage GPU allocation carefully.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Forge Node - AMD GPUs (2x RX 5700 XT)                  │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  GPU 0                    GPU 1                         │
│  ├─ systemd: lolMiner   ├─ systemd: lolMiner           │
│  └─ K8s: ROCm pods     └─ K8s: ROCm pods              │
│                                                         │
│  ROCm Device Plugin ──→ Exposes GPUs to Kubernetes      │
│  (amd.com/gpu resource)                                 │
└─────────────────────────────────────────────────────────┘
```

## Current Status

✅ **ROCm K8s Device Plugin**: Installed and running on all nodes
- Namespace: `kube-system`
- DaemonSet: `amdgpu-device-plugin-daemonset`
- Exposes GPU resource: `amd.com/gpu`
- **Fixed**: Removed hardcoded `nodeName: forge` to run on all AMD GPU nodes
- **Status**: Running on 4 nodes (Forge, Sentry, Nexus, Zephyr)

✅ **Mining**: Active via systemd
- Service: `lolminer` (GPU 0 and GPU 1)
- Hashrate: ~4.42 g/s total
- User: root

✅ **Kubernetes GPU Scheduling**: Tested and working
- Test pod successfully accessed both GPUs
- HIP/ROCm libraries available
- Ready for PyTorch, TensorFlow, and other ROCm workloads

## GPU Allocation Model

### Option 1: Separate GPUs (Recommended)

```
GPU 0: Mining only (systemd)
GPU 1: Kubernetes workloads
```

**Setup:**
```bash
# Stop mining on GPU 1
ssh forge 'systemctl stop lolminer@amd-1'

# Deploy K8s workload that requests 1 GPU
kubectl apply -f my-ai-workload.yaml
```

**Advantages:**
- No conflicts
- Mining continues on GPU 0
- Simple to manage

### Option 2: Dynamic Switching

```
Both GPUs: Mine 24/7 via systemd
Stop miner → Deploy K8s → Restart miner
```

**Setup:**
```bash
# 1. Stop mining on specific GPU
ssh forge 'systemctl stop lolminer@amd-0'

# 2. Deploy K8s workload
kubectl apply -f my-ai-workload.yaml

# 3. Wait for completion
kubectl wait --for=condition=complete job/my-ai-job

# 4. Restart mining
ssh forge 'systemctl start lolminer@amd-0'
```

**Advantages:**
- Maximum mining hashrate when not doing AI
- Both GPUs available for AI when needed

## Example: Deploy ROCm AI Workload

### 1. Create GPU Test Namespace

```yaml
# kubernetes-manifests/test/rocm-workload.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: gpu-test
  labels:
    pod-security.kubernetes.io/enforce: privileged
    pod-security.kubernetes.io/audit: privileged
    pod-security.kubernetes.io/warn: privileged
```

### 2. Deploy Simple ROCm Test

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: rocm-gpu-test
  namespace: gpu-test
spec:
  nodeName: forge
  restartPolicy: Never
  containers:
  - name: rocm-test
    image: rocm/dev-ubuntu-22.04:6.2
    command: ["/bin/bash", "-c", "rocminfo && rocm-smi --showuse"]
    resources:
      requests:
        amd.com/gpu: "1"
        memory: "4Gi"
      limits:
        amd.com/gpu: "1"
        memory: "8Gi"
    securityContext:
      privileged: true
    volumeMounts:
    - name: dev
      mountPath: /dev
  volumes:
  - name: dev
    hostPath:
      path: /dev
```

### 3. Deploy and Monitor

```bash
# Deploy
kubectl apply -f kubernetes-manifests/test/rocm-workload.yaml

# Monitor
kubectl get pod rocm-gpu-test -n gpu-test -w

# View logs
kubectl logs rocm-gpu-test -n gpu-test

# Check GPU allocation
kubectl describe node forge | grep -A5 "amd.com/gpu"
```

## Monitoring GPU Usage

### Check GPU Allocation

```bash
# Kubernetes view
kubectl describe node forge | grep -A5 "amd.com/gpu"

# Host view
ssh forge 'rocm-smi --showuse --showmemuse'
```

### Check Mining Status

```bash
# Systemd services
ssh forge 'systemctl status lolminer*'

# Mining processes
ssh forge 'ps aux | grep lolMiner | grep -v grep'
```

### Check Kubernetes GPU Workloads

```bash
# Find pods using GPUs
kubectl get pods -A -o json | \
  jq -r '.items[] | select(.spec.nodeName == "forge") | \
  select(.spec.containers[]?.resources?.limits?."amd.com/gpu" != null) | \
  "\(.metadata.namespace)/\(.metadata.name)"'
```

## Best Practices

### 1. Resource Limits

Always set GPU resource requests:
```yaml
resources:
  requests:
    amd.com/gpu: "1"  # Request 1 GPU
  limits:
    amd.com/gpu: "1"  # Limit to 1 GPU
```

### 2. Node Affinity

Schedule to specific GPU nodes:
```yaml
spec:
  nodeName: forge  # AMD GPU node
  # OR use node selector
  nodeSelector:
    kubernetes.io/hostname: forge
```

### 3. Privileged Mode

ROCm workloads currently need privileged mode:
```yaml
securityContext:
  privileged: true
```

This is required for `/dev/kfd` access and GPU memory management.

### 4. Volume Mounts

Mount device directories:
```yaml
volumeMounts:
- name: dev
  mountPath: /dev
volumes:
- name: dev
  hostPath:
    path: /dev
```

## Maintenance

### Restarting Device Plugin

If GPU resources become unavailable:

```bash
# Check plugin status
kubectl get pods -n kube-system | grep amdgpu

# Restart specific pod
kubectl delete pod amdgpu-device-plugin-daemonset-<pod-id> -n kube-system

# Or recreate entire DaemonSet
kubectl delete daemonset amdgpu-device-plugin-daemonset -n kube-system
kubectl apply -f https://raw.githubusercontent.com/RadeonOpenCompute/k8s-device-plugin/master/k8s-ds-amdgpu-dp.yaml

# Verify GPU resources exposed
kubectl describe node <node-name> | grep "amd.com/gpu"
```

### Verifying GPU Discovery

```bash
# On host with GPU
ssh <node> 'LD_LIBRARY_PATH=/run/opengl-driver/lib rocminfo'

# In Kubernetes pod
kubectl run rocm-test --image=rocm/dev-ubuntu-22.04:6.2 --rm -it --restart=Never \
  --overrides='{"spec":{"nodeName":"<node-name>","containers":[{"name":"test","command":["/bin/bash","-c","rocminfo && sleep 3600"],"image":"rocm/dev-ubuntu-22.04:6.2","resources":{"limits":{"amd.com/gpu":"1"}},"volumeMounts":[{"name":"dev","mountPath":"/dev"}]}],"volumes":[{"name":"dev","hostPath":{"path":"/dev"}}]}}'
```

## Troubleshooting

**Problem**: Container shows 0 GPUs

**Solutions:**
1. Check device plugin is running:
   ```bash
   kubectl get pods -n kube-system | grep amdgpu
   ```

2. Verify GPU resources on node:
   ```bash
   kubectl describe node forge | grep "amd.com/gpu"
   ```

3. Check container has privileged mode:
   ```yaml
   securityContext:
     privileged: true
   ```

4. Verify `/dev/kfd` is accessible:
   ```bash
   kubectl exec -it <pod> -- ls -la /dev/kfd
   ```

### Mining Hashrate Drops

**Problem**: Mining hashrate decreased

**Check:**
1. Is a K8s workload using the same GPU?
   ```bash
   kubectl get pods -A -o wide | grep forge
   ```

2. Stop conflicting K8s workload:
   ```bash
   kubectl delete pod <conflicting-pod>
   ```

3. Restart mining service:
   ```bash
   ssh forge 'systemctl restart lolminer@amd-0'
   ```

### Pod Pending - Insufficient GPUs

**Problem**: Pod stuck in Pending state

**Check:**
1. View pod events:
   ```bash
   kubectl describe pod <pod-name>
   ```

2. Check GPU allocation:
   ```bash
   kubectl describe node forge | grep "amd.com/gpu"
   ```

3. Stop mining on target GPU:
   ```bash
   ssh forge 'systemctl stop lolminer@amd-0'
   ```

## Future Improvements

### 1. GPU Partitioning

Explore MIG (Multi-Instance GPU) equivalent for AMD:
- Split GPU into multiple instances
- Run mining + AI simultaneously on same GPU

### 2. Automated Switching

Create Kubernetes operator that:
- Automatically stops mining when AI job arrives
- Restarts mining when job completes
- Manages GPU allocation dynamically

### 3. Monitoring Dashboard

Set up Grafana dashboard showing:
- Real-time GPU utilization
- Mining hashrate
- Kubernetes workload status
- GPU temperature and power

## References

- **ROCm Documentation**: https://rocm.docs.amd.com/
- **ROCm K8s Device Plugin**: https://github.com/RadeonOpenCompute/k8s-device-plugin
- **PyTorch ROCm**: https://pytorch.org/get-started/locally/
- **TensorFlow ROCm**: https://www.tensorflow.org/install/docker#rocm_radeon_installer

## Summary

✅ **Mining**: Works via systemd (lolMiner)
✅ **AI Workloads**: Work via Kubernetes (ROCm)
✅ **Coexistence**: Stop miner on target GPU, deploy K8s workload, restart miner
✅ **Device Plugin**: Exposes GPUs to Kubernetes for scheduling

**Next Steps:**
1. Decide on GPU allocation model (Option 1 or 2)
2. Deploy actual AI/inference workloads
3. Set up monitoring and automation
4. Document workload-specific procedures

---

**Last Updated**: 2026-03-21
**Status**: Tested and working
**Tested By**: Claude Code (ROCm GPU Test Pod)
