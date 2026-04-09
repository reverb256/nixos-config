# AI Inference Services - Complete Kubernetes Migration Plan
**Date**: 2026-03-21
**Goal**: Migrate ALL AI inference services from NixOS systemd to Kubernetes

## Services to Migrate

### 1. AI Inference Gateway ✅ (In Progress)
**Systemd Service**: `ai-inference-gateway.service`
**K8s Deployment**: `ai-inference-gateway` (ai-inference namespace)
**Status**: Configuration fixed, needs to be applied
**Action**: Apply gateway fix, then remove systemd service

### 2. llama.cpp Server
**Systemd Service**: `llama-cpp-qwen.service` (if exists)
**K8s Deployment**: `llama-cpp-qwen` (ai-inference namespace)
**Status**: K8s deployment exists
**Action**: Verify K8s deployment works, remove systemd version

### 3. Qdrant Vector Database
**Systemd Service**: `qdrant.service` (if exists)
**K8s Deployment**: `qdrant` (ai-inference namespace)
**Status**: K8s deployment exists
**Action**: Verify K8s deployment works, remove systemd version

### 4. Redis Cache
**Systemd Service**: `redis@ai-inference.service` (port 6380)
**K8s Deployment**: `redis` (ai-inference namespace)
**Status**: K8s deployment exists
**Action**: Verify K8s deployment works, remove systemd version

### 5. SearXNG Search
**Systemd Service**: Unknown (check if exists)
**K8s Deployment**: Should exist in ai-inference namespace
**Status**: Need to verify
**Action**: Create or verify K8s deployment, remove systemd version

## Migration Steps

### Phase 1: Verify K8s Deployments (Current Session)
```bash
# 1. Check all deployments in ai-inference namespace
kubectl get deployments -n ai-inference
kubectl get pods -n ai-inference
kubectl get services -n ai-inference

# 2. Verify each service is healthy
kubectl get pods -n ai-inference -o wide

# 3. Test service connectivity
# - Gateway
kubectl exec -n ai-inference ai-inference-gateway-xxxxx -- curl http://localhost:8080/health
# - llama.cpp
kubectl exec -n ai-inference llama-cpp-qwen-xxxxx -- curl http://localhost:8080/health
# - Qdrant
kubectl exec -n ai-inference qdrant-xxxxx -- curl http://localhost:6333/health
# - Redis
kubectl exec -n ai-inference redis-xxxxx -- redis-cli ping
```

### Phase 2: Update Dependent Services
**No changes needed** - All services already use K8s service DNS:
- Gateway → `llama-cpp-qwen.ai-inference.svc.cluster.local:8080`
- Gateway → `qdrant:6333`
- Gateway → `redis:6380` (if configured)
- Gateway → `searxng:7777`

### Phase 3: Remove Systemd Services

#### 3.1. Disable systemd services (NixOS config)
**File**: `/etc/nixos/hosts/zephyr/configuration.nix`

```nix
# BEFORE
{
  services.ai-inference.enable = true;
  # ... other AI inference services
}

# AFTER
{
  services.ai-inference.enable = false;  # Disable on NixOS, use K8s instead
}
```

#### 3.2. Rebuild NixOS
```bash
cd /etc/nixos
just check  # Validate configuration
just switch # Apply to Zephyr
```

#### 3.3. Verify systemd services stopped
```bash
# Check services are disabled
systemctl status ai-inference-gateway.service
systemctl status llama-cpp-qwen.service
systemctl status qdrant.service
systemctl status redis@ai-inference.service
```

### Phase 4: Update Documentation
**Files to update**:
- `/etc/nixos/modules/services/ai-inference/README.md`
- `/etc/nixos/docs/ai-inference-gateway-refactor-2026-03-21.md`

Add note: "All AI inference services now run on Kubernetes. NixOS systemd versions have been deprecated."

### Phase 5: Cleanup (Optional)
Remove NixOS module if no longer needed:
```bash
# Only if ALL services moved to K8s and verified working
rm -rf /etc/nixos/modules/services/ai-inference
```

## Verification Checklist

### Pre-Migration
- [ ] All K8s deployments are running and healthy
- [ ] All K8s services are accessible
- [ ] Gateway can connect to llama.cpp backend
- [ ] Gateway can connect to Qdrant
- [ ] Gateway can connect to Redis
- [ ] Gateway can connect to SearXNG
- [ ] End-to-end API test works

### Post-Migration
- [ ] Systemd services are disabled and stopped
- [ ] `just switch` completed without errors
- [ ] No AI inference services in `systemctl list-units`
- [ ] K8s services still accessible
- [ ] Gateway API still works
- [ ] No resource conflicts (ports, memory)

## Rollback Plan

If issues occur:
```bash
# 1. Re-enable systemd services in NixOS config
# Edit /etc/nixos/hosts/zephyr/configuration.nix
# Set: services.ai-inference.enable = true;

# 2. Rebuild NixOS
cd /etc/nixos
just switch

# 3. Verify systemd services started
systemctl status ai-inference-gateway.service

# 4. Optionally scale down K8s deployments
kubectl scale deployment ai-inference-gateway -n ai-inference --replicas=0
```

## Service Dependencies

```
ai-inference-gateway
├── llama-cpp-qwen (backend LLM)
├── qdrant (vector DB for RAG)
├── redis (caching)
└── searxng (web search)
```

**Migration Order** (reverse dependency order):
1. Verify leaf services first (llama.cpp, Qdrant, Redis, SearXNG)
2. Then verify gateway (depends on all above)
3. Then disable systemd versions
4. Then rebuild NixOS

## Resource Impact

### Before (NixOS Systemd)
- Zephyr: 4+ systemd services
- Manual process management
- Host resource allocation
- No autoscaling

### After (Kubernetes)
- Cluster-wide resource management
- Automatic scaling (HPA)
- Better resource isolation
- Unified monitoring

## Estimated Resource Savings

After removing systemd services from Zephyr:
- **Memory**: ~2-4 GB freed (depends on service configurations)
- **CPU**: ~2-4 cores freed
- **Storage**: Minimal (config files only)

## Timeline

### Session 1 (Current)
- ✅ Fix gateway backend URL
- ✅ Create migration plan
- ⏳ Verify all K8s deployments
- ⏳ Apply gateway fix

### Session 2 (Next)
- Disable systemd services in NixOS config
- Rebuild Zephyr
- Verify K8s services still work
- Update documentation

### Session 3 (Future)
- Cleanup deprecated NixOS modules
- Optimize K8s resource requests/limits
- Add HPA for autoscaling

## Risk Assessment

### Low Risk
- K8s deployments already exist
- Service isolation prevents conflicts
- Can easily rollback with NixOS

### Medium Risk
- Gateway configuration changes
- Network DNS resolution issues
- Resource allocation changes

### High Risk
- **None identified** - All services have K8s equivalents

## Success Criteria

1. All AI inference services running on Kubernetes
2. No systemd services for AI inference on any host
3. Gateway API fully functional
4. RAG (Qdrant) working
5. Web search (SearXNG) working
6. No resource conflicts
7. Monitoring/observability intact

## Next Steps

### Immediate (This Session)
1. Apply gateway fix: `./apply-gateway-fix.sh`
2. Verify all K8s pods: `kubectl get pods -n ai-inference`
3. Test gateway API
4. Document any issues

### Follow-up (Next Session)
1. Update NixOS config to disable systemd services
2. Rebuild Zephyr: `just switch`
3. Verify systemd services stopped
4. Final verification test

### Future
1. Add HPA for autoscaling
2. Implement backup/restore for Qdrant
3. Add monitoring dashboards
4. Optimize resource allocation
