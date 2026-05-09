# NixOS Cluster - Agent Guidelines

**Generated:** 2026-04-26 | **Commit:** 29d0d02f | **Branch:** main

## Quick Start

```bash
just check              # Quick flake validation (no build)
just switch             # Apply to local host (via tmux deploy session)
just test-apply         # Test configuration without persisting
just deploy [<host>]    # Deploy to all or specific host (Colmena + NFS)
just rollback           # Rollback local host
just status             # Cluster health overview
just health             # Detailed health check
```

> NOTE: `just test` does NOT exist. Use `just test-apply` or `just check`.

## Cluster Overview

| Host | IP | Role | RAM | GPUs |
|------|-----|------|-----|------|
| Zephyr | 10.1.1.110 | Workstation, control plane, gaming, NFS server | 31GB | 2x NVIDIA |
| Nexus | 10.1.1.120 | Primary server, AI Gateway, monitoring, storage | 46GB | 1x NVIDIA |
| Forge | 10.1.1.130 | GPU computing, mining | 15GB | 2x NVIDIA + 2x AMD |
| Sentry | 10.1.1.140 | Monitoring, AI inference (Vulkan) | 31GB | 1x AMD Radeon RX 5600 XT (6GB) |

**Resources**: 78 cores, 123GB RAM, 7 GPUs, 8.4TB storage
**K3s**: v1.34.5+k3s1 — All 4 nodes functional, **Flannel CNI** (VXLAN, UDP 8472)
**AI Gateway**: Sovereign Service Mesh operational on Nexus (10.15.67.242:8080)

## Deployment Model (Hybrid NFS + Colmena)

1. **Zephyr** exports `/etc/nixos` via NFS (read-only) to remote hosts
2. Remote hosts mount `/etc/nixos` from Zephyr — config is already there
3. `just deploy` uses Colmena to orchestrate `nixos-rebuild switch` across hosts
4. **Only Zephyr modifies config** — remotes mount read-only

> See `modules/services/nixos-share.nix` for NFS server/client setup.

## Extracted Projects (7)

Non-system projects live in `/data/projects/own/` as standalone flakes:

| Project | Flake Input | Purpose |
|---------|-------------|---------|
| ai-inference-gateway | `ai-gateway` | AI gateway service |
| compute-market | `compute-market` | GPU time-slicing |
| ~~caddy-ingress~~ | `caddy-ingress` | Archived — NixOS Caddy replaces K8s ingress controller |
| gpu-proxy | `gpu-proxy` | Stratum mining proxy |
| knowledge-fabric | `knowledge-fabric` | Knowledge base |
| llama-cpp-turboquant | `llama-turboquant` | TurboQuant + DFlash llama.cpp |
| hermes-chat | (local package) | Hermes Agent desktop client |
| mcp-registry | `mcp-registry` | MCP server management |

> NOTE: `searxng-cluster` is NOT extracted — not in flake.nix inputs. Lives in `kubernetes/modules/searxng.nix` via easykubenix.

## Project Structure

```
/etc/nixos/                          # 268 .nix files, ~45k lines
├── flake.nix                        # Main flake + host definitions
├── colmena.nix                      # Multi-host Colmena deployment
├── justfile                         # Task runner (deploy, check, rollback)
├── hosts/<hostname>/                # Per-host configs
│   └── (never edit hardware-configuration.nix)
├── modules/                         # Reusable modules (~171 .nix files)
│   ├── system/                      # Core system (34 files)
│   ├── services/                    # Background daemons (67 files)
│   ├── desktop/                     # Wayland compositors (11 files)
│   ├── home-manager/                # HM modules (15 files)
│   ├── profiles/                    # Composable hardware/role/network profiles (9 files)
│   ├── hardware/                    # GPU, AMD, NVIDIA, monitoring, RGB (7 files)
│   ├── development/                 # Dev tools (11 files)
│   ├── gaming/                      # Game launchers (3 files)
│   ├── network/                     # Networking (3 files: cluster-hosts, cluster-dns, cluster-networking)
│   ├── common/                      # Shared host defaults (2 files)
│   ├── security/                    # PAM, GPG (3 files)
│   ├── shell/                       # Shell config (2 files)
│   ├── multimedia/                  # GStreamer (1 file)
├── kubernetes/                      # K8s Nix modules via easykubenix (21 .nix files)
│   ├── modules/                     # K8s resource definitions
│   │   ├── nix-csi.nix              # Upstream nix-csi (with builtins.currentSystem fix)
│   │   ├── ai-inference.nix         # AI gateway, privacy filter, llama servers
│   │   ├── llama-servers.nix        # llama.cpp deployments (Vulkan/CUDA)
│   │   ├── monitoring.nix           # Prometheus, Grafana
│   │   └── ingress.nix              # Caddy ingress controller
│   └── default.nix                  # Easykubenix entry point
├── kubernetes-manifests/            # K8s YAML manifests (~256 files)
│   ├── archive/                     # Migrated manifests (archived)
│   ├── calico/                      # Archived Calico CNI reference configs
│   └── gpu/                         # GPU scheduling examples
├── scripts/                         # Utility scripts (~118 files: 78 .sh, 30 .py, misc)
├── packages/                        # Custom packages (~14 .nix files)
│   ├── privacy-filter.nix           # OpenAI PII detection
│   ├── llama-cpp-vulkan.nix         # Vulkan llama.cpp for AMD
│   ├── llama-cpp-*.nix              # CUDA, ROCm, TurboQuant variants
│   └── hermes-chat.nix              # Hermes Agent desktop client
├── tests/                           # NixOS tests (8 files)
├── secrets/                         # Agenix encrypted secrets (42 .age files)
└── .github/workflows/               # CI/CD (5 workflows, SHA-pinned)
```

## ⚠️ Critical Safety Rules

### mkOptionDefault (MANDATORY for extensible options)

```nix
# ❌ WRONG - Replaces node configs (breaks SSH!)
networking.firewall.allowedTCPPorts = [22 53 6443];

# ✅ CORRECT - Merges with node configs
networking.firewall.allowedTCPPorts = lib.mkOptionDefault [22 53 6443];
```

| Use `mkOptionDefault` | Use Direct Assignment |
|-----------------------|----------------------|
| Lists (ports, packages) | Booleans |
| Attrs that merge (systemd.services) | Strings (hostName) |

### Workload Scheduling (ZEPHYR OOM PREVENTION)

**⚠️ CRITICAL: ZEPHYR HAS CONSTANT OOM EXHAUSTION (31GB RAM running control plane + AI + gaming)**

**Default ALL non-infrastructure, non-mining workloads to NEXUS (46GB RAM)**

| Node | RAM | Purpose |
|------|-----|---------|
| **Nexus** | 46GB | ✅ DEFAULT for ALL workloads |
| **Zephyr** | 31GB | ⚠️ Infrastructure + mining ONLY |
| **Forge** | 16GB | Mining + GPU compute |
| **Sentry** | 31GB | Monitoring + Vulkan AI inference (5600 XT) |

**Enforce in K8s manifests:**
```yaml
spec.template.spec.nodeName: nexus  # Force scheduling
# OR use nodeAffinity (see kubernetes-manifests/AGENTS.md)
```

### GPU Isolation Limitation

**⚠️ nvidia-container-runtime is broken on NixOS** - The libnvidia-ml.so.1 dlopen fails due to NixOS glibc LD_LIBRARY_PATH handling.

**Impact**: K8s pods cannot properly isolate GPUs. Both visible GPUs show in `/dev` regardless of `CUDA_VISIBLE_DEVICES`.

**Workaround**: 
- Use `CUDA_VISIBLE_DEVICES` as a hint only - llama.cpp respects it
- Both pods run privileged on the same host
- Use `mining-inference-coordinator` to shift mining when inference is active

**For inference-only workloads**: Safe because each pod uses the GPU specified in the env var.

### Stop Immediately If
- SSH breaks on any node
- Multiple nodes affected
- `nix flake check` fails

### Doc Rot Prevention (Pocock Rule)

**Planning documents are living documents.** If reality has diverged from a plan doc, the plan is wrong — not reality.

Rules:
1. **Every plan doc** (`docs/plans/*.md`) MUST have a "Last Verified" date header
2. **Before following any plan**, check if it was verified in the last 7 days. If not, re-verify against current cluster state before proceeding
3. **After completing work described in a plan**, update the plan with actual outcomes (what changed vs what was planned)
4. **Stale plans** (>14 days since verification) should be flagged, not followed blindly
5. **AGENTS.md itself** — if you notice a section is wrong during work, fix it immediately. Don't file it for later

Use the `doc-rot-guard` skill for systematic stale detection.

## Code Style

- **2-space indentation**, trailing semicolons
- **kebab-case** for files: `gpu-exporters.nix`
- **Line length**: 80-100 chars

### Lib Helpers

```nix
# ExecStart — use lib.getExe
serviceConfig.ExecStart = lib.getExe pkgs.lm_sensors + " -s";

# Multi-line scripts — use writeShellScript
ExecStart = pkgs.writeShellScript "my-script" ''
  if [ ! -f "$CONFIG_FILE" ]; then echo "Not found"; exit 1; fi
'';

# PATH — use lib.makeBinPath
serviceConfig.Path = lib.makeBinPath [pkgs.bash pkgs.coreutils];

# Data transforms — use lib.pipe
uid = lib.pipe title [
  (builtins.replaceStrings [" "] ["-"])
  lib.strings.trim
  lib.toLower
];

# Types — use types.either for flexible options
port = mkOption { type = types.either types.int types.str; default = 5432; };
```

### Module Template

```nix
{ config, lib, pkgs, ... }:
let
  cfg = config.services.my-service;
  inherit (lib) mkEnableOption mkOption types mkIf;
in {
  options.services.my-service = {
    enable = mkEnableOption "My Service";
    port = mkOption { type = types.port; default = 8080; };
  };
  config = mkIf cfg.enable {
    networking.firewall.allowedTCPPorts = lib.mkOptionDefault [ cfg.port ];
    systemd.services.my-service = {
      wantedBy = [ "multi-user.target" ];
      serviceConfig.ExecStart = lib.getExe pkgs.my-package;
    };
  };
}
```

### Naming Conventions

| Namespace | Usage |
|-----------|-------|
| `services.*` | Background daemons |
| `programs.*` | Interactive GUI apps |
| `hardware.*` | Hardware config |
| `profiles.*` | Composable profiles |

## Deployment Workflow

1. Edit config on Zephyr (source of truth)
2. `git add` new files (Nix only sees git-tracked files!)
3. `just check` → `just switch` → `just deploy`

### Testing Checklist

| File Changed | Test On |
|--------------|---------|
| `modules/network/*` | zephyr AND nexus |
| `modules/system/ssh.nix` | ALL 4 nodes |
| `modules/system/users.nix` | ALL 4 nodes |
| `modules/default.nix` | Entire cluster |

## Supply Chain Security

- All package managers: 7-day cooldown (npm, bun, uv, pnpm)
- Container images: pinned versions, no `:latest` tags
- K8s admission policy blocks `:latest` (see `kubernetes-manifests/security/`)
- `container-scanning.nix` is imported in `default.nix` (auto-enabled when Podman is enabled)
- GitHub Actions pinned to commit SHAs


## Central SSO Authentication

**Architecture:** Casdoor OIDC (auth.lan) → oauth2-proxy (central-auth.service) → Caddy forward_auth
**Deployed on:** Zephyr + Nexus (both run central-auth.service)

### Service Classification

| Type | Services |
|------|----------|
| Public (no auth) | searxng.lan, ai-inference.lan |
| Protected (SSO) | haven.lan, openwebui.lan, kagent.lan, grafana.lan, mission-control.lan |

### Caddy Config

- **Zephyr** (`hosts/zephyr/caddy-routes.nix`): `mkAuthRoute` for protected, `mkRoute` for public
- **Nexus** (`modules/services/cluster-services.nix`): `protected = true` per service in registry
- Both proxy auth to local oauth2-proxy on port 4180

### DNS

All `.lan` domains → VIP 10.1.1.100 (keepalived MASTER on zephyr).
Unbound on all nodes with `local-zone "lan." static`.

### ⚠️ No K8s Sidecars

Do NOT deploy oauth2-proxy as K8s sidecar containers. Use the `central-auth` NixOS service instead.
Sidecars were removed 2026-05-02 from: haven, openwebui, kagent-ui, mission-control, llama-server-sentry, llama-server-zephyr-3090-moe.
Auth is handled exclusively by Caddy `forward_auth` → local `central-auth` (oauth2-proxy) on zephyr + nexus.

### Grafana Deployment

Grafana runs **only as K8s** (`monitoring` namespace, sentry, NodePort 32102).
The NixOS `services.monitoring.grafana` module (`modules/services/monitoring/grafana-v2.nix`) is **disabled on all hosts** — it's dead code.
Grafana OAuth uses Casdoor via `GF_AUTH_GENERIC_OAUTH` env vars + Caddy `forward_auth` as a second layer.
Secrets populated by `kubectl-apply-k8s-secrets` from agenix (`monitoring/grafana-oidc-secret`, `monitoring/grafana-admin-secret`).

## MCP Infrastructure

**In-cluster:** kubernetes-mcp (SSE :8080 on nexus) + nixos-cluster-mcp (DaemonSet, SSE :8081 on all nodes)
**Claude Code:** `nix run /etc/nixos#kubernetes-mcp-server` and `nix run /etc/nixos#nixos-cluster-mcp` (stdio)
**Hermes:** SSE URL for kubernetes, stdio for others (see `~/.hermes/config.yaml`)
**OpenCode:** 7 MCP servers via `~/.config/opencode/opencode.json` (`type: "local"` + command array). GitHub uses `--toolsets repos,issues,pull_requests,actions,code_security,notifications`.
**Registry:** `modules/services/mcp-server-registry.nix` — single source of truth
**Full plan:** `docs/plans/2026-05-01-mcp-system-plan.md`

### OpenCode MCP Server Verification (2026-05-09)

| Server | Bridge Script | Tools | Status |
|--------|--------------|-------|--------|
| github | `/data/agents/mcp-bridges/github-mcp.sh` | 39 (repos, issues, PRs, actions, code_security) | ✅ Working |
| nixos-cluster | `nix run /etc/nixos#nixos-cluster-mcp` | 15 (cluster_status, node_info, gpu_inventory, etc.) | ✅ Working |
| kubernetes | `nix run /etc/nixos#kubernetes-mcp-server` | 14 (pods_list, events_list, resources_*) | ✅ Working |
| searxng | `/data/agents/mcp-bridges/searxng-mcp.sh` | 15 (web_search, search_code, etc.) | ✅ Working |
| selfhosted-tools | `/data/agents/mcp-bridges/selfhosted-mcp.sh` | 15 (web_reader, read_github_file, search_github_repo, etc.) | ✅ Working |
| git | `/data/agents/mcp-bridges/git-mcp.sh` | 29 (git_log, git_diff, git_status, etc.) | ✅ Working |
| casdoor | `/data/agents/mcp-bridges/opencode-casdoor-bridge.py` | 5 (get_applications, etc.) | ⚠️ Auth required |

### Key Tool Names (correct for stdio JSON-RPC calls)

| Server | Common Tool Calls |
|--------|-----------------|
| nixos-cluster | `cluster_status`, `node_info`, `gpu_inventory`, `gateway_health`, `pod_status`, `check_models` |
| kubernetes | `pods_list`, `pods_get`, `pods_log`, `pods_exec`, `pods_run`, `events_list`, `resources_list` |
| github | `list_repositories`, `search_repositories`, `get_file_contents`, `list_commits`, `list_issues`, `list_pull_requests`, `create_pull_request` |
| searxng | `web_search`, `search_code`, `search_github`, `search_stackoverflow`, `search_nixos_options` |
| selfhosted-tools | `web_reader`, `read_github_file`, `search_github_repo`, `get_github_repo_structure`, `get_github_commits` |
| casdoor | `get_applications`, `get_application`, `add_application`, `update_application`, `delete_application` |

### Casdoor Auth Note

The `opencode-casdoor-bridge.py` uses OAuth2 `client_credentials` grant with scope `openid profile email`. Tool calls require the `mcp-client` app (client_id `3e6db9fe2befb4718ed5`) to have proper MCP scopes configured in Casdoor. Alternatively, `casdoor-mcp-bridge.py` uses password grant with admin credentials for full access.

## AI Agent Coding Principles (Pocock/Matt Workshop)

These apply to ALL agents (Hermes, Claude Code, OpenCode, OmP, Droid). Non-negotiable.

1. **TDD is mandatory.** Tests written before implementation. No test = no merge. Spec reviewers must reject if no test exists.
2. **Fresh context over compaction.** When context gets heavy, checkpoint to disk and start fresh. Do not push through degraded context.
3. **Vertical slicing.** Every task cuts across all layers (DB → API → UI). Never "all models then all endpoints then all UI."
4. **Two-stage review.** Spec compliance first (did you build the right thing?), code quality second (did you build it right?).
5. **Push/pull standards.** Implementers pull conventions on demand. Reviewers get conventions pushed inline.
6. **Alignment before planning.** Run grill-me before writing-plans. No plan without shared understanding of the problem.

When Hermes dispatches to subagents (claude-code, opencode, omp), it enforces these via the dispatch context. Subagents don not need to know the skills — Hermes injects the rules.

## Codified Conventions (Hermes Skills)

All repeatable patterns are codified as Hermes Agent skills at `~/.hermes/skills/devops/` (~277 total, 49 devops-specific).
**Load this skill before ANY NixOS module or K8s manifest work.**

### Quick Reference: 12 Convention Categories

| # | Pattern | Critical? | Summary |
|---|---------|-----------|---------|
| 1 | **K8s Scratch Pattern** | Yes | `ghcr.io/lillecarl/nix-csi/scratch:1.0.1` + hostPath `/nix` mount for Nix-built binaries. Python venvs/non-Nix binaries → use systemd on host. |
| 2 | **Extensible Lists** | **BREAKS SSH** | `lib.mkOptionDefault` for ALL lists in shared modules (ports, packages). Direct assignment replaces across all hosts. |
| 3 | **Deployment Safety** | Yes | `revisionHistoryLimit = 2`, `maxSurge = 0`, explicit `replicas = 1`. `Recreate` for GPU, `RollingUpdate` for stateless. Scale to 0 before deleting. |
| 4 | **GPU Scheduling** | Yes | Default ALL workloads to **Nexus** (46GB). Zephyr = infrastructure only (31GB, constant OOM). `nodeName` preferred over `nodeAffinity`. |
| 5 | **Caddy Routing** | Yes | Zephyr: `mkRoute`/`mkAuthRoute` helpers. Nexus: service registry with `protected = true`. Both use Caddy `forward_auth` → local oauth2-proxy. |
| 6 | **Nix Module Boilerplate** | No | `services.*` namespace, `mkEnableOption`, `mkIf cfg.enable`, register in `modules/default.nix`, `git add` new files. |
| 7 | **Lib Helpers** | No | `lib.getExe` for ExecStart, `writeShellScript` for multi-line scripts, `makeBinPath` for PATH, `pipe` for transforms. |
| 8 | **Network Policies** | No | `default-deny-all` per namespace + `allow-dns` egress + specific allow policies. |
| 9 | **Agenix Secrets** | No | `/run/agenix/<name>` paths, `config.age.secrets.*.path` references, never hardcode secrets. |
| 10 | **Systemd Services** | No | `wantedBy = ["multi-user.target"]`, `Restart = "on-failure"`, `writeShellScript` over `bash -c`. |
| 11 | **Pod Security Standards** | No | PSS labels: `enforce=baseline`, `audit=restricted`, `warn=restricted` on all namespaces. |
| 12 | **Managed-By Labels** | No | `"app.kubernetes.io/managed-by" = "easykubenix"` on all K8s resources. |

### Anti-Patterns (DO NOT)

- **Run Python venvs in scratch containers** — symlink resolution fails
- **Use `:latest` container tags** — admission policy blocks them
- **Schedule non-essential workloads on zephyr** — 31GB, constant OOM
- **Trust `nix-instantiate --parse` for easykubenix** — Lix 2.94.1 bug
- **Mix imperative `kubectl apply` with declarative Nix module changes** — track one or the other
- **Deploy oauth2-proxy as K8s sidecars** — use NixOS `central-auth` service
- **Forget `_namedlist = true`** on easykubenix containers/volumes/volumeMounts/env blocks
- **Use `bash -c '...'` for ExecStart** — use `writeShellScript`
- **Manually concatenate PATH** — use `lib.makeBinPath`
- **Use `systemctl enable`** — declare in NixOS config
- **Import images on wrong K3s node** -- import on the node where the pod runs
- **Build Nix containers without `git commit`** -- flakes only see tracked files

## Reference

| Document | Purpose |
|----------|---------|
| `CLAUDE.md` | Full agent context (safety rules, K8s troubleshooting) |
| `INFRASTRUCTURE-AUDIT.md` | Live cluster state and issues |
| `ROADMAP.md` | Kubernetes migration plan |
| `modules/README.md` | Module development guide |
| `skills/cluster-conventions/SKILL.md` | Full convention reference with templates (12 patterns) |

---

**Version**: 8.0 | **Last Updated:** 2026-05-02
**Changes**: Documentation audit — fixed all file counts, module tree, CNI reference, secrets count, scripts count, Hermes skills count (~38), container-scanning import status
