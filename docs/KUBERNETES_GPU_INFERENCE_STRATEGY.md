# Kubernetes GPU Inference Strategy

**Created:** 2026-03-18 | **Status:** Planning

## Current State Analysis

### GPU Infrastructure
| Node | GPUs | VRAM | Current Use |
|------|------|------|-------------|
| Zephyr | RTX 3090 + 3060 Ti | 32GB | AI Gateway (systemd), llamafile |
| Nexus | RTX 3060 Ti | 8GB | Mining |
| Forge | 2x RTX 4060 | 16GB | Mining |
| Sentry | RX 5600 XT (AMD) | - | Monitoring |

**Total NVIDIA: 5 GPUs, 72GB VRAM**

### Problem: 35B Model Performance
- **Current:** llama.cpp on Zephyr only (2 GPUs, 35B model)
- **Bottleneck:** Cross-GPU PCIe communication between heterogeneous GPUs
- **Result:** 35 t/s generation speed (vs 86 t/s on 4B model)

## Root Cause Analysis

### 1. Single-Node Deployment
The 35B model is confined to Zephyr's 2 GPUs with:
- **Heterogeneous GPUs:** RTX 3090 (24GB) + RTX 3060 Ti (8GB)
- **PCIe bottleneck:** Cross-GPU communication over PCIe
- **Memory fragmentation:** 17.7GB on 3090 + 5.5GB on 3060 Ti

### 2. llama.cpp Limitations
- **No tensor parallelism across nodes** (single-node only)
- **Basic multi-GPU:** Simple tensor splitting without optimization
- **No pipeline parallelism:** Cannot distribute across cluster nodes

### 3. Kubernetes GPU Support Missing
- **No NVIDIA Device Plugin:** GPUs not exposed to K8s scheduler
- **No GPU Operator:** Manual driver management required
- **No node affinity:** GPU pods not properly scheduled

## Solution Architecture

### Option 1: sglang (Recommended for Multi-Node)

**Advantages:**
- Multi-node tensor parallelism
- Advanced scheduling (radix attention)
- OpenAI-compatible API
- Better Qwen3.5 support

**Deployment:**
```yaml
# sglang deployment with 4 GPUs across cluster
apiVersion: apps/v1
kind: Deployment
metadata:
  name: qwen35-sglang
spec:
  template:
    spec:
      containers:
      - name: sglang
        image: lmsysorg/sglang:v0.1.15
        resources:
          limits:
            nvidia.com/gpu: 4
        env:
        - name: TENSOR_PARALLEL_SIZE
          value: "4"
        - name: MODEL_PATH
          value: "Qwen/Qwen3.5-35B"
```

**Node Distribution:**
- Zephyr: 2 GPUs (RTX 3090 + 3060 Ti)
- Nexus: 1 GPU (RTX 3060 Ti)
- Forge: 1 GPU (RTX 4060)

### Option 2: vLLM (Best Performance)

**Advantages:**
- PagedAttention for 20x+ throughput
- Continuous batching
- Multi-GPU tensor parallelism
- Excellent Qwen3.5 support

**Deployment:**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: qwen35-vllm
spec:
  template:
    spec:
      containers:
      - name: vllm
        image: vllm/vllm-openai:v0.6.0
        resources:
          limits:
            nvidia.com/gpu: 4
        command: ["python", "-m", "vllm.entrypoints.openai.api_server"]
        args:
        - --model=Qwen/Qwen3.5-35B
        - --tensor-parallel-size=4
        - --max-model-len=32768
```

### Option 3: TensorRT-LLM (Maximum Performance)

**Advantages:**
- NVIDIA-optimized inference
- FP8 quantization support
- Best performance on NVIDIA hardware

**Disadvantages:**
- Complex setup
- Model conversion required
- Less flexible than sglang/vLLM

## Implementation Plan

### Phase 1: Enable Kubernetes GPU Support

```nix
# Add to zephyr/configuration.nix
services.kubernetes = {
  # Enable NVIDIA device plugin
  manifests = {
    nvidiaDevicePlugin = {
      namespace = "kube-system";
      source = ./kubernetes-manifests/nvidia-device-plugin.yaml;
    };
  };
};
```

```bash
# NVIDIA Device Plugin DaemonSet
kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.14.0/deployments/static/nvidia-device-plugin.yml
```

### Phase 2: Label GPU Nodes

```bash
kubectl label nodes zephyr nvidia.com/gpu.present=true
kubectl label nodes zephyr nvidia.com/gpu.product=RTX3090
kubectl label nodes zephyr nvidia.com/gpu.count=2

kubectl label nodes nexus nvidia.com/gpu.present=true
kubectl label nodes nexus nvidia.com/gpu.product=RTX3060Ti
kubectl label nodes nexus nvidia.com/gpu.count=1

kubectl label nodes forge nvidia.com/gpu.present=true
kubectl label nodes forge nvidia.com/gpu.product=RTX4060
kubectl label nodes forge nvidia.com/gpu.count=2
```

### Phase 3: Deploy Multi-Node Inference

**Option A: Single Pod with Node Selector (sglang)**
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: qwen35-inference
spec:
  # Use host network for multi-node communication
  hostNetwork: true
  containers:
  - name: sglang
    image: lmsysorg/sglang:v0.1.15
    resources:
      limits:
        nvidia.com/gpu: 5  # Request all cluster GPUs
    env:
    - name: TENSOR_PARALLEL_SIZE
      value: "5"
    - name: MASTER_ADDR
      value: "zephyr"  # Control plane node
    volumeMounts:
    - name: model-cache
      mountPath: /models
  volumes:
  - name: model-cache
    hostPath:
      path: /var/cache/ai-inference
```

**Option B: Ray Cluster for Distributed Inference**
```yaml
# Ray Head on Zephyr
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ray-head
spec:
  template:
    spec:
      nodeName: zephyr
      containers:
      - name: ray-head
        image: rayproject/ray:2.9.0
        command: ["ray", "start", "--head"]
        ports:
        - containerPort: 6379
        - containerPort: 8265

---
# Ray Workers on GPU nodes
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: ray-worker
spec:
  selector:
    matchLabels:
      nvidia.com/gpu.present: "true"
  template:
    spec:
      containers:
      - name: ray-worker
        image: rayproject/ray:2.9.0
        command: ["ray", "start", "--address=ray-head.zephyr:6379"]
        resources:
          limits:
            nvidia.com/gpu: 1
```

### Phase 4: Migrate AI Gateway to Kubernetes

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ai-inference-gateway
spec:
  replicas: 3
  template:
    spec:
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchExpressions:
                - key: app
                  operator: In
                  values:
                  - ai-inference-gateway
              topologyKey: kubernetes.io/hostname
      containers:
      - name: gateway
        image: ghcr.io/your-org/ai-gateway:latest
        env:
        - name: BACKEND_URL
          value: "http://qwen35-sglang:8000"
        - name: REDIS_URL
          value: "redis://redis-service:6379"
        resources:
          requests:
            cpu: "2"
            memory: "4Gi"
          limits:
            cpu: "4"
            memory: "8Gi"
```

## Performance Optimization

### Batch Size Tuning
| Model | GPUs | batch-size | ubatch-size | Expected t/s |
|-------|------|------------|-------------|--------------|
| Qwen3.5-4B | 2 | 64 | 16 | 86 |
| Qwen3.5-35B | 2 | 64 | 16 | 35 |
| Qwen3.5-35B | 4 | 128 | 32 | ~70 |
| Qwen3.5-35B | 5 | 256 | 64 | ~100+ |

### KV Cache Quantization
```python
# 8-bit keys, 4-bit values (50% memory savings, minimal quality loss)
--cache-type-k q8_0 --cache-type-v q4_0
```

### Flash Attention
```bash
# Must be enabled for Qwen3.5
--flash-attn on
```

## Monitoring

### GPU Metrics
```yaml
apiVersion: v1
kind: Service
metadata:
  name: gpu-exporter
spec:
  selector:
    app: nvidia-gpu-exporter
  ports:
  - port: 9400
    targetPort: 9400
```

### Prometheus Queries
```promql
# GPU utilization
sum(nvidia_gpu_utilization_gpu) by (hostname)

# GPU memory usage
sum(nvidia_gpu_memory_used_bytes) by (hostname)

# Inference throughput
rate(inference_tokens_total[5m])
```

## Next Steps

1. ✅ **Immediate:** Fix llama.cpp KV cache (q8_0/q4_0)
2. ⏳ **Week 1:** Install NVIDIA Device Plugin for K8s
3. ⏳ **Week 2:** Deploy sglang with 4-GPU tensor parallelism
4. ⏳ **Week 3:** Migrate AI Gateway to K8s
5. ⏳ **Week 4:** Benchmark and optimize

## References

- [sglang Documentation](https://lmsys.org/blog/2024-01-17-sglang/)
- [vLLM Multi-GPU](https://docs.vllm.ai/en/latest/serving/multi_gpu.html)
- [NVIDIA K8s Device Plugin](https://github.com/NVIDIA/k8s-device-plugin)
- [Ray on Kubernetes](https://docs.ray.io/en/latest/cluster/kubernetes.html)
