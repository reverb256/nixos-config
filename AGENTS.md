# NixOS Cluster - Universal Agent Guidelines

## Purpose
Universal guidelines for ALL AI agents (Claude Code, Cursor, Copilot, Qwen-Agent, OpenCode, etc.) working on this NixOS configuration.

**Agent-specific instructions**: See `@.claude/CLAUDE.md` (Claude Code), `.github/copilot-instructions.md` (GitHub Copilot), or agent-specific instruction files.

---

## Quick Start

**For AI Agents:**
1. Read this file for universal cluster patterns
2. Use agent-specific instructions for your tool
3. Use `just` commands for all operations

**For Humans:**
1. Read this file for universal patterns
2. Check agent-specific files for your AI tool
3. Use `just` commands for all operations

---

## WHAT: Project Overview

NixOS flake-based 4-host Linux cluster:
- **Zephyr** (10.1.1.110) - Control plane, gaming, AI inference
- **Nexus** (10.1.1.120) - Storage, GPU computing
- **Forge** (10.1.1.130) - GPU computing, mining
- **Sentry** (10.1.1.140) - Monitoring, logging

**Resources**: 78 cores, 123GB RAM, 7 GPUs (5x NVIDIA + 2x AMD), 8.4TB storage

**Architecture**: Declarative, reproducible, composable (profile-based), scalable (multi-host)

---

## HOW: Commands & Workflow

### Essential Commands
```bash
just test              # Verify configuration builds
just switch            # Apply to local host (auto-pauses CPU mining)
just deploy            # Deploy to all hosts via Colmena
just ci-local          # Full CI pipeline locally
```

### Development Workflow
1. Make changes
2. `git add` new files (Nix packages git-tracked files!)
3. `git commit`
4. `just test` (verify configuration)
5. `just deploy` (apply to all hosts)

### Testing Before Deployment
- `modules/networking/*` → Test SSH on zephyr AND nexus
- `modules/system/ssh.nix` → Test SSH on all 4 nodes
- `modules/system/users.nix` → Test login on all 4 nodes
- `modules/default.nix` → Test entire cluster

### Stop Immediately If
- SSH breaks on any node → Document incident, wait for human
- Multiple nodes affected → STOP ALL WORK, create urgent task

---

## WHAT: Project Structure

```
/etc/nixos/
├── flake.nix                    # Main flake with host definitions
├── hosts/                       # Host-specific configurations
│   ├── zephyr/
│   ├── nexus/
│   ├── forge/
│   └── sentry/
├── modules/                     # Reusable NixOS modules
│   ├── profiles/                # Hardware, role, network profiles
│   └── system/                  # System-level modules
├── .claude/                     # Claude-specific files
│   ├── agents/                  # Agent definitions
│   └── skills/                  # Skill definitions
├── .github/                     # GitHub-specific files
│   └── copilot-instructions.md  # GitHub Copilot instructions
├── justfile                     # CI/CD commands
├── AGENTS.md                    # Universal patterns (this file)
└── ROADMAP.md                   # Kubernetes migration plan
```

---

## HOW: Code Style & Conventions

### Nix Language Style
- **2-space indentation**, trailing semicolons
- **kebab-case** for files and modules
- **Line length**: 80-100 chars (soft limit 120)

### Critical: Module System
In shared modules, use `lib.mkOptionDefault` for extensible options:

```nix
# ❌ WRONG - REPLACES node configs
networking.firewall.allowedTCPPorts = [22 53 6443];

# ✅ CORRECT - MERGES with node configs
networking.firewall.allowedTCPPorts = lib.mkOptionDefault [22 53 6443];
```

**Why:** Direct assignment breaks SSH and other critical services on all nodes.

### Profile System
Composable configurations for hardware, roles, and networking:
```nix
imports = [
  ../../modules/profiles/hardware/amd-zen.nix
  ../../modules/profiles/role/mining.nix
  ../../modules/profiles/network/tailscale.nix
];
```

---

## HOW: Multi-Host Deployment

### Colmena Commands
```bash
nix run .#apps.x86_64-linux.colmena -- build          # Build all hosts
nix run .#apps.x86_64-linux.colmena -- apply --on <host>  # Apply to host
just deploy                                     # Deploy to all hosts
```

### Remote Deployment Notes
- Remote hosts use `boot` goal to avoid switch inhibitors
- Local host (zephyr) uses `switch` goal
- Mining auto-pauses during deployment

### Important Notes
- Keep `system.stateVersion` and `home.stateVersion` current
- Never edit `hardware-configuration.nix` or `flake.lock`
- Always use `just` commands for CI/CD integration
- Never suppress build errors (no `|| true`)
- Check storage mounts after deployment

---

## WHAT: Kubernetes Migration

**Status**: Phase 1 Complete (K8s v1.35.0 running)

**Architecture**:
- **Control Plane (Zephyr)**: API server, etcd, Flannel CNI, CoreDNS
- **Worker Nodes**: Nexus (storage), Forge (GPU), Sentry (monitoring)
- **Storage**: Longhorn (distributed), NFS (shared), local (databases)

**Full Plan**: See `@ROADMAP.md`

---

## HOW: MCP Integration

**Protocol**: JSON-RPC 2.0 over HTTP/SSE
**Critical Header**: `Accept: application/json, text/event-stream`

**Server Config**: `.claude/settings.json`

**Common Tools**: `webSearchPrime`, `imageSearchPrime`

**Troubleshooting**:
- 400 Bad Request: Missing Accept header
- 404 Not Found: Case-sensitive tool names

---

## Reference Documents

### Agent-Specific Instructions
- **Claude Code**: `@.claude/CLAUDE.md`
- **GitHub Copilot**: `.github/copilot-instructions.md`
- **Qwen-Agent**: `@QWEN.md`

### Cluster Information
- **Cluster Health**: `just status` or read `STATUS.md`
- **Full Documentation Index**: `@DOCUMENTATION_INDEX.md`
- **Kubernetes Roadmap**: `@ROADMAP.md`

### Claude-Specific Files
- **Multi-Host Validator**: `.claude/agents/multi-host-validator.md`
- **Add-Service Skill**: `.claude/skills/add-service/SKILL.md`
- **Nix-Rebuild Skill**: `.claude/skills/nix-rebuild/SKILL.md`

### Safety & Deployment
- **Hookify Rules**: `.claude/hookify-*.md`
- **Incident Reports**: `AGENT_INCIDENT_REPORT.md`

---

**Version**: 2.0 | **Updated**: 2026-03-15
**Changes**: Multi-file pattern alignment, progressive disclosure, universal agent focus


