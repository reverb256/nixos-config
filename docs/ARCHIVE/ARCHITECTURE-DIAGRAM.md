# NixOS Cluster Architecture

**Generated:** 2026-05-02 | **4 Nodes** | **78 Cores / 123GB RAM / 7 GPUs / 8.4TB Storage**

> **⚠️ STALE (21 days old). Resource counts, host roles, and topology may have drifted. Verify before following.**

## Physical Topology

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        LAN 10.1.1.0/24                                 │
│                        VIP: 10.1.1.100 (keepalived)                    │
│                                                                         │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐│
│  │   ZEPHYR     │  │    NEXUS     │  │    FORGE     │  │   SENTRY     ││
│  │  10.1.1.110  │  │  10.1.1.120  │  │  10.1.1.130  │  │  10.1.1.140  ││
│  │              │  │              │  │              │  │              ││
│  │ 31GB RAM     │  │ 46GB RAM     │  │ 15GB RAM     │  │ 31GB RAM     ││
│  │ 2x NVIDIA    │  │ 1x NVIDIA    │  │ 2x NVIDIA    │  │ 1x AMD       ││
│  │ Workstation  │  │ Primary Srv  │  │ GPU Compute  │  │ Monitoring   ││
│  │ Control Plane│  │ AI Gateway   │  │ Mining       │  │ AI Inference ││
│  │ NFS Server   │  │ Storage      │  │              │  │ ROCm (5600XT)││
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘│
│         │ NFS (ro)   │ NFS (ro)   │ NFS (ro)   │              │
└─────────┼────────────┼────────────┼────────────┼──────────────┘
          │            │            │            │
    ┌─────┘            │            │            │
    │ /etc/nixos export│            │            │
    │ (source of truth)│            │            │
    └──────────────────┘────────────┘────────────┘
```

## K3s Kubernetes Cluster

```
K3s v1.34.5+k3s1 — Flannel CNI (VXLAN, UDP 8472)
4 nodes: zephyr (control), nexus, forge, sentry

Namespaces: infra, ai-inference, monitoring, haven, kagent,
            orchestration, automation, nixkube, mining, search
```

## Web Services & Caddy Routing

All `.lan` domains resolve to VIP **10.1.1.100** (keepalived MASTER on zephyr).
Unbound DNS on all nodes: `local-zone "lan." static`.

### Zephyr Caddy (primary ingress)

```
                    ┌─────────────────────────────────────┐
                    │          CADDY (zephyr)              │
                    │         VIP 10.1.1.100              │
                    │         TLS: cluster CA              │
                    └──────────┬──────────────────────────┘
                               │
              ┌────────────────┼────────────────┐
              ▼                ▼                 ▼
     ┌─────────────┐  ┌──────────────┐  ┌──────────────┐
     │   PUBLIC    │  │   PROTECTED  │  │  CASDOOR SSO │
     │  (no auth)  │  │ (Casdoor SSO)│  │  auth.lan    │
     └──────┬──────┘  └──────┬───────┘  │  :8000       │
            │                │           └──────────────┘
            │                │                   │
            │                │           ┌───────┴────────┐
            │                │           │ oauth2-proxy   │
            │                │           │ central-auth   │
            │                │           │ :4180          │
            │                │           └───────┬────────┘
            │                │                   │
            │                └── forward_auth ───┘
            │
            ▼
  ┌──────────────────┐     ┌─────────────────────────────────┐
  │ ai.lan           │     │ 🔒 haven.lan          → :32100 │
  │ → 127.0.0.1:1237 │     │ 🔒 mission-control.lan → :32101 │
  │                  │     │ 🔒 kagent.lan          → :32103 │
  │ ai-inference.lan │     │ 🔒 grafana.lan         → :32102 │
  │ → 10.15.67.242   │     │ 🔒 openwebui.lan       → :32080 │
  │   :8080          │     │ 🔒 llama.zephyr.lan    → :1237  │
  │                  │     │ 🔒 llama.sentry.lan    │
  │ brain.lan        │     │   → 10.1.1.140:1235    │
  │ → 10.244.1.7:3000│     └─────────────────────────────────┘
  │                  │
  │ searxng.lan      │
  │ search.lan       │
  │ → 127.0.0.1:32081│
  └──────────────────┘
```

### Auth Flow

```
Browser → Caddy (.lan) ──→ forward_auth ──→ oauth2-proxy (:4180)
                                                   │
                                          ┌────────┴────────┐
                                          │  Casdoor OIDC   │
                                          │  auth.lan:8000  │
                                          └────────┬────────┘
                                                   │
                                          ┌────────┴────────┐
                                          │  401 → Redirect │
                                          │  to login page  │
                                          └─────────────────┘
```

## AI Infrastructure

```
┌─────────────────────────────────────────────────────────────────────┐
│                      AI INFERENCE GATEWAY                           │
│                    nexus (10.15.67.242:8080)                        │
│                    ai-inference-gateway (K8s)                       │
│                                                                     │
│  100+ models from:                                                  │
│  ┌─────────────┐ ┌──────────────┐ ┌──────────┐ ┌───────────────┐  │
 │  │ Local LLMs  │ │  Z.AI API    │ │ NVIDIA   │                  │  │
 │  │ (llama.cpp) │ │  (cloud)     │ │ NIM      │                  │  │
│  └──────┬──────┘ └──────────────┘ └──────────┘ └───────────────┘  │
│         │                                                           │
│    ┌────┴────────────────────────────────────┐                      │
│    │          Local Llama.cpp Servers         │                      │
│    ├─────────────────────────────────────────┤                      │
│    │                                         │                      │
│    │  ZEPHYR                                 │                      │
│    │  ├─ llama-server-zephyr (TurboQuant)    │                      │
│    │  │  RTX 3090 · llama.cpp Vulkan         │                      │
│    │  ├─ llama-server-zephyr-3090-moe        │                      │
│    │  │  RTX 3090 · MoE models               │                      │
│    │  └─ llama-server-zephyr-3090-dense      │                      │
│    │     RTX 3090 · Dense models             │                      │
│    │                                         │                      │
│    │  NEXUS                                  │                      │
│    │  └─ llama-server (CUDA)                 │                      │
│    │                                         │                      │
│    │  SENTRY                                 │                      │
│    │  └─ (Vulkan inference via llama.cpp)    │                      │
│    │     AMD RX 5600 XT (6GB)                │                      │
│    └─────────────────────────────────────────┘                      │
│                                                                      │
│  ┌──────────────────────────────────────────────┐                   │
│  │            Supporting Services                │                   │
│  │                                               │                   │
│  │  privacy-filter (sentry) ─ PII detection      │                   │
│  │  qdrant (sentry) ── vector DB for RAG         │                   │
│  │  knowledge-fabric-api (nexus) ─ KB service    │                   │
│  │  redis (ai-inference ns) ─ caching            │                   │
│  └──────────────────────────────────────────────┘                   │
└─────────────────────────────────────────────────────────────────────┘
```

## MCP Server Infrastructure

```
┌─────────────────────────────────────────────────────────────────┐
│                    MCP SERVER ECOSYSTEM                          │
│                                                                  │
│  ┌─────────────┐  ┌──────────────────────────────────────────┐  │
│  │   Hermes    │  │        MCP Servers (8 total)              │  │
│  │   Agent CLI │  │                                          │  │
│  │             │  │  ┌──────────────┐  ┌──────────────────┐  │  │
│  │ config.yaml │──│  │ kubernetes   │  │ lightpanda       │  │  │
│  │ (Nix-managed│  │  │ HTTP /mcp    │  │ stdio            │  │  │
│  │  mcp_servers│  │  │ K8s DNS      │  │ headless browser │  │  │
│  │  injection) │  │  │ 21 tools     │  │ 20 tools         │  │  │
│  │             │  │  └──────────────┘  └──────────────────┘  │  │
│  │             │  │                                          │  │
│  │  Injected   │  │  ┌──────────────┐  ┌──────────────────┐  │  │
│  │  at boot by │  │  │ nixos-cluster│  │ searxng          │  │  │
│  │  hermes-mcp │  │  │ stdio (nix)  │  │ stdio (bridge)   │  │  │
│  │  -servers   │  │  │ 15 tools     │  │ 13 tools         │  │  │
│  │  .service   │  │  └──────────────┘  └──────────────────┘  │  │
│  └─────────────┘  │                                          │  │
│                    │  ┌──────────────┐  ┌──────────────────┐  │  │
│                    │  │ casdoor      │  │ web-reader (Z.AI)│  │  │
│                    │  │ stdio (py)   │  │ HTTP             │  │  │
│                    │  │ 5 tools      │  │ 1 tool           │  │  │
│                    │  └──────────────┘  ├──────────────────┤  │  │
│                    │                    │ web-search (Z.AI)│  │  │
│                    │                    │ HTTP             │  │  │
│                    │                    │ 1 tool           │  │  │
│                    │                    ├──────────────────┤  │  │
│                    │                    │ zread (Z.AI)     │  │  │
│                    │                    │ HTTP             │  │  │
│                    │                    │ 3 tools          │  │  │
│                    │                    └──────────────────┘  │  │
│                    └──────────────────────────────────────────┘  │
│                                                                  │
│  API keys: Z.AI keys from agenix, injected at boot              │
│  Registry: modules/services/mcp-server-registry.nix             │
└─────────────────────────────────────────────────────────────────┘
```

## GPU & Mining

```
┌─────────────────────────────────────────────────────────┐
│                    GPU ALLOCATION                        │
│                                                         │
│  ZEPHYR (2x NVIDIA)                                     │
│  ├─ RTX 3090 (24GB) ── llama.cpp TurboQuant + MoE      │
│  └─ RTX 3060 Ti (8GB) ── gpu-miner + dense llama.cpp   │
│                                                         │
│  NEXUS (1x NVIDIA)                                      │
│  └─ RTX 3060 (12GB) ── gpu-miner + llama-server        │
│                                                         │
│  FORGE (2x NVIDIA + 2x AMD)                             │
│  ├─ NVIDIA GPU 0 ── gpu-miner-forge-nvidia-0            │
│  ├─ NVIDIA GPU 1 ── gpu-miner-forge-nvidia-1            │
│  ├─ AMD GPU 0 ──── gpu-miner-forge-amd-0                │
│  └─ AMD GPU 1 ──── gpu-miner-forge-amd-1                │
│                                                         │
│  SENTRY (1x AMD)                                        │
│  └─ RX 5600 XT (6GB) ── Vulkan inference + privacy-filter│
│                                                         │
│  mining-coordinator (zephyr) ── profit switching        │
│  gpu-proxy ── stratum mining proxy                      │
└─────────────────────────────────────────────────────────┘
```

## Monitoring Stack

```
┌─────────────────────────────────────────────────┐
│              MONITORING (monitoring ns)          │
│                                                  │
│  Prometheus (ai-inference ns, nexus)             │
│  ├─ Scrapes: node-exporters, GPU exporters,     │
│  │  AI gateway metrics, kubelet                  │
│  └─ Port: 9090                                  │
│                                                  │
│  Grafana (monitoring ns, sentry)                 │
│  ├─ NodePort: 32102                             │
│  ├─ grafana.lan (Caddy + Casdoor SSO)           │
│  └─ Datasource: Prometheus                      │
│                                                  │
│  Alloy (monitoring ns, 1 per node)              │
│  ├─ Log collection → Loki                       │
│  └─ Host metrics forwarding                     │
│                                                  │
│  Node Exporters (every node)                     │
│  GPU Exporters (NVIDIA: :9400, AMD: :9104)      │
│                                                  │
│  Health Checks (host-level NixOS services)       │
│  ├─ crash-watchdog                              │
│  ├─ self-healing-alerts                         │
│  └─ memory-monitor (CronJob)                    │
└─────────────────────────────────────────────────┘
```

## Key Infrastructure Services

```
┌──────────────────────────────────────────────────────────────┐
│                    SHARED INFRASTRUCTURE                      │
│                                                               │
│  NFS         Zephyr exports /etc/nixos → nexus/forge/sentry  │
│  keepalived  VIP 10.1.1.100, zephyr=MASTER                   │
│  Unbound     DNS on all nodes, .lan local zone               │
│  Casdoor     OIDC SSO at auth.lan (zephyr :8000)             │
│  Caddy       TLS reverse proxy on zephyr + nexus             │
│  Agenix      41 encrypted secrets, decrypted at boot         │
│  Tailscale   VPN mesh, exit node on zephyr                   │
│                                                               │
│  Storage:                                                     │
│  ├─ NFS mounts (config sharing)                              │
│  ├─ Local PVs (fast-local-ssd class on nexus)                │
│  ├─ Garage S3 (backup-to-garage)                             │
│  └─ Syncthing (zephyr/forge/sentry file sync)                │
│                                                               │
│  CI/CD:                                                       │
│  ├─ GitHub Actions (5 workflows, SHA-pinned)                 │
│  ├─ Colmena (multi-host NixOS deploy)                        │
│  └─ kubectl-apply-k8s-secrets (agenix → K8s secrets)         │
└──────────────────────────────────────────────────────────────┘
```

## Data Flow: Request Lifecycle

```
1. User → Browser → https://haven.lan
                    │
2. DNS: haven.lan → 10.1.1.100 (VIP)
                    │
3. keepalived → zephyr (MASTER)
                    │
4. Caddy receives TLS request
                    │
5. forward_auth → oauth2-proxy (:4180)
                    │
6. oauth2-proxy → Casdoor OIDC (auth.lan:8000)
                    │
7. ✅ Authenticated → proxy to backend
                    │
8. Backend: haven pod (K8s NodePort :32100)
                    │
9. Response → Caddy → Browser
```
