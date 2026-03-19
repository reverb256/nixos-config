# llama.cpp Qwen3.5 Kubernetes Deployment

## Overview
Deploys llama.cpp (commit b8419) with Qwen3.5-2B-Instruct model on Kubernetes GPU nodes with Flash Attention and bf16 KV cache optimization.

## Architecture
- **Model**: Qwen3.5-2B-IQ4_NL.gguf (quantized 2B parameter model)
- **GPU**: 1x NVIDIA RTX 3090 on Zephyr (24GB VRAM)
- **Storage**: HostPath PV from /home/j_kro/.lmstudio/models
- **Memory**: 4Gi shared memory for performance
- **Service**: OpenAI-compatible API on port 8080
- **Metrics**: Prometheus metrics on port 9090

## Key Features
- **Flash Attention**: Enabled for faster inference
- **bf16 KV Cache**: Brain float 16 for reduced memory usage
- **NGPL 999**: Maximum GPU layers offloaded to GPU
- **Context Window**: 16384 tokens
- **OpenAI-Compatible**: Drop-in replacement for OpenAI API
- **Quantization**: IQ4_NL (4-bit quantization for efficiency)

## Deployment Steps

### 1. Create Storage
```bash
kubectl apply -f kubernetes-manifests/llama-cpp/01-pvc.yaml
```

### 2. Build llama.cpp Image (on Zephyr)
```bash
# Build the llama.cpp image from NixOS
ssh zephyr
cd /etc/nixos
nix-build -A llama-cpp -K

# Load into containerd (if using docker)
# docker load < result

# For Kubernetes, we'll use the NixOS-built binary directly
# See deployment manifest for image configuration
```

### 3. Deploy llama.cpp
```bash
kubectl apply -f kubernetes-manifests/llama-cpp/02-deployment.yaml
kubectl apply -f kubernetes-manifests/llama-cpp/03-service.yaml
```

### 4. Verify Deployment
```bash
# Check pod status
kubectl get pods -n ai-inference -l app=llama-cpp-qwen

# View logs
kubectl logs -n ai-inference deployment/llama-cpp-qwen -f

# Port-forward for testing
kubectl port-forward -n ai-inference deployment/llama-cpp-qwen 8080:8080
```

### 5. Test Inference
```bash
# Health check
curl http://localhost:8080/health

# List models (OpenAI-compatible)
curl http://localhost:8080/v1/models

# Generate completion
curl http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen",
    "messages": [{"role": "user", "content": "Hello!"}],
    "max_tokens": 100
  }'
```

## Model Configuration

### Qwen3.5-2B-IQ4_NL
- **Parameters**: 2B (quantized to 4-bit)
- **VRAM Usage**: ~2GB (with NGL 999)
- **Context Length**: 16384 tokens
- **Flash Attention**: Enabled
- **KV Cache Type**: bf16 (reduced memory)

### Alternative Models Available
```
/models/unsloth/Qwen3.5-0.8B-GGUF/  # Smallest, fastest
/models/unsloth/Qwen3.5-2B-GGUF/   # Balanced
/models/unsloth/Qwen3.5-4B-GGUF/   # More capable
/models/unsloth/Qwen3.5-9B-GGUF/   # High quality
/models/unsloth/Qwen3.5-27B-GGUF/  # Largest (may need 2x GPUs)
```

To change model, update the deployment manifest:
```yaml
args:
  - "--model"
  - "/models/unsloth/Qwen3.5-4B-GGUF/Qwen3.5-4B-IQ4_NL.gguf"
```

## Resource Optimization

### For RTX 3090 (24GB):
```yaml
# Current config (2B model)
--ctx-size 16384
--ngl 999
--batch-size 512

# For 4B model:
--ctx-size 8192
--ngl 999
--batch-size 256
```

### For RTX 4060 (8GB):
```yaml
# Reduce context and batch size
--ctx-size 4096
--ngl 999
--batch-size 128
```

## Integration with AI Gateway
Update AI Inference Gateway to use llama.cpp:
```bash
# Old: Local llama.cpp
LLAMA_CPP_URL = "http://127.0.0.1:8083"

# New: Kubernetes llama.cpp service
LLAMA_CPP_URL = "http://llama-cpp-qwen.ai-inference.svc.cluster.local:8080"
```

## Monitoring

### Metrics Endpoint
```bash
# llama.cpp exposes Prometheus metrics on port 9090
kubectl port-forward -n ai-inference deployment/llama-cpp-qwen 9090:9090
curl http://localhost:9090/metrics
```

### GPU Usage
```bash
# Check GPU utilization
kubectl exec -n ai-inference deployment/llama-cpp-qwen -- nvidia-smi

# View llama.cpp KV cache stats
kubectl logs -n ai-inference deployment/llama-cpp-qwen | grep "kv cache"
```

### Performance Metrics
- **Tokens/second**: Check logs for generation speed
- **KV Cache Usage**: bf16 KV cache reduces memory by ~50%
- **GPU Utilization**: Should be 80-95% during inference
- **Memory Usage**: ~2-3GB for 2B model with NGL 999

## Troubleshooting

### Pod CrashLoopBackOff
- Check GPU availability: `kubectl describe node zephyr | grep nvidia.com/gpu`
- Verify model path: `kubectl exec -it <pod> -- ls -la /models/`
- Review logs: `kubectl logs -n ai-inference deployment/llama-cpp-qwen`

### Model Loading Errors
- Verify GGUF file exists
- Check file permissions on hostPath
- Ensure model path is correct in deployment

### Out of Memory
- Reduce `--ctx-size` or `--batch-size`
- Use smaller model (0.8B or 2B instead of 4B)
- Decrease `--ngl` (GPU layers) to offload less to GPU

### Slow Inference
- Increase `--threads` (up to CPU count)
- Enable `--flash-attn` (already enabled)
- Check GPU utilization with nvidia-smi
- Reduce context size for faster prompt processing

## Performance Tuning

### For Speed (Latency):
```yaml
--ctx-size 4096      # Smaller context
--batch-size 128     # Smaller batches
--threads 8          # More threads
--flash-attn on      # Flash attention
```

### For Throughput:
```yaml
--ctx-size 16384     # Larger context
--batch-size 512     # Larger batches
--ubatch-size 512    # Micro-batch size
--threads 4          # Fewer threads
```

### For Memory Efficiency:
```yaml
--cache-type-k bf16  # bf16 KV cache (already enabled)
--cache-type-v bf16
--ngl 999           # Max GPU offloading
```

## Comparison: llama.cpp vs vLLM

| Feature | llama.cpp | vLLM |
|---------|-----------|------|
| Memory Usage | ~2GB (2B model) | ~8GB (7B model) |
| Flash Attention | ✅ Native support | ⚠️ Experimental |
| Quantization | ✅ GGUF (4-bit) | ❌ No quantization |
| bf16 KV Cache | ✅ Working | ⚠️ CUDA issues |
| Model Support | Wide range | Transformer-only |
| GPU Requirements | 8GB+ VRAM | 16GB+ VRAM |
| Production Ready | ✅ Stable | ⚠️ Version compatibility |

## References
- llama.cpp: https://github.com/ggerganov/llama.cpp
- Qwen Models: https://huggingface.co/Qwen
- GGUF Models: https://huggingface.co/models?search=gguf
- Kubernetes GPU Scheduling: https://kubernetes.io/docs/tasks/manage-gpus/
