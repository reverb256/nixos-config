# SearXNG Knowledge Fabric Integration Test

**Date:** 2026-03-23
**Status:** ✅ Configuration Fixed, ⏳ Testing Required

---

## Changes Made

### 1. ✅ SearXNG Deployment Fixed
**File:** `kubernetes-manifests/search/searxng-deployment.yaml`
- Disabled bot detection (`limiter: false`, `bot_detection.enabled: false`)
- Removed invalid `limiter.toml` ConfigMap
- Result: SearXNG pods running without bot detection errors

### 2. ✅ Caddy Ingress Headers Fixed
**File:** `kubernetes-manifests/ingress/02-configmap.yaml`
- Added `X-Forwarded-For` header to search.cluster.local route
- Added `X-Real-IP` header to search.cluster.local route
- Result: Proper client IP forwarding for bot detection

### 3. ✅ Zen Browser Configuration Verified
**File:** `modules/home-manager/zen-browser.nix`
- Line 614: Sidebar pin points to `https://search.cluster.local` ✅
- Line 834: Search engine uses `https://search.cluster.local/search?q={searchTerms}` ✅
- Result: Zen Browser correctly configured for SearXNG

### 4. ✅ Knowledge Fabric SearXNG Source Fixed
**File:** `modules/services/ai-inference/ai-inference_gateway/middleware/knowledge_fabric/sources/searxng_source.py`
- Updated URL: `http://searxng.search.svc.cluster.local:8080` (was `http://10.1.1.110:8890`)
- Updated docstrings to reflect Kubernetes deployment
- Result: Knowledge fabric now points to correct Kubernetes service

---

## Service Architecture

```
Zen Browser (Workstation)
    ↓
https://search.cluster.local
    ↓
Caddy Ingress (nexus, forge, sentry)
    ↓ X-Forwarded-For, X-Real-IP headers
SearXNG Service (search namespace)
    ↓ ClusterIP: 10.0.0.247:8080
SearXNG Pods (3 replicas)

AI Gateway (ai-inference namespace)
    ↓ /knowledge-fabric endpoint
SearXNG Source Adapter
    ↓ http://searxng.search.svc.cluster.local:8080
SearXNG Service (cluster DNS)
```

---

## Testing Checklist

### Phase 1: Verify SearXNG Web Interface
- [ ] Access https://search.cluster.local from browser
- [ ] Verify search returns results (try "test query")
- [ ] Check no 403 errors in logs
- [ ] Verify bot detection warnings are gone

### Phase 2: Test Knowledge Fabric Integration
- [ ] Scale up ai-inference-gateway deployment:
  ```bash
  kubectl scale deployment ai-inference-gateway -n ai-inference --replicas=1
  ```
- [ ] Check pod starts successfully:
  ```bash
  kubectl get pods -n ai-inference -l app=ai-inference-gateway
  ```
- [ ] Test /knowledge-fabric endpoint:
  ```bash
  curl -X POST http://localhost:8080/knowledge-fabric \
    -H "Content-Type: application/json" \
    -d '{"query": "test search", "sources": ["searxng"]}'
  ```
- [ ] Verify SearXNG source returns results

### Phase 3: Verify Zen Browser Integration
- [ ] Open Zen Browser
- [ ] Click "SearXNG" pin in System workspace
- [ ] Verify search.cluster.local loads
- [ ] Try a search query (e.g., "@sx test")
- [ ] Verify results appear

---

## Current Status

### ✅ Working
- SearXNG deployment: 3/3 replicas running
- Caddy ingress: 3/3 nodes operational
- Zen browser: Configured correctly
- Knowledge fabric: URL updated to cluster DNS

### ⏳ Needs Testing
- AI Gateway: Currently 0/0 replicas (scaled down)
- Knowledge fabric endpoint: Not tested yet
- End-to-end search: Not verified

### 🔧 Known Issues
- Bot detection warnings in logs (expected, since disabled)
- Some engines inactive (ahmia, torch) - these are optional

---

## Troubleshooting

### If AI Gateway fails to start:
```bash
# Check logs
kubectl logs -n ai-inference deployment/ai-inference-gateway

# Check events
kubectl describe pod -n ai-inference -l app=ai-inference-gateway

# Common issues:
# - Missing environment variables
# - PVC not mounted (qdrant storage)
# - Service account permissions
```

### If /knowledge-fabric returns errors:
```bash
# Test SearXNG directly from gateway pod
kubectl exec -n ai-inference deployment/ai-inference-gateway -- \
  curl "http://searxng.search.svc.cluster.local:8080/search?q=test&format=json"

# Check DNS resolution
kubectl exec -n ai-inference deployment/ai-inference-gateway -- \
  nslookup searxng.search.svc.cluster.local

# Check service connectivity
kubectl exec -n ai-inference deployment/ai-inference-gateway -- \
  telnet searxng.search.svc.cluster.local 8080
```

### If Zen Browser can't access search.cluster.local:
```bash
# Check Caddy ingress is running
kubectl get pods -n ingress-system -l app.kubernetes.io/name=caddy-ingress

# Check Caddy config
kubectl get configmap caddy-config -n ingress-system -o yaml

# Check DNS resolution
nslookup search.cluster.local

# Check TLS certificate (if using HTTPS)
curl -v https://search.cluster.local 2>&1 | grep -i "certificate\|tls"
```

---

## Commits Created

1. **b3b6cbc** - fix(searxng): Resolve HTTP 403 errors and verify storage classes
2. **cac3f6c** - docs(status): Correct monitor brightness issue - RESOLVED
3. **4a95947** - fix(knowledge-fabric): Update SearXNG source to use Kubernetes service

---

## Next Steps

1. **Immediate:** Test SearXNG web interface from browser
2. **This Week:** Scale up AI Gateway and test /knowledge-fabric
3. **Documentation:** Update knowledge-fabric docs with SearXNG integration
4. **Monitoring:** Add metrics for SearXNG query success rate

---

**Last Updated:** 2026-03-23 10:45 UTC
