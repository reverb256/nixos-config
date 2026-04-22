# Sovereign Service Mesh — Implementation Plan

**Date:** 2026-04-22
**Status:** DRAFT — awaiting founder approval
**Deadline driver:** ZAI expires May 8 — all work must be local-first before then

---

## Executive Summary

Collapse 4 parallel tool stacks (Hermes, omp, opencode, pi) into a single sovereign service mesh. Every tool becomes a thin client pointing at the AI gateway. The gateway already has ~80% of the needed infrastructure — this plan fills the gaps and cuts the dead weight.

---

## Current State (What Exists)

### Gateway (nexus:8080) — already powerful
```
/search              — SearXNG raw web search
/search/hybrid       — RAG + SearXNG with intent routing + reranking
/search/agent        — Intent detection + summarization
/rag/search          — Qdrant semantic search (brain-wiki)
/rag/collections     — List Qdrant collections
/v1/embeddings       — BGE-M3 embedding generation
/v1/chat/completions — Model routing (Qwen3.6→:1237, SGemma→:1236, Qwen3.5→:1235)
```

**RAG pipeline:** BGE-M3 (1024 dim, sparse+dense), Qdrant, HybridSearchEngine with QueryIntent routing (REALTIME/CODE/FACTUAL/PROCEDURAL/COMPARATIVE/CONTEXTUAL), RRF fusion, CrossEncoder reranking.

**KEY INSIGHT: The search mesh ALREADY EXISTS.** `/search/hybrid` + `/search/agent` together provide classify→route→merge→rerank→summarize. The pieces just need a unified wrapper.

### Knowledge Fabric (TypeScript pi extension)
- Manages brain/core/CORE.md, brain/daily/, brain-wiki Qdrant collection
- Ingests→chunks→embeds→upserts to Qdrant
- Query-v2 with semantic search
- Runs as pi extension (pi-ai / pi-coding-agent npm packages)

### pi (the agent)
- Unique: hive, harness, local-model-discovery, model-router, claude-rules.ts
- Shared with omp: brain, commit-hygiene, nixos-guard, pre-code-guard, pre-push-guard, runtime-verify, scope-guard, secret-scanner, stuck-escape-hatch, style-scout

### omp (primary coding agent)
- 16 extensions: brain, chain-checkpoint, agent-compositor, diff-quality-scorer, repo-graph, session-analytics, skill-mcp-loader
- No config.yml found — runs from defaults or env vars
- Worktree isolation, chain state, extension system = real value

### Hermes
- Persistent memory tool (separate from Qdrant)
- spoc-search.py (thin SearXNG wrapper)
- brain-query.py (direct Qdrant queries)
- Native MCP client, WhatsApp bridge, API server (8642)

---

## Gap Analysis

| Capability | Gateway Has It? | Missing |
|------------|-----------------|---------|
| Web search (SearXNG) | YES | — |
| RAG search (Qdrant) | YES | — |
| Hybrid search (both) | YES | — |
| Intent detect + summarize | YES | — |
| Model routing | YES | Role routes (smol/slow/plan) |
| Knowledge commit/upsert | PARTIAL | Need /v1/knowledge/commit |
| Unified search wrapper | NO | Need /v1/search auto-pick |
| Cross-tool session state | NO | Need /v1/sessions (Phase 2) |
| Per-tool config unification | NO | Each tool has own configs |

**The plan is mostly wiring, not building.**

---

## Phase 0: Kill pi (Day 1)

**Rationale:** pi's unique value (hive, harness, model-router, local-model-discovery) is replaced by the mesh or not needed post-ZAI. omp already has overlapping extensions.

### Steps
1. **Audit pi-unique extensions:**
   - hive → replaced by omp tmux orchestration. Kill.
   - harness → omp has equivalent. Kill.
   - local-model-discovery → gateway handles. Kill.
   - model-router → gateway handles. Kill.
   - claude-rules.ts → port to omp or Hermes skill if useful.

2. **Port knowledge-fabric out of pi:**
   - Option A: Rewrite as gateway endpoint (preferred, mesh-native)
   - Option B: Standalone CLI tool via gateway
   - Option C: Run as omp extension (interim — omp has brain ext)
   - **Recommendation: Option C interim, Option A in Phase 1**

3. **Remove pi from NixOS:**
   - Remove from system packages
   - Archive ~/.pi/ → ~/.archive/pi-2026-04-22/
   - Remove pi refs in justfile, scripts, crons

### Deliverables
- [ ] pi removed from system packages
- [ ] ~/.pi/ archived
- [ ] knowledge-fabric still operational via omp
- [ ] No broken references

---

## Phase 1: Gateway Unified Endpoints (Days 2-4)

### Step 1.1: /v1/search — Unified Search Wrapper

```python
@app.post("/v1/search")
async def unified_search(request: Request):
    """
    Single sovereign search endpoint.
    Auto-classifies query → routes to best pipeline → returns structured result.
    
    Body: {
        "query": str,
        "mode": "auto" | "web" | "local" | "hybrid",  # default: auto
        "summarize": bool,  # default: true
        "collection": str,  # default: "brain-wiki"
        "max_results": int,  # default: 10
    }
    
    Response: {
        "answer": str,       # summarized answer
        "sources": [...],    # all sources with scores
        "intent": str,       # detected intent
        "mode_used": str,    # actual mode used
        "novel": bool,       # new-to-brain info?
        "confidence": str,   # high/medium/low
    }
    """
```

**Implementation:** ~100 lines in main.py. Reuses HybridSearchEngine + AgentSearchEngine. Auto mode uses QueryIntent classification. Summarize calls internal /v1/chat/completions. Novel detection via cosine distance against Qdrant top matches.

### Step 1.2: /v1/knowledge/commit — Knowledge Upsert

```python
@app.post("/v1/knowledge/commit")
async def knowledge_commit(request: Request):
    """
    Commit knowledge to the brain.
    Body: {
        "content": str,
        "source": str,  # "hermes" | "omp" | "search" | "manual"
        "metadata": {...},
        "collection": str,  # default: "brain-wiki"
    }
    """
```

Reuses existing RAG pipeline (chunk→embed→upsert). Adds source tracking metadata.

### Step 1.3: /v1/knowledge/query — Wrapper

Thin wrapper over /rag/search with v1 API convention. Auto-discovers collections.

### Step 1.4: Model Role Routes

```python
@app.post("/v1/chat/smol")   # → SuperGemma4 (fast)
@app.post("/v1/chat/slow")   # → Qwen3.6-35B (deep)
@app.post("/v1/chat/plan")   # → Qwen3.6-35B + planning system prompt
```

Post-ZAI: slow → NIM Qwen3 Coder 480B, plan → NIM DeepSeek V3.1

### Deliverables
- [ ] /v1/search endpoint working
- [ ] /v1/knowledge/commit endpoint working
- [ ] /v1/knowledge/query endpoint working
- [ ] /v1/chat/smol, /v1/chat/slow, /v1/chat/plan working
- [ ] Gateway redeployed to nexus
- [ ] Tested with curl

---

## Phase 2: Wire Hermes Through Mesh (Days 4-5)

### Step 2.1: Hermes search → gateway /v1/search
- Update sovereign-search skill to default to gateway
- Keep spoc-search.py as emergency fallback

### Step 2.2: Hermes memory → gateway /v1/knowledge/commit
- Dual-write: local store (primary, Hermes reads every session) + gateway (secondary, cross-tool access)
- Create Hermes skill/hook that calls gateway after memory writes
- (Hermes Agent upstream doesn't expose memory write hooks — workaround via skill discipline)

### Step 2.3: Hermes brain queries → gateway /v1/knowledge/query
- Update brain-query.py to hit gateway
- Keep direct Qdrant as fallback

### Deliverables
- [ ] sovereign-search skill updated
- [ ] brain-query.py updated
- [ ] Memory dual-write tested
- [ ] Fallback paths verified

---

## Phase 3: Collapse Per-Tool Configs (Days 5-7)

### Step 3.1: omp → gateway only
```yaml
# Target omp config
gateway: http://nexus:8080/v1
agents: ~/.omp/agent/agents/
extensions: ~/.omp/agent/extensions/
chains: ~/.omp/agent/chains/
task:
  isolation:
    mode: worktree
    merge: patch
async:
  maxJobs: 10
```

- omp model config → baseURL at gateway
- omp brain extension → gateway /v1/knowledge/query
- omp search → gateway /v1/search
- omp self-learning → gateway /v1/knowledge/commit

### Step 3.2: Harvest opencode, deprecate
1. Port 16 MCP server configs to Hermes native MCP client
2. Port PR review pattern to Hermes skill or omp agent
3. Remove opencode binary
4. Archive config

### Step 3.3: Verify mesh exclusivity
- [ ] Hermes: search, memory, brain → all through gateway
- [ ] omp: models, brain, search → all through gateway
- [ ] Crons: scheduled tasks → all through gateway
- [ ] No hardcoded service URLs outside gateway config

---

## Phase 4: Post-ZAI Model Tuning (May 8+)

Fallback chain after ZAI dies:
```
default → Qwen3.6-35B (zephyr:1237, 3090 24GB)
smol    → SuperGemma4 (zephyr:1236, 3060Ti 8GB)
rocsmol → Qwen3.5-4B (sentry:1235, 5600XT)
slow    → NIM Qwen3 Coder 480B (free tier)
plan    → NIM DeepSeek V3.1 (free tier)
fallback → Pollinations (free, uncensored)
```

- [ ] Remove ZAI from gateway fallback chain
- [ ] Test NIM models for coding quality
- [ ] Finalize role assignments

---

## Phase 5: Evaluate omp's Future (May 10+)

**Keep omp if:** extension system, worktree isolation, chain state provide genuine value over delegate_task
**Kill omp if:** mesh makes it redundant — port remaining extensions to Hermes skills

---

## Architecture After Completion

```
                ┌──────────────────────────────────┐
                │     AI GATEWAY (nexus:8080)       │
                │                                   │
                │  /v1/search         (unified)     │
                │  /v1/knowledge/query (Qdrant)     │
                │  /v1/knowledge/commit             │
                │  /v1/embeddings                   │
                │  /v1/chat/completions (router)    │
                │  /v1/chat/smol | slow | plan      │
                │                                   │
                │  Backends:                        │
                │  SearXNG:30888 Qdrant:6333        │
                │  Qwen3.6:1237  SGemma:1236        │
                │  Qwen3.5:1235  NIM/Pollinations   │
                └──────────────┬───────────────────┘
                               │
          ┌────────────────────┼────────────────────┐
          │                    │                    │
    ┌─────▼─────┐      ┌──────▼──────┐     ┌──────▼──────┐
    │  HERMES    │      │    OMP      │     │  CRON JOBS  │
    │  (SPOC)    │      │  (coding)   │     │  (scheduled)│
    └────────────┘      └─────────────┘     └─────────────┘
         all calls through gateway only
```

---

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Gateway down = everything dies | CRITICAL | systemd on nexus (46GB, stable). Health check + auto-restart. Direct fallback in scripts. |
| main.py is 5261 lines | MEDIUM | New endpoints ~100 lines each. Extract to routes/ if needed later. |
| omp config mechanism unknown | LOW | Investigate omp's actual config loading. |
| ZAI dies before mesh ready | MEDIUM | Gateway already routes to local models. Mesh works without ZAI. |
| Knowledge-fabric port | MEDIUM | omp brain ext as interim. Gateway endpoint long-term. |

---

## Effort Estimates

| Phase | Time | Complexity |
|-------|------|------------|
| Phase 0: Kill pi | 2-3h | Low |
| Phase 1: Gateway endpoints | 4-6h | Medium |
| Phase 2: Wire Hermes | 2-3h | Low |
| Phase 3: Collapse configs | 3-4h | Medium |
| Phase 4: Post-ZAI tuning | 2-3h | Low |
| **Total** | **13-19h** | |

---

## Build Order (Priority)

1. Phase 0 — kill pi (immediate, low risk)
2. Phase 1.1 — /v1/search (highest value)
3. Phase 1.4 — model role routes
4. Phase 1.2-1.3 — knowledge endpoints
5. Phase 3.1 — wire omp to gateway
6. Phase 2 — wire Hermes to mesh
7. Phase 3.2 — harvest opencode
8. Phase 4 — post-ZAI tuning (May 8)
9. Phase 5 — evaluate omp's future
