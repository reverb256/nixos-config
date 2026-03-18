# Kubernetes GPU Inference Migration - Implementation Summary

**Date:** 2026-03-18
**Status:** Phase 1 Complete, Phase 2 In Progress

## Executive Summary

Successfully implemented core Kubernetes GPU infrastructure for multi-GPU AI inference. The system now has:
- ✅ NVIDIA GPU device plugin deployed (Zephyr: 2 GPUs exposed)
- ✅ llama.cpp optimized for Qwen3.5 (systemd, ready for K8s migration)
- ✅ K8s manifests created for vLLM, sglang, AI Gateway
- ✅ Observability stack configured (Prometheus, Grafana)
- ✅ Priority classes for workload scheduling
- ⏳ Network issues on Forge/Nexus (Flannel CNI)
- ⏳ Container image registry needed for custom builds

## Completed Tasks

### 1. llama.cpp Optimization ✅

**Changes Applied:**
```bash
# From /etc/nixos/modules/services/llamafile.nix
ctxSize: 32768 (Qwen3.5 supports up to 262K)
threads: 12 (better utilization)
batchSize: 64 (lower latency)
ubatchSize: 16 (optimal micro-batch)
flashAttention: true
parallelDecoding: 3
enableThinking: true (chain-of-thought)
cacheTypeK: q8_0 (8-bit quantization)
cacheTypeV: q4_0 (4-bit quantization)
```

**Performance:** Service running with all optimizations active
- Command line: `--flash-attn on --parallel 3 --chat-template-kwargs '{"enable_thinking":true}' --cache-type-k q8_0 --cache-type-v q4_0`

### 2. Kubernetes GPU Infrastructure ✅

**NVIDIA Device Plugin:**
```yaml
# Deployed: /etc/nixos/kubernetes-manifests/nvidia-device-plugin-daemonset.yaml
Status: Running on Zephyr (2 GPUs detected)
Node Labels:
  - zephyr: nvidia.com/gpu=2
  - forge: nvidia.com/gpu=0 (network issue)
  - nexus: nvidia.com/gpu=0 (network issue)
```

**Cluster GPU Inventory:**
| Node | GPUs | VRAM | K8s Status |
|------|------|------|------------|
| Zephyr | RTX 3090 + 3060 Ti | 32GB | ✅ 2 GPUs exposed |
| Forge | 2x RTX 4060 | 16GB | ⚠️ Network issue |
| Nexus | RTX 3060 Ti | 8GB | ⚠️ Network issue |

### 3. Kubernetes Manifests Created ✅

**Location:** `/etc/nixos/kubernetes-manifests/ai-inference/`

| File | Purpose | Status |
|------|---------|--------|
| `priority-classes.yaml` | GPU workload scheduling | ✅ Created |
| `vllm-deployment.yaml` | vLLM multi-GPU inference | ✅ Created (image fix needed) |
| `sglang-deployment.yaml` | sglang multi-GPU inference | ✅ Created |
| `gateway-deployment.yaml` | AI Gateway multi-backend router | ✅ Created |
| `gateway-deployment-simple.yaml` | Simplified gateway (host networking) | ✅ Created |
| `redis-deployment.yaml` | Redis cache/queue | ✅ Created |
| `qdrant-deployment.yaml` | Vector database for RAG | ✅ Created |
| `observability.yaml` | Prometheus + Grafana | ✅ Created |

### 4. Architecture Design ✅

```
┌─────────────────────────────────────────────────────────────┐
│                     Service Mesh (Future)                   │
│                    (Istio - mTLS, Circuit Breaker)          │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                   AI Gateway (3 replicas)                   │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Smart Routing:                                     │   │
│  │  - Simple queries → llama.cpp (fastest)             │   │
│  │  - Complex queries → vLLM (quality)                  │   │
│  │  - Multi-node → sglang (scale)                      │   │
│  │  - Fallback → ZAI API (graceful degradation)       │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                              ↓
        ┌─────────────────┬──────────────┬──────────────┐
        ↓                 ↓              ↓              ↓
   llama.cpp          vLLM          sglang       ZAI API
   (Zephyr)          (Zephyr)       (Zephyr)     (External)
   systemd          K8s Pods      K8s Pods     HTTP
   port 8083        port 8000      port 8000     API
```

## Known Issues and Next Steps

### Issue 1: Container Images
**Problem:** vLLM/sglang images don't exist in expected tags
**Solution:** Build custom images or use different tags
**Priority:** Medium

### Issue 2: Network (Flannel CNI)
**Problem:** Forge and Nexus have Flannel CNI conflicts
**Error:** `cni0 already has an IP address different from 10.244.x.1/24`
**Solution:** Restart Flannel on affected nodes or switch to Cilium
**Priority:** High

### Issue 3: Gateway Container
**Problem:** Containerized gateway needs NixOS Python environment
**Solution:** Use host networking or build custom image with Nix
**Priority:** Medium (systemd gateway works as fallback)

## Immediate Actions

### 1. Fix Flannel Networking
```bash
# On Forge and Nexus:
sudo systemctl restart kube-flannel
# Or use Cilium instead
kubectl apply -f https://raw.githubusercontent.com/cilium/cilium/v1.15.0/install.yaml
```

### 2. Build Custom Images
```bash
# Use NixOS to build container images
nix-build '<nixos>{ dockerTools, pkgs.python3, ... }'

# Or use alternative approach with hostPath mounts
```

### 3. Test Current Setup
```bash
# Test llama.cpp backend
curl http://10.1.1.110:8083/v1/models

# Test AI Gateway (systemd)
curl http://10.1.1.110:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"gguf","messages":[{"role":"user","content":"Say hi"}],"max_tokens":10}'
```

## Performance Targets

| Configuration | Expected Speed |
|---------------|---------------|
| Current (llama.cpp 4B, 2 GPUs) | 86 t/s |
| vLLM (4B, 2 GPUs) | ~100 t/s |
| vLLM (35B, 4 GPUs across nodes) | ~70 t/s |
| sglang (4B, 2 GPUs) | ~90 t/s |
| sglang (35B, 5 GPUs) | ~100+ t/s |

## Files Created/Modified

### NixOS Configuration
- `/etc/nixos/modules/services/llamafile.nix` - Added Qwen3.5 optimization options
- `/etc/nixos/hosts/zephyr/configuration.nix` - Enabled optimizations

### Kubernetes Manifests
- `/etc/nixos/kubernetes-manifests/ai-inference/priority-classes.yaml`
- `/etc/nixos/kubernetes-manifests/ai-inference/vllm-deployment.yaml`
- `/etc/nixos/kubernetes-manifests/ai-inference/sglang-deployment.yaml`
- `/etc/nixos/kubernetes-manifests/ai-inference/gateway-deployment.yaml`
- `/etc/nixos/kubernetes-manifests/ai-inference/gateway-deployment-simple.yaml`
- `/etc/nixos/kubernetes-manifests/ai-inference/redis-deployment.yaml`
- `/etc/nixos/kubernetes-manifests/ai-inference/qdrant-deployment.yaml`
- `/etc/nixos/kubernetes-manifests/ai-inference/observability.yaml`

### Documentation
- `/etc/nixos/docs/KUBERNETES_GPU_INFERENCE_STRATEGY.md` - Complete architecture plan

## Testing Graceful Degradation

### Test 1: llama.cpp Backend Health
```bash
curl http://10.1.1.110:8083/health
curl http://10.1.1.110:8083/v1/models
```

### Test 2: AI Gateway Routing
```bash
# Test with different models
curl http://10.1.1.110:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen3.5-4b","messages":[{"role":"user","content":"Hello"}]}'
```

### Test 3: GPU Resource Availability
```bash
kubectl describe node zephyr | grep -A5 "Allocated resources"
kubectl top pods -n ai-inference
```

### Test 4: Failover to ZAI API
```bash
# Stop llama.cpp and verify fallback
sudo systemctl stop llamafile.service
curl http://10.1.1.110:8080/v1/chat/completions ...
sudo systemctl start llamafile.service
```

## Rollback Plan

If issues arise:
1. **Immediate:** `kubectl delete -f /etc/nixos/kubernetes-manifests/ai-inference/`
2. **Gateway:** Systemd gateway continues working on port 8080
3. **Inference:** llama.cpp on port 8083 unaffected
4. **Monitoring:** Remove via `nixos-rebuild switch` to previous generation

## Success Criteria

- [x] llama.cpp optimized and running
- [x] NVIDIA device plugin deployed
- [x] GPU nodes labeled in Kubernetes
- [x] K8s manifests created for all services
- [x] Observability stack configured
- [ ] Container images built/available
- [ ] All pods running successfully
- [ ] Multi-backend routing functional
- [ ] Graceful degradation tested
- [ ] Performance benchmarks met

## Next Session Priorities

1. **Fix Flannel CNI** on Forge/Nexus (blocker for multi-node)
2. **Build container images** for vLLM/sglang
3. **Deploy Istio service mesh** for mTLS and circuit breaking
4. **Complete gateway containerization**
5. **End-to-end testing** of graceful degradation
6. **Performance benchmarking** across backends

## References

- llama.cpp: https://github.com/ggerganov/llama.cpp
- vLLM: https://docs.vllm.ai/
- sglang: https://lmsys.org/blog/2024-01-17-sglang/
- Qwen3.5: https://huggingface.co/Qwen/Qwen3.5-4B
- NVIDIA K8s Device Plugin: https://github.com/NVIDIA/k8s-device-plugin
