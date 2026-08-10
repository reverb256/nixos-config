# NixOS Cluster Configuration

> **Status:** Canonical project entry point
> **Last Verified:** 2026-08-09
> **Owner:** j_kro

Flake-based multi-host NixOS configuration for a 4-node cluster.

## Quick Start

```bash
# Rebuild local host
just switch

# Deploy to all nodes
just deploy

# Deploy to specific node
just deploy <hostname>

# Build and test activation without switching permanently
just test-apply

# Fast flake validation without a build
just check
```

## Cluster Architecture

**Nodes:**
- **Zephyr** (10.1.1.110) - Control plane, gaming, AI inference
- **Nexus** (10.1.1.120) - Storage, GPU computing, Hermes Agent gateway
- **Forge** (10.1.1.130) - GPU computing, mining
- **Sentry** (10.1.1.140) - Monitoring, logging

**Checked-in inventory totals:** 78 cores, 123GB RAM, 7 GPUs, 8.4TB storage.
These are planning/inventory values; verify live hardware before operational decisions.

## Build Architecture

The NixOS target is the generic `x86_64-linux` platform. This repository does
**not** apply `-march=x86-64-v3` globally to the complete userspace.

- All hosts use the CachyOS `linuxPackages-...-x86_64-v3` kernel package.
- Selected llama.cpp packages are explicitly compiled with
  `-march=x86-64-v3` (see `modules/development/llama-cpp-optimization.nix` and
  `packages/llama-cpp-ik.nix`).
- The rest of the system uses each package's normal nixpkgs compiler settings.
- `big-parallel` is a Nix builder capability label, not an architecture target
  or a thread count.

Distributed-build policy is declared in
`modules/system/distributed-builds.nix`. Deployment dispatch is separate from
Nix's builder capability list: `just deploy` and `just deploy-async` invoke
`/etc/nixos/scripts/deploy/nexus-dispatch.sh`, which runs the canonical
Colmena apply on Nexus. Zephyr remains the authoring/source-of-truth host.


| Host | Local max jobs | Role |
|------|----------------|------|
| Zephyr | 0 | Authoring/source-of-truth host; no local build jobs |
| Nexus | 6 | Deployment dispatcher and exclusive primary builder |
| Sentry | 0 | Monitoring/inference host; not a build target |
| Forge | 0 in the distributed-build module | GPU/mining host; deployment builds on the target when required |

The module generates `/etc/nix/machines` from its own host list and excludes
the current host. The root `machines` file is the Nix machines file supplied to Colmena via
`colmena.nix`; it is not a global `-march` policy. Verify deployed runtime
settings with `nix show-config` and `/etc/nix/machines` before treating live
state as current.

## Project Architecture

**⚠️ IMPORTANT:** Home Manager leaf configuration is maintained in a separate repository
[`reverb256/home-manager-config`](https://github.com/reverb256/home-manager-config) (at
`/home/j_kro/Projects/home-manager-config`). It is consumed here as the
`home-manager-config` flake input. This repository retains shared-leaf modules and the
NixOS bridge under `modules/home-manager/` and `modules/system/home-manager.nix`; it is
not the source of the external leaf configuration.

| Project | Location | Purpose |
|---------|----------|---------|
| ai-inference-gateway | `/data/projects/own/ai-inference-gateway` | AI gateway service |
| compute-market | `/data/projects/own/compute-market` | GPU time-slicing |
| caddy-ingress | `/data/projects/own/caddy-ingress` | Custom Caddy build |
| gpu-proxy | `/data/projects/own/gpu-proxy` | Stratum mining proxy |
| knowledge-fabric | `/data/projects/own/knowledge-fabric` | Knowledge base system |
| llama-cpp-turboquant | `/data/projects/own/llama-cpp-turboquant` | TurboQuant llama.cpp |
| mcp-registry | `/data/projects/own/mcp-registry` | MCP server management |

These are referenced as **flake inputs** in `flake.nix` - each project maintains its own versioning and build process.

See [`docs/current-state.md`](docs/current-state.md) for the repository's current configuration boundaries and verification workflow.

## Configuration Structure

```
/etc/nixos/
├── flake.nix                  # Main flake + host definitions + project inputs
│                                 home-manager-config is a pinned flake input
├── hosts/                     # Host-specific NixOS configurations
│   ├── zephyr/
│   ├── nexus/
│   ├── forge/
│   └── sentry/
├── modules/                   # Reusable NixOS modules
│   ├── common-host-defaults.nix
│   ├── system/                # System-level modules incl. HM bridge
│   │   └── home-manager.nix   # Bridges to home-manager-config flake input
│   ├── services/
│   ├── desktop/
│   └── gaming/
└── secrets/                   # Encrypted secret material (SecretSpec/sops-nix paths)
```

> Home Manager leaf modules (fish, starship, niri, alacritty, …) live in
> [`reverb256/home-manager-config`](https://github.com/reverb256/home-manager-config).
> This repository keeps the NixOS bridge in `modules/system/home-manager.nix` and
> consumes the external modules through the `home-manager-config` flake input.

## Key Documentation

- **[`docs/current-state.md`](docs/current-state.md)** - Current checked-in architecture and documentation routing
- **[`DOCUMENTATION_INDEX.md`](DOCUMENTATION_INDEX.md)** - Full documentation catalog
- **AGENTS.md** - Universal cluster patterns and workflows
- **CONTRIBUTING.md** - Worktree, PR, and contribution workflow
- **DOCS-MAINTENANCE.md** - Documentation freshness and classification policy
- **ROADMAP.md** - Historical Kubernetes migration roadmap and hardening context
- **[`docs/audit-2026-07-27.md`](docs/audit-2026-07-27.md)** - Dated multi-area audit; verify findings against live state before acting

## Safety First

⚠️ **Before making changes to shared modules:**
1. Read CLAUDE.md "Critical Agent Safety Constraints"
2. Use `lib.mkOptionDefault` for extensible options
3. Test on nodes with custom configs (nexus, forge) before deploying
4. Verify SSH port 22 is never blocked

## Home Manager

User-environment configuration is managed by a separate flake:
[`reverb256/home-manager-config`](https://github.com/reverb256/home-manager-config).

- Canonical leaf modules: `reverb256/home-manager-config/modules/*.nix`
- nixos-config consumes it as the `home-manager-config` flake input
- Local `modules/home-manager/` contains only retained shared-leaf modules, not the external leaf configuration
- Bridge: `modules/system/home-manager.nix` (NixOS activation path)
- `homeConfigurations.<host>` in `flake.nix` uses `inputs.home-manager-config.modules.standalone.nix`

Standalone HM build / activation:
```bash
# From nixos-config (NixOS activation path)
nix build .#homeConfigurations.zephyr.activationPackage

# From home-manager-config directly
cd /home/j_kro/Projects/home-manager-config
home-manager switch --flake .#zephyr

# From wrapper (plain switch on zephyr)
cd ~/.config/home-manager
home-manager switch
```

## See Also

- [NixOS Manual](https://nixos.org/manual/nixos/stable/)
- [Home Manager Manual](https://nix-community.github.io/home-manager/)
- [Flakes Guide](https://nixos.wiki/wiki/Flakes)
