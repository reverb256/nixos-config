# NixOS Cluster - Agent Guidelines

## 🔴 HARD RULE: DECLARATIVE ONLY — NEVER IMPERATIVE

**ALL persistent NixOS state lives in `.nix` files under git.** Shell commands
on a running NixOS host are ONLY acceptable for reading state. They are NEVER
acceptable for: configuring services, fixing bugs, attaching devices, changing
networking, editing secrets, or "patching" running daemons.

The workflow for ANY NixOS change:
1. Edit the `.nix` file on zephyr (the source-of-truth host)
2. Commit + push to central
3. Deploy via Colmena (`cd /etc/nixos && git add -A && git commit -m "..." && git push && colmena deploy`)

The live host is a *consumer* of the config, not the source of truth. Never
treat what a running host shows as authoritative — it's a rolled-back snapshot.

**Violation of this rule is the #1 most expensive recurring failure pattern.**
The user has demanded this be forced. If your first instinct is to SSH into
a NixOS host and run a command, STOP — find the `.nix` file first.

**Generated:** 2026-05-25 | **Commit:** `83524727` | **Branch:** main

## Quick Start

```bash
just check              # Quick flake validation (no build)
just switch             # Apply to local host
just deploy [<host>]    # Build + deploy to all or specific host
just rollback           # Rollback local host
just status             # Git status + main alignment
just health             # Cluster connectivity overview
just new-worktree <NNN> # Create worktree for issue NNN
```

> NOTE: `just test` does NOT exist. Use `just test-apply` or `just check`.

## Workflow

### Branch Model

```
main — Integration AND production branch (PRs land here, CI validates, deployed state tracks main HEAD)
issue-NNN-* — All new work, only in worktrees under /data/projects/own/
```

- /etc/nixos on ALL nodes stays on `main` (never a feature branch)
- The deployed cluster state = `main` HEAD after `just deploy`
- All changes go through PR → main (CI validates) → cluster via `just deploy`

### Default: Kelos-Powered (delegated to AI agents)

1. **Create an issue** — with clear acceptance criteria, label `agent-ready`
2. **Kelos handles the rest** — agent creates worktree, implements, pushes branch, opens PR
3. **Review the PR** — human reviews, requests changes via comments
4. **Merge** — squash-merge via GitHub UI into `main`
5. **Deploy** — `just deploy` directly from `main` HEAD

### Manual Fallback (exploratory/architectural work)

```bash
just new-worktree NNN    # Creates /data/projects/own/nixos-config-NNN
cd /data/projects/own/nixos-config-NNN
# ... edit, test, commit ...
git push origin issue-NNN-desc
gh pr create --base main --head issue-NNN-desc --title "type: description (#NNN)" --body "Closes #NNN"
```


## Cluster Overview

| Host | IP | Role | RAM | GPUs |
|------|-----|------|-----|------|
| Zephyr | 10.1.1.110 | Workstation, control plane, gaming, NFS server | 31GB | 2x NVIDIA |
| Nexus | 10.1.1.120 | Primary server, AI Gateway, monitoring, storage | 46GB | 1x NVIDIA |
| Forge | 10.1.1.130 | GPU computing, mining | 15GB | 2x NVIDIA + 2x AMD |
| Sentry | 10.1.1.140 | Monitoring, AI inference (Vulkan) | 31GB | 1x AMD Radeon RX 5600 XT (6GB) |

**Resources**: 78 cores, 123GB RAM, 7 GPUs, 8.4TB storage
**K3s**: v1.34.5+k3s1 — All 4 nodes functional, **Flannel CNI** (VXLAN, UDP 8472)
**Sentry SMT**: Re-enabled via enable-smt systemd service (CachyOS kernel defaults nosmt)
**AI Gateway**: Sovereign Service Mesh operational on Nexus (10.15.67.242:8080)

## Deployment Model (GitOps + nix-copy-closure)

1. **Zephyr** is the sole development host — all config is authored here
2. **Worktrees** under `/data/projects/own/` are the ONLY development target
3. `/etc/nixos` tracks `main` on all hosts (never a feature branch)
4. `just deploy` builds closures and copies them to remote hosts via `nix-copy-closure` + `switch-to-configuration`
5. The deployed cluster state = `main` HEAD as last copied via `just deploy` (no separate `prod` branch)

> NFS has been removed cluster-wide. See `modules/services/k8s-nix-deploy.nix` for the remote deployment mechanism.


## Self-Hosted GitHub Actions Runner

**Host:** nexus (ID: 28) | **Binary:** Official runner v2.334.0 | **Status:** Online

### Runner Location
- **Directory:** `/home/j_kro/actions-runner-official/`
- **Wrapper Script:** `/home/j_kro/actions-runner-official/start-runner.sh` (sets ICU env vars for dotnet)
- **Systemd Service:** `github-actions-runner.service` (auto-start on boot)
- **Work Directory:** `_work/` within runner directory

### Environment (NixOS-specific)
The runner requires these environment variables for dotnet 6.0 and HTTPS on NixOS:
```nix
LD_LIBRARY_PATH=/nix/store/.../icu4c-74.2/lib
NIX_ICU_DATA=/nix/store/.../icu4c-74.2/share/icu/74.2
SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt
REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-bundle.crt
NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-bundle.crt
```

### CI/CD Workflows
| Workflow | Purpose | Trigger |
|----------|---------|---------|
| `ci.yml` | Parse check, quick check, lint, test suite, security scan, build | PR, push, manual |
| `deploy.yml` | Colmena deployment to cluster nodes | Manual dispatch |
| `flake-update.yml` | Automatic flake lock updates | Schedule |
| `stale.yml` | Close stale issues/PRs | Schedule |

### CI Tools
Tool packages available on nexus via `environment.systemPackages`:
- `statix` — Nix code linter
- `deadnix` — Dead Nix code detector
- `osv-scanner` — Vulnerability scanner (v2.3.3)

### Troubleshooting
- **Runner not connecting:** Check systemd: `systemctl status github-actions-runner`
- **dotnet ICU errors:** Ensure LD_LIBRARY_PATH and NIX_ICU_DATA are set in the environment
- **Job failures:** Check `runner.log` in the runner directory and `_diag/` for diagnostics
- **SSL errors:** Ensure SSL_CERT_FILE points to the NixOS ca-bundle

### Registration
The runner is registered with GitHub for `reverb256/nixos-config` using the official runner configuration script. Re-registration requires a fresh token from GitHub Actions settings.


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
| vllm-turboquant | `vllm-turboquant` | vLLM + TurboQuant container build |

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

| Type | Services | Auth Method |
|------|----------|-------------|
| Public (no auth) | searxng.lan, dashboard.lan, gitea.lan, vaultwarden.lan, n8n.lan | Own auth or none |
| Proxy SSO (forward_auth) | haven.lan, kagent.lan, grafana.lan, mission-control.lan, qdrant.lan, brain.lan, ai-inference.lan, workspace.lan | Caddy -> oauth2-proxy -> Casdoor |
| Native OIDC (direct to Casdoor) | grafana.lan (also behind forward_auth), ai-inference.lan (JWT/JWKS for API), gitea.lan, openwebui.lan | Direct Casdoor app |

### Native OIDC Support Matrix (audited 2026-05-14)

| Service | Native OIDC | In Use? | Notes |
|---------|-------------|---------|-------|
| Grafana | ✅ Supported | ✅ Wired | `GF_AUTH_GENERIC_OAUTH_*` env vars, client-id `fa39ccce16fbc8ad4d23`. Also behind Caddy forward_auth as second layer. |
| AI Gateway | ✅ JWKS/JWT | ✅ Wired | JWT auth with JWKS from Casdoor for API. Admin UI behind forward_auth. |
| Gitea | ✅ Supported | ✅ Wired | Direct Casdoor app `app-gitea`. On `mkRoute` (no forward_auth). |
| Open WebUI | ✅ Supported | ✅ Wired (May 14) | Casdoor app `app-openwebui` (client-id `openwebui`). OIDC env vars deployed to pod + persisted in `ai-inference.nix`. "Sign in with Casdoor" on login page. |
| n8n | ⚠️ Enterprise | ❌ | OIDC requires enterprise license. Not available on self-hosted instance. |
| Haven | ❌ No support | — | Own JWT+bcrypt auth. No OIDC config options. Proxy auth is correct. |
| Mission Control | ❌ No support | — | Auth providers: session, API key, Google Sign-In, proxy header. No generic OIDC. |
| Kagent | ❌ No support | — | `AUTH_MODE=*** only. Open OIDC feature request (#476) unimplemented. |
| Qdrant | ❌ No user auth | — | API-key only. Proxy auth correct. |
| Vaultwarden | ❌ No support | — | Bitwarden SSO enterprise-only. |
| Workspace | ❌ No auth at all | — | Headless service. Proxy auth correct. |

### Stale OIDC Secrets (cleaned up 2026-07-14)

Three K8s secrets (`haven-oidc`, `mission-control-oidc`, `kagent-oidc`) were
removed in the 2026-07-14 audit — they were never mounted or referenced by any pod.
The `casdoor-app-sync` systemd service handles the real oauth2-proxy Casdoor app.

## Cluster Mesh SSH Account

**Purpose:** Dedicated service account for inter-node SSH mesh (health checks, exec tunneling).

**Policy:** Cluster does NOT use root SSH. All automated inter-node communication uses `cluster-mesh@10.1.1.x`.

### Architecture

```
cluster-mesh service account
├── User: cluster-mesh (system user, no shell)
├── Group: cluster-mesh
├── SSH key: cns-ssh-key (sops-nix, owned cluster-mesh:cluster-mesh 0600)
├── Key location: /var/lib/cluster-mesh/.ssh/id_ed25519
└── Authorized keys: Restricted via command=
```

### Services Using Cluster-Mesh SSH

| Service | Purpose | Command |
|---------|---------|---------|
| `cns-watcher.service` | CNS secret distribution to nodes | `ssh -i /var/lib/cluster-mesh/.ssh/id_ed25519 cluster-mesh@10.1.1.x` |
| `nexus-exec-tunnel.service` | Nexus exec tunnel (Zephyr→Nexus) | `ssh -i /var/lib/cluster-mesh/.ssh/id_ed25519 cluster-mesh@nexus` |
| `cns-health.timer` | CNS health check verification | `ssh -i /var/lib/cluster-mesh/.ssh/id_ed25519 cluster-mesh@10.1.1.x` |

### Configuration

Enable on hosts that participate in SSH mesh:

```nix
services.cluster-mesh.enable = true;
```

Module: `modules/security/cluster-mesh.nix`

### SSH Key Management

1. **Agenix Secret:** `secrets/cns-ssh-key.age`
2. **Owner:** `cluster-mesh:cluster-mesh 0600`
3. **Copy Service:** `cluster-mesh-key-setup.service` copies from `/run/secrets/cns-ssh-key` → `/var/lib/cluster-mesh/.ssh/id_ed25519`
4. **Deployment:** Auto-applied on all hosts via module auto-discovery

### Usage Pattern

For service-to-service SSH in systemd units:

```bash
ssh -i /var/lib/cluster-mesh/.ssh/id_ed25519 cluster-mesh@10.1.1.120 <command>
```

Never use `root@10.1.1.x` in automated services.

### Node IPs

| Host | IP |
|------|-----|
| Zephyr | 10.1.1.110 |
| Nexus | 10.1.1.120 |
| Forge | 10.1.1.130 |
| Sentry | 10.1.1.140 |

## Service ↔ Network Bridge

The bridge between NixOS system config and K8s workloads is `/etc/nixos/kubernetes/service-ports.nix`.  
This file is the **single source of truth for all static NodePort assignments**. Every `.lan` service that routes through Caddy gets its port defined here.

**Flow:**
```
service-ports.nix  ──import──► caddy-routes.nix (zephyr host Caddy)
                   ──import──► services.nix (nexus cluster Caddy)
                   ──consume──► K8s Helm charts (nodePort must match)
```

**To add a new service:**
1. Pick an unused port in the 30xxx range, add to `service-ports.nix`
2. Add `.lan` DNS record in `cluster-dns.nix` (DNS -> VIP 10.1.1.100)
3. Add Caddy route in `caddy-routes.nix` or `services.nix` using `ports.my-service`
4. Deploy K8s Service with `nodePort: <same port>`

The NixOS rebuild atomically updates DNS + Caddy. Ports are guaranteed to match because both sides read the same file.  
**NixOS defines the contract (ports, hostnames, TLS). K8s deploys into that contract.**

### Caddy Config

- **Zephyr** (`hosts/zephyr/caddy-routes.nix`): `mkAuthRoute` for protected, `mkRoute` for public
- **Nexus** (`modules/services/cluster-services.nix`): `protected = true` per service in registry
- Both proxy auth to local oauth2-proxy on port 4180 (K8s oauth2-proxy also runs in `auth` namespace as fallback)

### DNS

All `.lan` domains -> VIP 10.1.1.100 (keepalived MASTER on zephyr).
Unbound on all nodes with `local-zone "lan." static`.

### ⚠️ No K8s Sidecars

Do NOT deploy oauth2-proxy as K8s sidecar containers. Use the `central-auth` NixOS service instead.
Sidecars were removed 2026-05-02 from: haven, openwebui, kagent-ui, mission-control, llama-server-sentry, llama-server-zephyr-3090-moe.
Auth is handled exclusively by Caddy `forward_auth` -> local `central-auth` (oauth2-proxy) on zephyr + nexus.

### Nexus DE VM (libvirt/QEMU — migrated from KubeVirt 2026-07-14)

A Windows 11 desktop VM on **nexus** (4K TV on RTX 3060 Ti, USB keyboard/mouse).
Source of truth:

- `modules/services/nexus-de-vm.nix` — libvirt domain definition, GPU handoff coordinator, systemd service

**Key design: dynamic GPU handoff (no boot-time VFIO blacklist):**
- The RTX 3060 Ti boots on the **nvidia driver** (available for AI inference).
- The `nexus-de-vm` systemd service runs a coordinator script:
  1. Drain host GPU processes (llama, vLLM)
  2. Unbind GPU from `nvidia` → bind to `vfio-pci`
  3. Start `virsh start nexus-de`
  4. On stop: reverse the process → GPU returns to nvidia driver
- This lets the GPU serve AI workloads when the VM is off.

**VM spec:**
- 8 vCPU (host-passthrough), 24Gi RAM, UEFI + TPM 2.0
- GPU: 10DE:2486 (RTX 3060 Ti), audio: 10DE:228b — VFIO passthrough
- USB: TV keyboard (1a2c:2124) + mouse (1532:008f) — USB passthrough
- Disk: `/var/lib/libvirt/images/nexus-de.qcow2` (qcow2, SATA)
- Network: default libvirt network (NAT to host bridge)
- Spice display on port 5900 for install/debug
- VirtIO drivers ISO at `/var/lib/libvirt/images/virtio-win.iso`

**Lifecycle:**
```bash
systemctl start nexus-de-vm    # Handoff + start VM
systemctl stop nexus-de-vm     # Stop VM + return GPU to host
systemctl status nexus-de-vm   # Check state
virsh console nexus-de         # Direct console
```

### Kubernetes service routing (kube-proxy owns ClusterIP)

**Do NOT add a static route for the K8s service CIDR (`10.43.0.0/16`) via `flannel.1`.**
kube-proxy performs ClusterIP translation via iptables/nftables; routing service IPs directly
through the Flannel VXLAN device bypasses kube-proxy and breaks in-cluster service discovery
(notably CoreDNS). This was removed from `cluster-dns.nix` (the old `networking.localCommands`
`ip route add 10.43.0.0/16 via 10.42.0.1 dev flannel.1`). Host access to cluster services is via
NodePort through Caddy, never routed ClusterIPs.

### Grafana Deployment

Grafana runs **only as K8s** (`monitoring` namespace, sentry, NodePort 32102).
The NixOS `services.monitoring.grafana` module (`modules/services/monitoring/grafana-v2.nix`)
was deleted 2026-07-14 — Grafana runs exclusively as K8s.
Grafana OAuth uses Casdoor via `GF_AUTH_GENERIC_OAUTH` env vars + Caddy `forward_auth` as a second layer.
Secrets populated by sops-nix (`monitoring/grafana-oidc-secret`, `monitoring/grafana-admin-secret`).

## ⚠️ CRITICAL: /data/projects/own/ Flake Inputs

**Many cluster services live in `/data/projects/own/`, NOT in /etc/nixos modules!**

These are **flake inputs** defined in `flake.nix` (line ~106), NOT NixOS modules. When you need to:
- Find the **AI Inference Gateway** → `/data/projects/own/ai-inference-gateway/`
- Find **GPU time-slicing** → `/data/projects/own/compute-market/`
- Find **Knowledge base** → `/data/projects/own/knowledge-fabric/`

**ALWAYS check this directory first** for service implementations, especially for AI/ML workloads.

### How to identify flake-based services:
- Look in `flake.nix` → `inputs` section for `path:/data/projects/own/*` entries
- The flake outputs a `container` package which is pushed to local registry (`nexus:5000`)
- K8s modules reference these via `inputs.<name>.packages.x86_64-linux.container`

## MCP Infrastructure

**In-cluster:** kubernetes-mcp (SSE :8080 on nexus) + nixos-cluster-mcp v0.1.1 (DaemonSet, SSE :8081 on all nodes)
**Claude Code:** `nix run /etc/nixos#kubernetes-mcp-server` and `nix run /etc/nixos#nixos-cluster-mcp` (stdio)
**Hermes:** SSE URL for kubernetes, stdio for others (see `~/.hermes/config.yaml`)
**OpenCode:** 8 MCP servers + 4 model providers via `~/.config/opencode/opencode.json` (`type: "local"` + command array). Local models: vLLM (8040), llama.cpp Zephyr (1237), llama.cpp Sentry (1235).
**OmP:** MCP servers via `~/.omp/agent/mcp.json` — kubernetes, nixos-cluster, github, git, searxng, casdoor, gateway, context7, filesystem, fetch, lightpanda. Local models via `~/.omp/agent/models.json`.
**PI:** MCP servers via `~/.pi/agent/mcp.json` — kubernetes, nixos-cluster, github, git, searxng, casdoor, selfhosted-tools. Local models via `~/.pi/agent/models.json`.
**Registry:** `modules/services/mcp-server-registry.nix` — single source of truth
**Full plan:** `docs/plans/2026-05-01-mcp-system-plan.md`

### OpenCode MCP Server Verification (2026-05-10)

| Server | Bridge Script | Tools | Status |
|--------|--------------|-------|--------|
| github | `/data/agents/mcp-bridges/github-mcp.sh` | 39 (repos, issues, PRs, actions, code_security) | ✅ Working |
| nixos-cluster | `nix run /etc/nixos#nixos-cluster-mcp` | 15 (cluster_status, node_info, gpu_inventory, etc.) | ✅ Working |
| kubernetes | `nix run /etc/nixos#kubernetes-mcp-server` | 14 (pods_list, events_list, resources_*) | ✅ Working |
| searxng | `/data/agents/mcp-bridges/searxng-mcp.sh` | 15 (web_search, search_code, etc.) | ✅ Working |
| selfhosted-tools | `/data/agents/mcp-bridges/selfhosted-mcp.sh` | 15 (web_reader, read_github_file, etc.) | ✅ Working |
| git | `/data/agents/mcp-bridges/git-mcp.sh` | 29 (git_log, git_diff, git_status, etc.) | ✅ Working |
| casdoor | `/data/agents/mcp-bridges/opencode-casdoor-bridge.py` | 5 (get_applications, etc.) | ✅ Working |
| gateway | `/etc/nixos/scripts/mcp-gateway-bridge` | MCP tool proxy via ai-inference-gateway | ✅ Working |

### OpenCode Model Providers (2026-05-10)

| Provider | Base URL | Models | Purpose |
|----------|----------|--------|---------|
| zai-coding-plan | api.z.ai | GLM-5.1, GLM-5, GLM-4.6, etc. | Primary cloud models |
| local-vllm | 10.1.1.110:8040 | Qwen3.5-2B-AWQ | Fast local (Zephyr 3060Ti) |
| local-llama-zephyr | 10.1.1.110:1237 | Qwen3.6-35B-A3B | Large local (Zephyr 3090) |
| local-llama-sentry | 10.1.1.140:1235 | Qwen3.5-4B | Medium local (Sentry ROCm) |

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

## Primary Workflow (MANDATORY — ALL AGENTS)

**This applies to Hermes, Claude Code, Pi, OMP, OpenCode, and ALL delegated agents.**

### Golden Rule
**Issue → Branch/Worktree → PR → Merge → Close Issue**. No direct pushes to main. Ever.

### Worktree-First Development

Work on the cluster node closest to your workload using git worktrees:

```bash
# Create a worktree on the right node
git worktree add /data/projects/own/<repo>-NNN issue-NNN-short-description

# Or create from main
git worktree add -b issue-NNN-short-description /data/projects/own/<repo>-NNN main
```

**Node selection by workload:**
- AI/GPU changes → Sentry (Vulkan) or Nexus (46GB)
- K8s/infrastructure → Zephyr
- Data-heavy → Nexus (46GB RAM)
- Light work → any node

Every /data/projects/own/ repo has this workflow.

## GitHub Issues Workflow (MANDATORY)

**Every change MUST be tracked through a GitHub issue.** This applies to ALL agents and human contributors. No issue = no code.

### Workflow (6 Layers)

| Layer | What | Enforced By |
|-------|------|-------------|
| 1 | **Issue Templates** (`.github/ISSUE_TEMPLATE/`) | PR review — bug, feature, task templates pre-filled |
| 2 | **PR Template** (`.github/PULL_REQUEST_TEMPLATE.md`) | PR submission — MUST reference `Closes #NNN` |
| 3 | **AGENTS.md Mandate** | Agent session start — check/create issue first |
| 4 | **Git Hooks** (`.githooks/prepare-commit-msg`) | `git commit` — warns if `(#NNN)` missing from message |
| 5 | **CI Integration** | Workflow posts deploy status to linked issue |
| 6 | **justfile Commands** | `just issue-*` — quick issue operations |

### Agent Protocol (Every Session)

Before writing any code, agents MUST:

1. **Check existing issues:** `gh issue list --limit 10` (or via GitHub MCP: `list_issues`)
2. **If no issue exists** for the task → create one using the appropriate template:
   - `gh issue create --title "..." --label "p1,k8s" --body "$(cat .github/ISSUE_TEMPLATE/feature_request.md)"`
   - Or via GitHub MCP: `create_pull_request` with `list_issues` first
3. **Create a branch** named `issue-NNN-short-description`:
   - `git checkout -b issue-42-fix-dns-timeout`
4. **Commit with issue reference**: Every commit message MUST include `(#NNN)`:
   ```
   fix(caddy): resolve TLS handshake timeout on nexus (#42)
   ```
5. **Open PR with `Closes #NNN`**:
   ```
   gh pr create --title "Fix DNS timeout" --body "Closes #42"
   ```

### justfile Commands

```
just issue-create           # Interactive issue creation
just issue-list             # List open issues with status
just issue-close N          # Close issue #N with comment
just branch-from N          # Create + switch to issue-NNN-description
```

### Labels

Use the existing label system:
- **Priority**: `priority:critical`, `priority:high`, `priority:medium`, `p1`, `p2`
- **Domain**: `infra`, `k8s`, `security`, `ai-inference`, `config-drift`
- **Type**: `bug`, `enhancement`, `documentation`, `cleanup`

### Verification

- `git log --oneline -5` should show `(#NNN)` in every non-merge commit
- Every open PR's body should contain `Closes #NNN` or `Related to #NNN`
- Every issue should have appropriate labels (priority + domain)

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
| 9 | **sops-nix Secrets** | No | `/run/secrets/<name>` paths, never hardcode secrets. |
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
- **Edit `/etc/nixos` directly on remote nodes** — accumulates stray editor backups, phantom host configs, and root-owned contamination that block `git checkout` / `git reset` on cluster nodes. Use `just deploy` from zephyr.

## Known Issues (audited 2026-07-14)

| # | Issue | Status | Action |
|---|-------|--------|--------|
| 1 | **dashboard.lan (Glance)** | Nix config complete, namespace never deployed | Deploy via easykubenix, verify DNS + Caddy route |
| 2 | **Casdoor MCP bridge scopes** | mcp-client OAuth app missing MCP scopes | Add MCP scopes to app mcp-client in Casdoor |
| 3 | **Nexus NVMe boot timeout** | ✅ Resolved 2026-07-14 | `nvme_core.timeout=30` already in nexus hardware.nix |
| 4 | **NodePort access bypasses Caddy auth** | P0 — 17 services accessible on 30000-32767 from LAN | Restrict NodePort range to VIP only (see #291) |
| 5 | **etcd encryption at rest** | P0 — no encryption config | Add encryption-provider-config to k3s server args |

### Resolved (2026-05-14)
- K8s Tailscale Funnel live: 5 ingresses via operator, ProxyGroup 2/2, host funnel disabled
- Funnel manifests committed to Nix at kubernetes-manifests/tailscale/
- JCCF influence actor added with RSS feed
- Katzilla references purged from code + docs
- Media executives expanded to 17 tracked execs
- Corporate + influence ingestion modules built (2,850 lines)
- Dev Funnel Ingresses created with proper affinity rules
- Data source expansion plan written (7 modules, 4 phases)

## Reference


| Document | Purpose |
|----------|---------|
| `CLAUDE.md` | Full agent context (safety rules, K8s troubleshooting) |
| `INFRASTRUCTURE-AUDIT.md` | Live cluster state and issues |
| `ROADMAP.md` | Kubernetes migration plan |
| `modules/README.md` | Module development guide |
| `skills/cluster-conventions/SKILL.md` | Full convention reference with templates (12 patterns) |

---

**Version**: 9.5 | **Last Updated:** 2026-07-14
**Changes**: Updated from 2026-07-08 to 2026-07-14. Audit remediation sprint (#291): nodeName zephyr→nexus, :latest tags documented, lolminer purged, grafana-v2.nix deleted, nix-cache Prometheus scrape wired, root junk cleaned. Stale OIDC secrets confirmed already removed. nvme_core.timeout confirmed already set on nexus.

## Known Frictions & Workarounds (2026-05-18)

### SSH to Remote Nodes
Fish shell + devenv startup on remotes pollutes command output:
```
Error: × IO error: not a terminal
Changes that will be made to bash/devenv.nix: ...
```
**Fix:** Always use bash explicitly for SSH commands:
```bash
ssh nexus 'bash --norc --noprofile -c "cd /data/projects/own/maplespike && git status"'
```
For multi-line:
```bash
ssh nexus 'bash --norc --noprofile 2>/dev/null' << 'REMOTE'
cd /data/projects/own/maplespike
git status --short
REMOTE
```

### Worktree Staleness
After PR merge, clean up the worktree:
```bash
git worktree remove /data/projects/own/<repo>-NNN && git branch -d issue-NNN-desc
```
If permissions block: `sudo rm -rf /data/projects/own/<repo>-NNN`

### Branch Visibility Across Nodes
Push to origin (GitHub) not bare for all-node visibility:
- `git push origin issue-NNN-desc` — visible on all 4 nodes
- `git push bare issue-NNN-desc` — Zephyr only

### Template Activation Gap
Hermes Nix template only applies to fresh configs. To reapply:
```bash
rm ~/.hermes/config.yaml && just switch
```

### After-Cleanup Verification
Verify all 4 nodes after any cleanup:
```bash
for host in zephyr nexus forge sentry; do
  echo "$host: $(ssh $host 'bash --norc --noprofile -c "cd /data/projects/own/maplespike && git log --oneline -1"' 2>/dev/null)"
done
```

## NVIDIA Nemotron Models

| Model | Purpose |
|-------|---------|
| `nvidia/nemotron-3-super-120b-a12b` | Main coding model |
| `nvidia/nemotron-3-nano-30b-a3b` | Lightweight model |
| `nvidia/nemotron-3-nano-omni-30b-a3b-reasoning` | Reasoning/vision model |
## Deployment Protocol (CRITICAL — Learned from Sentry)

NEVER use `nixos-anywhere` for hosts with existing data — it's a provisioning tool for fresh bare metal.

### Correct Deployment Flow

```bash
# 1. Build closure locally (on Nexus)
sudo nix build "path:/etc/nixos#nixosConfigurations.<host>.config.system.build.toplevel" --no-link --print-out-paths

# 2. Copy closure to target
nix copy --to "ssh://j_kro@<ip>" /nix/store/<hash>-nixos-system-<host>-...

# 3. Activate with FULL switch (not boot)
ssh j_kro@<ip> "sudo nix-env -p /nix/var/nix/profiles/system --set /nix/store/<hash>... && sudo /nix/store/<hash>.../bin/switch-to-configuration switch"
```

### Post-Deployment Verification

```bash
# 1. Check generation (should be > 1 after first deployment)
ssh j_kro@<ip> "readlink /nix/var/nix/profiles/system && sudo nix-env -p /nix/var/nix/profiles/system --list-generations | tail -3"

# 2. Check failed services (0 or known-minor only)
ssh j_kro@<ip> "systemctl list-units --state=failed"

# 3. Verify recovery specialisation exists in boot menu
ssh j_kro@<ip> "sudo bootctl list | grep recovery"

# 4. Check sops-nix secrets are decrypted
ssh j_kro@<ip> "ls /run/secrets/"

# 5. Boot performance
ssh j_kro@<ip> "systemd-analyze time"
```

### Also ship this script: `scripts/deploy-host.sh`

```bash
./scripts/deploy-host.sh <hostname>
```

See `DEPLOYMENT-LESSONS.md` for the full postmortem.

### Cross-Host Config Rule

Shared modules (`modules/system/home-manager.nix`, `modules/home-manager/*.nix`) must:
- Use generic defaults (e.g., `"*"` for monitor wildcard)
- Use `mkIf (hostName == "...")` for per-host overrides
- **Never** assume Zephyr's config is universal

---

## SOPS-NIX

For canonical sops-nix guidance —  location, registry module reference, adding secrets, re-keying, recovery — see [SOPS-NIX.md](./SOPS-NIX.md).
