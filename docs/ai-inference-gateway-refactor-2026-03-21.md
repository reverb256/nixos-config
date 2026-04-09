# AI Inference Gateway Refactoring Guide
**Date**: 2026-03-21
**Purpose**: Migrate from LM Studio to pure llama.cpp backend on Kubernetes

## Current Architecture

### NixOS Systemd Service (Zephyr)
- **Backend URL**: `http://127.0.0.1:8083`
- **Backend Type**: `llama-cpp`
- **Purpose**: Host-based gateway for local development

### Kubernetes Deployment (BROKEN)
- **Backend URL**: `http://127.0.0.1:8083` (localhost doesn't work in pods!)
- **Backend Type**: `llama-cpp`
- **Issue**: Pods can't access localhost services
- **Status**: 0/2 replicas available

## Target Architecture

### llama.cpp Service Discovery
```yaml
# Service: llama-cpp-qwen.ai-inference.svc.cluster.local:8080
# Maps to: Host port 8083 OR Pod port 8080
```

**Two modes available**:
1. **Host-based** (current): Service Endpoints → Zephyr's IP:8083
2. **Pod-based** (future): Service → llama-cpp-qwen pod:8080

### Gateway Configuration
```yaml
BACKEND_URL: "http://llama-cpp-qwen.ai-inference.svc.cluster.local:8080"
BACKEND_TYPE: "llama-cpp"
```

## Changes Required

### 1. Update Kubernetes ConfigMap
**File**: `kubernetes-manifests/ai-inference/gateway-deployment.yaml`

```diff
- BACKEND_URL: "http://127.0.0.1:8083"
+ BACKEND_URL: "http://llama-cpp-qwen.ai-inference.svc.cluster.local:8080"
```

### 2. Add PriorityClass
**File**: `kubernetes-manifests/ai-inference/gateway-deployment.yaml`

```yaml
spec:
  priorityClassName: "high-priority"  # Already exists in cluster
```

### 3. Remove nodeSelector (Optional)
**Current**: Gateway pinned to Zephyr (localhost dependency)
**After**: Can run on any node (uses internal service DNS)

```diff
- nodeSelector:
-   kubernetes.io/hostname: zephyr
```

## Migration Steps

### Option A: Apply New Manifest (Recommended)
```bash
# Apply refactored configuration
kubectl apply -f kubernetes-manifests/ai-inference/gateway-deployment-refactored.yaml

# Verify gateway is running
kubectl get pods -n ai-inference -l app=ai-inference-gateway

# Test connectivity
kubectl exec -n ai-inference ai-inference-gateway-xxxxx -- curl http://llama-cpp-qwen.ai-inference.svc.cluster.local:8080/health
```

### Option B: Edit Existing ConfigMap
```bash
# Edit ConfigMap directly
kubectl edit configmap ai-gateway-config -n ai-inference

# Change BACKEND_URL to service DNS
# Restart pods to pick up changes
kubectl rollout restart deployment ai-inference-gateway -n ai-inference
```

## Verification

### 1. Check Gateway Health
```bash
kubectl get pods -n ai-inference -l app=ai-inference-gateway
kubectl logs -n ai-inference ai-inference-gateway-xxxxx
```

### 2. Test Backend Connectivity
```bash
# From gateway pod
kubectl exec -n ai-inference ai-inference-gateway-xxxxx -- \
  curl http://llama-cpp-qwen.ai-inference.svc.cluster.local:8080/health

# From host
curl http://10.1.1.110:8083/health  # Host's llama.cpp
```

### 3. Test Gateway API
```bash
# Via gateway service
curl http://ai-inference-gateway.ai-inference.svc.cluster.local:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "qwen3.5-4b", "messages": [{"role": "user", "content": "Hello"}]}'
```

## NixOS Service Status

**No changes required** - The NixOS systemd service continues to work as-is:
- Host-based gateway on port 8080
- Connects to llama.cpp on localhost:8083
- Used for local development and MCP integration

## Rollback Plan

If issues occur:
```bash
# Revert to old configuration
kubectl apply -f kubernetes-manifests/ai-inference/gateway-deployment.yaml

# Or restore ConfigMap
kubectl rollout undo deployment ai-inference-gateway -n ai-inference
```

## Future Improvements

### Phase 2: Pod-based llama.cpp
- Remove host dependency entirely
- Use llama-cpp-qwen deployment (port 8080)
- Update Endpoints to point to pods instead of host IP

### Phase 3: Multiple Backend Support
- Configure Z.AI as primary fallback
- Add Pollinations for specific use cases
- Implement backend routing logic

## Related Files

- `kubernetes-manifests/ai-inference/gateway-deployment.yaml` - Current (broken)
- `kubernetes-manifests/ai-inference/gateway-deployment-refactored.yaml` - New (fixed)
- `kubernetes-manifests/llama-cpp/04-service-endpoints.yaml` - Service definition
- `modules/services/ai-inference/gateway.nix` - NixOS service (unchanged)
- `hosts/zephyr/configuration.nix` - NixOS config (unchanged)

## Troubleshooting

### Gateway pods stuck in CrashLoopBackOff
```bash
# Check logs
kubectl logs -n ai-inference ai-inference-gateway-xxxxx

# Common issue: Can't reach backend
# Verify service DNS resolves
kubectl exec -n ai-inference ai-inference-gateway-xxxxx -- nslookup llama-cpp-qwen.ai-inference.svc.cluster.local
```

### Backend connection refused
```bash
# Verify llama.cpp is running
kubectl get endpoints -n ai-inference llama-cpp-qwen

# Check if host's llama.cpp is accessible
curl http://10.1.1.110:8083/health
```

### Service DNS not resolving
```bash
# Check CoreDNS is running
kubectl get pods -n kube-system -l k8s-app=kube-dns

# Test DNS resolution
kubectl run test-dns --rm -it --image=busybox -- nslookup llama-cpp-qwen.ai-inference.svc.cluster.local
```

## Summary

**Problem**: Gateway configured with localhost URL (`127.0.0.1:8083`) which doesn't work in Kubernetes pods.

**Solution**: Use Kubernetes service DNS (`llama-cpp-qwen.ai-inference.svc.cluster.local:8080`) for internal service discovery.

**Impact**: Gateway pods can now successfully connect to llama.cpp backend, bringing replicas from 0/2 to 2/2 available.
