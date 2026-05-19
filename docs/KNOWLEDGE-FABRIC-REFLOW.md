# Knowledge Fabric Reflow Architecture
**Goal:** Unify Brain, KB MCP, Hermes, and Knowledge Fabric into autonomous knowledge ecosystem

## Current State (Fragmented)
```
Brain ←→ Qdrant (working)
  ↓
KB MCP ←→ llama-cpp (working but isolated)

Knowledge Fabric (code only, no deploy) ──⊘

Hermes Agent (systemd) ──⊘ Brain
  ↓
Hermes Dashboard (standalone)

Claude Code Router (zephyr:3456) ──?──

SearXNG+Valkey (K8s) ──⊘ (no consumers)

AI Inference Gateway (stopped) ──✕
```

## Target Architecture (Autonomous Flow)

```
┌─────────────────────────────────────────────────────────────────────┐
│                       INGESTION LAYER                                │
├─────────────────────────────────────────────────────────────────────┤
│  Web (SearXNG) → local-html-extract → embeddings → Qdrant         │
│  Git repos → ingest → embeddings → Qdrant                          │
│  Agent sessions → brain_ingest → Qdrant                              │
│  Documents (38 eBooks) → KB MCP ingest → Qdrant                    │
└─────────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────────┐
│                      PROCESSING LAYER                                │
├─────────────────────────────────────────────────────────────────────┤
│  Brain Query: hybrid (vector + keyword) search                        │
│    ↓                                                                │
│  Knowledge Fabric: orchestrates multi-step reasoning               │
│    - SearXNG for web search                                        │
│    - KB MCP for technical docs                                     │
│    - Brain for historical context                                  │
│    - LLM for synthesis                                             │
└─────────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────────┐
│                      CONSUMPTION LAYER                               │
├─────────────────────────────────────────────────────────────────────┤
│  Hermes Agent ← primary interface (natural language)               │
│  Pi Agent ← secondary interface (coding tasks)                      │
│  Claude Code Router ← IDE integration (fallback)                     │
│  Dashboards ← visualization (Grafana + Hermes)                     │
└─────────────────────────────────────────────────────────────────────┘
```

## Connection Points to Implement

### 1. Brain ↔ Knowledge Fabric
**Now:** Brain queries only Qdrant
**Need:** Knowledge Fabric as Brain tool
```
brain_query "how does WiVRn work?"
  → Knowledge Fabric agent:
    1. Search Qdrant (brain-wiki)
    2. Search KB MCP (38 eBooks)
    3. SearXNG web search if gaps
    4. LLM synthesis
    5. Return answer with citations
```

### 2. SearXNG → Brain Ingestion Pipeline
**Now:** SearXNG results discarded after use
**Need:** Valuable results auto-ingested
```
SearXNG query → Valkey cache (dedupe)
  → If result quality > threshold:
    → Fetch content
    → brain_ingest
    → Qdrant
```

### 3. Hermes Agent ↔ Knowledge Fabric
**Now:** Hermes standalone, no knowledge access
**Need:** Hermes uses Knowledge Fabric as backend
```
Hermes query
  → Knowledge Fabric router:
    - Brain context (user history)
    - KB search (technical)
    - SearXNG (current events)
    - LLM synthesis
  → Hermes responds with full context
```

### 4. Pi Agent Integration
**Now:** Pi has brain_query, knowledge base MCP
**Need:** Unified Knowledge Fabric MCP
```
Pi tools:
  - brain_query (existing)
  - knowledge_fabric_query (new - unified)
    - combines brain + kb + searxng + llm
```

## Components to Connect

| Component | Location | Status | Connect To |
|-----------|----------|--------|------------|
| Knowledge Fabric | `/data/projects/knowledge-fabric` | Code only | Deploy to K8s first |
| Hermes Agent | systemd nexus | Running | Connect to Knowledge Fabric API |
| Claude Code Router | systemd zephyr:3456 | Running | Deprecate or integrate |
| AI Gateway | systemd zephyr:8080 | Stopped | Revive or remove |
| SearXNG | K8s | Running | Add ingest pipeline |
| Valkey | K8s | Running | Cache layer for KF |

## Implementation Phases

### Phase 1: Deploy Knowledge Fabric (P0)
```
1. Deploy knowledge-fabric to K8s
2. Test: curl KF_API/health
3. Verify connections:
   - Qdrant (nexus:6333)
   - Valkey (K8s:6379)
   - SearXNG (K8s:7777)
```

### Phase 2: Hermes Integration (P0)
```
1. Add Knowledge Fabric client to hermes-agent
2. Update hermes config to use KF as default backend
3. Test: hermes "explain WiVRn" → uses KF
```

### Phase 3: Brain/KB MCP ↔ KF Bridge (P1)
```
1. Knowledge Fabric exposes MCP endpoint
2. Pi agent adds knowledge_fabric MCP tool
3. Deprecate separate brain_query/kb_query
```

### Phase 4: Autonomous Ingestion (P1) ✅ Implemented 2026-05-19
```
1. Cron job: scan Valkey for high-quality searx results ✅
   - search.CronJob.searxng-ingest: runs every 4 hours
   - Calculates quality score (position, content length, trusted domains, engine count)
   - Threshold: 0.6 (configurable via QUALITY_THRESHOLD env var)
2. Auto-ingest to Qdrant ✅
   - Creates searxng-results collection with 2048-dim Cosine vectors
   - Uses AI Gateway embedding endpoint (BidirLM-Omni-2.5B)
   - Payload: title, url, content, source, quality_score, engines, query, ingested_at
3. Weekly: re-index stale documents ✅
   - search.CronJob.searxng-stale-reindex: runs Sunday at 03:00
   - Re-fetches content and re-embeds documents older than 30 days
   - Tracks reindex_count in payload
```

### Phase 5: Cleanup (P2)
```
1. Deprecate Claude Code Router (if KF replaces)
2. Remove AI Gateway (if unused)
3. Consolidate all knowledge paths through KF
```

## Decision Matrix

| Question | Answer |
|----------|--------|
| Is Knowledge Fabric production-ready? | Code exists, needs deploy |
| Does Hermes need KF? | Yes - currently isolated |
| Keep Claude Code Router? | Evaluate after Hermes+KF working |
| Keep AI Gateway? | Likely remove (hermes handles routing) |
| SearXNG auto-ingest? | Yes, but with rate limiting |

## Next Action
Deploy Knowledge Fabric to K8s (already defined in easykubenix). Verify:
```
kubectl get deploy -n search knowledge-fabric
kubectl logs -n search deploy/knowledge-fabric
```

Then connect Hermes to KF API.
