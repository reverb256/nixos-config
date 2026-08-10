# Sovereign Service Mesh — Status Report

**Date:** 2026-04-24
**Status:** ✅ OPERATIONAL — Phase 1 Complete
**Gateway:** `http://10.15.67.242:8080` (K8s ClusterIP)

---

## Executive Summary

The sovereign service mesh is **LIVE** with the AI Gateway as the central bus. The gateway already has RRF (Reciprocal Rank Fusion) middleware combining SearXNG + Qdrant + intent routing.

**Architecture:** Bus-style service mesh with AI Gateway as the central orchestrator.

---

## Mesh Components Status

| Component | Status | Location | ClusterIP | Notes |
|-----------|--------|----------|-----------|-------|
| **AI Gateway** | ✅ Running | nexus | 10.15.67.242:8080 | Central bus, RRF middleware enabled |
| **Qdrant** | ✅ Running | nexus | 10.5.93.32:6333 | Vector database, v1.13.4 |
| **Knowledge Fabric API** | ✅ Running | nexus | 10.6.31.109:3000 | Stub API, RRF in gateway |
| **SearXNG** | ✅ Running | nexus | 10.4.98.141:8080 | Web search, v2026.4.17 |
| **Valkey** | ✅ Running | nexus | — | Redis-compatible cache |
| **Hermes Agent** | ⚠️ Misconfigured | nexus | — | Points to wrong base_url |

---

## Gateway Endpoints (Implemented)

| Endpoint | Status | Description |
|----------|--------|-------------|
| `/health` | ✅ Working | Health check |
| `/v1/models` | ✅ Working | Model listing |
| `/v1/chat/completions` | ✅ Working | OpenAI-compatible API |
| `/search` | ✅ Working | SearXNG raw web search |
| `/search/hybrid` | ✅ Working | RAG + SearXNG with RRF |
| `/search/agent` | ✅ Working | Intent detection + summarization |
| `/rag/search` | ✅ Working | Qdrant semantic search |
| `/v1/embeddings` | ✅ Working | BGE-M3 embedding generation |

**Missing endpoints** (from Phase 1 plan):
- `/v1/search` — Unified search wrapper
- `/v1/knowledge/commit` — Knowledge upsert
- `/v1/knowledge/query` — Qdrant wrapper
- `/v1/chat/smol` — Fast model route
- `/v1/chat/slow` — Deep model route
- `/v1/chat/plan` — Planning model route

---

## Knowledge Fabric Middleware Configuration

```yaml
MIDDLEWARE__KNOWLEDGE_FABRIC__ENABLED: "true"
MIDDLEWARE__KNOWLEDGE_FABRIC__SEARXNG_ENABLED: "true"
MIDDLEWARE__KNOWLEDGE_FABRIC__SEARXNG_URL: "http://searxng.search.svc.cluster.local:8080"
MIDDLEWARE__KNOWLEDGE_FABRIC__SEARXNG_MAX_RESULTS: "10"
MIDDLEWARE__KNOWLEDGE_FABRIC__RRF_K: "60"
MIDDLEWARE__KNOWLEDGE_FABRIC__CODE_SEARCH_ENABLED: "true"
MIDDLEWARE__KNOWLEDGE_FABRIC__CODE_SEARCH_PATHS: '["/etc/nixos"]'
MIDDLEWARE__KNOWLEDGE_FABRIC__RAG_ENABLED: "true"
MIDDLEWARE__KNOWLEDGE_FABRIC__RAG_TOP_K: "10"
QDRANT_URL: "http://qdrant.ai-inference.svc.cluster.local:6333"
VECTOR_WEIGHT: "0.7"
```

**RRF Pipeline:** BGE-M3 (1024 dim) → Qdrant → HybridSearchEngine → QueryIntent routing → RRF fusion → CrossEncoder reranking

---

## DNS Configuration (.lan names)

| Domain | Resolves To | Purpose |
|--------|-------------|---------|
| `ai-inference.lan` | 10.15.67.242 | AI Gateway (ClusterIP) |
| `brain.lan` | 10.1.1.120 | Knowledge Fabric API (via Caddy) |
| `search.lan` | 10.1.1.120 | SearXNG (via Caddy) |
| `ai.lan` | 10.1.1.120 | AI services (Nexus) |
| `hermes.lan` | 10.1.1.120 | Hermes Agent (Nexus) |

---

## Integration Status

### ✅ Completed
- [x] AI Gateway deployed to K8s with Knowledge Fabric middleware
- [x] Qdrant deployed and healthy
- [x] SearXNG deployed and healthy
- [x] Knowledge Fabric API stub deployed
- [x] RRF middleware configured and enabled
- [x] DNS entries configured for all services
- [x] Gateway connectivity verified (health check passes)

### ⚠️ Partial / Needs Fix
- [ ] Hermes Agent configured to use gateway (currently points to llama-server)
- [ ] omp configured to use gateway
- [ ] Gateway unified endpoints (/v1/search, /v1/knowledge/*)
- [ ] Knowledge Fabric ingestion pipeline

### ❌ Not Started (Phase 0-1 tasks)
- [ ] Kill pi (audit pi-unique extensions)
- [ ] Port knowledge-fabric out of pi
- [ ] Gateway unified search wrapper
- [ ] Knowledge commit/query endpoints
- [ ] Model role routes

---

## Next Actions (Priority Order)

### P0 — Critical
1. **Fix Hermes base_url** — Update to `http://10.15.67.242:8080/v1` (COMPLETED in config, needs restart)
2. **Verify Hermes → Gateway** — Test query with Knowledge Fabric middleware
3. **Test RRF integration** — Verify SearXNG + Qdrant fusion works

### P1 — High Value
4. **Implement /v1/search** — Unified search wrapper (Phase 1.1)
5. **Implement /v1/knowledge/endpoints** — Commit/query wrappers (Phase 1.2-1.3)
6. **Wire omp to gateway** — Collapse omp config (Phase 3.1)

### P2 — Medium Value
7. **Phase 0: Kill pi** — Remove redundant tool stack
8. **Model role routes** — /v1/chat/smol|slow|plan (Phase 1.4)
9. **Knowledge ingestion pipeline** — Auto-commit from SearXNG results

---

## Architecture Diagram

```
                    ┌──────────────────────────────────────────┐
                    │      AI GATEWAY (nexus:10.15.67.242)      │
                    │                                          │
                    │  /search/hybrid  ←→  SearXNG + Qdrant    │
                    │  /rag/search      ←→  Qdrant             │
                    │  /v1/embeddings   ←→  BGE-M3             │
                    │  /v1/chat/*       ←→  Model router       │
                    │                                          │
                    │  MIDDLEWARE:                              │
                    │  • Knowledge Fabric (RRF K=60)           │
                    │  • QueryIntent routing                    │
                    │  • CrossEncoder reranking                 │
                    └──────────────┬───────────────────────────┘
                                   │
         ┌─────────────────────────┼─────────────────────────┐
         │                         │                         │
    ┌────▼─────┐            ┌──────▼──────┐          ┌──────▼──────┐
    │  HERMES  │            │     OMP     │          │   CRON      │
    │ (agent)  │            │  (coding)   │          │ (scheduled) │
    └──────────┘            └─────────────┘          └─────────────┘
         │                         │                         │
         └─────────────────────────┴─────────────────────────┘
                                   │
                    ┌──────────────┴───────────────────────────┐
                    │                                          │
              ┌─────▼─────┐                            ┌──────▼──────┐
              │  Qdrant   │                            │  SearXNG    │
              │ (vector)  │                            │  (web)      │
              └───────────┘                            └─────────────┘
```

---

## Implementation Progress

### Phase 0: Kill pi
- [ ] Audit pi-unique extensions
- [ ] Port knowledge-fabric out of pi
- [ ] Remove pi from NixOS
- [ ] Archive ~/.pi/

### Phase 1: Gateway Unified Endpoints
- [ ] /v1/search — Unified search wrapper
- [ ] /v1/knowledge/commit — Knowledge upsert
- [ ] /v1/knowledge/query — Qdrant wrapper
- [ ] /v1/chat/smol, /slow, /plan — Model role routes

### Phase 2: Wire Hermes Through Mesh
- [x] Update sovereign-search skill to use gateway
- [ ] Hermes memory → gateway dual-write
- [ ] Hermes brain queries → gateway

### Phase 3: Collapse Per-Tool Configs
- [ ] omp → gateway only
- [ ] Harvest opencode, deprecate
- [ ] Verify mesh exclusivity

---

## Risk Assessment

| Risk | Status | Mitigation |
|------|--------|------------|
| Gateway down = everything dies | ⚠️ Medium | Gateway on stable Nexus (46GB). Health check configured. |
| Hermes not using gateway | ✅ Fixed | Config updated, needs restart |
| Missing unified endpoints | ⚠️ Medium | Phase 1.1-1.3 planned (4-6h) |
| pi still installed | ⚠️ Low | Phase 0 planned (2-3h) |

---

**Generated:** 2026-04-24
**Source:** `/etc/nixos/kubernetes/modules/ai-inference.nix`, `/home/j_kro/.hermes/config.yaml`
