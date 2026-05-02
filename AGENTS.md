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
| Sentry | 10.1.1.140 | Monitoring, AI inference (ROCm) | 31GB | 1x AMD Radeon RX 5600 XT (8GB) |

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
/etc/nixos/                          # 280+ .nix files, 40k+ lines
├── flake.nix                        # Main flake + host definitions
├── colmena.nix                      # Multi-host Colmena deployment
├── justfile                         # Task runner (deploy, check, rollback)
├── hosts/<hostname>/                # Per-host configs (8 files each)
│   └── (never edit hardware-configuration.nix)
├── modules/                         # Reusable modules
│   ├── system/                      # Core system (43 files)
│   ├── services/                    # Background daemons (73 files)
│   ├── desktop/                     # Wayland compositors (14 files)
│   ├── home-manager/                # HM modules (12 files)
│   ├── profiles/                    # Composable hardware/role/network profiles
│   ├── hardware/                    # GPU, AMD, NVIDIA, monitoring, RGB (7 files)
│   ├── development/                 # Dev tools (6 files)
│   ├── gaming/                      # Game launchers (3 files)
│   └── network/                     # Networking (4 files)
├── kubernetes/                      # K8s Nix modules via easykubenix (15 files)
│   ├── modules/                     # K8s resource definitions
│   │   ├── nix-csi.nix              # Upstream nix-csi (with builtins.currentSystem fix)
│   │   ├── ai-inference.nix         # AI gateway, privacy filter, llama servers
│   │   ├── llama-servers.nix        # llama.cpp deployments (Vulkan/CUDA)
│   │   ├── monitoring.nix           # Prometheus, Grafana
│   │   └── ingress.nix              # Caddy ingress controller
│   └── default.nix                  # Easykubenix entry point
├── kubernetes-manifests/            # K8s YAML manifests
│   ├── archive/                     # Migrated manifests (200+ files archived)
│   ├── calico/                      # Calico CNI reference configs
│   └── gpu/                         # GPU scheduling examples
├── scripts/                         # Utility scripts (101 files)
├── packages/                        # Custom packages
│   ├── privacy-filter.nix           # OpenAI PII detection (NEW)
│   ├── llama-cpp-vulkan.nix         # Vulkan llama.cpp for AMD (NEW)
│   ├── llama-cpp-*.nix              # CUDA, ROCm, TurboQuant variants
│   └── hermes-chat.nix              # Hermes Agent desktop client
├── tests/                           # NixOS tests (8 files)
├── secrets/                         # Agenix encrypted secrets (41 .age files)
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
| **Sentry** | 31GB | Monitoring + ROCm AI inference (5600 XT) |

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
- `container-scanning.nix` exists but **not imported** in `default.nix`
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
**Registry:** `modules/services/mcp-server-registry.nix` — single source of truth
**Full plan:** `docs/plans/2026-05-01-mcp-system-plan.md`

## Reference

| Document | Purpose |
|----------|---------|
| `CLAUDE.md` | Full agent context (safety rules, K8s troubleshooting) |
| `INFRASTRUCTURE-AUDIT.md` | Live cluster state and issues |
| `ROADMAP.md` | Kubernetes migration plan |
| `modules/README.md` | Module development guide |

---

**Version**: 5.1 | **Last Updated:** 2026-05-02
