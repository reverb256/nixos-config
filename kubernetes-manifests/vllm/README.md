# vLLM Qwen3.5 Kubernetes Deployment

## Overview
Deploys vLLM (high-throughput LLM inference engine) with Qwen2.5-7B-Instruct model on Kubernetes GPU nodes.

## Architecture
- **Model**: Qwen/Qwen2.5-7B-Instruct
- **GPU**: 1x NVIDIA RTX 3090 on Zephyr (24GB VRAM)
- **Storage**: 50Gi PVC on fast-local-ssd (Zephyr local storage)
- **Memory**: 8Gi shared memory for tensor parallel inference
- **Service**: OpenAI-compatible API on port 8000

## Components
- **Deployment**: Single replica with GPU resource requests
- **Service**: ClusterIP for internal cluster access
- **PVC**: Model cache storage on fast-local-ssd
- **Secret**: Optional HuggingFace token for private models

## GPU Scheduling
Uses node affinity to schedule on Zephyr with RTX 3090:
```yaml
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
        - matchExpressions:
            - key: nvidia.com/gpu.product
              operator: In
              values:
                - RTX3090
```

## Resource Limits
- **CPU**: 8 cores limit, 2 cores request
- **Memory**: 16Gi limit, 8Gi request
- **GPU**: 1x NVIDIA GPU (RTX 3090 preferred)

## Deployment Steps

### 1. Create Storage
```bash
kubectl apply -f kubernetes-manifests/vllm/01-pvc.yaml
```

### 2. Deploy vLLM
```bash
kubectl apply -f kubernetes-manifests/vllm/02-deployment.yaml
kubectl apply -f kubernetes-manifests/vllm/03-service.yaml
```

### 3. Verify Deployment
```bash
# Check pod status
kubectl get pods -n ai-inference -l app=vllm-qwen3.5

# View logs (model download takes time)
kubectl logs -n ai-inference deployment/vllm-qwen3.5 -f

# Port-forward for testing
kubectl port-forward -n ai-inference deployment/vllm-qwen3.5 8000:8000
```

### 4. Test Inference
```bash
# Health check
curl http://localhost:8000/health

# List models
curl http://localhost:8000/v1/models

# Generate completion
curl http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen/Qwen2.5-7B-Instruct",
    "messages": [{"role": "user", "content": "Hello!"}],
    "max_tokens": 100
  }'
```

## Integration with AI Gateway
Update AI Inference Gateway to use vLLM:
```bash
# Old: Local llama.cpp
VLLM_URL = "http://127.0.0.1:8080"

# New: Kubernetes vLLM service
VLLM_URL = "http://vllm-qwen3.5.ai-inference.svc.cluster.local:8000"
```

## Monitoring
- **Metrics**: vLLM exposes Prometheus metrics on `/metrics`
- **Logs**: `kubectl logs -n ai-inference deployment/vllm-qwen3.5`
- **GPU Usage**: `kubectl exec -n ai-inference deployment/vllm-qwen3.5 -- nvidia-smi`

## Troubleshooting

### Pod CrashLoopBackOff
- Check GPU availability: `kubectl describe node zephyr | grep nvidia.com/gpu`
- Verify PVC is bound: `kubectl get pvc -n ai-inference vllm-model-cache`
- Review logs: `kubectl logs -n ai-inference deployment/vllm-qwen3.5`

### OOMKilled
- Reduce `max-model-len` or `gpu-memory-utilization`
- Increase memory limits in deployment

### Slow Startup
- Model download from HuggingFace takes time (5-10 minutes on first run)
- Check startup probe timeout: `initialDelaySeconds: 30, failureThreshold: 30`
- Total startup grace period: ~5 minutes (30s * 10 attempts)

## Performance Tuning

### For RTX 3090 (24GB):
```bash
--max-model-len 4096        # Context window
--gpu-memory-utilization 0.9  # Use 90% of GPU memory
--max-num-batched-tokens 2048  # Batch size
```

### For RTX 4060 (8GB) - Forge:
Reduce memory usage:
```bash
--max-model-len 2048
--gpu-memory-utilization 0.8
--max-num-batched-tokens 1024
```

### Multi-GPU (Tensor Parallel):
For models requiring 2+ GPUs:
```bash
--tensor-parallel-size 2
--max-model-len 8192
```

## References
- vLLM Docs: https://docs.vllm.ai/
- Qwen Models: https://huggingface.co/Qwen
- Kubernetes GPU Scheduling: https://kubernetes.io/docs/tasks/manage-gpus/
