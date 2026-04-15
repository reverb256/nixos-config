# Infrastructure Audit — 2026-04-15 (Updated)

## Cluster Overview

| Host | CPU | RAM (used/total) | GPUs | Disk | Load | Uptime |
|------|-----|-------------------|------|------|------|--------|
| **Zephyr** | 16c | 21GB/31GB | RTX 3060 Ti 8GB + RTX 3090 24GB | 88% (118GB free) | 21.5 | 1.6d |
| **Nexus** | 24c | 20GB/46GB | RTX 3060 Ti 8GB @100% | 37% (569GB free) | 6.0 | 5.8d |
| **Forge** | 6c | 10GB/15GB | 2× RX 5700 XT + 2× RTX 4060 @100% | 81% (44GB free) | 4.7 | 4.1d |
| **Sentry** | 16c | 15GB/31GB | RX 5600 XT 6GB | 74% (59GB free) | 11.2 | 5.8d |

**Total**: 78 cores, 123GB RAM, 7 GPUs, 8.4TB storage

---

## K3s Cluster — ALL HEALTHY ✅

| Node | Status | Role | K3s Version | Runtime |
|------|--------|------|-------------|----------|
| zephyr | ✅ Ready | control-plane, etcd | v1.34.5+k3s1 | containerd 2.1.5 |
| nexus | ✅ Ready | control-plane, etcd | v1.34.5+k3s1 | containerd 2.1.5 |
| forge | ✅ Ready | agent | v1.34.5+k3s1 | containerd 2.1.5 |
| sentry | ✅ Ready | control-plane, etcd | v1.34.5+k3s1 | containerd 2.1.5 |

**VIP**: 10.1.1.100 (keepalived) — API server failover
**CNI**: Flannel (host-gw)
**etcd**: 3-node quorum (zephyr, nexus, sentry)

### Running Workloads (34 pods, 16 namespaces)

| Namespace | Pods | Workloads |
|-----------|------|-----------|
| mining | 9 | xmrig (zephyr, nexus, sentry), gpu-miner (forge ×4, nexus) |
| nixkube | 6 | nix-cache-0, nix-nodes ×4, proxy |
| kube-system | 6 | CoreDNS, metrics-server, local-path-provisioner, nvidia-device-plugin ×3 |
| ai-inference | 4 | llama-server (sentry, zephyr), open-webui, grafana |
| cert-manager | 3 | cert-manager, cainjector, webhook |
| search | 2 | searxng ×2 |
| ingress-system | 2 | caddy-ingress-controller ×2 |
| ingress-nginx | 1 | nginx-ingress-controller |
| haven | 1 | haven |

### Services (Cluster DNS)

| Host | Backend | Node | Protocol |
|------|---------|------|----------|
| ai.lan | llama-server | zephyr + sentry | HTTP |
| openwebui.lan | open-webui | nexus | HTTP |
| search.lan | searxng | nexus | HTTP |
| haven.lan | haven | nexus | HTTP |
| hermes.lan | hermes-dashboard | nexus (systemd) | HTTPS (Caddy) |
| api.hermes.lan | hermes-agent | nexus (systemd) | HTTPS (Caddy) |

---

## Recent Fixes (2026-04-15)

| Fix | Root Cause | Commit |
|-----|-----------|--------|
| **K3s: All 4 nodes Ready** | nexus: other agent disabled k3s; forge: `--flannel-external-ip` fatal in v1.34 | `3987440a`, `78bcd3b8` |
| **Sentry: GPU inference 59 tok/s** | llama-cpp updated to 6a6780a2, cmake flags fixed | deployed |
| **Sentry: firewall port 1235** | Port 8888 blocked by Calico/nftables | deployed |
| **Desktop: niri auto-login** | defaultSession changed from plasma → niri-uwsm | deployed |
| **Desktop: media keys** | `spawn` → `spawn-sh` in niri config (shell env) | deployed |
| **Desktop: brightness slider** | Patched nocturia for Samsung HDMI | deployed |
| **Scripts: $# escaping** | `''$#` in Nix multiline strings | deployed |
| **Monitoring: GPU exporters** | Added NVIDIA + AMD exporters to all hosts | deployed |
| **Monitoring: firewall ports** | mkOptionDefault for 9100/9105 on all hosts | deployed |
| **Hermes Agent** | Deployed with NixOS module, Z.AI provider, HTTPS | deployed |
| **Hermes Dashboard** | Vite SPA via Caddy HTTPS at hermes.lan | deployed |

---

## P0 — Critical

### 🔴 Zephyr disk at 88% (118GB free)
931GB disk nearly full. Was 798GB used. Largest consumers need audit.

### 🔴 Forge disk at 81% (44GB free)
230GB disk, only 44GB free. Mining logs? Container images?

### 🔴 Zephyr load average 21.5 on 16 cores
Mining + AI inference + desktop + control plane = overloaded.
Plan: Migrate non-essential workloads to nexus.

### 🔴 Sentry load average 11.2 on 16 cores
Inference + monitoring + mining. Should be lower.

---

## P1 — Monitoring Gaps

### 🟡 GPU exporters deployed but unverified
NVIDIA + AMD exporters added to all hosts. Need to verify Prometheus scrape targets.

### 🟡 Duplicate monitoring stack
Prometheus + Grafana on BOTH nexus AND sentry. Consolidate to nexus.

### 🟡 No alerting rules
`rule_files: []` in Prometheus config. Zero alerts configured.

### 🟡 No AMD GPU metrics verified
Forge has 2× RX 5700 XT, Sentry has 1× RX 5600 XT — exporter deployed but scrape unverified.

---

## P2 — Security Gaps

### 🟠 llama-server exposed on 0.0.0.0
Both zephyr and sentry bind port 1235 to all interfaces. Should be LAN-only.

### 🟠 Grafana exposed on 0.0.0.0 (nexus:3000)
Plain HTTP on LAN. Should be behind Caddy with TLS.

### 🟠 etcd ports accessible on LAN
2379/2380 on zephyr/nexus/sentry. Should be restricted to cluster nodes.

### 🟠 fail2ban only on zephyr + forge
nexus and sentry have no fail2ban.

---

## P3 — Operational Issues

### 🔵 Zephyr thermal: Tctl 54.2°C
Was 70.9°C with ALARM. Improved after load redistribution.

### 🔵 keepalived failing on some nodes
Pre-existing. VIP failover may be unreliable.

### 🔵 brain_query timeouts
LLM-based relevance search times out. Needs investigation.

---

## P4 — Optimization Opportunities

### ⚡ Wave 1: Free zephyr RAM
Migrate AI gateway, Redis, Qdrant, Vaultwarden to nexus (46GB, 26GB free).

### ⚡ Wave 2: Consolidate observability
Remove duplicate Prometheus/Grafana/Alertmanager from sentry → nexus only.

### ⚡ Model benchmarks on RTX 3090
12 GGUF models (1.3GB–18GB). Need llama-bench with matching ABI.

### ⚡ Multi-model GPU serving
Keep gemma-4-E4B always loaded, add Qwen3.5-27B on demand.

### ⚡ Forge storage cleanup
81% disk. Audit container images, mining logs, old nix generations.

---

## Hermes Agent (Nexus)

| Component | Status | Details |
|-----------|--------|---------|
| Service | ✅ Active | `hermes-agent.service` on nexus |
| API Server | ✅ Running | port 8642, key-auth |
| Provider | ✅ Z.AI glm-5.1 | Via gateway with API key |
| Dashboard | ✅ HTTPS | hermes.lan via Caddy |
| DNS | ✅ Resolved | hermes.lan, api.hermes.lan → 10.1.1.120 |
| TLS | ✅ Valid | Cluster CA leaf cert with SANs |

## Host Distribution Plan

| Host | Role | Priority Workloads |
|------|------|--------------------|
| **Zephyr** | Workstation + control plane | niri desktop, gaming, k3s server, NFS, mining |
| **Nexus** | Primary server | Hermes Agent, monitoring, AI services, storage, mining |
| **Forge** | Compute only | Mining (GPU), no other workloads |
| **Sentry** | Inference + archive | llama-server (ROCm), monitoring backup, mining |

---

## Next Steps (Priority Order)

1. **Model benchmarks** — Fix llama-bench ABI, benchmark all 12 models on RTX 3090
2. **AI inference gateway** — Reactivate with intelligent model routing
3. **Hermes Subconscious profile** — gkisokay patterns: room metaphor, walk scripts, signal board
4. **Multi-model serving** — Always-loaded + on-demand models on RTX 3090
5. **Wave 1: Free zephyr** — Migrate Redis, Qdrant, AI gateway to nexus
6. **Wave 2: Observability** — Consolidate Prometheus/Grafana to nexus
7. **pi-mcp-server** — HTTP MCP endpoint wrapping pi --mode rpc
8. **Security hardening** — Bind services to LAN, add fail2ban, restrict etcd
9. **Alerting rules** — CPU/RAM/disk/GPU alerts
10. **Forge cleanup** — Audit disk, clean old images/logs
