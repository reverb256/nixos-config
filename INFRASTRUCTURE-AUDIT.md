# Infrastructure Audit — 2026-05-14

> **⚠️ 9 days old, approaching staleness threshold (7 days). Re-verify key metrics before relying.**

## Cluster Overview

| Host | CPU | RAM (used/total) | GPUs | Disk | Load | K8s Status |
|------|-----|-------------------|------|------|------|------------|
| **Zephyr** | 16c | 6.8GB/31GB (23%) | RTX 3060 Ti + RTX 3090 | 86% | ~4 | Ready |
| **Nexus** | 24c | 9.0GB/46GB (20%) | RTX 3060 Ti | 37% | ~7 | Ready |
| **Forge** | 6c | 3.8GB/15GB (29%) | 2× RX 5700 XT + 2× RTX 4060 | 81% | ~5 | Ready |
| **Sentry** | 16c | 9.8GB/31GB (34%) | RX 5600 XT | 74% | ~11 | Ready |

**CNI:** Flannel VXLAN (default K3s CNI) — UDP 8472

---

## K3s Cluster

| Node | Status | Role | Age | Version | CNI |
|------|--------|------|-----|---------|-----|
| zephyr | Ready | control-plane, etcd | 25d | v1.34.5+k3s1 | Flannel |
| nexus | Ready | control-plane, etcd | 3d | v1.34.5+k3s1 | Flannel |
| forge | Ready | agent | 27d | v1.34.5+k3s1 | Flannel |
| sentry | Ready | control-plane, etcd | 27d | v1.34.5+k3s1 | Flannel |

**CNI:** Flannel VXLAN (default) — 10.244.0.0/16 pod network, UDP 8472
**60 pods running across 22 namespaces.**
**OS:** NixOS 26.05 (Yarara), Kernel 7.0.0-cachyos, containerd 2.1.5-k3s1

**Note:** ClusterIP unreachable from host (kube-proxy in container, no iptables DNAT). Fixed by routing 10.0.0.0/12 via Flannel gateway + NodePort for Caddy routes.

**Stuck pods:** `debug-nexus` in default namespace (CreateContainerConfigError) — orphaned debug pod.

---

## Central SSO Authentication

### Architecture

Centralized OAuth2 Proxy (oauth2-proxy v7) on zephyr + nexus, backed by Casdoor OIDC at auth.lan.
All protected services use Caddy `forward_auth` to enforce authentication. No per-pod sidecars.

### Service Classification

| Type | Services | Expected Status |
|------|----------|-----------------|
| Public (no auth) | searxng.lan, openwebui.lan, dashboard.lan, gitea.lan, vaultwarden.lan, n8n.lan | 200 |
| Protected (SSO) | haven.lan, kagent.lan, grafana.lan, mission-control.lan, qdrant.lan, brain.lan, ai-inference.lan, workspace.lan | 401 → login redirect |
| Native OIDC | grafana.lan (dual), ai-inference.lan (JWT), gitea.lan (direct Casdoor app) | Direct Casdoor auth |
| Auth endpoint | auth.lan (Casdoor) | 200 |

### Native OIDC Audit (2026-05-14)

| Service | Native OIDC | In Use? | Notes |
|---------|-------------|---------|-------|
| Grafana | ✅ Supported | ✅ Wired | `GF_AUTH_GENERIC_OAUTH_*` → Casdoor. Also behind forward_auth. |
| AI Gateway | ✅ JWKS/JWT | ✅ Wired | JWT auth with JWKS from Casdoor. |
| Gitea | ✅ Supported | ✅ Wired | Direct Casdoor app `app-gitea`. |
| Open WebUI | ✅ Supported | ✅ Wired (May 14) | Casdoor app `app-openwebui`. OIDC env vars deployed. |
| n8n | ⚠️ Enterprise | ❌ | Requires license key. |
| Haven, MC, Kagent | ❌ No support | — | Proxy auth is correct approach. |
| Qdrant, Vaultwarden, Workspace | ❌ No support | — | Proxy auth correct. |

### Stale OIDC Secrets

Three K8s secrets defined in Nix modules but **never mounted** (removed sidecar remnants):
`haven-oidc`, `mission-control-oidc`, `kagent-oidc`. Safe to clean up.

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

### Fixes Applied (2026-05-02, Session 2)

- Fixed Grafana K8s OAuth: removed duplicated/conflicting `GF_AUTH_GENERIC_OAUTH_*` env vars (monitoring.nix)
- Fixed Grafana admin-secret namespace: was applying to `ai-inference`, now correctly applies to `monitoring`
- Removed K8s sidecars (haven, kagent, mission-control) — auth now handled by Caddy forward_auth only
- Fixed Service targetPorts: changed from 4180 (removed sidecar) to actual app ports (3000, 8080)
- Removed alert-webhook stub deployment — AlertManager logs directly via Alloy → Loki
- Fixed privacy-filter NetworkPolicy: allows ingress from `ai-inference` and `ingress-system` namespaces

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
| mcp-server-registry.nix | Complete | 17 servers defined, generates Claude Code, Hermes, Kagent CRDs, NetworkPolicies, Casdoor apps |
| nixkube CSI | Running | nix-node DaemonSet on all 4 nodes |
| RemoteMCPServer CRD | Installed | 5 instances (kubernetes, nixos-cluster, searxng, lightpanda, casdoor) |
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

### Known Stubs (need real implementation)

| Component | File | Status |
|-----------|------|--------|
| Knowledge Fabric API | `kubernetes/modules/ai-inference.nix` | Inline Python stub — returns empty results. RRF middleware runs in gateway. Needs Qdrant embedding pipeline. |
| Gaming detection | `kubernetes/modules/host-services.nix` | `sleep infinity` — real detection runs on host via NixOS systemd (needs D-Bus/GameMode) |
| nix-csi | `kubernetes/modules/nix-csi.nix` | Empty module — CSI volumes use hostPath mounts directly |
| Privacy filter | `kubernetes/modules/privacy-filter.nix` | `pip install` at runtime — not a proper container image |

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
| **Monitoring (K8s)** | | | | |
| Grafana | — | — | — | Running (NodePort 32102) |
| Prometheus | — | — | — | Running |
| Loki | — | — | — | Running |
| Mimir | — | — | — | Running |
| Tempo | — | — | — | Running |
| Alloy (DaemonSet) | Running | Running | Running | Running |
| AlertManager | — | — | — | Running |
| **Monitoring (NixOS)** | | | | |
| node-exporter | Running | Running | Running | Running |
| NVIDIA GPU exporter | Running | Running | Running | — |
| **Mining** | | | | |
| gpu-miner-zephyr | Running | — | — | — |
| gpu-miner-forge (AMD) | — | — | Running | — |
| gpu-miner-forge (NVIDIA) | — | — | Running | — |
| xmrig-* | Running | Running | — | Running |

### Grafana Deployment Model

Grafana runs **only as a K8s Deployment** in the `monitoring` namespace on sentry (NodePort 32102).
The NixOS `services.monitoring.grafana` module (`grafana-v2.nix`) is **disabled on all hosts** — it's dead code.
Access: `grafana.lan` → VIP 10.1.1.100 → Zephyr Caddy → `mkAuthRoute` → NodePort 32102 → K8s Grafana.
OAuth via Casdoor SSO (Caddy forward_auth). Grafana also has native `GF_AUTH_GENERIC_OAUTH` configured as fallback.

---

**Last Updated:** 2026-05-14

---

## Security Audit — 2026-05-14

### Blind Spots (10 items)

| # | Issue | Severity | Fix |
|---|-------|----------|-----|
| 1 | 72 secrets in etcd plaintext | P0 | Enable etcd encryption + rotate all |
| 2 | 30+ pods running as root | P0 | runAsNonRoot + drop ALL capabilities |
| 3 | 17 NodePort services bypass Caddy auth | P1 | Firewall NodePort range or ClusterIP migration |
| 4 | Zero runtime security (Falco) | P1 | Deploy Falco DaemonSet |
| 5 | No mTLS, plaintext pod traffic | P2 | Service mesh evaluation |
| 6 | No K8s audit policy | P2 | Enable + ship to Loki |
| 7 | No image scanning | P3 | Trivy admission webhook |
| 8 | No model file integrity | P3 | SHA-256 verification before loading |
| 9 | ai-inference namespace privileged | P3 | Lock to baseline after GPU isolation fixed |
| 10 | No SBOM for any image | P3 | Generate SBOMs |

### Decision Log

| Decision | Rationale | Date |
|----------|-----------|------|
| NodePort restriction (P1) prioritized over secrets encryption (P0) | 17 NodePorts actively bypass auth today. Secrets are high blast radius but lower immediate risk in single-operator homelab. | May 14 |

---

## Tailscale Funnel State — 2026-05-14 (LIVE)

### Architecture

```
Internet → Tailscale Funnel :443 → K8s Operator ProxyGroup → reverse_proxy → backend Pod
```

Funnel is managed entirely through the K8s Tailscale operator. Host-level funnel is disabled.

### Current State

| Component | Status |
|-----------|--------|
| Operator | 1/1 Running on sentry |
| ProxyClass ha-funnel | Anti-affinity, mining toleration, resource limits |
| ProxyGroup funnel-proxies | 2/2 pods, ProxyGroupReady: True |
| Host funnel | Disabled (`tailscale funnel --https=443 off`) |
| Manifests location | `/etc/nixos/kubernetes-manifests/tailscale/` |

### Funnel Ingresses (5 total)

| Namespace | Ingress | Type |
|-----------|---------|------|
| maplespike-dev | maplespike-api | Dev API |
| maplespike-dev | maplespike-portal | Dev Portal |
| maplespike-dev | maplespike-mcp | Dev MCP |
| maplespike | maplespike-api | Prod API |
| maplespike | maplespike-portal | Prod Portal |

### Manifests in Nix Source of Truth

| File | Purpose |
|------|---------|
| `operator.yaml` | Tailscale k8s-operator deployment |
| `funnel-proxyclass.yaml` | ha-funnel ProxyClass (anti-affinity) |
| `funnel-proxygroup.yaml` | funnel-proxies ProxyGroup (2 replicas) |
| `funnel-dev.yaml` | Dev namespace ingresses (api, portal, mcp) |
| `funnel-prod.yaml` | Prod namespace ingresses (api, portal) |

## Recent Infrastructure Changes — 2026-05-14

| Change | Description |
|--------|-------------|
| Open WebUI Casdoor OIDC wired | `app-openwebui` Casdoor app, env vars deployed, GPU rollout fix |
| Gitea DNS fixed | Missing `gitea.lan. A` record added to unbound |
| Unbound config improved | Added `local-dns-extra.conf` include for manual overrides |
| Dev funnel Ingresses affinity | Spread across nexus/sentry/forge, zephyr excluded |
| Corporate + influence ingestion modules | 2,850 lines built across lobbying, procurement, execs, actors |
| Katzilla references purged | All code + docs references removed |

**Last Updated:** 2026-05-14
