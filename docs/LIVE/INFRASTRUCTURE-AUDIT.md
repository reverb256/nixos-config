---
last-verified: 2026-06-12
verified-by: Sisyphus
verification-method: just docs-audit + cluster inspection
expires: 2026-06-19
---
# Infrastructure Audit — 2026-06-12

## Cluster Overview

4-node NixOS + K3s cluster.

| Host | Role | RAM | GPUs | Primary Workloads |
|------|------|-----|------|--------------------|
| Zephyr (10.1.1.110) | Control plane, NFS server, workstation | 31GB | 2× NVIDIA | Gaming, control plane, some inference |
| **Nexus (10.1.1.120)** | **Primary server (DEFAULT for workloads)** | **46GB** | 1× NVIDIA | AI Gateway, Qdrant, Knowledge Fabric, SearXNG, monitoring |
| Forge (10.1.1.130) | GPU compute | 15GB | 2× NVIDIA + 2× AMD | Mining, GPU tasks |
| Sentry (10.1.1.140) | Monitoring + inference | 31GB | 1× AMD RX 5600 XT | Observability stack, Vulkan inference |

**CNI:** Flannel (VXLAN, UDP 8472). **K3s:** v1.34.5+k3s1.

**Critical Rule:** Schedule ALL non-infra workloads to Nexus (46GB). Zephyr is OOM-prone.

## Sovereign Service Mesh (Central Bus)

**Status:** Operational on Nexus.

**AI Gateway** at 10.15.67.242:8080 is the single entry point for all AI traffic.

**Components:**
- AI Gateway (central bus with RRF middleware)
- Qdrant (vector DB)
- Knowledge Fabric API (currently stub)
- SearXNG (search)
- Valkey (cache)

All `.lan` domains route through Caddy on Zephyr/Nexus with central-auth (oauth2-proxy + Casdoor).

**Grafana:** K8s only (monitoring namespace on Sentry, NodePort 32102). NixOS grafana module is dead code.

## MCP Infrastructure

Multiple MCP servers (kubernetes, nixos-cluster, searxng, casdoor, git, etc.) available via stdio and SSE.

**Hermes, OpenCode, OmP, Pi** all configured to use local MCP servers.

## Documentation Rules (Enforced)

- All claims in `docs/LIVE/` must be verifiable.
- No document >14 days old without fresh `last-verified` stamp.
- Contradictions must be resolved immediately.
- Pocock Rule: If cluster reality diverges from a plan, update the plan.

## Verification

Run `just docs-audit` (which runs `docs/meta/VERIFICATION-SUITE/run.sh`).

This file is the **single source of truth** for cluster state. All other documentation must align with it.
