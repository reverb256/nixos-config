# NixOS Configuration - Agent Guidelines

## Purpose
This document provides guidelines for AI agents (OpenCode, Cursor, Copilot, Qwen-Agent, etc.) working on this NixOS configuration. It focuses on universal workflows, testing strategies, and common patterns.

**For Claude Code-specific patterns**, see `CLAUDE.md`.

---

## Quick Start

**For AI Agents:**
1. Use `just test` before making changes
2. Use `just deploy` to apply changes
3. See DOCUMENTATION_INDEX.md for comprehensive docs

**For Humans:**
1. Read this file for universal patterns
2. Check CLAUDE.md or QWEN.md for agent-specific patterns
3. Use `just` commands for all operations


---

## Project Overview
NixOS flake-based 4-host Linux cluster (Zephyr, Nexus, Forge, Sentry) with declarative configuration, profile-based architecture, and multi-host deployment via Colmena.

**Cluster Resources**: 78 cores, 123GB RAM, 7 GPUs (5x NVIDIA + 2x AMD), 8.4TB storage

**Architecture**:
- **Declarative**: All configuration in Nix expressions
- **Reproducible**: Same inputs → same output
- **Composable**: Profile-based system
- **Scalable**: Multi-host deployment


## Build & Test Commands

### Primary Workflow: Just Commands
```bash
just test              # Verify configuration
just switch            # Apply to local host (wrapper auto-pauses CPU mining)
just deploy            # Deploy to all cluster hosts (via Colmena)
just ci-local          # Run full CI pipeline locally
```

### Direct Commands (via wrapper)
```bash
# nixos-rebuild wrapper translates to Colmena automatically
sudo nixos-rebuild switch --flake .#zephyr   # Apply locally (mining pause)
sudo nixos-rebuild build --flake .#zephyr    # Build without applying
sudo nixos-rebuild test --flake .#zephyr     # Test (rollback safe)
nix flake update                              # Update flake inputs
```

**Wrapper Behavior:**
- All `nixos-rebuild` commands use the wrapper script (installed via NixOS module)
- Wrapper translates commands to Colmena for deployment consistency
- Automatically pauses CPU mining (xmrig) during builds, GPU mining (lolminer) continues
- Writes state files to `/run/nixos-deploy/{host}.json` for visibility
- Native bypass: `NIXOS_REBUILD_NATIVE=1 sudo nixos-rebuild ...`

### Critical Workflows
**Before Deployment**:
1. `just test` - Verify configuration builds
2. Check storage mounts
3. Review hookify warnings

**Git Workflow**:
1. Make changes
2. `git add` new files (Nix only packages git-tracked files!)
3. `git commit`
4. `just test`
5. `just deploy`

**Note:** Colmena automatically handles configuration distribution to all hosts. Manual `just sync` is no longer required.

---


## Code Style Guidelines
- **2-space indentation**, trailing semicolons
- **kebab-case** for files and modules
- **Line length**: 80-100 chars (soft limit 120)

## Project Structure
```
/etc/nixos/
├── flake.nix              # Flake inputs/outputs
├── hosts/                 # Per-host configs
├── modules/               # Reusable modules
│   ├── profiles/          # Profile-based configs
│   └── system/            # System-level modules
├── justfile               # CI/CD commands
├── AGENTS.md              # Universal patterns
├── CLAUDE.md              # Claude Code patterns
└── ROADMAP.md             # Kubernetes plan
```

## Profile System
Composable configurations for hardware, roles, and networking:
```nix
imports = [
  ../../modules/profiles/hardware/amd-zen.nix
  ../../modules/profiles/role/mining.nix
  ../../modules/profiles/network/tailscale.nix
];
```

**Profile Types**:
- **Hardware**: CPU/GPU capabilities (amd-zen, nvidia-gpu, etc.)
- **Role**: Host function (workstation, storage, mining, ai)
- **Network**: Connectivity (tailscale, cluster)

---



## Multi-Host Deployment (Colmena)

### Colmena Commands
```bash
nix run .#apps.x86_64-linux.colmena -- build          # Build all hosts
nix run .#apps.x86_64-linux.colmena -- apply --on <host>  # Apply to host
nix run .#apps.x86_64-linux.colmena -- apply --on nexus,forge,sentry boot  # Remote deploy (boot goal)
just deploy                                     # Deploy to all hosts
```

### Remote Deployment Notes
- Remote hosts use `boot` goal to avoid switch inhibitors
- Local host (zephyr) uses `switch` goal
- Mining auto-pauses during deployment

### Cluster Storage Verification
The `modules/system/cluster-storage.nix` module ensures all storage mounts are active on boot.

```bash
systemctl status ensure-cluster-storage
/data/@projects/infra/nixos/verify-cluster-storage.sh
```

### Important Notes
- Keep `system.stateVersion` and `home.stateVersion` current
- Never edit `hardware-configuration.nix` or `flake.lock`
- Always use `just` commands for CI/CD integration
- Never suppress build errors (no `|| true`)
- Check storage mounts after deployment
- Hookify rules enforce safe patterns (see `.claude/hookify-*.md`)

---

## Kubernetes Migration

### Overview
Migrating from systemd services to Kubernetes using `services.kubernetes` (full upstream, not K3s). See `/etc/nixos/ROADMAP.md` for the complete 9-week plan.

### Migration Phases
1. **Week 1-2**: Bootstrap single-node cluster on Zephyr
2. **Week 2-3**: Add worker nodes (Nexus, Forge, Sentry)
3. **Week 3-4**: Migrate stateful services (PostgreSQL, Redis)
4. **Week 4-6**: Migrate stateless services
5. **Week 6-7**: GPU workloads with device plugins
6. **Week 7-8**: Monitoring and observability
7. **Week 8-9**: Cleanup and optimization

### Architecture
**Control Plane (Zephyr)**: API server, etcd, Flannel CNI, CoreDNS
**Worker Nodes**: Nexus (storage), Forge (GPU), Sentry (monitoring)
**Storage**: Longhorn (distributed), NFS (shared), local (databases)
**Networking**: Tailscale VPN, Flannel VXLAN, Caddy ingress

### GPU Passthrough
```nix
# NVIDIA nodes
hardware.graphics.nvidia.enable = true;

# AMD nodes
hardware.graphics.amdgpu.enable = true;

# Mixed vendor (Forge) - deploy both plugins
```

### Key Commands
```bash
# Cluster management
kubectl get nodes
kubectl get pods --all-namespaces
kubectl logs <pod-name> -n <namespace>

# Deployment
kubectl apply -f manifests/
kubectl rollout restart deployment/<name> -n <namespace>

# Storage
kubectl get pv,pvc -n <namespace>
```

### Service Migration Workflow
1. Create Kubernetes manifest (Deployment + Service)
2. Test in development namespace
3. Migrate data (if stateful): `pg_dump` → `kubectl cp`
4. Switch traffic to Kubernetes service
5. Monitor and rollback if needed

### NixOS Configuration
```nix
services.kubernetes = {
  enable = true;
  roles = ["master" "node"];
  apiserverAddress = "https://10.0.0.10:6443";
  podNets = ["10.244.0.0/16"];
  easyCerts = true;
};

virtualisation.docker.enable = true;
```

### Documentation
- **Full Plan**: `/etc/nixos/ROADMAP.md`
- **Kubernetes Docs**: https://kubernetes.io/docs/
- **NixOS Module**: https://search.nixos.org/options?query=services.kubernetes

---

## MCP (Model Context Protocol) Integration

### Overview
AI inference gateway includes MCP broker aggregating tools from multiple MCP servers.

### Server Configuration
```json
{
  "mcpServers": {
    "web-search-prime": {
      "url": "https://api.z.ai/api/mcp/web_search_prime/mcp",
      "headers": {
        "Authorization": "Bearer /run/agenix/zai-api-key"
      }
    }
  }
}
```

### Protocol Details
- **Format**: JSON-RPC 2.0 over HTTP/SSE
- **Methods**: `initialize`, `tools/list`, `tools/call`
- **Response**: Server-Sent Events (SSE)
- **Critical Header**: `Accept: application/json, text/event-stream`

### Authentication Pattern
Headers with file paths need special handling:
```python
if header_value.startswith("Bearer "):
    file_path = header_value.split(" ", 1)[1].strip()
    with open(file_path, "r") as f:
        api_key = f.read().strip()
        headers[header_name] = f"Bearer {api_key}"
```

### Common Tools
- **webSearchPrime**: Web search with ranking
- **imageSearchPrime**: Image search and analysis

### Usage Examples
```bash
# List available tools
curl http://127.0.0.1:8080/mcp/tools | jq '.'

# Invoke tool
curl -X POST http://127.0.0.1:8080/mcp/call \
  -H "Content-Type: application/json" \
  -d '{"server": "web-search-prime", "tool": "webSearchPrime"}'
```

### Troubleshooting
**400 Bad Request from ZAI MCP**: Missing Accept header
- Fix: Always include `Accept: application/json, text/event-stream`
- See: `.claude/hookify.warn-mcp-accept-headers.local.md`

**404 Not Found**: Incorrect tool name (case-sensitive)
- Fix: Use exact name from `/mcp/tools`
- Example: `webSearchPrime` not `web_search`

### Documentation
- **MCP Spec**: https://modelcontextprotocol.io/
- **Cluster Architecture**: See ROADMAP.md

---


## Hookify Rules
Safe deployment pattern enforcement in `.claude/hookify-*.md`:

**Critical**: Block error suppression (`|| true`)

**High Priority**:
- Warn: Wrong deploy goals for remote hosts
- Warn: Git sync before deploy

**Medium Priority**:
- Warn: Autogen file edits (flake.lock)
- Warn: Git new files (remind to add)
- Warn: Test before deploy

## Service Management
```bash
systemctl status <service>
journalctl -u <service> -f
systemctl start/stop/restart/enable <service>
```

## Testing & Verification
```bash
just test                                    # Config test
/data/@projects/infra/nixos/verify-cluster-storage.sh  # Storage
just health-check                            # Service health
```

## Documentation
- **DOCUMENTATION_INDEX.md**: Comprehensive index
- **AGENTS.md**: Universal patterns (this file)
- **CLAUDE.md**: Claude Code patterns
- **QWEN.md**: Qwen-Agent patterns
- **ROADMAP.md**: Kubernetes migration

## Getting Help
**AI Agents**: Read docs, use semantic tools, follow hookify guidance
**Humans**: Start with DOCUMENTATION_INDEX.md, use `just status`, check `journalctl -xe`

---

**Version**: 1.0 | **Updated**: 2026-03-08 | **Template**: `/etc/nixos/docs/templates/base-template.md.j2`


