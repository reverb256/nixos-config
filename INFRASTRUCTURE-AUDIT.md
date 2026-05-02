# Infrastructure Audit — 2026-05-01

## Cluster Overview

| Host | CPU | RAM (used/total) | GPUs | Disk | Load | Status |
|------|-----|-------------------|------|------|------|--------|
| **Zephyr** | 16c | 18GB/31GB | RTX 3060 Ti + RTX 3090 | 86% | ~5 | Unknown* |
| **Nexus** | 24c | ~20GB/46GB | RTX 3060 Ti | 37% | ~6 | Unknown* |
| **Forge** | 6c | ~10GB/15GB | 2× RX 5700 XT + 2× RTX 4060 | 81% | ~5 | Unknown* |
| **Sentry** | 16c | ~15GB/31GB | RX 5600 XT | 74% | ~11 | Unknown* |

*All nodes show Unknown — kubelet not reporting Ready condition. Pods run fine, cosmetic issue.
**CNI:** Flannel VXLAN (default K3s CNI) — UDP 8472

---

## K3s Cluster

| Node | Status | Role | Age | Version | CNI |
|------|--------|------|-----|---------|-----|
| zephyr | Unknown | control-plane, etcd | 24d | v1.34.5+k3s1 | Flannel |
| nexus | Unknown | control-plane, etcd | 2d | v1.34.5+k3s1 | Flannel |
| forge | Unknown | agent | 26d | v1.34.5+k3s1 | Flannel |
| sentry | Unknown | control-plane, etcd | 26d | v1.34.5+k3s1 | Flannel |

**CNI:** Flannel VXLAN (default) — 10.244.0.0/16 pod network, UDP 8472
**~56 pods running across 24 namespaces.**

**Note:** ClusterIP unreachable from host (kube-proxy in container, no iptables DNAT). Fixed by routing 10.0.0.0/12 via Flannel gateway + NodePort for Caddy routes.


---

## Central SSO Authentication

### Architecture

Centralized OAuth2 Proxy (oauth2-proxy v7.15.2) on zephyr + nexus, backed by Casdoor OIDC at auth.lan.
All protected services use Caddy `forward_auth` to enforce authentication.

### Service Classification

| Type | Services | Expected Status |
|------|----------|-----------------|
| Public (no auth) | searxng.lan, ai-inference.lan | 200 |
| Protected (SSO) | haven.lan, openwebui.lan, kagent.lan, grafana.lan, mission-control.lan | 401 → login redirect |
| Auth endpoint | auth.lan (Casdoor) | 200 |

### Routing

- All `.lan` services resolve to VIP 10.1.1.100 (keepalived MASTER on zephyr)
- **Zephyr Caddy** (`caddy-routes.nix`): mkAuthRoute for protected, mkRoute for public
- **Nexus Caddy** (`cluster-services.nix`): `protected = true` flag per service
- Both Caddys proxy auth checks to local oauth2-proxy on port 4180

### Key Files

| File | Purpose |
|------|---------|
| `modules/services/central-auth.nix` | oauth2-proxy NixOS module (runs on zephyr + nexus) |
| `hosts/zephyr/caddy-routes.nix` | Zephyr Caddy route definitions |
| `modules/services/cluster-services.nix` | Nexus Caddy + service registry |
| `modules/network/cluster-dns.nix` | Unbound DNS with .lan local-zone |

### Cleanup Done (2026-05-02)

- Removed oauth2-proxy sidecars from ALL K8s pods (haven, openwebui, kagent-ui, mission-control, llama-server-sentry, llama-server-zephyr-3090-moe)
- Deleted 8 orphaned K8s Ingress resources (referenced non-existent `caddy` IngressClass)
- Removed stale `llama.zephyr.lan` Caddy route
- Fixed unbound `local-zone "lan." static` declaration (was missing from generated config)

---

## MCP Infrastructure — 2026-05-01

### In-Cluster MCP Servers

| Server | Type | Namespace | Node(s) | Transport | Status |
|--------|------|-----------|---------|-----------|--------|
| kubernetes-mcp | Deployment | infra | nexus | SSE :8080 | Running |
| nixos-cluster-mcp | DaemonSet | infra | all 4 | SSE :8081 | Running (4 pods) |

### Claude Code MCP (18 servers)

| Status | Count | Servers |
|--------|-------|---------|
| Working | 11 | context-mode, context7, git, fetch, filesystem, zread, sonatype-guide, chrome-devtools, playwright, kubernetes, nixos-cluster |
| Broken | 7 | nixos, grep-app, searxng, gateway, web-reader, pinecone, web-search-prime |
| Needs auth | 2 | sentry, gitlab |

### Hermes MCP (6 servers)

| Server | Transport | Status |
|--------|-----------|--------|
| lightpanda | stdio | Working |
| bsky | stdio | Working |
| casdoor | stdio bridge | Working |
| nixos-cluster | stdio | Working |
| searxng | stdio | Working |
| kubernetes | SSE | Working |

### MCP Gateway Infrastructure

| Component | Status | Notes |
|-----------|--------|-------|
| Casdoor SSO | Running | Central SSO operational, OIDC auth for all protected services |
| mcp-gateway-bridge | Not deployed | Superseded by direct NixOS Caddy routes |
| mcp-server-registry.nix | Partial | 13 servers defined, not generating downstream configs |
| nixkube CSI | Running | nix-node DaemonSet on all 4 nodes |
| RemoteMCPServer CRD | Installed | 0 instances |
| mcp-proxy | Not deployed | Needed for Casdoor tool sync with stdio servers |

**Full plan:** `docs/plans/2026-05-01-mcp-system-plan.md`

---

## Sovereign Service Mesh — OPERATIONAL

### AI Gateway (Central Bus)

**Location:** K8s Deployment on Nexus
**NodePort:** 10.1.1.110:30880 (Caddy routes via NodePort, not ClusterIP)
**Status:** Running

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
| AI Gateway | Running | 10.15.67.242:8080 | nexus | Central bus with RRF middleware |
| Qdrant | Running | 10.5.93.32:6333 | nexus | Vector database |
| Knowledge Fabric API | Running | 10.6.31.109:3000 | nexus | Stub API (RRF in gateway) |
| SearXNG | Running | 10.4.98.141:8080 | nexus | Web search |

---

## Service Distribution

| Service | Zephyr | Nexus | Forge | Sentry |
|---------|-------|-------|-------|--------|
| K3s | server | server | agent | server |
| **AI Mesh** | | | | |
| AI Gateway | — | Running | — | — |
| Qdrant | — | Running | — | — |
| SearXNG | — | Running | — | — |
| **MCP** | | | | |
| kubernetes-mcp | — | Running | — | — |
| nixos-cluster-mcp | Running | Running | Running | Running |
| nixkube CSI | Running | Running | Running | Running |
| **LLM Servers** | | | | |
| llama-server-zephyr | Running | — | — | — |
| llama-server-sentry (AMD) | — | — | — | Running |
| **Monitoring** | | | | |
| node-exporter | Running | Running | Running | Running |
| NVIDIA GPU exporter | Running | Running | Running | — |
| **Mining** | | | | |
| gpu-miner-zephyr | Running | — | — | — |
| gpu-miner-forge (AMD) | — | — | Running | — |
| gpu-miner-forge (NVIDIA) | — | — | Running | — |
| xmrig-* | Running | Running | — | Running |

---

**Last Updated:** 2026-05-02
