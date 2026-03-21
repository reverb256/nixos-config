# AMD GPU Utilization Strategy

## Overview

**AMD GPUs as First-Class AI Citizens**: The 3 AMD GPUs in the cluster (1x 5600 XT on Sentry, 2x 5700 XT on Forge) are not limited to mining - they're fully capable of running AI/ML workloads via ROCm or Vulkan backends. This significantly expands the cluster's AI inference capacity beyond NVIDIA GPUs.

## AMD GPU Inventory

| Node | GPU | Model | VRAM | Primary Use Case | AI Framework Support |
|------|-----|-------|------|------------------|---------------------|
| **Sentry** | 5600 XT | RX 5600 XT | 6 GB GDDR6 | AI inference (llamafile) | ROCm, Vulkan (llama.cpp) |
| **Forge** | 5700 XT #1 | RX 5700 XT | 8 GB GDDR6 | AI training/inference | ROCm, PyTorch (ROCm), TensorFlow |
| **Forge** | 5700 XT #2 | RX 5700 XT | 8 GB GDDR6 | AI training/inference | ROCm, PyTorch (ROCm), TensorFlow |

**Total AMD VRAM**: 22 GB (vs 38 GB NVIDIA VRAM across 5 NVIDIA GPUs)
**Total Cluster AI Capacity**: 60 GB VRAM (8 GPUs combined)

## Supported AI Frameworks on AMD

### 1. llama.cpp (ROCm/Vulkan)
**Best for**: LLM inference, text generation, code completion

```dockerfile
# llamafile with AMD GPU support
FROM ghcr.io/nvidia/cuda:11.8.0-base-ubuntu22.04
# Actually use ROCm base image for AMD
FROM rocm/pytorch:rocm5.7_ubuntu22.04_py3.10

RUN git clone https://github.com/ggerganov/llama.cpp
WORKDIR /llama.cpp
RUN make LLAMA_HIPBLAS=1 LLAMA_HIP=1  # Enable AMD ROCm support

ENTRYPOINT ["./llama-cli", "--model", "/models/model.gguf", "--gpu-layers", "999", "--n-gpu-layers", "999"]
```

**Performance**:
- 5600 XT: ~20-30 tokens/sec (7B models)
- 5700 XT: ~25-35 tokens/sec (7B models)
- VRAM utilization: 4-6 GB per model (quantized)

### 2. PyTorch (ROCm)
**Best for**: Deep learning training, computer vision, NLP

```python
# PyTorch with ROCm support
import torch

# Verify AMD GPU available
print(f"ROCm available: {torch.version.hip}")  # Should show ROCm version
print(f"GPUs detected: {torch.cuda.device_count()}")

# Move model to AMD GPU
device = torch.device("cuda:0")  # First AMD GPU
model = model.to(device)

# Training loop
for batch in dataloader:
    batch = batch.to(device)
    output = model(batch)
    loss = criterion(output, target)
    loss.backward()
    optimizer.step()
```

**Performance**:
- 5700 XT: ~60-70% of RTX 3060 Ti performance (FP32)
- Memory bandwidth: 448 GB/s (5700 XT) vs 360 GB/s (5600 XT)
- Good for: Training smaller models (<8B parameters)

### 3. TensorFlow (ROCm)
**Best for**: Production ML pipelines, TFLite models

```python
import tensorflow as tf

# Verify AMD GPU available
print(f"GPUs: {tf.config.list_physical_devices('GPU')}")

# Simple inference
model = tf.keras.models.load_model('/model/model.h5')
prediction = model.predict(input_data)
```

### 4. Stable Diffusion (AMD)
**Best for**: Image generation, art generation

```bash
# Automatic1111 WebUI with AMD support
git clone https://github.com/AUTOMATIC1111/stable-diffusion-webui
cd stable-diffusion-webui

# Enable AMD (ROCm) support
export COMMANDLINE_ARGS="--precision full --no-half"
./webui.sh
```

**Performance**:
- 5700 XT: ~3-5 seconds per 512x512 image (SD 1.5)
- 5600 XT: ~5-7 seconds per 512x512 image (SD 1.5)

## Deployment Patterns

### Pattern 1: Dedicated AI Inference (Sentry)

```yaml
# llamafile on Sentry 5600 XT
apiVersion: apps/v1
kind: Deployment
metadata:
  name: llamafile-sentry
  namespace: ai-inference
spec:
  replicas: 1
  selector:
    matchLabels:
      app: llamafile
      node: sentry
  template:
    spec:
      nodeName: sentry
      priorityClassName: production-services  # P2 - higher than mining
      containers:
      - name: llamafile
        image: ghcr.io/abbadox/llamafile:latest-rocm
        resources:
          requests:
            amd.com/gpu: 1
            cpu: "2000m"
            memory: "4000Mi"
          limits:
            amd.com/gpu: 1
            cpu: "4000m"
            memory: "8000Mi"
        env:
        - name: GPU_LAYERS
          value: "999"  # Offload all layers to GPU
        - name: HIP_VISIBLE_DEVICES
          value: "0"
```

### Pattern 2: Shared AI Training (Forge AMD GPUs)

```yaml
# PyTorch training job on Forge 5700 XT
apiVersion: batch/v1
kind: Job
metadata:
  name: train-model
  namespace: ai-training
spec:
  template:
    spec:
      priorityClassName: production-services  # P2 - higher than mining
      nodeName: forge
      restartPolicy: OnFailure
      containers:
      - name: trainer
        image: rocm/pytorch:rocm5.7_ubuntu22.04_py3.10
        command: ["python", "train.py"]
        resources:
          limits:
            amd.com/gpu: 1
        env:
        - name: HIP_VISIBLE_DEVICES
          value: "0"  # Use first 5700 XT
        volumeMounts:
        - name: dataset
          mountPath: /data
      volumes:
      - name: dataset
        persistentVolumeClaim:
          claimName: training-dataset
```

### Pattern 3: Multi-GPU AI Workload (Forge 2x 5700 XT)

```yaml
# Distributed training across both Forge AMD GPUs
apiVersion: batch/v1
kind: Job
metadata:
  name: distributed-training
  namespace: ai-training
spec:
  parallelism: 2  # 2 pods, 1 per GPU
  completions: 1
  template:
    spec:
      priorityClassName: production-services
      nodeName: forge
      containers:
      - name: trainer
        image: rocm/pytorch:rocm5.7_ubuntu22.04_py3.10
        command: ["python", "distributed_train.py"]
        resources:
          limits:
            amd.com/gpu: 1
        env:
        - name: WORLD_SIZE
          value: "2"  # 2 GPUs total
        - name: RANK
          valueFrom:
            fieldRef:
              fieldPath: metadata.annotations["pod.rank"]
```

## Resource Management

### AMD GPU Device Plugin Configuration

```yaml
# AMD GPU device plugin
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: amdgpu-device-plugin-daemonset
  namespace: kube-system
spec:
  selector:
    matchLabels:
      app: amdgpu-dp-ds
  template:
    spec:
      nodeSelector:
        gpu: amd  # Only on AMD GPU nodes
      containers:
      - name: amdgpu-dp
        image: rocm/k8s-device-plugin:latest
        resources:
          limits:
            amd.com/gpu: 1  # Request 1 GPU for the plugin itself
```

### PriorityClass Configuration for AI Workloads

```yaml
# production-services (Priority 500000)
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: production-services
value: 500000
globalDefault: false
description: "AI inference, training, monitoring - preempts mining"
```

### Node Selectors for AMD GPUs

```yaml
# Forge AMD GPUs
nodeSelector:
  kubernetes.io/hostname: forge
  gpu.vendor: amd
  gpu.model: 5700-xt

# Sentry AMD GPU
nodeSelector:
  kubernetes.io/hostname: sentry
  gpu.vendor: amd
  gpu.model: 5600-xt
```

## Workload Distribution Strategy

### Sentry 5600 XT (1 GPU - 6 GB VRAM)

**Primary Use**: AI inference (llamafile)
**Secondary**: Mining (when idle)

**Workload Priority**:
1. AI inference (P2) - llamafile, LLM serving
2. Monitoring dashboards (P2)
3. Mining (P3) - lolminer when idle

**Ideal Models**:
- 7B parameter models (quantized to 4-bit)
- Code completion (CodeLlama 7B)
- Text generation (Mistral 7B)

**Avoid**:
- Models > 13B parameters (exceeds 6 GB VRAM)
- Training workloads (better on Forge 5700 XT with 8 GB)

### Forge 5700 XT #1 (1 GPU - 8 GB VRAM)

**Primary Use**: AI training/inference
**Secondary**: Mining (when idle)

**Workload Priority**:
1. AI training (P2) - PyTorch, TensorFlow
2. AI inference (P2) - LLM serving, Stable Diffusion
3. Mining (P3) - lolminer when idle

**Ideal Workloads**:
- Training models up to 7B parameters
- Fine-tuning LLMs (LoRA, QLoRA)
- Image generation (Stable Diffusion)
- Computer vision training

### Forge 5700 XT #2 (1 GPU - 8 GB VRAM)

**Primary Use**: AI training/inference
**Secondary**: Mining (when idle)

**Same as #1**: Can run parallel training jobs or double throughput

## Preemption Behavior

### Scenario 1: AI Training Job Arrives

**Before**:
```
Forge: 5700 XT #1 mining, 5700 XT #2 mining
Sentry: 5600 XT mining
```

**AI training job submitted** (requests 2x AMD GPUs):
```
Priority: P2 (production-services) > P3 (mining)
Action: Preempt 2 AMD miners
```

**After**:
```
Forge: 5700 XT #1 TRAINING, 5700 XT #2 TRAINING
Sentry: 5600 XT mining
```

### Scenario 2: llamafile on Sentry + Training on Forge

**Before**:
```
All 3 AMD GPUs mining
```

**llamafile starts** on Sentry + **training job** on Forge:
```
Priority: P2 (AI workloads) > P3 (mining)
Action: Preempt all 3 AMD miners
```

**After**:
```
Sentry: 5600 XT llamafile (AI inference)
Forge: 5700 XT #1 training, 5700 XT #2 training
Total: 3/3 AMD GPUs for AI workloads
```

### Scenario 3: Mixed AI + Mining

**State**:
```
Sentry: 5600 XT llamafile (P2)
Forge: 5700 XT #1 mining (P3), 5700 XT #2 training (P2)
```

**Result**: 2/3 AMD GPUs for AI, 1/3 AMD GPU for mining
**Automatic balance**: Yunikorn scheduler optimizes based on demand

## Performance Comparison

### AMD vs NVIDIA for AI Workloads

| GPU | VRAM | Training (FP32) | Inference (INT8) | Power | Cost Efficiency |
|-----|------|-----------------|------------------|-------|-----------------|
| **RTX 3090** | 24 GB GDDR6X | 100% (baseline) | 100% (baseline) | 350W | Low |
| **RTX 3060 Ti** | 8 GB GDDR6 | 55% | 60% | 200W | Medium |
| **RX 5700 XT** | 8 GB GDDR6 | 40% | 45% | 225W | **High** |
| **RX 5600 XT** | 6 GB GDDR6 | 25% | 30% | 150W | **Very High** |

**Key Insights**:
- AMD GPUs are 40-60% of NVIDIA performance for AI
- But AMD GPUs are much more cost-efficient for inference
- Perfect for: Development, testing, non-production workloads
- Avoid for: Large-scale training, production inference (use NVIDIA)

## Use Case Recommendations

### Best Use Cases for AMD GPUs

1. **LLM Inference** (llamafile)
   - 7B models quantized (Q4_K_M, Q5_K_M)
   - Code completion (CodeLlama 7B)
   - Chatbots (Mistral 7B, TinyLlama)

2. **Image Generation**
   - Stable Diffusion 1.5/2.1
   - Art generation, image editing
   - Low-res image generation (512x512)

3. **Fine-Tuning**
   - LoRA/QLoRA fine-tuning of LLMs
   - Transfer learning
   - Small dataset training

4. **Development/Testing**
   - Model development before NVIDIA training
   - Experimentation with new architectures
   - CI/CD pipeline testing

### Avoid These Use Cases

1. **Large Model Training**
   - Models > 13B parameters
   - Complex computer vision (ResNet-152+, ViT-Large)
   - Use NVIDIA GPUs instead

2. **Production Inference**
   - Low-latency requirements (<50ms)
   - High-throughput (>100 req/sec)
   - Use NVIDIA GPUs instead

3. **Multi-GPU Training**
   - Distributed training across >2 GPUs
   - Scale: Use NVIDIA GPUs (better ROCm support)

## Monitoring AMD GPU Utilization

### Metrics to Track

```yaml
# AMD GPU metrics (via rocm-smi)
- GPU utilization (%)
- VRAM usage (MB)
- GPU temperature (°C)
- GPU power (W)
- Memory clock (MHz)
- Compute clock (MHz)
```

### Commands

```bash
# Check AMD GPU status
ssh forge "rocm-smi"
ssh sentry "rocm-smi"

# Monitor GPU utilization
watch -n 1 "rocm-smi --showuse --showpower"

# Check VRAM usage
rocm-smi --showmemusage --showvoltage
```

### Grafana Dashboard Queries

```promql
# AMD GPU utilization
rocm_gpu_utilization{gpu_vendor="amd"}

# AMD VRAM usage
rocm_vram_used_bytes{gpu_vendor="amd"} / rocm_vram_total_bytes{gpu_vendor="amd"}

# AMD GPU temperature
rocm_gpu_temperature{gpu_vendor="amd"}
```

## Deployment Examples

### Example 1: LLM Inference Service (Sentry)

```yaml
apiVersion: v1
kind: Service
metadata:
  name: llamafile-sentry
  namespace: ai-inference
spec:
  selector:
    app: llamafile
  ports:
  - port: 8080
    targetPort: 8080
  type: LoadBalancer
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: llamafile-sentry
  namespace: ai-inference
spec:
  replicas: 1
  selector:
    matchLabels:
      app: llamafile
  template:
    spec:
      nodeName: sentry
      priorityClassName: production-services
      containers:
      - name: llamafile
        image: ghcr.io/abbadox/llamafile:latest-rocm
        ports:
        - containerPort: 8080
        resources:
          requests:
            amd.com/gpu: 1
          limits:
            amd.com/gpu: 1
        env:
        - name: MODEL
          value: "/models/mistral-7b-instruct-v0.2.Q4_K_M.gguf"
        - name: GPU_LAYERS
          value: "999"
        - name: PORT
          value: "8080"
```

### Example 2: Stable Diffusion Service (Forge)

```yaml
apiVersion: v1
kind: Service
metadata:
  name: stable-diffusion-forge
  namespace: ai-inference
spec:
  selector:
    app: stable-diffusion
  ports:
  - port: 7860
  type: LoadBalancer
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: stable-diffusion-forge
  namespace: ai-inference
spec:
  replicas: 1
  selector:
    matchLabels:
      app: stable-diffusion
  template:
    spec:
      nodeName: forge
      priorityClassName: production-services
      containers:
      - name: sd-webui
        image: automatic1111/stable-diffusion-webui:rocm
        ports:
        - containerPort: 7860
        resources:
          requests:
            amd.com/gpu: 1
          limits:
            amd.com/gpu: 1
        env:
        - name: COMMANDLINE_ARGS
          value: "--precision full --no-half --listen 0.0.0.0"
        volumeMounts:
        - name: models
          mountPath: /sd-models
      volumes:
      - name: models
        persistentVolumeClaim:
          claimName: sd-models
```

## Benefits for HA Upgrade

### 1. Increased AI Capacity

**Before**:
- 5 NVIDIA GPUs for AI
- 3 AMD GPUs for mining only
- Total AI capacity: 5 GPUs

**After**:
- 5 NVIDIA GPUs for AI
- 3 AMD GPUs for AI (when not mining)
- Total AI capacity: 8 GPUs = **60% increase** ✅

### 2. Better Resource Utilization

**Before**:
```
AMD GPUs: 100% mining (underutilized for AI potential)
AI jobs: Queue on NVIDIA GPUs only
Mining revenue: Lost during AI job execution
```

**After**:
```
AMD GPUs: AI inference/training (priority) → Mining (fallback)
AI jobs: Can use AMD GPUs when NVIDIA busy
Mining revenue: Only lost when AI jobs actually running
```

### 3. Reduced Latency for AI Workloads

**Before**:
- AI jobs wait for NVIDIA GPU availability
- Queue time: 5-30 minutes (if all NVIDIA GPUs busy)

**After**:
- AI jobs can use AMD GPUs immediately
- Queue time: <1 minute (3 additional GPUs available)

### 4. Cost Efficiency

**AMD GPU Cost Efficiency**:
- 5700 XT: 40-60% of 3060 Ti performance at 50% of cost
- 5600 XT: 25-30% of 3060 Ti performance at 30% of cost
- Perfect for: Development, testing, non-production AI workloads

## Implementation Checklist

### Phase 1: Enable AMD GPU Support (Week 1)
- [ ] Install AMD GPU device plugin on Sentry/Forge
- [ ] Verify ROCm drivers loaded (`rocminfo`, `rocm-smi`)
- [ ] Test llamafile with ROCm backend on Sentry
- [ ] Test PyTorch with ROCm on Forge

### Phase 2: Deploy AI Workloads (Week 2)
- [ ] Deploy llamafile on Sentry (5600 XT)
- [ ] Deploy Stable Diffusion on Forge (5700 XT)
- [ ] Test preemption: AI workload preempts mining
- [ ] Verify mining resumes when AI workload completes

### Phase 3: Optimize Performance (Week 3)
- [ ] Benchmark AMD vs NVIDIA for key workloads
- [ ] Tune GPU memory allocation (VRAM limits)
- [ ] Optimize model quantization for AMD GPUs
- [ ] Deploy monitoring dashboards for AMD GPU utilization

### Phase 4: Production Validation (Week 4)
- [ ] Run AI training jobs on Forge AMD GPUs
- [ ] Validate model quality (same as NVIDIA)
- [ ] Measure performance impact on mining revenue
- [ ] Document AMD GPU best practices

## Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| AMD GPU utilization (AI) | >60% | Percentage of time AMD GPUs run AI workloads |
| AMD GPU utilization (mining) | <40% | Percentage of time AMD GPUs mine |
| AI job queue depth | <2 jobs | Pending AI jobs waiting for GPU |
| AMD AI inference latency | <2x NVIDIA | AMD inference time vs NVIDIA (acceptable) |
| Mining revenue impact | <15% drop | Mining hashrate during AI workloads vs baseline |

## Conclusion

**AMD GPUs as AI Workhorses**:
- ✅ 3 AMD GPUs significantly expand AI capacity (60% increase)
- ✅ Perfect for: LLM inference, image generation, fine-tuning
- ✅ Cost-efficient alternative to NVIDIA for development/testing
- ✅ Preemptible architecture: AI > Mining
- ✅ Mining continues when AMD GPUs idle

**This strategy maximizes GPU utilization** across all 8 GPUs (5 NVIDIA + 3 AMD) for both revenue generation (mining/Akash) and AI workloads.

---

**Version**: 1.0
**Created**: 2026-03-21
**Maintainer**: Cluster Operations Team
