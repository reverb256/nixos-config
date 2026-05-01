# MCP System Plan — Complete Coverage

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix all broken MCP servers, unify the registry across 3 consumers (Claude Code, Hermes, in-cluster agents), harden with auth/observability, and add operational tools.

**Architecture:** `mcp-server-registry.nix` as single source of truth. Generates configs for Claude Code (stdio), Hermes (stdio+SSE), and Kagent `RemoteMCPServer` CRDs (in-cluster). Casdoor as MCP Auth Provider (OAuth 2.1). agentgateway or supergateway as MCP proxy layer. nixkube CSI for DaemonSet package distribution.

**Tech Stack:** Nix registry, Python FastMCP, Go kubernetes-mcp-server, Casdoor SSO (native MCP Auth Provider), supergateway/agentgateway proxy, mcpo (REST), nixkube CSI, Kagent CRDs

---

## Ecosystem Research (2026-05-01)

### Key Tools Evaluated

| Tool | Type | Purpose | Fit |
|------|------|---------|-----|
| **Casdoor MCP Auth Provider** | Auth | Native OAuth 2.1 + DCR + PKCE + JWKS for MCP | **Perfect** — we already run Casdoor. Official docs at casdoor.org/docs/mcp-auth/ |
| **agentgateway** (Linux Foundation) | Gateway/proxy | MCP + A2A proxy, multi-tenancy, observability, governance | **Strong** — enterprise-grade, LF-backed, supports both MCP and A2A. May be overkill initially |
| **supergateway** | Transport bridge | `npx supergateway --stdio "cmd"` → SSE/WS | **Best fit** — simplest stdio-to-HTTP bridge, solves our G workstream directly |
| **mcpo** (open-webui) | REST bridge | Expose any MCP tool as OpenAPI HTTP endpoint | **Useful** — lets non-MCP clients (scripts, curl) use MCP tools via REST |
| **Docker MCP Gateway** | Container orchestration | MCP servers as isolated Docker containers | **Low** — we use K8s not Docker Compose |
| **MetaMCP** | Aggregation | Three-level hierarchy: Servers->Namespaces->Endpoints | **Interesting** — 1:1 endpoint:namespace constraint limits us |
| **MCP Security Standard (MSSS)** | Hardening framework | Levels 1-4: RBAC, audit, sandboxing, egress filtering | **Reference** — we should target Level 2 (OAuth + RBAC + audit logging) |

### A2A Protocol (Google)

Agent-to-Agent protocol — complementary to MCP. Key differences:
- **MCP**: Agent-to-Tool (stateless calls, tool manifests)
- **A2A**: Agent-to-Agent (stateful tasks, Agent Cards, lifecycle management)

Relevance: agentgateway supports both MCP and A2A. Could enable proper multi-agent orchestration (Hermes-pi-Claude Code-Codex) instead of ad-hoc delegation. **Future phase.**

### Critical Insight: Casdoor Has Native MCP Auth

Casdoor's official docs now include a complete "Casdoor as MCP Auth Provider" section covering:
- OAuth 2.1 endpoints (authorization, token, introspection)
- Dynamic Client Registration (DCR) — RFC 7591
- PKCE (Proof Key for Code Exchange)
- JWKS endpoints
- Consent screens
- Token validation

This means our DIY casdoor-mcp-bridge.py is **redundant**. The correct approach is to configure MCP servers to use Casdoor as their OAuth 2.1 authorization server per the MCP spec, not bridge through a custom script.

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
| bsky | stdio | 401 auth failure |
| casdoor | stdio bridge | 401 auth failure |
| nixos-cluster | stdio | Working |
| searxng | stdio | Working (12 tools) |
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
| Casdoor SSO | Running (systemd on Zephyr), 4 MCP servers registered, tool sync failing (401s) |
| mcp-gateway-bridge | Exists but broken (ClusterIP routing) |
| mcp-server-registry.nix | 13 servers defined, not generating downstream configs |
| RemoteMCPServer CRD | Installed, 0 instances |
| casdoor-mcp-bridge.py | Custom bridge at `/data/agents/mcp-bridges/`, hitting 401s — should be replaced by native Casdoor MCP Auth |

### Known Issues

1. **ClusterIP unreachable from host** — kube-proxy in container, no iptables DNAT on host. Fixed: route 10.0.0.0/12 via Flannel gateway + NodePort for Caddy.
2. **DaemonSet hardcoded /nix/store path** — requires manual `nix copy` on rebuild.
3. **All nodes show Unknown** — kubelet not reporting Ready (cosmetic, pods run fine).
4. **Casdoor tool sync 500/401** — stdio servers need HTTP proxy + auth tokens stale.
5. **Duplicate nixos-cluster-mcp** — `/etc/nixos/packages/` AND `/data/projects/own/`.
6. **easykubenix manifestYAMLFile hangs** — `toYAMLFile` + `builtins.readFile` on unbuilt derivation.
7. **Casdoor admin password** — needs agenix-managed bcrypt hash.
8. **SearXNG endpoint** — `http://10.4.98.141:8080` is SearXNG web UI, NOT MCP endpoint.
9. **bsky MCP auth** — credentials expired/invalid, returning 401 on all calls.
10. **No MCP gateway/proxy layer** — all servers are point-to-point, no unified entrypoint, no audit logging.

---

## Workstream A: Fix Broken Claude Code Servers (7 fixes)

### A1: Remove grep-app
Remove from `.mcp.json` — binary doesn't exist in nixpkgs.

### A2: Fix searxng
Point to working wrapper at `/data/agents/mcp-bridges/searxng-mcp.sh` or use `uvx searxng-mcp`.

### A3: Fix gateway bridge
The AI Inference Gateway is a NixOS systemd service on Nexus (10.15.67.242:8080), NOT a K8s NodePort.
Update `mcp-gateway-bridge` env `GATEWAY_URL` to `http://10.15.67.242:8080` (or `https://ai-inference.lan/v1` with CA trust).
Caddy routes via `ai-inference.lan` TLS — bridge must either use HTTP directly or trust the cluster CA.

### A4: Fix web-reader (Z.AI)
Verify `$ZAI_API_KEY` env and z.ai API connectivity from zephyr.

### A5: Fix nixos (mcp-nixos)
Pin to older version with compatible schema, or remove.

### A6: Fix pinecone
Replace API key with valid one from Pinecone console.

### A7: Fix web-search-prime
Same Z.AI auth issue as A4.

### A8: Add Z.AI HTTP MCP servers
Three Z.AI cloud MCP servers defined but not wired into Hermes:
- `web-search-prime` — `https://api.z.ai/api/mcp/web_search_prime/mcp`
- `web-reader` — `https://api.z.ai/api/mcp/web_reader/mcp`
- `zread` — `https://api.z.ai/api/mcp/zread/mcp`
All use Bearer token auth via `$ZAI_API_KEY`. Verify key validity and add to Hermes config.

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

## Workstream G: MCP Gateway / Proxy Layer (CRITICAL PATH)

### G1: Deploy supergateway as stdio-to-HTTP bridge
Use `supergateway` (npx supergateway) to expose stdio MCP servers as HTTP/SSE endpoints.

```
supergateway --stdio "/data/agents/mcp-bridges/searxng-mcp.sh" --port 9001
supergateway --stdio "mcp-server" --port 9002  # nixos-cluster
supergateway --stdio "lightpanda mcp" --port 9003
```

Deploy as K8s Deployment or systemd services on Nexus (46GB RAM, default workload node).

### G2: Fix bsky auth
Regenerate/update Bluesky credentials for bsky MCP server. Current 401 indicates stale password/app password.

### G3: Replace casdoor-mcp-bridge.py with native Casdoor MCP Auth
Our custom bridge is hitting 401s. Instead:
1. Follow casdoor.org/docs/mcp-auth/overview/ to configure Casdoor as OAuth 2.1 provider
2. Configure MCP servers' Protected Resource Metadata to point to Casdoor
3. Enable DCR (Dynamic Client Registration) in Casdoor for automatic MCP client enrollment
4. Remove `/data/agents/mcp-bridges/casdoor-mcp-bridge.py`

### G4: Verify Casdoor tool sync
Once G1 + G3 are done, confirm all registered servers sync tools through the gateway.

### G5: (Optional) Deploy mcpo for REST access
Expose key MCP tools (searxng, nixos-cluster) as OpenAPI HTTP endpoints:
```
mcpo --port 9010 --server-command "/data/agents/mcp-bridges/searxng-mcp.sh"
```
Enables curl/script access to MCP tools without MCP client.

### G6: (Future) Evaluate agentgateway
Linux Foundation-backed. Supports MCP + A2A. Multi-tenancy, observability, governance.
Consider for Phase 2 if we need:
- Agent-to-agent communication (Hermes-pi-Claude Code-Codex)
- Centralized audit logging across all MCP calls
- Per-client tool visibility and RBAC
- A2A protocol for multi-agent task delegation

---

## Workstream H: Declarative Pipeline

### H1: Fix easykubenix manifestYAMLFile build
Resolve `toYAMLFile` hanging on unbuilt derivations.

### H2: Wire manifest build into deploy
`just deploy` applies manifests automatically.

---

## Workstream I: MCP Security Hardening (MSSS)

Reference: github.com/mcp-security-standard/mcp-server-security-standard

Target: MSSS Level 2 (Standard Assurance)

### I1: OAuth authentication via Casdoor
Covered by G3. All MCP endpoints require valid OAuth 2.1 token.

### I2: RBAC for tool access
Configure Casdoor permissions to restrict which clients can invoke which tools.
E.g., read-only agents get search tools only; admin agents get deploy/rollback tools.

### I3: Audit logging
Log all MCP tool invocations (who, what, when, result).
Can be done at gateway level (supergateway/agentgateway) or application level.

### I4: Network isolation
Ensure MCP endpoints are only reachable within cluster network (10.x.x.x).
Already partially covered by NetworkPolicies — extend to all MCP services.

---

## Execution Order

```
Phase 1 (Foundation):
  A (fix broken) -> G2 (bsky auth) -> C1 (dedup) ->
  G1 (supergateway, CRITICAL PATH) -> G3 (Casdoor native MCP auth) ->
  G4 (verify tool sync)

Phase 2 (Registry + Auth):
  D (CSI) -> E1 (probes) -> C2-C6 (registry generation) ->
  B (auth) -> I1-I3 (security hardening)

Phase 3 (Tools + Pipeline):
  F (operational tools) -> E2/E3 (node/GPU) -> H (pipeline)

Phase 4 (Advanced):
  G5 (mcpo REST) -> G6 (agentgateway eval) -> I4 (full network isolation) ->
  A2A multi-agent protocol
```

NOTE: G1 (supergateway) + G3 (Casdoor native MCP auth) is the critical path. Without a proper proxy layer, Casdoor cannot sync tools from stdio servers, and the gateway architecture cannot function.

**Estimated: ~28 hours across 36 tasks.**

## Architecture

```
mcp-server-registry.nix (source of truth)
  |
  +--> Claude Code settings.json (stdio)
  +--> Hermes config.yaml (stdio + SSE URLs)
  +--> Kagent RemoteMCPServer CRDs (SSE discovery)
  +--> NetworkPolicy rules (per namespace)
  +--> Casdoor MCP gateway registration

Casdoor (MCP Auth Provider — OAuth 2.1)
  |
  +--> DCR endpoint for automatic MCP client registration
  +--> PKCE flow for secure token exchange
  +--> JWKS endpoint for token validation
  +--> Permission policies (RBAC for tool access)
  +--> Audit log of all MCP auth events

supergateway (stdio-to-HTTP transport bridge)
  |
  +--> searxng-mcp      -> :9001 (SSE)
  +--> nixos-cluster-mcp -> :9002 (SSE)
  +--> lightpanda        -> :9003 (SSE)
  +--> Any future stdio MCP server

mcpo (REST bridge, optional)
  |
  +--> Exposes MCP tools as OpenAPI HTTP endpoints
  +--> curl/script access without MCP client

agentgateway (future)
  |
  +--> MCP + A2A unified proxy
  +--> Multi-tenancy, observability, governance
  +--> Agent-to-agent communication (Hermes-pi-Claude-Codex)

nixkube CSI (package distribution)
  |
  +--> Auto-fetches Nix closures into pods without hostPath mounts

In-Cluster:
  kubernetes-mcp  -> http://10.12.22.155:8080 (SSE)
  nixos-cluster   -> http://10.1.1.110:8081 (DaemonSet SSE)
```

---

**Version:** 2.1 | **Created:** 2026-05-01 | **Updated:** 2026-05-01 | **Supersedes:** `2026-05-01-k8s-mcp-server-design.md`

---

## Audit — 2026-05-01 Session 2

### Completed

| Workstream | Task | What was done |
|------------|------|---------------|
| A | A1-A7 | All 7 broken servers fixed or removed from configs |
| E | E3 | `gpu_inventory()` tool added |
| E | E1 | Health probes added to both Deployment and DaemonSet in infrastructure.nix |
| F | 11 tools | server.py rewritten with 15 tools (cluster_status, node_info, pod_status, deployment_logs, rollout_restart, rollout_status, safe_scale, check_models, get/set_deployment_env, describe_pod, get_events, gpu_inventory, gateway_health, eval_status) |
| G | G1-G2 | supergateway deployed as systemd template, 4 bridges running (searxng:9001, lightpanda:9003, nixos-cluster:9004, casdoor:9005) |
| — | Critical | Fixed kubernetes-mcp CrashLoopBackOff (removed broken liveness probe on `/`) |
| — | Critical | Restored SSE transport in server.py (argparse + main() entry point) |
| — | Critical | Updated dependency from `mcp` to `fastmcp>=2.0.0` |

### Remaining (20 tasks)

| Workstream | Tasks | Status |
|------------|-------|--------|
| B | B1-B2 | Sentry/GitLab OAuth not completed |
| C | C1-C6 | Registry not generating configs; duplicate nixos-cluster-mcp not deduped |
| D | D1-D2 | DaemonSet still uses hostPath, not nixkube CSI |
| E | E2 | Node Unknown status not investigated |
| F | F2-F6 | Missing: rollback_host, config_diff, check_storage, check_network, check_secrets |
| G | G3 | Casdoor tool sync still failing (401s) |
| H | H1-H2 | easykubenix build still hangs, manifests not auto-applied |

