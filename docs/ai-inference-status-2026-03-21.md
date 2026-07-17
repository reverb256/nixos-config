# AI Inference Gateway - Migration Status Update
**Date**: 2026-03-21
**Status**: ✅ Gateway accessible, DNS issue identified

## What We Accomplished

### ✅ Completed
1. **Fixed Gateway Backend URL**
   - Changed from `http://127.0.0.1:8083` to `http://llama-cpp-qwen.ai-inference.svc.cluster.local:8080`
   - Updated Kubernetes ConfigMap

2. **Fixed LimitRange GPU Issue**
   - Added explicit `nvidia.com/gpu: "0"` to gateway deployment
   - Pods can now be created without hitting GPU quota

3. **Made Gateway Accessible from Kubernetes**
   - Changed NixOS gateway host from `127.0.0.1` to `0.0.0.0`
   - Rebuilt Zephyr with new configuration
   - Gateway now listens on all interfaces

4. **Created ExternalService**
   - `ai-inference-gateway-external` service points to NixOS systemd gateway
   - Endpoint: `10.1.1.110:8080` (Zephyr's IP)

5. **Verified Gateway Health**
   ```json
   {
     "status": "healthy",
     "gateway": {"version": "2.0.0", "host": "0.0.0.0", "port": 8080},
     "backend": {"url": "http://127.0.0.1:8083", "type": "llama-cpp", "healthy": true},
     "qdrant": {"healthy": true, "url": "http://127.0.0.1:6333"},
     "redis": {"healthy": true, "url": "redis://localhost:6380"}
   }
   ```

### ⚠️ Known Issues

1. **DNS Resolution Across Namespaces**
   - **Issue**: Pods in `ai-coding` namespace can't resolve services in `ai-inference` namespace
   - **Error**: `Could not resolve host: ai-inference-gateway-external.ai-inference.svc.cluster.local`
   - **Workaround**: Use direct IP (`10.1.1.110:8080`) instead of service DNS
   - **Root Cause**: Needs investigation (CoreDNS, network policies, or service discovery)

2. **Container Image Not Available**
   - **Issue**: `ghcr.io/j-kro/ai-inference-gateway:latest` returns 403 Forbidden
   - **Impact**: Can't run gateway as pure Kubernetes deployment
   - **Current Solution**: Using NixOS systemd service with ExternalService
   - **Future Solution**: Build and push container image

3. **LimitRange Still Has GPU Defaults**
   - **Issue**: LimitRange still auto-assigns GPUs to all pods
   - **Workaround**: Explicitly set `nvidia.com/gpu: "0"` in deployments
   - **Needs**: Fix LimitRange to remove GPU from `default` and `defaultRequest`

## Current Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Kubernetes Cluster                                           │
│                                                              │
│  ┌─────────────────┐    ┌──────────────────────────────┐  │
│  │ ai-coding       │    │ ai-inference                 │  │
│  │ Namespace       │    │ Namespace                   │  │
│  │                 │    │                              │  │
│  │ ┌─────────────┐ │    │ ┌──────────────────────────┐ │  │
│  │ │claude-code  │ │    │ │ ┌──────────────────────┐ │ │  │
│  │ │(deployment) │ │    │ │ │ llama.cpp Qwen       │ │ │  │
│  │ └─────────────┘ │    │ │ │ (deployment/pod)     │ │ │  │
│  │                 │    │ │ └──────────────────────┘ │ │  │
│  │ ┌─────────────┐ │    │ │                            │ │  │
│  │ │opencode     │ │    │ │ ┌──────────────────────┐ │ │  │
│  │ │(deployment) │ │    │ │ │ Qdrant (StatefulSet) │ │ │  │
│  │ └─────────────┘ │    │ │ └──────────────────────┘ │ │  │
│  │                 │    │ │                            │ │  │
│  └─────────────────┘    │ │ ┌──────────────────────┐ │ │  │
│                         │ │ │ Redis (deployment)  │ │ │  │
│                         │ │ └──────────────────────┘ │ │  │
│                         │ └────────────────────────────┘ │  │
│                         └──────────────────────────────────┘  │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ Zephyr Host (10.1.1.110)                                 │  │
│  │                                                           │  │
│  │  ┌─────────────────────────────────────────────────┐    │  │
│  │  │ NixOS Systemd Services                           │    │  │
│  │  │                                                   │    │  │
│  │  │  • ai-inference-gateway (0.0.0.0:8080)  ✅      │    │  │
│  │  │  • llama-cpp-qwen (127.0.0.1:8083)     ✅      │    │  │
│  │  │  • qdrant (localhost:6333)              ✅      │    │  │
│  │  │  • redis (localhost:6380)               ✅      │    │  │
│  │  └─────────────────────────────────────────────────┘    │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## Services Status

| Service | Type | Status | Endpoint |
|---------|------|--------|----------|
| AI Gateway | Systemd | ✅ Running | 10.1.1.110:8080 |
| llama.cpp | Systemd | ✅ Running | 127.0.0.1:8083 |
| Qdrant | K8s | ✅ Running | qdrant:6333 |
| Redis | K8s | ✅ Running | redis:6379 |
| Claude Code | K8s | ✅ Running | N/A |
| OpenCode | K8s | ✅ Running | N/A |

## Access Methods

### From Kubernetes Pods
```bash
# Via direct IP (works)
curl http://10.1.1.110:8080/v1/chat/completions

# Via ExternalService (DNS broken)
curl http://ai-inference-gateway-external.ai-inference.svc.cluster.local:8080/v1/chat/completions
```

### From Host
```bash
# Via localhost
curl http://127.0.0.1:8080/health

# Via host IP
curl http://10.1.1.110:8080/health
```

## Next Steps

### Immediate (Fix DNS Issue)
1. Investigate CoreDNS configuration
2. Check network policies between namespaces
3. Verify service discovery is working
4. Test DNS resolution with `nslookup` from pods

### Short-term (Build Container Image)
1. Create Dockerfile for gateway
2. Build container image locally
3. Push to container registry
4. Update Kubernetes deployment to use new image
5. Test pure Kubernetes deployment

### Long-term (Complete Migration)
1. Move all services to Kubernetes (remove systemd versions)
2. Fix LimitRange to not auto-assign GPUs
3. Implement proper service discovery
4. Add monitoring and observability
5. Document final architecture

## Testing Commands

```bash
# Test gateway health
curl http://10.1.1.110:8080/health | jq .

# Test gateway API
curl -X POST http://10.1.1.110:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "qwen3.5-4b", "messages": [{"role": "user", "content": "Hello"}]}'

# Test from Kubernetes pod
kubectl run test-gateway -n ai-coding --image=curlimages/curl \
  --restart=Never --command -- \
  curl -s http://10.1.1.110:8080/health

# Check all AI inference pods
kubectl get pods -n ai-inference

# Check all AI coding pods
kubectl get pods -n ai-coding
```

## Files Modified

1. `/etc/nixos/kubernetes-manifests/ai-inference/gateway-deployment.yaml`
   - Updated BACKEND_URL to service DNS
   - Added explicit GPU=0 in resources
   - Removed nodeSelector

2. `/etc/nixos/hosts/zephyr/configuration.nix`
   - Changed gateway host from `127.0.0.1` to `0.0.0.0`

3. `/etc/nixos/kubernetes-manifests/ai-inference/gateway-external-service.yaml`
   - Created ExternalService pointing to NixOS gateway

4. `/etc/nixos/kubernetes-manifests/ai-inference/limitrange-fixed.yaml`
   - Created fixed LimitRange (not yet applied successfully)

## Summary

✅ **Gateway is working and accessible from Kubernetes**
✅ **Backend connectivity verified (llama.cpp, Qdrant, Redis)**
✅ **AI coding tools (Claude, OpenCode) deployed on Kubernetes**
⚠️ **DNS resolution issue needs investigation**
⚠️ **Container image needs to be built for pure K8s deployment**

The migration is partially complete. The gateway and backend services are working, but we're using a hybrid approach (systemd + Kubernetes) rather than pure Kubernetes.
