# Multi-GPU Deployment Strategy

## Current State

### Active Deployments
- **Zephyr**: 2x NVIDIA GPUs (RTX 3060 Ti + RTX 3090)
  - ✅ llama.cpp running (commit 8244)
  - ✅ Kubernetes service: llama-cpp-qwen.ai-inference.svc.cluster.local:8080
  - ✅ Model: Qwen3.5-2B-IQ4_NL.gguf
  - ✅ GPU memory: 1331 MiB + 2726 MiB

### Available GPUs
- **Nexus**: 1x NVIDIA RTX 3060 Ti (8GB) - 99% free
- **Forge**: 2x NVIDIA RTX 4060 (8GB each) - 95% free
- **Forge**: 2x AMD RX 5700 XT (8GB each) - Available
- **Sentry**: 1x AMD RX 5600 XT (4GB) - Available

## Deployment Plan

### Step 1: Deploy llama.cpp to Nexus

#### 1.1 Copy NixOS module configuration
```bash
scp /etc/nixos/modules/services/ai-inference/llama-cpp.nix nexus:/etc/nixos/modules/services/ai-inference/
```

#### 1.2 Update Nexus configuration
Add to `/etc/nixos/hosts/nexus/configuration.nix`:
```nix
services.llama-cpp = {
  enable = true;
  package = pkgs.llama-cpp-b8419;
  host = "0.0.0.0";
  port = 8083;
  modelsPath = "/home/j_kro/.lmstudio/models";
  model = "unsloth/Qwen3.5-2B-GGUF/Qwen3.5-2B-IQ4_NL.gguf";
  extraArgs = [
    "--ngl" "999"           # Max GPU offload
    "--ctx-size" "16384"    # Context length
    "--threads" "8"         # CPU threads
    "--batch-size" "512"
    "--ubatch-size" "512"
    "--flash-attn" "on"
    "--cache-type-k" "bf16"
    "--cache-type-v" "bf16"
    "--metrics"
    "--port-metrics" "9090"
  ];
};
```

#### 1.3 Apply and rebuild
```bash
sudo nixos-rebuild switch
```

### Step 2: Deploy llama.cpp to Forge

#### 2.1 Same configuration as Nexus
Use identical NixOS configuration

#### 2.2 Apply and rebuild
```bash
sudo nixos-rebuild switch
```

### Step 3: Create Kubernetes Services

Services already created:
- `/etc/nixos/kubernetes-manifests/llama-cpp/10-service-nexus.yaml`
- `/etc/nixos/kubernetes-manifests/llama-cpp/11-service-forge.yaml`

Apply them:
```bash
kubectl apply -f /etc/nixos/kubernetes-manifests/llama-cpp/10-service-nexus.yaml
kubectl apply -f /etc/nixos/kubernetes-manifests/llama-cpp/11-service-forge.yaml
```

### Step 4: AMD GPU Deployment (Phase 2)

#### Option 1: llama.cpp with ROCm
Pros: Same codebase, proven stability
Cons: ROCm installation required

#### Option 2: MLC LLM
Pros: AMD-optimized, good performance
Cons: Different API, more complex

#### Option 3: Vulkan Compute
Pros: Cross-vendor, portable
Cons: Lower performance

**Recommendation**: Start with llama.cpp + ROCm for consistency

## Load Balancing Strategy

### Round-Robin Distribution
Create a Kubernetes Service with multiple endpoints:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: llama-cpp-qwen-cluster
  namespace: ai-inference
spec:
  type: ClusterIP
  ports:
    - port: 8080
      targetPort: 8083
---
apiVersion: v1
kind: Endpoints
metadata:
  name: llama-cpp-qwen-cluster
  namespace: ai-inference
subsets:
  - addresses:
      - ip: 10.1.1.110  # zephyr
      - ip: 10.1.1.108  # nexus
      - ip: 10.1.1.109  # forge
    ports:
      - port: 8083
```

### AI Gateway Configuration
Update Gateway to use load-balanced service:
```python
BACKEND_URL = "http://llama-cpp-qwen-cluster.ai-inference.svc.cluster.local:8080"
```

## Performance Expectations

### Single Instance (Current)
- Throughput: ~7 req/s
- Response time: ~140ms
- Capacity: ~600 req/min

### Multi-Instance (3 nodes)
- Throughput: ~21 req/s (3x)
- Response time: ~140ms (unchanged)
- Capacity: ~1800 req/min (3x)
- Redundancy: High (2 backup nodes)

## GPU Memory Allocation

### Per Instance
- Model: Qwen3.5-2B-IQ4_NL.gguf (~1.5 GB)
- KV Cache: ~500 MB (bf16)
- Overhead: ~300 MB
- **Total**: ~2.3 GB per GPU

### Cluster-Wide
- 3 NVIDIA GPUs × 2.3 GB = ~7 GB VRAM
- All GPUs have plenty of headroom

## Monitoring

### Per-Node Metrics
```bash
# Zephyr
curl http://10.1.1.110:9090/metrics

# Nexus  
curl http://10.1.1.108:9090/metrics

# Forge
curl http://10.1.1.109:9090/metrics
```

### Gateway Load Balancing
Monitor request distribution:
```bash
kubectl logs -f -n ai-inference deploy/ai-inference-gateway | grep "backend"
```

## Rollout Plan

1. ✅ **Zephyr**: Already deployed
2. ⏳ **Nexus**: Deploy today (15 min)
3. ⏳ **Forge**: Deploy today (15 min)
4. ⏳ **Load Balancer**: Configure (5 min)
5. ⏳ **Testing**: End-to-end verification (10 min)
6. ⏳ **AMD GPUs**: Phase 2 (future)

**Total Time**: ~45 minutes for NVIDIA GPU cluster

## Success Criteria

- ✅ All 3 NVIDIA nodes running llama.cpp
- ✅ Kubernetes services configured
- ✅ Load balancer distributing requests
- ✅ End-to-end inference working on all nodes
- ✅ 3x throughput improvement
- ✅ High availability (2 backup nodes)
