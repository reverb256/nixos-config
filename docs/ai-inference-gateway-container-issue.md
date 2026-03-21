# AI Inference Gateway - Container Image Issue
**Date**: 2026-03-21
**Status**: Blocked - Container image not accessible

## Current Issue

Gateway pods failing with image pull error:
```
Failed to pull image "ghcr.io/j-kro/ai-inference-gateway:latest": 403 Forbidden
```

## Root Cause

The container image `ghcr.io/j-kro/ai-inference-gateway:latest` either:
1. Doesn't exist in the registry
2. Is private and requires authentication
3. Has been removed/renamed

## Possible Solutions

### Option 1: Build and Push Container Image (Recommended)
Create a proper container image for the gateway:

```dockerfile
# Dockerfile
FROM python:3.13-slim

WORKDIR /app

# Copy gateway code
COPY ai_inference_gateway/ /app/ai_inference_gateway/

# Install dependencies
RUN pip install --no-cache-dir \
    fastapi uvicorn httpx openai anthropic \
    prometheus-client pyjwt cryptography \
    python-multipart uvloop httptools aiohttp psutil \
    qdrant-client sentence-transformers rank-bm25 \
    numpy beautifulsoup4 redis pydantic pydantic-settings

# Expose port
EXPOSE 8080 9190

# Run gateway
CMD ["uvicorn", "ai_inference_gateway.main:app", "--host", "0.0.0.0", "--port", "8080"]
```

Build and push:
```bash
docker build -t ghcr.io/j-kro/ai-inference-gateway:latest .
docker push ghcr.io/j-kro/ai-inference-gateway:latest
```

### Option 2: Use Local NixOS Gateway (Quick Fix)
Keep the gateway running as a systemd service and create an ExternalService:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: ai-inference-gateway-external
  namespace: ai-inference
spec:
  type: ClusterIP
  ports:
  - name: http
    port: 8080
    targetPort: 8080
---
apiVersion: v1
kind: Endpoints
metadata:
  name: ai-inference-gateway-external
  namespace: ai-inference
subsets:
  - addresses:
    - ip: 10.1.1.110  # Zephyr's IP
    ports:
    - name: http
      port: 8080
```

### Option 3: Build Image with Nix
Use Nix to build a container image:

```nix
# Add to flake.nix
packages.ai-inference-gateway-image = pkgs.dockerTools.buildLayeredImage {
  name = "ai-inference-gateway";
  tag = "latest";
  config.Cmd = [ "${gatewayPython}/bin/uvicorn" "ai_inference_gateway.main:app" "--host" "0.0.0.0" "--port" "8080" ];
  config.ExposedPorts = { "8080" = {}; "9190" = {}; };
  config.WorkingDir = "/app";
};
```

### Option 4: Use Alternative Image Registry
If the image exists elsewhere, update the deployment:

```yaml
spec:
  template:
    spec:
      containers:
      - name: gateway
        image: localhost:5000/ai-inference-gateway:latest  # Local registry
        # OR
        image: registry.gitlab.com/j-kro/ai-inference-gateway:latest
```

## Current Status

**Completed**:
- ✅ Gateway ConfigMap updated with correct backend URL
- ✅ LimitRange issue resolved (explicit GPU=0 in deployment)
- ✅ Pods can now be created (no more GPU quota errors)

**Blocked**:
- ❌ Container image not accessible
- ❌ Need to build/push image or use alternative approach

## Recommendation

**For immediate unblocking**: Use Option 2 (ExternalService) to point to the NixOS systemd gateway

**For long-term**: Use Option 1 (Build container image) to have a fully Kubernetes-native deployment

## Next Steps

1. Decide which approach to use
2. Implement chosen solution
3. Verify gateway is accessible
4. Test backend connectivity
5. Complete migration to Kubernetes

## Related Files

- `kubernetes-manifests/ai-inference/gateway-deployment.yaml` - Deployment config
- `modules/services/ai-inference/gateway.nix` - NixOS systemd service
- `docs/ai-inference-k8s-migration-plan.md` - Migration plan
