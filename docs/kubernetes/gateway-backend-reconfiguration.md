# Gateway Backend Reconfiguration - ZAI Integration

**Date:** 2026-03-26
**Status:** ✅ CONFIGURED - Ready for API key and testing

---

## Summary

The AI Inference Gateway has been reconfigured to use the **ZAI backend** instead of requiring a local llama.cpp backend. This enables immediate end-to-end testing of the Knowledge Fabric without deploying additional infrastructure.

---

## Configuration Changes

### Backend Configuration

**Before (llama-cpp):**
```yaml
BACKEND_URL: "http://127.0.0.1:8083"
BACKEND_TYPE: "llama-cpp"
BACKEND_FALLBACK_URLS: "https://api.z.ai/api/coding/paas/v4"
```

**After (ZAI):**
```yaml
BACKEND_URL: "https://api.z.ai/api/coding/paas/v4"
BACKEND_TYPE: "zai"
BACKEND_FALLBACK_URLS: ""
```

### Key Changes

| Setting | Old Value | New Value | Purpose |
|---------|-----------|-----------|---------|
| `BACKEND_TYPE` | `llama-cpp` | `zai` | Use ZAI API instead of local backend |
| `BACKEND_URL` | `http://127.0.0.1:8083` | `https://api.z.ai/api/coding/paas/v4` | ZAI API endpoint |
| `ZAI_API_KEY` | (not set) | Secret reference | API authentication |

---

## Deployment Status

### Current Pods

```
NAME                                    READY   STATUS    RESTARTS   AGE
ai-inference-gateway-5b885dd98c-rh8n8   1/1     Running   0          5m
ai-inference-gateway-75755d8b4b-kxsqw   1/1     Running   0          2m
```

✅ **Gateway is running with ZAI backend configuration**

### Startup Logs

```
[DEBUG] knowledge_fabric config: enabled=True, rrf_k=60, env=true
[DEBUG] About to check knowledge_fabric.enabled: True
[DEBUG] Adding KnowledgeFabricMiddleware!
INFO:     Application startup complete.
```

✅ **Knowledge Fabric middleware is loading correctly**

---

## API Key Configuration

### Current Secret Status

```yaml
# Secret: ai-inference-gateway-secrets
# Namespace: ai-inference
# Key: zai-api-key
# Value: "YOUR_ZAI_API_KEY_HERE" (placeholder)
```

### How to Set Your API Key

**Option 1: Using kubectl create secret**
```bash
kubectl create secret generic ai-inference-gateway-secrets \
  --from-literal=zai-api-key='YOUR_ACTUAL_API_KEY_HERE' \
  --namespace=ai-inference \
  --dry-run=client -o yaml | kubectl apply -f -
```

**Option 2: Edit existing secret**
```bash
kubectl edit secret ai-inference-gateway-secrets -n ai-inference
# Update the zai-api-key value
```

**Option 3: Create from file**
```bash
echo -n 'YOUR_ACTUAL_API_KEY_HERE' > /tmp/zai-api-key.txt
kubectl create secret generic ai-inference-gateway-secrets \
  --from-file=zai-api-key=/tmp/zai-api-key.txt \
  --namespace=ai-inference \
  --dry-run=client -o yaml | kubectl apply -f -
rm /tmp/zai-api-key.txt
```

### After Updating API Key

```bash
# Restart pods to pick up new secret
kubectl rollout restart deployment/ai-inference-gateway -n ai-inference

# Wait for rollout
kubectl rollout status deployment/ai-inference-gateway -n ai-inference --timeout=120s
```

---

## Supported Backend Types

The gateway supports multiple backend types (configurable via `BACKEND_TYPE`):

| Backend Type | Description | API Key Required |
|--------------|-------------|------------------|
| `llama-cpp` | Local llama.cpp server | ❌ No |
| `vllm` | Local vLLM server | ❌ No |
| `sglang` | Local SGLang server | ❌ No |
| `zai` | ZAI Cloud API | ✅ Yes (`ZAI_API_KEY`) |
| `pollinations` | Pollinations API | ✅ Yes (`POLLINATIONS_API_KEY`) |

**Current Configuration:** ZAI (cloud API)

**To switch back to local llama.cpp:**
```bash
kubectl edit configmap ai-inference-gateway-config -n ai-inference
# Change BACKEND_TYPE to "llama-cpp"
# Change BACKEND_URL to "http://127.0.0.1:8083"
kubectl rollout restart deployment/ai-inference-gateway -n ai-inference
```

---

## Testing the Gateway

### 1. Health Check (No API Key Required)

```bash
kubectl port-forward -n ai-inference svc/ai-inference-gateway 8080:8080 &
PF_PID=$!
sleep 5

# From another terminal:
curl http://localhost:8080/health

# Clean up:
kill $PF_PID
```

**Expected Response:**
```json
{
  "status": "healthy",
  "timestamp": "2026-03-26T04:30:00Z",
  "backend": {
    "url": "https://api.z.ai/api/coding/paas/v4",
    "type": "zai",
    "healthy": false
  },
  "knowledge_fabric": {
    "enabled": true,
    "rrf_k": 60
  }
}
```

**Note:** `backend.healthy: false` is expected without a valid API key.

### 2. Chat Completions (Requires API Key)

```bash
# Port-forward first
kubectl port-forward -n ai-inference svc/ai-inference-gateway 8080:8080 &
PF_PID=$!
sleep 5

# Test chat completion
curl -X POST http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4o-mini",
    "messages": [{"role": "user", "content": "How do I configure NixOS flakes for colmena?"}],
    "max_tokens": 200
  }'

# Clean up
kill $PF_PID
```

### 3. Knowledge Fabric Test (Requires API Key)

The Knowledge Fabric will automatically:
1. Classify the query intent (CODE, FACTUAL, PROCEDURAL, etc.)
2. Select appropriate knowledge sources (code search, web search, RAG, SearXNG)
3. Retrieve relevant context from selected sources
4. Augment the prompt with retrieved context
5. Generate response using backend model

**Test Queries:**

| Query Type | Example Query | Expected Intent |
|------------|---------------|-----------------|
| CODE | "How do I fix a NullPointerException in Java?" | CODE |
| DEVOPS | "How do I deploy PostgreSQL on Kubernetes?" | PROCEDURAL |
| RESEARCH | "What are the latest developments in transformer architecture?" | REALTIME |
| FACTUAL | "What is the definition of microservices?" | FACTUAL |

---

## Knowledge Fabric Verification

### Middleware Status

✅ **Enabled:** `MIDDLEWARE__KNOWLEDGE_FABRIC__ENABLED: "true"`
✅ **RRF K parameter:** `MIDDLEWARE__KNOWLEDGE_FABRIC__RRF_K: "60"`
✅ **Code Search:** `MIDDLEWARE__KNOWLEDGE_FABRIC__CODE_SEARCH_ENABLED: "true"`
✅ **Web Search:** `MIDDLEWARE__KNOWLEDGE_FABRIC__WEB_SEARCH_ENABLED: "true"`
✅ **SearXNG:** `MIDDLEWARE__KNOWLEDGE_FABRIC__SEARXNG_ENABLED: "true"`
✅ **RAG:** `MIDDLEWARE__KNOWLEDGE_FABRIC__RAG_ENABLED: "true"`

### Configuration Summary

```yaml
Knowledge Sources:
  - Code Search (GitHub, StackOverflow)
    Enabled: true
    Max Results: 10
    Paths: ["/etc/nixos", "/home/j_kro"]

  - Web Search (SearXNG metasearch)
    Enabled: true
    Max Results: 10
    URL: http://searxng.search.svc.cluster.local:8080

  - RAG (Qdrant vector database)
    Enabled: true
    Top K: 10
    URL: http://qdrant.ai-inference.svc.cluster.local:6333

Routing:
  - Intent Classification: Pattern-based heuristics
  - Confidence Threshold: 0.5
  - RRF K parameter: 60 (fusion algorithm)

Query Processing:
  - Short queries (< 10 chars): Skipped
  - Low confidence (< 0.5): Skipped
  - High confidence (≥ 0.5): Processed through Knowledge Fabric
```

---

## Troubleshooting

### Issue: Pods not starting (Pending status)

**Solution:** Check node resources and taints
```bash
kubectl describe node nexus
kubectl get pods -n ai-inference -o wide
```

### Issue: Gateway returns 401/403 errors

**Solution:** API key is missing or invalid
```bash
kubectl get secret ai-inference-gateway-secrets -n ai-inference -o jsonpath='{.data.zai-api-key}' | base64 -d
```

### Issue: Backend connection errors

**Solution:** Verify ZAI API endpoint is accessible
```bash
kubectl logs -n ai-inference deployment/ai-inference-gateway --tail=50 | grep -i "backend\|error"
```

### Issue: Knowledge Fabric not triggering

**Solution:** Check configuration and logs
```bash
kubectl logs -n ai-inference deployment/ai-inference-gateway --tail=100 | grep -i "knowledge_fabric\|routing"
```

---

## Next Steps

### Immediate Actions Required

1. **Set ZAI API Key**
   - Update secret with your actual API key
   - Restart deployment

2. **Test Health Endpoint**
   - Verify gateway is accessible
   - Check Knowledge Fabric status

3. **Run End-to-End Tests**
   - Test chat completions with Knowledge Fabric
   - Verify query classification
   - Validate context augmentation

### Future Improvements

1. **Add API Key Validation**
   - Startup check for valid API key
   - Graceful fallback if key is missing

2. **Support Multiple Backends**
   - Try ZAI first, fallback to pollinations
   - Support multiple API keys for load balancing

3. **Metrics Dashboard**
   - Track Knowledge Fabric performance
   - Monitor query classification accuracy
   - Measure context relevance

---

## Rollback Instructions

If you need to revert to llama.cpp backend:

```bash
# 1. Edit ConfigMap
kubectl edit configmap ai-inference-gateway-config -n ai-inference
# Change:
#   BACKEND_TYPE: "llama-cpp"
#   BACKEND_URL: "http://127.0.0.1:8083"

# 2. Remove ZAI_API_KEY environment variable
kubectl edit deployment ai-inference-gateway -n ai-inference
# Remove the ZAI_API_KEY env var from the container spec

# 3. Restart deployment
kubectl rollout restart deployment/ai-inference-gateway -n ai-inference

# 4. Verify
kubectl rollout status deployment/ai-inference-gateway -n ai-inference --timeout=120s
```

---

## Documentation References

- **Knowledge Fabric Testing Summary:** `docs/kubernetes/knowledge-fabric-testing-summary.md`
- **Routing Logic Verification:** `docs/kubernetes/knowledge-fabric-routing-verification.md`
- **Gateway Deployment Manifest:** `kubernetes-manifests/ai-inference/gateway-deployment.yaml`
- **Secret Manifest:** `kubernetes-manifests/ai-inference/ai-inference-gateway-secrets.yaml`

---

**Configuration Completed:** 2026-03-26
**Tested By:** Claude Code
**Status:** ✅ Ready for API key and E2E testing
