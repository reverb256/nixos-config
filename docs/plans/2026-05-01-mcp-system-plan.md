# MCP System Plan — Complete Coverage

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix all broken MCP servers, unify the registry across 3 consumers (Claude Code, Hermes, in-cluster agents), harden with auth/observability, and add operational tools.

**Architecture:** `mcp-server-registry.nix` as single source of truth. Generates configs for Claude Code (stdio), Hermes (stdio+SSE), and Kagent `RemoteMCPServer` CRDs (in-cluster). Casdoor as auth gateway. nixkube CSI for DaemonSet package distribution.

**Tech Stack:** Nix registry, Python FastMCP, Go kubernetes-mcp-server, Casdoor SSO, nixkube CSI, Kagent CRDs

---

## Current State (2026-05-01)

### MCP Servers — Claude Code (18 registered, 7 broken)

| # | Server | Status | Issue |
|---|--------|--------|-------|
| 1 | context-mode | Working | — |
| 2 | context7 | Working | — |
| 3 | git | Working | — |
| 4 | fetch | Working | — |
| 5 | filesystem | Working | deferred tools |
| 6 | zread | Working | — |
| 7 | sonatype-guide | Working | deferred tools |
| 8 | chrome-devtools | Working | deferred tools |
| 9 | playwright | Working | deferred tools |
| 10 | kubernetes | Working | SSE in-cluster, stdio via nix run |
| 11 | nixos-cluster | Working | SSE DaemonSet, stdio via nix run |
| 12 | nixos | Broken | mcp-nixos schema breaking changes |
| 13 | grep-app | Broken | binary not in nixpkgs |
| 14 | searxng | Broken | wrapper script path broken in .mcp.json |
| 15 | gateway | Broken | GATEWAY_URL unreachable (ClusterIP DNAT) |
| 16 | web-reader | Broken | times out on all requests |
| 17 | pinecone | Broken | API key rejected |
| 18 | web-search-prime | Broken | same Z.AI auth issue as web-reader |

### Auth-needed (2)

| Server | Issue |
|--------|-------|
| sentry | OAuth flow not completed (needs DSN token) |
| gitlab | OAuth flow not completed (needs PAT) |

### MCP Servers — Hermes (6 configured)

| Server | Transport | Status |
|--------|-----------|--------|
| lightpanda | stdio | Working |
| bsky | stdio | Working |
| casdoor | stdio bridge | Working (pending restart) |
| nixos-cluster | stdio | Working |
| searxng | stdio | Working (pending restart) |
| kubernetes | SSE | Working |

### In-Cluster (Kagent CRDs)

| Server | Status |
|--------|--------|
| kubernetes-mcp | Running (infra namespace, SSE) |
| nixos-cluster-mcp | Running (DaemonSet, 4 nodes, SSE) |

### Infrastructure

| Component | Status |
|-----------|--------|
| nixkube CSI driver | Running (nix-node DaemonSet, all 4 nodes) |
| Casdoor SSO | Running, 4 MCP servers registered, tool sync failing |
| mcp-gateway-bridge | Exists but broken (ClusterIP routing) |
| mcp-server-registry.nix | 13 servers defined, not generating downstream configs |
| RemoteMCPServer CRD | Installed, 0 instances |

### Known Issues

1. **ClusterIP unreachable from host** — kube-proxy in container, no iptables DNAT on host. Fixed: route 10.0.0.0/12 via Flannel gateway + NodePort for Caddy.
2. **DaemonSet hardcoded /nix/store path** — requires manual `nix copy` on rebuild.
3. **All nodes show Unknown** — kubelet not reporting Ready (cosmetic, pods run fine).
4. **Casdoor tool sync 500** — stdio servers need HTTP proxy.
5. **Duplicate nixos-cluster-mcp** — `/etc/nixos/packages/` AND `/data/projects/own/`.
6. **easykubenix manifestYAMLFile hangs** — `toYAMLFile` + `builtins.readFile` on unbuilt derivation.

---

## Workstream A: Fix Broken Claude Code Servers (7 fixes)

### A1: Remove grep-app
Remove from `.mcp.json` — binary doesn't exist in nixpkgs.

### A2: Fix searxng
Point to working wrapper at `/data/agents/mcp-bridges/searxng-mcp.sh` or use `uvx searxng-mcp`.

### A3: Fix gateway bridge
Update `mcp-gateway-bridge` env `GATEWAY_URL` to NodePort `http://10.1.1.110:30880`.

### A4: Fix web-reader (Z.AI)
Verify `$ZAI_API_KEY` env and z.ai API connectivity from zephyr.

### A5: Fix nixos (mcp-nixos)
Pin to older version with compatible schema, or remove.

### A6: Fix pinecone
Replace API key with valid one from Pinecone console.

### A7: Fix web-search-prime
Same Z.AI auth issue as A4.

---

## Workstream B: Complete Auth (2 servers)

### B1: Sentry OAuth
Generate DSN token and configure.

### B2: GitLab OAuth
Create PAT and configure.

---

## Workstream C: Unify Registry

### C1: Deduplicate nixos-cluster-mcp
Pick `/etc/nixos/packages/` as canonical. Remove `/data/projects/own/nixos-cluster-mcp/`. Update Hermes config.

### C2: Registry to Claude Code config
Generate `settings.json` mcpServers from `mcp-server-registry.nix`.

### C3: Registry to Hermes config
Generate `config.yaml` mcp_servers from registry.

### C4: Registry to RemoteMCPServer CRDs
Generate Kagent CRDs for in-cluster discovery.

### C5: Registry to NetworkPolicy
Auto-generate per-server policies.

### C6: Registry to Casdoor registration
Auto-register servers in Casdoor gateway.

---

## Workstream D: DaemonSet to nixkube CSI

### D1: Convert DaemonSet volumes
Replace hostPath with nixkube CSI ephemeral inline volume:
```yaml
volumes:
- name: nix-store
  csi:
    driver: nixkube
    volumeAttributes:
      x86_64-linux: ${nixosClusterMcp}
```

### D2: Verify on all nodes
Confirm pods start without manual `nix copy`.

---

## Workstream E: Observability

### E1: DaemonSet health probes
Add liveness/readiness probes on SSE `/sse` endpoint.

### E2: Node status investigation
Debug kubelet not reporting Ready condition.

### E3: GPU utilization tool
Add `nvidia-smi` query to `check_node_capacity`.

---

## Workstream F: Operational Tools (nixos-cluster-mcp)

### F1: aggregate_logs
Multi-pod/namespace log tailing with label selector.

### F2: rollback_host
`nixos-rebuild rollback` on specific host via SSH.

### F3: config_diff
`nixos-rebuild build --dry-run` diff before deploy.

### F4: check_storage
PVC usage, volume health, storage class status.

### F5: check_network
DNS resolution, pod-to-pod connectivity, network policy audit.

### F6: check_secrets
Agenix decryption status across all hosts.

### F7: gpu_status
GPU util, VRAM, processes per node via `nvidia-smi`.

---

## Workstream G: mcp-proxy for Casdoor Gateway

### G1: Generic stdio-to-HTTP adapter
Deploy `supergateway` or custom adapter to expose stdio MCP servers as HTTP.

### G2: Deploy HTTP proxies
Wrap searxng, nixos-cluster, casdoor as HTTP for Casdoor.

### G3: Verify Casdoor tool sync
Confirm all 4 registered servers sync tools.

---

## Workstream H: Declarative Pipeline

### H1: Fix easykubenix manifestYAMLFile build
Resolve `toYAMLFile` hanging on unbuilt derivations.

### H2: Wire manifest build into deploy
`just deploy` applies manifests automatically.

---

## Execution Order

```
A (fix broken) -> C1 (dedup) -> D (CSI) -> E1 (probes) ->
G (mcp-proxy) -> C2-C6 (registry generation) -> B (auth) ->
F (tools) -> E2/E3 (node/GPU) -> H (pipeline)
```

**Estimated: ~22 hours across 30 tasks.**

## Architecture

```
mcp-server-registry.nix (source of truth)
  |
  +--> Claude Code settings.json (stdio)
  +--> Hermes config.yaml (stdio + SSE URLs)
  +--> Kagent RemoteMCPServer CRDs (SSE discovery)
  +--> NetworkPolicy rules (per namespace)
  +--> Casdoor MCP gateway (auth + routing)

Casdoor (auth gateway)
  +--> kubernetes-mcp  -> http://10.12.22.155:8080
  +--> searxng-mcp     -> http://10.4.98.141:8080
  +--> nixos-cluster   -> http://10.1.1.110:8081 (DaemonSet SSE)
  +--> lightpanda      -> http://10.1.1.110:3100

mcp-proxy (stdio->HTTP adapter)
  +--> Exposes stdio-only servers as HTTP for Casdoor tool sync

nixkube CSI (package distribution)
  +--> Auto-fetches Nix closures into pods without hostPath mounts
```

---

**Version:** 1.0 | **Created:** 2026-05-01 | **Supersedes:** `2026-05-01-k8s-mcp-server-design.md`
