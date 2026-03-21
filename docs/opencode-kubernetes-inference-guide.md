# OpenCode with Kubernetes AI Inference Guide

**Date**: 2026-03-21  
**Status**: ✅ **Configured for Kubernetes Inference (llama.cpp/vLLM/SGLang)**

## Overview

OpenCode is configured to use your **Kubernetes-based AI inference** instead of cloud APIs:

- **Gateway**: AI Inference Gateway (`ai-inference-gateway.ai-inference.svc.cluster.local:8080`)
- **Backends**: llama.cpp, vLLM, or SGLang running in Kubernetes pods
- **Default Model**: Qwen 3.5 4B
- **Disabled**: All cloud providers (OpenAI, Anthropic, Google, Cohere)

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│ Kubernetes Cluster                                              │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │ ai-inference Namespace                                    │ │
│  │                                                            │ │
│  │  ┌──────────────────────────────────────────────────────┐ │ │
│  │  │ AI Inference Gateway (2 replicas)                    │ │ │
│  │  │ Service: ai-inference-gateway:8080                   │ │ │
│  │  │                                                        │ │ │
│  │  │ ┌────────────────────────────────────────────────┐ │ │ │
│  │  │ │ Routes to backend inference engines:           │ │ │ │
│  │  │ │                                                │ │ │ │
│  │  │ │ ┌──────────────┐  ┌──────────────┐              │ │ │ │
│  │  │ │ │ llama.cpp    │  │ vLLM         │              │ │ │ │
│  │  │ │ │ (Qwen 3.5 4B)│  │ (Qwen 3.5 32B)│              │ │ │ │
│  │  │ │ └──────────────┘  └──────────────┘              │ │ │ │
│  │  │ │                                                │ │ │ │
│  │  │ │ ┌──────────────┐                                │ │ │ │
│  │  │ │ │ SGLang        │                                │ │ │ │
│  │  │ │ │ (DeepSeek R1) │                                │ │ │ │
│  │  │ │ └──────────────┘                                │ │ │ │
│  │  │ └────────────────────────────────────────────────┘ │ │ │
│  │  └──────────────────────────────────────────────────────┘ │ │
│  │                                                            │ │
│  │  ┌──────────────────────────────────────────────────────┐ │ │
│  │  │ Support Services                                     │ │ │
│  │  │ • Qdrant (vector DB)                                │ │ │
│  │  │ • Redis (caching)                                   │ │ │
│  │  │ • Prometheus (metrics)                              │ │ │
│  │  └──────────────────────────────────────────────────────┘ │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │ OpenCode Pod (ai-coding namespace)                      │ │
│  │                                                            │ │
│  │  Access via:                                               │ │
│  │  http://ai-inference-gateway.ai-inference.svc.cluster.local:8080/v1 │ │
│  │                                                            │ │
│  │  Uses PVC: ai-coding-configs (unified configs)            │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Configuration

### OpenCode Config

**Location**: `/home/j_kro/.opencode/config.json` (synced via PVC to Kubernetes pods)

```json
{
  "model": "ai-gateway/qwen3.5-4b",
  "provider": {
    "ai-gateway": {
      "options": {
        "baseURL": "http://ai-inference-gateway.ai-inference.svc.cluster.local:8080/v1"
      }
    }
  },
  "enabled_providers": ["ai-gateway", "lmstudio"],
  "disabled_providers": ["openai", "anthropic", "google", "cohere"]
}
```

### AI Gateway Configuration

**ConfigMap**: `ai-gateway-config` in `ai-inference` namespace

```yaml
BACKEND_TYPE: "llama-cpp"  # or "vllm" or "sglang"
BACKEND_URL: "http://llama-cpp-qwen.ai-inference.svc.cluster.local:8080"
DEFAULT_MODEL: "qwen3.5-4b"
```

## Usage

### Start OpenCode with Kubernetes Inference

```bash
# Use default model (Qwen 3.5 4B via AI Gateway)
opencode-k8s

# Explicitly specify model
opencode-k8s -m ai-gateway/qwen3.5-4b

# Run with prompt
opencode-k8s run "Explain this Kubernetes deployment"

# Interactive session
opencode-k8s
```

### Switch Between Backends

```bash
# llama.cpp backend (default)
kubectl configmap -n ai-inference edit ai-gateway-config --from-literal=BACKEND_TYPE=llama-cpp
kubectl rollout restart deployment -n ai-inference ai-inference-gateway

# vLLM backend
kubectl configmap -n ai-inference edit ai-gateway-config --from-literal=BACKEND_TYPE=vllm
kubectl configmap -n ai-inference edit ai-gateway-config --from-literal=BACKEND_URL=http://vllm-inference.ai-inference.svc.cluster.local:8000
kubectl rollout restart deployment -n ai-inference ai-inference-gateway

# SGLang backend
kubectl configmap -n ai-inference edit ai-gateway-config --from-literal=BACKEND_TYPE=sglang
kubectl configmap -n ai-inference edit ai-gateway-config --from-literal=BACKEND_URL=http://sglang-inference.ai-inference.svc.cluster.local:8000
kubectl rollout restart deployment -n ai-inference ai-inference-gateway
```

## Available Models

### By Backend

**llama.cpp**:
- `ai-gateway/qwen3.5-4b` - Qwen 3.5 4B (default)
- `ai-gateway/qwen3.5-32b` - Qwen 3.5 32B (if configured)

**vLLM**:
- `ai-gateway/qwen3.5-32b` - Qwen 3.5 32B (vLLM optimized)
- Faster inference with PagedAttention

**SGLang**:
- `ai-gateway/deepseek-r1` - DeepSeek R1 reasoning model
- Speculative decoding for faster generation

### Test Different Models

```bash
# Qwen 3.5 4B (llama.cpp)
opencode-k8s -m ai-gateway/qwen3.5-4b run "Hello"

# Qwen 3.5 32B (vLLM)
opencode-k8s -m ai-gateway/qwen3.5-32b run "Explain this code"

# DeepSeek R1 (SGLang)
opencode-k8s -m ai-gateway/deepseek-r1 run "Analyze this architecture"
```

## Deployment Scaling

### Scale AI Gateway

```bash
# Scale up for more concurrent requests
kubectl scale deployment -n ai-inference ai-inference-gateway --replicas=4

# Check resource usage
kubectl top pod -n ai-inference -l app=ai-inference-gateway
```

### Scale Backend Inference

```bash
# Scale llama.cpp backend
kubectl scale deployment -n ai-inference llama-cpp-qwen --replicas=2

# Scale vLLM backend
kubectl scale deployment -n ai-inference vllm-qwen3.5 --replicas=1

# Scale SGLang backend
kubectl scale deployment -n ai-inference sglang-inference --replicas=1
```

## Monitoring

### Check Gateway Status

```bash
# Health check
curl http://ai-inference-gateway.ai-inference.svc.cluster.local:8080/health

# Metrics (Prometheus)
curl http://ai-inference-gateway.ai-inference.svc.cluster.local:9190/metrics

# View logs
kubectl logs -n ai-inference -l app=ai-inference-gateway -f
```

### Check Backend Status

```bash
# llama.cpp pods
kubectl get pods -n ai-inference -l app=llama-cpp-qwen

# vLLM pods  
kubectl get pods -n ai-inference -l app=vllm-qwen3.5

# SGLang pods
kubectl get pods -n ai-inference -l app=sglang-inference
```

### Performance Metrics

```bash
# Throughput (tokens/sec)
kubectl exec -n ai-inference deployment/ai-inference-gateway -- curl -s localhost:9190/metrics | grep throughput

# Request latency
kubectl exec -n ai-inference deployment/ai-inference-gateway -- curl -s localhost:9190/metrics | grep latency

# Queue depth
kubectl exec -n ai-inference deployment/ai-inference-gateway -- curl -s localhost:9190/metrics | grep queue
```

## Troubleshooting

### Issue: "Connection refused" to AI Gateway

**Check 1**: Verify pods are running

```bash
kubectl get pods -n ai-inference -l app=ai-inference-gateway
```

**Check 2**: Verify service exists

```bash
kubectl get svc -n ai-inference ai-inference-gateway
```

**Check 3**: Test from within cluster

```bash
kubectl run -n ai-inference --rm -i --restart=Never --image=curlimages/curl:latest -- \
  curl -s http://ai-inference-gateway:8080/health
```

### Issue: "Model not found"

**Solution**: Check available models via gateway

```bash
# List models
curl http://ai-inference-gateway.ai-inference.svc.cluster.local:8080/v1/models | jq '.data[].id'

# Verify backend is configured correctly
kubectl get configmap -n ai-inference ai-gateway-config -o yaml
```

### Issue: Slow inference

**Check 1**: Backend pod resources

```bash
kubectl top pod -n ai-inference -l app=llama-cpp-qwen
```

**Check 2**: GPU allocation

```bash
kubectl describe pod -n ai-inference <llama-pod> | grep -A20 "Allocated resources"
```

**Solution**: Scale gateway or backend

```bash
kubectl scale deployment -n ai-inference ai-inference-gateway --replicas=4
```

### Issue: OpenCode using cloud API instead

**Verify config**

```bash
# Check OpenCode config in pod
kubectl exec -n ai-coding opencode-XXX -- cat /home/j_kro/.opencode/config.json | jq '.disabled_providers'

# Should show: ["openai", "anthropic", "google", "cohere"]
```

**Test with explicit model**

```bash
opencode-k8s -m ai-gateway/qwen3.5-4b run "Test local model"
```

## Advanced Configuration

### Multiple Model Endpoints

Configure different backends for different model sizes:

```json
{
  "provider": {
    "ai-gateway-4b": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "AI Gateway (4B models)",
      "options": {
        "baseURL": "http://ai-inference-gateway-4b.ai-inference.svc.cluster.local:8080/v1"
      }
    },
    "ai-gateway-32b": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "AI Gateway (32B models)",
      "options": {
        "baseURL": "http://ai-inference-gateway-32b.ai-inference.svc.cluster.local:8080/v1"
      }
    },
    "ai-gateway-reasoning": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "AI Gateway (Reasoning models)",
      "options": {
        "baseURL": "http://ai-inference-gateway-reasoning.ai-inference.svc.cluster.local:8080/v1"
      }
    }
  }
}
```

### Model Routing Strategy

**For quick tasks** (autocomplete, titles):
- `ai-gateway/qwen3.5-4b` (fast, low latency)

**For coding tasks**:
- `ai-gateway/qwen3.5-32b` via vLLM (faster inference)

**For reasoning**:
- `ai-gateway/deepseek-r1` via SGLang (speculative decoding)

**For general purpose**:
- `ai-gateway/qwen3.5-4b` (balanced)

## Performance Optimization

### Resource Allocation

**AI Gateway Pods**:
- CPU: 500m - 2000m
- Memory: 512Mi - 2Gi
- Replicas: 2 (can scale to 4)

**Backend Pods** (llama.cpp/vLLM/SGLang):
- GPU: 1x RTX 3090 per pod
- Memory: 16-32Gi per pod
- Replicas: 1 (scale based on load)

### Autoscaling

```bash
# Horizontal Pod Autoscaler for AI Gateway
kubectl get hpa -n ai-inference

# Manual scaling
kubectl scale deployment -n ai-inference ai-inference-gateway --replicas=4
```

### Load Balancing

AI Gateway uses Kubernetes service for load balancing:
- Round-robin distribution across gateway pods
- Each gateway pod routes to backend inference pods
- Backend pods can be scaled independently

## Integration with Cluster Services

### Knowledge Fabric (RAG)

The AI Gateway has RAG (Retrieval-Augmented Generation) enabled:

```yaml
RAG_ENABLED: "true"
RAG_TOP_K: "5"
QDRANT_URL: "http://qdrant:6333"
```

This means OpenCode can:
- Search codebase for context
- Retrieve relevant documentation
- Provide informed responses

### Web Search

```yaml
MIDDLEWARE__KNOWLEDGE_FABRIC__SEARXNG_ENABLED: "true"
MIDDLEWARE__KNOWLEDGE_FABRIC__SEARXNG_URL: "http://searxng:7777"
```

OpenCode can search the web for additional context when needed.

## Best Practices

### 1. Always Use Kubernetes Services

```bash
# Good - uses Kubernetes service discovery
opencode-k8s -m ai-gateway/qwen3.5-4b

# Risky - direct pod IP might change
opencode-k8s -m ai-gateway/qwen3.5-4b --baseURL=http://10.0.0.200:8080
```

### 2. Monitor Resource Usage

```bash
# Check gateway resource usage
kubectl top pod -n ai-inference -l app=ai-inference-gateway

# Check backend GPU usage
kubectl exec -n ai-inference llama-cpp-XXX -- nvidia-smi
```

### 3. Use Appropriate Models

**Quick queries** (< 100 tokens):
- Qwen 3.5 4B (llama.cpp)

**Code generation**:
- Qwen 3.5 32B (vLLM) for faster inference

**Complex reasoning**:
- DeepSeek R1 (SGLang) with thinking mode

### 4. Scale Based on Load

```bash
# Monitor queue depth
kubectl exec -n ai-inference ai-inference-gateway-XXX -- curl -s localhost:9190/metrics | grep queue

# Scale if queue depth > 5
kubectl scale deployment -n ai-inference ai-inference-gateway --replicas=4
```

## Comparison: Cloud vs Kubernetes

| Feature | Cloud API | Kubernetes Inference |
|---------|-----------|---------------------|
| **Latency** | 300-500ms | 50-100ms |
| **Cost** | $0.002-0.01/1K tokens | Free (hardware cost only) |
| **Privacy** | Data leaves cluster | Data stays in cluster |
| **Reliability** | Depends on internet | Depends on cluster |
| **Scalability** | Auto-scales | Manual scaling |
| **Model Control** | Limited to available APIs | Any open-source model |
| **Customization** | Limited | Full control |

## Summary

✅ **Configured**: OpenCode uses Kubernetes AI Gateway (llama.cpp/vLLM/SGLang)  
✅ **Default Model**: Qwen 3.5 4B via llama.cpp  
✅ **Cluster Internal**: All traffic stays within Kubernetes cluster  
✅ **Scalable**: Gateway (2-4 replicas) + Backend (1-2 replicas per GPU)  
✅ **Cost Effective**: No per-token costs, hardware already owned  
✅ **Private**: No data leaves cluster  
✅ **Flexible**: Switch between llama.cpp, vLLM, SGLang easily  

**Key Endpoints**:
- AI Gateway: `http://ai-inference-gateway.ai-inference.svc.cluster.local:8080`
- Models: `ai-gateway/qwen3.5-4b`, `ai-gateway/qwen3.5-32b`, `ai-gateway/deepseek-r1`
- Health: `http://ai-inference-gateway.ai-inference.svc.cluster.local:8080/health`
- Metrics: `http://ai-inference-gateway.ai-inference.svc.cluster.local:9190/metrics`
