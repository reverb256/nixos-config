# Gateway Endpoint Test Results — 2026-04-24

## Test Summary

| Endpoint | Method | Status | Notes |
|----------|--------|--------|-------|
| `/health` | GET | ✅ Working | Returns health status, backend info |
| `/v1/models` | GET | ✅ Working | Lists Qwen3.6-35B-A3B, TTS models |
| `/v1/chat/completions` | POST | ✅ Working | Returns chat completions |
| `/search` | POST | ⚠️ Partial | Returns error: "Cannot connect to SearXNG service" |
| `/search/hybrid` | — | ❓ Not tested | Needs verification |
| `/search/agent` | POST | ✅ Working | Returns intent classification, no results (due to SearXNG) |
| `/rag/search` | GET | ❌ Disabled | RAG service not enabled |
| `/v1/search` | — | ❌ Missing | **NEEDS IMPLEMENTATION** |
| `/v1/knowledge/commit` | — | ❌ Missing | **NEEDS IMPLEMENTATION** |
| `/v1/knowledge/query` | — | ❌ Missing | **NEEDS IMPLEMENTATION** |
| `/v1/chat/smol` | — | ❌ Missing | **NEEDS IMPLEMENTATION** |
| `/v1/chat/slow` | — | ❌ Missing | **NEEDS IMPLEMENTATION** |
| `/v1/chat/plan` | — | ❌ Missing | **NEEDS IMPLEMENTATION** |

## SearXNG Connection Issue

**Problem:** Gateway cannot connect to SearXNG service
**Error:** "Cannot connect to SearXNG service"
**SearXNG Status:** Running on port 8080, but rate-limited by Brave (403 errors)
**Gateway Config:** `MIDDLEWARE__KNOWLEDGE_FABRIC__SEARXNG_URL=http://searxng.search.svc.cluster.local:8080`

**Network Policies:** Allow gateway egress to search namespace on port 8080 ✅

**Likely Cause:** DNS resolution or routing issue between namespaces

## Existing Working Features

✅ Health checks with backend status
✅ Model listing (Qwen3.6-35B-A3B, TTS)
✅ Chat completions with streaming
✅ Intent classification (QueryIntent router)
✅ MCP server management
✅ Semantic cache
✅ PII redaction
✅ Content moderation
✅ RAG ingestion endpoints (`/rag/ingest`, `/rag/ingest/batch`)

## Next Steps

### Immediate (Fix SearXNG Connection)
1. Verify DNS resolution from gateway pod
2. Test network path: gateway → search namespace
3. Check if hostNetwork setting affects inter-pod communication

### Phase 1 Implementation (Required)
1. `/v1/search` — Unified search wrapper with auto mode
2. `/v1/knowledge/commit` — Knowledge upsert endpoint
3. `/v1/knowledge/query` — Qdrant query wrapper
4. `/v1/chat/smol|slow|plan` — Model role routes

---

**Generated:** 2026-04-24
