# vLLM Deployment Plan for NixOS Cluster

**Date**: 2026-03-25
**Status**: Planning Complete, Ready for Implementation
**Objective**: Deploy vLLM 0.6.3+ with native GGUF support to replace llama.cpp for NVIDIA GPUs

---

## Executive Summary

**Current State**: llama.cpp running as user process on Nexus (single point of failure)
**Target State**: vLLM deployment on Kubernetes with high availability and PagedAttention performance
**Key Advantage**: vLLM 0.6.0+ natively supports GGUF models - no conversion needed!

### Why vLLM?

| Feature | llama.cpp | vLLM |
|---------|-----------|------|
| **Throughput** | Baseline | **2.4× faster** (PagedAttention) |
| **GGUF Support** | Native | Native (v0.6.0+) |
| **GPU Backend** | CUDA, HIP, Vulkan | CUDA only |
| **Kubernetes Integration** | Manual | Production-ready |
| **Multi-GPU Scaling** | Limited | Tensor parallelism |
| **OpenAI API Compatibility** | Partial | Full |

---

## Current Infrastructure Context

### GPU Resources Available for vLLM

| Node | GPUs | Model | Memory | Availability |
|------|------|-------|--------|--------------|
| **Zephyr** | 2× NVIDIA | RTX 3090 (24GB), 3060 Ti (8GB) | 32GB total | ✅ Available (preemptible) |
| **Nexus** | 1× NVIDIA | RTX 3060 Ti (8GB) | 8GB | ✅ Available (preemptible) |
| **Forge** | 2× NVIDIA | RTX 4060 (8GB each) | 16GB total | ❌ Mining (can preempt) |
| **Sentry** | 1× AMD | RX 5600 XT | - | ⚠️ Not supported (vLLM CUDA-only) |

### Existing Models

**Current**: Qwen3.5-0.8B.Q8_0.gguf (868 MB)
- Location: `/home/j_kro/.lmstudio/models/Jackrong/Qwen3.5-0.8B-Claude-4.6-Opus-Reasoning-Distilled-GGUF`
- Works with both llama.cpp and vLLM (GGUF format)
- Quantization: Q8_0 (8-bit quantized)

**Future Considerations**:
- Larger models (Qwen3.5-7B, 14B) for better quality
- Multi-GPU tensor parallelism for 7B+ models

---

## Architecture Design

### Component 1: vLLM Deployment (NVIDIA GPUs)

**Namespace**: `ai-inference`
**Replicas**: 2 (high availability)
**Scheduling**: Node affinity for NVIDIA GPUs

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vllm-qwen
  namespace: ai-inference
  labels:
    app: vllm-qwen
    component: llm-inference
spec:
  replicas: 2
  revisionHistoryLimit: 2
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 0
      maxUnavailable: 1
  selector:
    matchLabels:
      app: vllm-qwen
  template:
    metadata:
      labels:
        app: vllm-qwen
    spec:
      # NVIDIA GPU node affinity
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: nvidia.com/gpu
                operator: Exists
              - key: nvidia.com/gpu.product
                operator: In
                values:
                - RTX_3090
                - RTX_3060_Ti
                - RTX_4060
      # Priority class for preemption
      priorityClassName: inference-high-priority
      containers:
      - name: vllm
        image: vllm/vllm-openai:v0.6.3.post1
        command:
        - python3
        - -m
        - vllm.entrypoints.openai.api_server
        args:
        - --model=/models/Qwen3.5-0.8B-Claude-4.6-Opus-Reasoning-Distilled-GGUF
        - --gpu-memory-utilization=0.9
        - --max-model-len=16384
        - --dtype=half
        - --enable-chunked-prefill
        env:
        - name: CUDA_VISIBLE_DEVICES
          value: "0"
        ports:
        - name: http
          containerPort: 8000
          protocol: TCP
        resources:
          requests:
            cpu: "2"
            memory: "4Gi"
            nvidia.com/gpu: "1"
          limits:
            cpu: "8"
            memory: "8Gi"
            nvidia.com/gpu: "1"
        volumeMounts:
        - name: models
          mountPath: /models
          readOnly: true
        livenessProbe:
          httpGet:
            path: /health
            port: 8000
          initialDelaySeconds: 60
          periodSeconds: 30
        readinessProbe:
          httpGet:
            path: /health
            port: 8000
          initialDelaySeconds: 30
          periodSeconds: 10
      volumes:
      - name: models
        hostPath:
          path: /home/j_kro/.lmstudio/models/Jackrong/Qwen3.5-0.8B-Claude-4.6-Opus-Reasoning-Distilled-GGUF
          type: Directory
```

### Component 2: vLLM Service

```yaml
apiVersion: v1
kind: Service
metadata:
  name: vllm-qwen
  namespace: ai-inference
  labels:
    app: vllm-qwen
spec:
  type: ClusterIP
  ports:
  - port: 8000
    targetPort: 8000
    protocol: TCP
    name: http
  selector:
    app: vllm-qwen
```

### Component 3: AI Gateway Update

**Current Backend**: `http://llama-server.autoresearch.svc.cluster.local:8080`
**New Backend**: `http://vllm-qwen.ai-inference.svc.cluster.local:8000`

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: ai-gateway-config
  namespace: ai-inference
data:
  BACKEND_URL: "http://vllm-qwen.ai-inference.svc.cluster.local:8000"
  BACKEND_TYPE: "vllm"
```

### Component 4: PriorityClass for Preemption

```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: inference-high-priority
value: 1000
globalDefault: false
description: "High priority for AI inference workloads (can preempt mining)"
```

---

## Implementation Steps

### Phase 1: Prerequisites (5 minutes)

```bash
# 1. Verify GPU nodes are ready
kubectl get nodes -L nvidia.com/gpu

# 2. Verify GPU resources available
kubectl describe node zephyr | grep -A 5 "nvidia.com/gpu"
kubectl describe node nexus | grep -A 5 "nvidia.com/gpu"

# 3. Create PriorityClass
kubectl apply -f kubernetes-manifests/ai-inference/vllm/00-priority-class.yaml
```

### Phase 2: Deploy vLLM (10 minutes)

```bash
# 1. Create namespace (if not exists)
kubectl create namespace ai-inference --dry-run=client -o yaml | kubectl apply -f -

# 2. Deploy vLLM
kubectl apply -f kubernetes-manifests/ai-inference/vllm/01-deployment.yaml

# 3. Verify deployment
kubectl get pods -n ai-inference -l app=vllm-qwen
kubectl logs -n ai-inference -l app=vllm-qwen --tail=50
```

### Phase 3: Test vLLM Endpoint (5 minutes)

```bash
# 1. Port-forward for testing
kubectl port-forward -n ai-inference deployment/vllm-qwen 8000:8000

# 2. Test health endpoint
curl http://localhost:8000/health

# 3. Test completion API
curl http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen3.5-0.8B-Claude-4.6-Opus-Reasoning-Distilled-GGUF",
    "messages": [{"role": "user", "content": "Hello!"}],
    "max_tokens": 100
  }'

# 4. Test from cluster (no port-forward)
kubectl run test-vllm --rm -it --image=curlimages/curl -- \
  curl http://vllm-qwen.ai-inference.svc.cluster.local:8000/health
```

### Phase 4: Update AI Gateway (5 minutes)

```bash
# 1. Update ConfigMap
kubectl apply -f kubernetes-manifests/ai-inference/vllm/02-gateway-configmap.yaml

# 2. Restart gateway pods
kubectl rollout restart deployment ai-inference-gateway -n ai-inference

# 3. Verify gateway connectivity
kubectl logs -n ai-inference -l app=ai-inference-gateway --tail=50
```

### Phase 5: Update Autoresearch (5 minutes)

```bash
# 1. Update autoresearch skill config
# File: /etc/nixos/.claude/skills/autoresearch-skills/autoresearch.py
LLAMA_SERVER_URL = os.getenv("LLAMA_SERVER_URL", "http://vllm-qwen.ai-inference.svc.cluster.local:8000")

# 2. Restart autoresearch (if running)
# Autoresearch will pick up new URL on next cycle
```

### Phase 6: Cleanup Old llama.cpp (Optional)

```bash
# Only after vLLM is fully verified working
# 1. Stop llama.cpp user process on Nexus
ssh nexus
pkill -f llama-server

# 2. Remove old service/endpoints
kubectl delete -f kubernetes-manifests/ai-inference/llama-server-service.yaml
```

---

## Rollback Plan

If vLLM deployment fails:

```bash
# 1. Rollback gateway config
kubectl rollout undo deployment ai-inference-gateway -n ai-inference

# 2. Restore llama.cpp
ssh nexus
# Restart llama-server user process

# 3. Delete vLLM deployment
kubectl delete deployment vllm-qwen -n ai-inference
kubectl delete service vllm-qwen -n ai-inference
```

---

## Performance Expectations

### Throughput Comparison

| Metric | llama.cpp | vLLM | Improvement |
|--------|-----------|------|-------------|
| **Tokens/sec** | ~50 t/s | ~120 t/s | 2.4× faster |
| **Time to First Token** | ~800ms | ~400ms | 2× faster |
| **Memory Usage** | ~2GB | ~1.5GB | 25% reduction |
| **Concurrent Requests** | 1 | 8+ | 8× capacity |

### Resource Utilization

**Single GPU (RTX 3060 Ti)**:
- Model: Qwen3.5-0.8B (868 MB)
- vLLM overhead: ~500 MB
- KV cache (16K context): ~6 GB
- **Total**: ~7.4 GB / 8 GB = 92% GPU memory utilization

**Multi-GPU (RTX 3090 + 3060 Ti)**:
- Tensor parallelism across 2 GPUs
- Supports 7B+ models with 16K context
- 2.4× throughput improvement

---

## Monitoring and Observability

### Prometheus Metrics

vLLM exposes Prometheus metrics on port 8000:

```yaml
# ServiceMonitor for Prometheus
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: vllm-qwen
  namespace: ai-inference
spec:
  selector:
    matchLabels:
      app: vllm-qwen
  endpoints:
  - port: http
    path: /metrics
    interval: 15s
```

### Key Metrics

- `vllm:num_requests_running`: Active inference requests
- `vllm:num_requests_waiting`: Queued requests
- `vllm:gpu_cache_usage_perc`: GPU KV cache utilization
- `vllm:time_to_first_token_avg`: Average TTFT latency
- `vllm:time_per_output_token_avg`: Average token generation time

### Grafana Dashboard

Create dashboard: "AI Inference - vLLM Performance"
- Request throughput (tokens/sec)
- Latency percentiles (p50, p95, p99)
- GPU memory utilization
- Request queue depth
- Error rate

---

## Troubleshooting

### Issue 1: Pods stuck in ContainerCreating

**Symptom**: `kubectl get pods -n ai-inference` shows pending status

**Diagnosis**:
```bash
kubectl describe pod vllm-qwen-xxxxx -n ai-inference
```

**Common Causes**:
1. **No GPUs available**: Check mining pods need preemption
   ```bash
   kubectl get pods -n mining
   # Scale down mining if needed
   kubectl scale deployment gpu-miner-forge-nvidia-0 -n mining --replicas=0
   ```

2. **Node affinity not matching**: Verify GPU labels
   ```bash
   kubectl get nodes -L nvidia.com/gpu.product
   ```

### Issue 2: vLLM OOM (Out of Memory)

**Symptom**: Pod crashes with "CUDA out of memory"

**Solution**:
1. Reduce `--max-model-len` (context window size)
2. Reduce `--gpu-memory-utilization` (default 0.9)
3. Use smaller model or quantization
4. Enable `--enable-chunked-prefill` for long inputs

### Issue 3: Slow inference

**Symptom**: High latency, low throughput

**Diagnosis**:
```bash
# Check GPU utilization
kubectl exec -n ai-inference vllm-qwen-xxxxx -- nvidia-smi

# Check vLLM metrics
kubectl exec -n ai-inference vllm-qwen-xxxxx -- curl http://localhost:8000/metrics
```

**Solutions**:
1. Enable `--enable-chunked-prefill` (already in manifest)
2. Increase `--gpu-memory-utilization` to 0.95
3. Use multi-GPU tensor parallelism for 7B+ models
4. Check for GPU contention with mining workloads

### Issue 4: Gateway connection refused

**Symptom**: Gateway logs show "connection refused" to vLLM

**Diagnosis**:
```bash
# Test DNS from gateway pod
kubectl exec -n ai-inference ai-inference-gateway-xxxxx -- \
  nslookup vllm-qwen.ai-inference.svc.cluster.local

# Test connectivity
kubectl exec -n ai-inference ai-inference-gateway-xxxxx -- \
  curl http://vllm-qwen.ai-inference.svc.cluster.local:8000/health
```

**Solutions**:
1. Verify vLLM service exists
2. Check network policies (should allow namespace-local traffic)
3. Verify port 8000 is correct

---

## Future Enhancements

### Phase 2: Multi-GPU Tensor Parallelism

**Target**: Deploy 7B+ models across multiple GPUs

```yaml
# Tensor parallelism across 2 GPUs (Zephyr: RTX 3090 + 3060 Ti)
args:
- --model=/models/Qwen3.5-7B-Instruct-GGUF
- --tensor-parallel-size=2
- --gpu-memory-utilization=0.9
```

### Phase 3: Model Registry Integration

**Target**: MLflow integration for model versioning

```yaml
env:
- name: MODEL_PATH
  value: "/mlflow/models/Qwen3.5-0.8B/Production/1"
volumeMounts:
- name: mlflow-models
  mountPath: /mlflow
```

### Phase 4: AMD GPU Support

**Option A**: SGLang (ROCm support)
**Option B**: llama.cpp with HIP (keep current deployment)

### Phase 5: Autoscaling

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: vllm-qwen-hpa
  namespace: ai-inference
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: vllm-qwen
  minReplicas: 2
  maxReplicas: 4
  metrics:
  - type: Resource
    resource:
      name: nvidia.com/gpu
      target:
        type: Utilization
        averageUtilization: 80
```

---

## File Structure

```
/etc/nixos/
├── docs/
│   └── vllm-deployment-plan.md (this file)
├── kubernetes-manifests/
│   └── ai-inference/
│       └── vllm/
│           ├── 00-priority-class.yaml
│           ├── 01-deployment.yaml
│           ├── 02-service.yaml
│           ├── 03-gateway-configmap.yaml
│           ├── 04-servicemonitor.yaml
│           └── README.md
└── .claude/
    └── skills/
        └── autoresearch-skills/
            └── autoresearch.py (update LLAMA_SERVER_URL)
```

---

## Success Criteria

- ✅ vLLM pods running on 2+ NVIDIA nodes
- ✅ Health endpoint returning 200 OK
- ✅ Completion API returning responses
- ✅ Gateway successfully routing to vLLM
- ✅ Autoresearch using vLLM endpoint
- ✅ Prometheus metrics being scraped
- ✅ Grafana dashboard showing metrics
- ✅ Performance: 2× faster than llama.cpp

---

**Documentation Owner**: j_kro
**Version**: 1.0 | **Created**: 2026-03-25
**Status**: Ready for implementation
