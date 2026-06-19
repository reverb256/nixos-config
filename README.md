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


## Security

**Security Audit (2026-06-17):** See  for full report.

**Credential Rules:**
- **NEVER** commit plaintext secrets —  blocks , , , , 
- **ALWAYS** use sops-nix/agenix encryption for secrets (, )
- **PRE-COMMIT** hook runs  to block secrets
- **SSH key** at  — NOT in repo (moved out during audit)
- Keys rotated by operator on schedule — see audit report for exposed credentials timeline

**Files to never track:**
-  — runtime env dumps with live API keys
-  — environment variable files
-  — plaintext environment secret files
- ,  — log/conversation artifacts
- , , ,  — stale backup files


## Security

**Security Audit (2026-06-17):** See `docs/ARCHIVE/SECURITY-AUDIT-2026-06-17.md` for full report.

**Credential Rules:**
- NEVER commit plaintext secrets -- `.gitignore` blocks `env-vars`, `.env`, `secrets/*.env`
- ALWAYS use sops-nix/agenix encryption for secrets (`secrets/*.age`, `secrets/*.yaml`)
- PRE-COMMIT hook runs `gitleaks protect --staged` to block secrets
- SSH key at `~/.ssh/id_ed25519` -- outside the repo (moved during audit)

**Files never to track:**
- `env-vars` -- runtime env dumps with live API keys
- `.env` -- environment variable files
- `secrets/*.env` -- plaintext env secret files
- `nohup.out`, `records/` -- log/conversation artifacts
- `*.bak`, `*.backup`, `*.rej`, `*.orig` -- stale backup files

## Security

**Security Audit (2026-06-17):** See `docs/ARCHIVE/SECURITY-AUDIT-2026-06-17.md` for full report.

**Credential Rules:**
- NEVER commit plaintext secrets -- `.gitignore` blocks `env-vars`, `.env`, `secrets/*.env`
- ALWAYS use sops-nix/agenix encryption for secrets (`secrets/*.age`, `secrets/*.yaml`)
- PRE-COMMIT hook runs `gitleaks protect --staged` to block secrets
- SSH key at `~/.ssh/id_ed25519` -- outside the repo (moved during audit)

**Files never to track:**
- `env-vars` -- runtime env dumps with live API keys
- `.env` -- environment variable files
- `secrets/*.env` -- plaintext env secret files
- `nohup.out`, `records/` -- log/conversation artifacts
- `*.bak`, `*.backup`, `*.rej`, `*.orig` -- stale backup files
## See Also

- [NixOS Manual](https://nixos.org/manual/nixos/stable/)
- [Home Manager Manual](https://nix-community.github.io/home-manager/)
- [Flakes Guide](https://nixos.wiki/wiki/Flakes)
