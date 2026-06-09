# NixOS Cluster Configuration

Flake-based multi-host NixOS configuration for a 4-node cluster.

## Quick Start

```bash
# Rebuild local host
just switch

# Deploy to all nodes
just deploy

# Deploy to specific node
just deploy <hostname>

# Test configuration without applying
just test
```

## Cluster Architecture

**Nodes:**
- **Zephyr** (10.1.1.110) - Control plane, gaming, AI inference
- **Nexus** (10.1.1.120) - Storage, GPU computing, Hermes Agent gateway
- **Forge** (10.1.1.130) - GPU computing, mining
- **Sentry** (10.1.1.140) - Monitoring, logging

**Resources:** 78 cores, 123GB RAM, 7 GPUs, 8.4TB storage

## Project Architecture

**⚠️ IMPORTANT:** Non-system projects have been extracted to standalone flakes in `/data/projects/own/`:

| Project | Location | Purpose |
|---------|----------|---------|
| ai-inference-gateway | `/data/projects/own/ai-inference-gateway` | AI gateway service |
| compute-market | `/data/projects/own/compute-market` | GPU time-slicing |
| caddy-ingress | `/data/projects/own/caddy-ingress` | Custom Caddy build |
| gpu-proxy | `/data/projects/own/gpu-proxy` | Stratum mining proxy |
| knowledge-fabric | `/data/projects/own/knowledge-fabric` | Knowledge base system |
| llama-cpp-turboquant | `/data/projects/own/llama-cpp-turboquant` | TurboQuant llama.cpp |
| mcp-registry | `/data/projects/own/mcp-registry` | MCP server management |
| searxng-cluster | `/data/projects/own/searxng-cluster` | Self-hosted search |

These are referenced as **flake inputs** in `flake.nix` - each project maintains its own versioning and build process.

See `/data/projects/AGENTS.md` for full project inventory.

## Configuration Structure

```
/etc/nixos/
├── flake.nix           # Main flake + host definitions + project inputs
├── hosts/              # Host-specific configurations
│   ├── zephyr/
│   ├── nexus/
│   ├── forge/
│   └── sentry/
├── modules/            # Reusable NixOS modules
│   ├── common-host-defaults.nix
│   ├── system/
│   ├── services/
│   ├── desktop/
│   └── gaming/
└── secrets/            # Agenix encrypted secrets
```

## Key Documentation

- **CLAUDE.md** - Agent patterns and best practices
- **AGENTS.md** - Universal cluster patterns and workflows
- **ROADMAP.md** - Kubernetes migration plan

## Safety First

⚠️ **Before making changes to shared modules:**
1. Read CLAUDE.md "Critical Agent Safety Constraints"
2. Use `lib.mkOptionDefault` for extensible options
3. Test on nodes with custom configs (nexus, forge) before deploying
4. Verify SSH port 22 is never blocked

## See Also

- [NixOS Manual](https://nixos.org/manual/nixos/stable/)
- [Home Manager Manual](https://nix-community.github.io/home-manager/)
- [Flakes Guide](https://nixos.wiki/wiki/Flakes)

## Kanban & Agent Orchestration

The cluster uses **Hermes Kanban** as the multi-agent coordination layer. A centralized gateway on sentry dispatches tasks to agent profiles, tracks state in SQLite, and provides CI/review monitoring.

### Architecture

```
GitHub Issues  ->  Reactions Poller (sentry, 60s)  ->  Kanban Task (fix/rework)
Pipeline Engine  ->  PipelineEngine.dedup/score/route  ->  Kanban Task (triage/research)
Hermes Gateway  ->  Dispatcher (60s tick)  ->  Agent Profile -> Worktree -> PR

WORKFLOW.md (canonical agent contract)
  |  feeds into
Agent prompt -> implements -> nix flake check -> git push -> gh pr create
```

### Live Components

| Component | Host | Purpose | Frequency |
|-----------|------|---------|-----------|
| hermes-agent.service | sentry | Gateway + kanban dispatcher | 60s tick |
| hermes-reactions.service | sentry | CI/review monitoring (nixos-config) | 60s poll |
| hermes-reactions-maplespike.service | sentry | CI/review monitoring (maplespike) | 60s poll |
| Pipeline engine skill | sentry | dedup/score/route/chain creation | On demand |

### Boards

| Board | Repo | Purpose |
|-------|------|---------|
| nixos-config | reverb256/nixos-config | Cluster infrastructure tasks |
| maplespike | reverb256/maplespike | Data ingestion module dev |

### Key Files

- WORKFLOW.md - Canonical agent contract (YAML frontmatter + prompt template)
- AGENTS.md - Universal cluster patterns and safety rules
- Pipeline engine: Hermes skill pipeline-engine (23 scripts)
