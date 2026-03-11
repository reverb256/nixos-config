# Kubernetes GPU Scheduling Infrastructure

## ✅ Completed Setup

### 1. NixOS Container Images
Built using `pkgs.dockerTools.buildImage` to ensure binary compatibility:
- **xmrig-proxy**: `nix build .#xmrig-proxy-image`
- **lolminer**: `nix build .#lolminer-image`

These images use the same binaries that work on bare metal, avoiding libuv/container networking issues.

### 2. Kubernetes Priority Classes
```bash
kubectl get priorityclasses
```
- **high-priority-ai** (value: 1000): For AI inference workloads
- **low-priority-mining** (value: 100): For cryptocurrency mining

When AI jobs need GPUs, they will immediately preempt mining pods.

### 3. xmrig-proxy Deployment
```bash
kubectl get pods -n mining -l app=xmrig-proxy
# NAME                           READY   STATUS    RESTARTS   AGE
# xmrig-proxy-8596b68867-f77hm   1/1     Running   0          10m
```

Successfully running in Kubernetes with:
- NixOS-built container image
- ConfigMap for configuration
- Service on port 3333 (stratum) and 8081 (API)
- Host networking for performance

## 🎯 Architecture

```
GPU Scheduler (Kubernetes)
├── High Priority (AI Inference)
│   ├── PriorityClass: high-priority-ai (1000)
│   └── Preempts: mining pods immediately
│
└── Low Priority (Mining)
    ├── PriorityClass: low-priority-mining (100)
    ├── Auto-resume: when GPUs free up
    └── Maximize utilization: when AI not running
```

## 📋 Next Steps

### 1. Build and Deploy lolminer Container Image

```bash
# Build the lolminer image
nix build .#lolminer-image

# Import into containerd on each GPU node
for host in zephyr forge; do
  ssh $host "sudo ctr -n k8s.io images import - < /etc/nixos/result"
done

# Deploy GPU miners
kubectl apply -f kubernetes-manifests/mining/gpu-miner-zephyr.yaml
kubectl apply -f kubernetes-manifests/mining/gpu-miner-forge.yaml
```

### 2. Stop Bare Metal Mining Services

Once Kubernetes miners are confirmed working:

```bash
# Disable bare metal systemd mining services
just switch  # This will apply the NixOS config with mining disabled

# Or manually stop:
for host in zephyr forge; do
  ssh $host "sudo systemctl stop lolminer-nvidia lolminer-amd"
done
```

### 3. Deploy AI Workloads with High Priority

When ready to schedule AI workloads:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ai-inference
spec:
  template:
    spec:
      priorityClassName: high-priority-ai  # Preempts mining
      containers:
      - name: ai-model
        resources:
          requests:
            nvidia.com/gpu: "1"
          limits:
            nvidia.com/gpu: "1"
```

When AI pods are scheduled:
1. Mining pods are **immediately evicted** (as requested)
2. AI pods start on the GPUs
3. When AI pods complete, mining pods **auto-resume**

### 4. Monitoring and Testing

```bash
# Watch for pod preemption events
watch -n 5 'kubectl get pods -n mining'

# Check GPU allocation
kubectl describe nodes | grep -A 5 "Allocated resources"

# Test preemption manually
# 1. Start AI pod with high-priority-ai
# 2. Watch mining pods get evicted
# 3. Delete AI pod
# 4. Watch mining pods auto-resume
```

## 🔧 Configuration Files

| File | Purpose |
|------|---------|
| `flake.nix` | Container image definitions |
| `kubernetes-manifests/common/priority-classes.yaml` | PriorityClass definitions |
| `kubernetes-manifests/mining/xmrig-proxy-deployment.yaml` | Proxy deployment |
| `kubernetes-manifests/mining/gpu-miner-zephyr.yaml` | Zephyr GPU miner |
| `kubernetes-manifests/mining/gpu-miner-forge.yaml` | Forge GPU miner (NVIDIA + AMD) |

## ⚡ Current Status

- ✅ xmrig-proxy: Running in Kubernetes
- ⏳ lolminer images: Built, need deployment
- ⏳ GPU miners: Manifests ready, pending deployment
- ⏳ Bare metal mining: Still running (will disable after K8s confirmed)

## 🎓 Key Insights

1. **Container Runtime**: Kubernetes uses containerd, not Docker. Images must be imported with `ctr`
2. **PriorityClasses**: Enable automatic GPU preemption based on workload priority
3. **Resource Requests**: Critical for scheduler to make preemption decisions
4. **NixOS Images**: Using the same binaries as bare metal ensures compatibility
5. **Immediate Eviction**: As requested, mining pods are killed instantly when AI needs GPUs

## 🚀 When AI Workloads Arrive

1. Deploy AI pod with `priorityClassName: high-priority-ai`
2. Kubernetes scheduler sees higher priority pod needs GPUs
3. Mining pods (low-priority-mining) are immediately evicted
4. AI pod starts on freed GPUs
5. Mining pods stop submitting new shares
6. When AI completes, mining pods auto-restart

This maximizes GPU utilization while ensuring AI workloads always have priority access.
