# NixOS Cluster - AGENTS.md

**Generated:** 2026-01-28 | **Branch:** fix-plasma-rtx3090-wayland

## Overview
Production NixOS 26.05 cluster with VR gaming, mining, and AI capabilities. 51-core distributed build pool across 4 hosts.

## Quick Reference
| Task | File | Key Config |
|------|------|------------|
| System packages | `modules/system-packages.nix` | Centralized only |
| Users/groups | `modules/users.nix` | j_kro, mining user |
| NVIDIA GPU | `hosts/zephyr/configuration.nix` | RTX 3090 beta driver |
| Mining | `modules/mining.nix` | lolminer, xmrig |
| VR/Steam | `modules/gaming.nix` | WiVRn, GameMode |
| Network | `modules/networking.nix` | Static IP 10.1.1.110 |
| Secrets | `secrets/` | Agenix encrypted |
| Cluster deploy | `justfile` | `just cluster-deploy` |
| MCP Servers | `modules/mcp-servers.nix` | AI assistant tools |
| Kimi Code | `~/.kimi/mcp.json` | MCP config |
| Kilo Code | `~/.kilocode/cli/global/settings/mcp_settings.json` | MCP config |
| OpenClaw | `modules/openclaw.nix` | AI agent orchestration |
| OpenClaw Common | `modules/openclaw-common.nix` | Shared agent config |
| Dev Environment | `.envrc` + `flake.nix` | direnv + nix-direnv |

## Structure
```
/etc/nixos/
├── flake.nix              # 12 inputs, 4 host definitions
├── configuration.nix      # Shared config (~167 lines)
├── hosts/                 # Per-host configs
│   ├── zephyr/           # Main workstation (RTX 3090)
│   ├── nexus/            # Backup server
│   ├── forge/            # Build worker
│   └── sentry/           # Monitoring
├── modules/              # 25 modular configs
│   ├── openclaw.nix      # AI agent orchestration
│   └── openclaw-common.nix # Shared agent configuration
├── secrets/              # Agenix encrypted secrets
└── justfile             # 25+ automation commands
```

## Development Environment (direnv + nix-direnv)

This repository includes automatic development environment setup using direnv.

### Setup
1. **Ensure direnv is enabled** (already in `home.nix`):
   ```bash
   programs.direnv.enable = true;
   programs.direnv.nix-direnv.enable = true;
   ```

2. **Allow the .envrc** (one-time per clone):
   ```bash
   cd /etc/nixos
   direnv allow
   ```

3. **Automatic loading** - When you `cd` into the directory, you'll get:
   - All Nix tools (nixfmt, alejandra, deadnix, statix)
   - Build tools (just, colmena)
   - Secret management (age, sops)
   - AIStor tools (minio-client)
   - System utilities (jq, curl, git)

### Available in DevShell
```bash
just              # Run just recipes (deploy, update, etc.)
colmena           # Deploy to cluster nodes
deadnix .         # Find dead Nix code
statix check .    # Lint Nix files
alejandra .       # Format Nix files
mc                # MinIO client for AIStor
nix fmt           # Format with nixfmt-tree
```

### How It Works
- `.envrc` - tells direnv to use `use flake`
- `flake.nix` devShell - defines all development packages
- `nix-direnv` - caches the shell for instant loading

### Customizing
Copy `.envrc.example` to `.envrc.local` for personal overrides:
```bash
cp .envrc.example .envrc.local
# Edit .envrc.local with your custom settings
```

## Conventions
- **Kernel**: `linuxPackages_zen` for gaming/mining
- **Desktop**: KDE Plasma 6 + Wayland (SDDM)
- **GPU**: NVIDIA proprietary (beta), 32-bit enabled
- **Modular**: All features in `modules/`, no main config bloat
- **Secrets**: Agenix for all sensitive data (no plaintext!)
- **Distributed**: 51 cores via Colmena + machines.nix

## Anti-Patterns (NEVER)
- Edit `hardware-configuration.nix` (auto-generated)
- Duplicate packages (use `system-packages.nix` only)
- Hardcode secrets (use Agenix)
- Add services to main config (create modules)
- Break Colmena deployment (use `just cluster-deploy`)
- **REPEAT FAILED COMMANDS** - If a command fails once, DO NOT run it again without modifying the approach or understanding why it failed

## Code Quality
```bash
just format    # alejandra .
just lint      # statix check .
deadnix .      # Find dead code
```

## Binary Caches

Configured in `modules/nix-config.nix` for faster builds:

| Cache | Purpose | Public Key |
|-------|---------|------------|
| `cache.nixos.org` | Official NixOS packages | `cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=` |
| `cuda-maintainers.cachix.org` | CUDA, PyTorch, TensorFlow | `cuda-maintainers.cachix.org-1:0dq3bujKpuEPMCX6U4WylrUDZ9JyUG0VpVZa7CNfq5E=` |
| `nix-community.cachix.org` | Community packages | `nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=` |
| `nixpkgs-wayland.cachix.org` | Wayland/Hyprland packages | `nixpkgs-wayland.cachix.org-1:3lwxaILxMRkVhehr5StQprHdEo4IrE8sRho9R9HOLYA=` |
| `nix-gaming.cachix.org` | Gaming packages (Proton-GE) | `nix-gaming.cachix.org-1:vn/szNT7r/Pc1FbcBjRGHLk7XNk0v2KvMq2v7EwXQ8w=` |
| `ezkea.cachix.org` | Anime Games Launcher | `ezkea.cachix.org-1:ioBmUbJTZIKsHmWWXPe1FSFbeVe+afhfgqgTSNd34eI=` |

**Note**: The `cuda-maintainers` cache is essential for AI/ML workloads to avoid building PyTorch/TensorFlow from source.

## CI/CD with Garnix

**Garnix** provides free CI/CD for Nix flakes:
- **Automatic builds** on every push to GitHub
- **Binary cache** at `cache.garnix.io` (already configured)
- **Build status** on GitHub PRs
- **Dashboard** at https://garnix.io/builds

### Configuration
- `garnix.yaml` - CI configuration file
- Connected to this repo - builds all flake outputs automatically

### What Gets Built
All flake outputs are built and cached:
- `nixosConfigurations.zephyr`, `nexus`, `forge`, `sentry`
- `packages.x86_64-linux.claude`, `kimi`
- `colmena` deployment configs
- Custom overlays

### Setup
1. Register at https://garnix.io (free tier)
2. Connect your GitHub repository
3. Push to GitHub - builds start automatically
4. Use cached builds locally with the configured `cache.garnix.io`

## MCP Servers Configuration

### Available MCP Servers

| Server | Transport | Purpose | Status |
|--------|-----------|---------|--------|
| **context7** | HTTP | Documentation search (up-to-date library docs) | ✓ Working |
| **grep_app** | HTTP | Code search | ✓ Working |
| **github** | HTTP | GitHub integration | ⚠ Auth required |
| **sentry** | HTTP | Error monitoring | ⚠ Auth required |
| **filesystem** | STDIO | Local filesystem | ✓ Working |
| **git** | STDIO | Git operations | ✓ Working |
| **playwright** | STDIO | Browser automation/testing | ✓ Working |
| **puppeteer** | STDIO | Browser automation | ⚠ Deprecated |
| **chrome-devtools** | STDIO | Chrome debugging | ✓ Working |
| **brave-search** | STDIO | Web search | ⚠ API key needed |
| **fetch** | STDIO | Web fetching | ⚠ Needs uvx fix |

### Configuration Files

**Kimi Code** (`~/.kimi/mcp.json`):
- JSON format with `mcpServers` object
- Supports HTTP and STDIO transports
- Test with: `kimi mcp test <server-name>`

**Kilo Code** (`~/.kilocode/cli/global/settings/mcp_settings.json`):
- JSON format with `mcpServers` object
- Additional options: `disabled`, `alwaysAllow`, `timeout`
- Supports streamable-http, stdio, sse transports

### NixOS Integration

The `services.mcp-servers` module in `modules/mcp-servers.nix` provides:
- Declarative MCP server package installation
- nix-ld support for dynamically linked executables
- Configuration file management
- Wrapper scripts for npm-based MCP servers

Enable in host configuration:
```nix
services.mcp-servers.enable = true;
services.mcp-servers.servers.brave-search.apiKey = "your-key-here"; # Optional
```

### Known Issues

1. **uvx/fetch server**: NixOS cannot run dynamically linked executables without nix-ld
   - Fix: Enable `programs.nix-ld.enable = true;`
   - Alternative: Use npm-based fetch servers

2. **github/sentry servers**: Require OAuth authentication
   - Run `kimi mcp auth <server>` to authenticate

3. **postgres server**: Disabled by default (requires DB connection)
   - Enable and configure connection string when needed

## OpenClaw Configuration

### Overview
OpenClaw is an AI agent orchestration system integrated across all cluster hosts. It provides declarative agent management with built-in authentication and environment-based configuration.

### Documentation
- **Official**: https://github.com/openclaw/nix-openclaw
- **Module**: `modules/openclaw.nix` - NixOS service configuration
- **Common**: `modules/openclaw-common.nix` - Shared agent settings

### Key Features
- **Built-in Auth**: No hardcoded API keys in configuration
- **Systemd Integration**: Native service management with proper isolation
- **Agent Isolation**: Dedicated `openclaw` user/group for security
- **Environment Files**: Secrets managed via `/etc/openclaw/` environment files
- **Cluster-Wide**: Consistent configuration across all 4 hosts

### Configuration Pattern
```nix
# In host configuration
services.openclaw.enable = true;
services.openclaw.agents.my-agent = {
  enable = true;
  environmentFile = config.age.secrets.openclaw-env.path;
};

### Lobster User Account
The `lobster` system user is dedicated for OpenClaw bot operations:
- **Home**: `/var/lib/lobster`
- **Groups**: `lobster`, `rclone`
- **Purpose**: Isolated AI agent execution
- **Services**: openclaw, openclaw-storage

## AIStor Object Storage for AI

### Overview
AIStor provides S3-compatible object storage optimized for AI/ML workloads. Deployed on **nexus** (largest storage node, 10.1.1.120).

### AI Capabilities (What You Get)

**Performance at Scale:**
- Distributed architecture for parallel data access
- Linear scaling from TBs to PBs
- Optimized for model training and serving
- High-throughput for LLM workloads

**AI/ML Ecosystem Integration:**
- Native PyTorch, Kubeflow, MLflow support
- Works with any S3-compatible framework
- RAG (Retrieval Augmented Generation) support
- Vector database compatibility

**Data Resilience:**
- Erasure coding for fault tolerance
- Data replication across nodes (if expanded)
- Erasure coding protects against drive failures
- 99.999999999% (11 nines) durability

**Lifecycle Management:**
- Automatic tiering of cold data
- Object retention policies
- Compliance with governance requirements
- Automated cleanup policies

### Free License (AIStor Free)
- **Cost**: $0
- **Deployment**: Single-node
- **Storage**: Unlimited (disk-limited)
- **API**: Full S3 compatibility
- **MCP**: Tech preview (enterprise required for GA)

### Current Setup
- **Endpoint**: `http://10.1.1.120:9000`
- **Console**: `http://10.1.1.120:9001`
- **User**: `lobster` (OpenClaw bot account)
- **Buckets**:
  - `ai-models` - Trained models and checkpoints
  - `training-data` - Datasets and corpora
  - `experiments` - ML experiment artifacts
  - `ai-logs` - Training logs and metrics
  - `nix-cache` - Nix binary cache

### Alternative Solutions (All Free)

| Alternative | Best For | License | Notes |
|-------------|----------|---------|-------|
| **Garage** | Small deployments | AGPL-3.0 | Lightweight, Rust-based |
| **SeaweedFS** | Large scale | Apache 2.0 | Distributed, scalable |
| **RustFS** | Performance | Apache 2.0 | 2.3x faster than MinIO |
| **Ceph+Rook** | Kubernetes | LGPL | Enterprise-grade |

**Current**: AIStor Free (single-node on nexus)

### Usage Examples

```bash
# Store model checkpoint
mc cp model.pt aistor/ai-models/run-47/final.pt

# Store dataset
cd /path/to/dataset && mc cp -r . aistor/training-data/imagenet/

# List experiments
mc ls aistor/experiments/

# Backup to cloud via rclone
rclone sync aistor:ai-models gdrive:ai-models-backup
```

### OpenClaw Storage MCP

Custom MCP implementation providing natural language interface:
- **Port**: 18800
- **User**: `lobster`
- **Features**:
  - Natural language: "Store model from training run 47"
  - Direct AIStor S3 integration
  - Rclone cloud backup coordination
  - Zero license fees

## Free Tier Management

### Automated Compliance
Enable automatic cleanup to stay within all free tier limits:

```nix
# In host configuration
services.nixos-free-tier = {
  enable = true;
  interval = "weekly";      # Cleanup frequency
  maxGenerations = 20;      # Keep last 20 generations
  deleteOlderThan = "30d";  # Delete generations older than 30 days
};
```

### Service Limits Overview

| Service | Free Tier | We Use | Status |
|---------|-----------|--------|--------|
| **Garnix** | Unlimited public builds | CI/CD + cache | ✅ Safe |
| **Cachix** | 5GB storage | Read-only (no push) | ✅ Safe |
| **GitHub** | 2000 min/month Actions | Garnix (not GH Actions) | ✅ Safe |
| **Nix Store** | Local disk only | Auto-cleanup weekly | ✅ Safe |

### What Gets Cleaned Automatically
- Old system generations (>30 days or >20 count)
- Unused nix store paths
- Home-manager old generations
- Store optimisation (deduplication)

### Manual Monitoring
```bash
# Check current usage
./scripts/free-tier-monitor.sh

# Force immediate cleanup
sudo ./scripts/free-tier-cleanup.sh
```
```

### Environment File Format
```bash
# /etc/openclaw/agent.env (managed via Agenix)
OPENCLAW_API_KEY=secret_key_here
OPENCLAW_MODEL=gpt-4
```

## Critical Gaps (TODO)
1. **Secrets**: Move all hardcoded tokens to Agenix
2. **Backups**: No borgbackup/restic configured
3. **Monitoring**: No Prometheus/Grafana
4. **Firewall**: SSH root enabled, no fail2ban
5. **Encryption**: No LUKS disk encryption

## Commands
```bash
# System
just switch              # Rebuild and switch
just update              # Update flake + rebuild
just clean               # Clean old generations

# Cluster
just cluster-deploy      # Deploy to all hosts
just cluster-status      # Check status

# Mining/Gaming
just mining-start        # Start mining
just gaming-start        # Enable gaming mode
just perf-monitor        # Show performance

# Development
just check               # nix flake check
just dev-setup           # Full pipeline
```

## Security Notes
- Passwordless sudo for wheel (convenience vs security tradeoff)
- SSH root login enabled (risk)
- Mining API ports should be localhost-only
- **Action needed**: Migrate secrets to Agenix

## Unique Features
- Custom `services.mining` option (not upstream)
- Smart mining pause (auto-detects VR/gaming)
- VRChat analytics blocking (18+ domains)
- WiVRn Quest Pro streaming (100Mbps HEVC)
- GameMode +150MHz NVIDIA overclock
- Systemd slices for workload isolation
- Multi-tier DNS with DoT
- MCP servers for AI assistants (kimi-code, kilo-code, opencode, claude-code, qwen-code)
- OpenClaw AI agent orchestration (cluster-wide)

## Files
- **65** nix files, **~6,935** total lines
- **23** modules, **310+** options
- **4** hosts in cluster

---
*Last updated: 2026-02-01 | Audit commit: OpenClaw configuration added*
