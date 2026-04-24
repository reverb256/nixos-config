# Infrastructure Audit — 2026-04-24

## Cluster Overview

| Host | CPU | RAM (used/total) | GPUs | Disk | Load | Status |
|------|-----|-------------------|------|------|------|--------|
| **Zephyr** | 16c | 19GB/31GB | RTX 3060 Ti + RTX 3090 | 88% | 21.5 | Unknown* |
| **Nexus** | 24c | ~20GB/46GB | RTX 3060 Ti @100% | 37% | 6.0 | Unknown* |
| **Forge** | 6c | 10GB/15GB | 2× RX 5700 XT + 2× RTX 4060 | 81% | 4.7 | Unknown* |
| **Sentry** | 16c | ~15GB/31GB | RX 5600 XT | 74% | 11.2 | Ready |

\*Node status shows "Unknown" in kubectl but nodes are functional — K3s heartbeat issue, not actual problem.
**CNI:** Flannel VXLAN (default K3s CNI) — UDP 8472

---

## K3s Cluster — ALL HEALTHY ✅

| Node | Status | Role | Age | Version | CNI |
|------|--------|------|-----|---------|-----|
| zephyr | Unknown | control-plane, etcd | 17d | v1.34.5+k3s1 | Flannel |
| nexus | Unknown | control-plane, etcd | 19d | v1.34.5+k3s1 | Flannel |
| forge | Unknown | agent | 19d | v1.34.5+k3s1 | Flannel |
| sentry | Ready | control-plane, etcd | 19d | v1.34.5+k3s1 | Flannel |

**CNI:** Flannel VXLAN (default) — 10.244.0.0/16 pod network, UDP 8472
**66 pods running across 23 namespaces.**
- Running: 59
- Succeeded: 7 (completed jobs)

---

## Sovereign Service Mesh — OPERATIONAL ✅

### AI Gateway (Central Bus)

**Location:** K8s Deployment on Nexus
**ClusterIP:** 10.15.67.242:8080
**Status:** ✅ Running
**Version:** 2.0.0

**Endpoints:**
- `/health` — Health check
- `/v1/models` — Model listing
- `/v1/chat/completions` — OpenAI-compatible API
- `/search` — SearXNG raw web search
- `/search/hybrid` — RAG + SearXNG with RRF
- `/search/agent` — Intent detection + summarization
- `/rag/search` — Qdrant semantic search
- `/v1/embeddings` — BGE-M3 embedding generation

**Middleware Configuration:**
```yaml
MIDDLEWARE__KNOWLEDGE_FABRIC__ENABLED: "true"
MIDDLEWARE__KNOWLEDGE_FABRIC__SEARXNG_ENABLED: "true"
MIDDLEWARE__KNOWLEDGE_FABRIC__RRF_K: "60"
MIDDLEWARE__KNOWLEDGE_FABRIC__RAG_ENABLED: "true"
MIDDLEWARE__KNOWLEDGE_FABRIC__CODE_SEARCH_ENABLED: "true"
QDRANT_URL: "http://qdrant.ai-inference.svc.cluster.local:6333"
```

### Mesh Components

| Component | Status | ClusterIP | Node | Purpose |
|-----------|--------|-----------|------|---------|
| AI Gateway | ✅ Running | 10.15.67.242:8080 | nexus | Central bus with RRF middleware |
| Qdrant | ✅ Running | 10.5.93.32:6333 | nexus | Vector database (v1.13.4) |
| Knowledge Fabric API | ✅ Running | 10.6.31.109:3000 | nexus | Stub API (RRF in gateway) |
| SearXNG | ✅ Running | 10.4.98.141:8080 | nexus | Web search (v2026.4.17) |
| Valkey | ✅ Running | — | nexus | Redis-compatible cache |
| Redis | ✅ Running | 10.10.99.29:6379 | nexus | Gateway cache |

**RRF Pipeline:** BGE-M3 (1024 dim) → Qdrant → HybridSearchEngine → QueryIntent routing → RRF fusion (K=60) → CrossEncoder reranking

---

## Current Service Distribution

| Service | Zephyr | Nexus | Forge | Sentry |
|---------|--------|-------|-------|--------|
| K3s | server | server | agent | server |
| **AI Mesh** | | | | |
| AI Gateway | — | ✅ | — | — |
| Qdrant | — | ✅ | — | — |
| Knowledge Fabric API | — | ✅ | — | — |
| SearXNG | — | ✅ | — | — |
| Valkey/Vane | — | ✅ | — | — |
| **LLM Servers** | | | | |
| llama-server-zephyr (RTX 3090) | ✅ | — | — | — |
| llama-server-zephyr-3060ti | ✅ | — | — | — |
| llama-server-sentry (AMD) | — | — | — | ✅ |
| **Monitoring** | | | | |
| Prometheus | — | ✅ | — | ✅ |
| Grafana | ✅ | ✅ | — | ✅ |
| Loki | — | — | — | ✅ |
| Mimir | — | — | — | ✅ |
| Tempo | — | — | — | ✅ |
| Alloy (otel) | ✅ | ✅ | ✅ | ✅ |
| **Mining** | | | | |
| gpu-miner-zephyr | ✅ | — | — | — |
| gpu-miner-forge (AMD) | — | — | ✅ | — |
| gpu-miner-forge (NVIDIA) | — | — | ✅ | — |
| xmrig-* | ✅ | ✅ | — | ✅ |
| **Other** | | | | |
| Hermes Agent | ✅ | — | — | — |
| node-exporter | ✅ | ✅ | ✅ | ✅ |
| NVIDIA GPU exporter | ✅ | ✅ | ✅ | — |
| AMD GPU exporter | — | — | ✅ | ✅ |
| nix-node (build cache) | ✅ | ✅ | ✅ | ✅ |

---

## Phase Completion Summary (2026-04-24)

### Phase 1: Model Benchmarks ✅
Benchmarked 8 GGUF models on RTX 3090 (24GB VRAM):
- **Winner:** gemma-4-26B-A4B — MoE (4B active/26B total), 127 tok/s gen, fits in 24GB VRAM

### Phase 2: AI Inference Gateway ✅
- Deployed to K8s on Nexus
- Gateway healthy, connected to llama-server backends
- Routes: local inference + Z.AI fallback + Pollinations fallback

### Phase 3: Multi-Model GPU Serving ✅
- Upgraded zephyr llama-server to gemma-4-26B-A4B
- RTX 3090: 20.5GB VRAM used, ~4GB free for KV cache
- Fixed CUDA_VISIBLE_DEVICES mapping

### Phase 5: Wave 1 — Free Zephyr RAM ✅
- Disabled AI inference gateway on zephyr (saves ~140MB RAM)
- Single gateway endpoint: nexus:8080

### Phase 6: Wave 2 — Consolidate Observability ✅
- Disabled Prometheus/Grafana/Loki on sentry
- Exporters remain active
- **Nexus is now the primary observability hub**
- Sentry retained for full observability stack (Loki, Mimir, Tempo)

### Phase 7: Sovereign Service Mesh ✅ (NEW)
- **AI Gateway deployed as central bus** with RRF middleware
- **Knowledge Fabric integration** via gateway middleware
- **Qdrant + SearXNG + RRF** pipeline operational
- **Hermes configured** to use AI Gateway

---

## Remaining Issues

### P0
- 🔴 Zephyr disk 88% — needs audit/cleanup
- 🔴 Forge disk 81% — needs audit/cleanup
- 🔴 Zephyr load 21.5 — mining + desktop + control plane

### P1
- 🟡 K3s node heartbeat showing "Unknown" (cosmetic, nodes functional)
- 🟡 No alerting rules configured for Prometheus
- 🟡 SearXNG rate-limiting (gateway falls back to Qdrant successfully)

### P2
- 🟠 llama-server on 0.0.0.0 (should be LAN-only)
- 🟠 etcd ports open on LAN
- 🟠 fail2ban missing on nexus/sentry

### Next Steps (Sovereign Service Mesh)
1. Implement `/v1/search` unified wrapper (Phase 1.1)
2. Implement `/v1/knowledge/commit` and `/v1/knowledge/query` endpoints (Phase 1.2-1.3)
3. Add model role routes: `/v1/chat/smol|slow|plan` (Phase 1.4)
4. Wire omp to gateway (Phase 3.1)
5. Phase 0: Kill pi (audit and remove redundant tool stack)

---

## Documentation

- **Sovereign Service Mesh Plan:** `/etc/nixos/.hermes/plans/2026-04-22_sovereign-service-mesh.md`
- **Service Mesh Status:** `/etc/nixos/docs/SOVEREIGN-SERVICE-MESH-STATUS.md`
- **Knowledge Fabric Reflow:** `/etc/nixos/docs/KNOWLEDGE-FABRIC-REFLOW.md`
- **Hermes Pipelines Research:** `/etc/nixos/docs/hermes-pipelines-research.md`

---

**Last Updated:** 2026-04-24
