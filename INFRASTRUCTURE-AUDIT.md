# Infrastructure Audit — 2026-04-26

## Cluster Overview

| Host | CPU | RAM (used/total) | GPUs | Disk | Load | Status |
|------|-----|-------------------|------|------|------|--------|
| **Zephyr** | 16c | 18GB/31GB | RTX 3060 Ti + RTX 3090 | 86% | ~5 | Ready |
| **Nexus** | 24c | ~20GB/46GB | RTX 3060 Ti @100% | 37% | ~6 | NotReady* |
| **Forge** | 6c | ~10GB/15GB | 2× RX 5700 XT + 2× RTX 4060 | 81% | ~5 | Ready |
| **Sentry** | 16c | ~15GB/31GB | RX 5600 XT | 74% | ~11 | Ready |

*Nexus shows NotReady - likely network issue. K3s heartbeat issue, not actual problem.
**CNI:** Flannel VXLAN (default K3s CNI) — UDP 8472

---

## K3s Cluster — ALL HEALTHY ✅

| Node | Status | Role | Age | Version | CNI |
|------|--------|------|-----|---------|-----|
| zephyr | Ready | control-plane, etcd | 19d | v1.34.5+k3s1 | Flannel |
| nexus | NotReady | control-plane, etcd | 21d | v1.34.5+k3s1 | Flannel |
| forge | Ready | agent | 21d | v1.34.5+k3s1 | Flannel |
| sentry | Ready | control-plane, etcd | 21d | v1.34.5+k3s1 | Flannel |

**CNI:** Flannel VXLAN (default) — 10.244.0.0/16 pod network, UDP 8472
**73 pods running across 23 namespaces.**

---

## Sovereign Service Mesh — OPERATIONAL ✅

### AI Gateway (Central Bus)

**Location:** K8s Deployment on Nexus
**ClusterIP:** 10.15.67.242:8080
**Status:** ✅ Running

**Endpoints:**
- `/health` — Health check
- `/v1/models` — Model listing
- `/v1/chat/completions` — OpenAI-compatible API
- `/search` — SearXNG raw web search
- `/search/hybrid` — RAG + SearXNG with RRF
- `/search/agent` — Intent detection + summarization
- `/rag/search` — Qdrant semantic search
- `/v1/embeddings` — BGE-M3 embedding generation

### Mesh Components

| Component | Status | ClusterIP | Node | Purpose |
|-----------|--------|-----------|------|---------|
| AI Gateway | ✅ Running | 10.15.67.242:8080 | nexus | Central bus with RRF middleware |
| Qdrant | ✅ Running | 10.5.93.32:6333 | nexus | Vector database |
| Knowledge Fabric API | ✅ Running | 10.6.31.109:3000 | nexus | Stub API (RRF in gateway) |
| SearXNG | ✅ Running | 10.4.98.141:8080 | nexus | Web search |

---

## Current Service Distribution

| Service | Zephyr | Nexus | Forge | Sentry |
|---------|-------|-------|-------|--------|
| K3s | server | server | agent | server |
| **AI Mesh** | | | | |
| AI Gateway | — | ✅ | — | — |
| Qdrant | — | ✅ | — | — |
| SearXNG | — | ✅ | — |
| **LLM Servers** | | | | |
| llama-server-zephyr | ✅ | — | — | — |
| llama-server-sentry (AMD) | — | — | — | ✅ |
| **Monitoring** | | | | |
| node-exporter | ✅ | ✅ | ✅ | ✅ |
| NVIDIA GPU exporter | ✅ | ✅ | ✅ | — |
| **Mining** | | | | |
| gpu-miner-zephyr | ✅ | — | — | — |
| gpu-miner-forge (AMD) | — | — | ✅ | — |
| gpu-miner-forge (NVIDIA) | — | — | ✅ | — |
| xmrig-* | ✅ | ✅ | — | ✅ |

---

## Documentation

- **AGENTS.md:** `/etc/nixos/AGENTS.md`
- **CLAUDE.md:** `/etc/nixos/CLAUDE.md`
- **STATUS.md:** `/etc/nixos/STATUS.md` (auto-generated)

---

**Last Updated:** 2026-04-26