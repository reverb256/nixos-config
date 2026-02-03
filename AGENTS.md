# NixOS Cluster - AGENTS.md

**Generated:** 2026-02-01 | **Branch:** feature/openclaw-secure

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
| **OpenClaw** | `modules/openclaw.nix` | AI agent gateway (port 18789) |
| **OpenClaw Storage** | `modules/openclaw-storage.nix` | AIStor MCP (port 18800) |
| **OpenClaw Nginx** | `modules/openclaw-nginx.nix` | Reverse proxy with SSL |
| Dev Environment | `.envrc` + `flake.nix` | direnv + nix-direnv |

## Structure
```
~/@projects/infra/nixos/
├── flake.nix              # 12 inputs, 4 host definitions
├── configuration.nix      # Shared config (~365 lines)
├── hosts/                 # Per-host configs
│   ├── zephyr/           # Main workstation (RTX 3090)
│   ├── nexus/            # AIStor/MinIO server
│   ├── forge/            # Mining/build worker
│   └── sentry/           # Monitoring
├── modules/              # 25+ modular configs
│   ├── openclaw.nix      # AI agent gateway
│   ├── openclaw-common.nix # Shared agent configuration
│   ├── openclaw-storage.nix # AIStor S3 MCP
│   ├── openclaw-backups.nix # Cloud backup automation
│   └── openclaw-nginx.nix # Reverse proxy with SSL
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
   cd ~/@projects/infra/nixos
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
| `cache.garnix.io` | Garnix CI builds | `cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g=` |
| `reverb-os.cachix.org` | Personal cache | `reverb-os.cachix.org-1:dctKtu02bV/4fbsYbGuVVxQo9R7X6lNqUet1qj2jYz=` |

**Note**: The `cuda-maintainers` cache is essential for AI/ML workloads to avoid building PyTorch/TensorFlow from source.

**Note**: Magic Nix Cache public endpoint was discontinued Jan 2025. Use GitHub Actions version for CI caching (see below).

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

## CI/CD with GitHub Actions

**GitHub Actions** workflow configured in `.github/workflows/nix.yml`:
- **Magic Nix Cache** for 30-50% faster CI builds (v13, latest)
- **Determinate Nix Installer** for reliable Nix setup
- **Multi-host builds** (zephyr, nexus, forge, sentry)

### Magic Nix Cache
Uses GitHub Actions cache API to share build results between workflow runs:
```yaml
- uses: DeterminateSystems/magic-nix-cache-action@v13
```

**Note**: Magic Nix Cache only works in GitHub Actions, not for local builds.

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

**Security-First Design:**
- **No sudo access**: Service user has zero privilege escalation
- **Localhost-only**: Services bind to 127.0.0.1 by default
- **Nginx proxy**: External access via reverse proxy with SSL/TLS
- **Systemd hardening**: NoNewPrivileges, PrivateTmp, ProtectSystem
- **Health monitoring**: 30-second health checks with auto-restart

### Documentation
- **Official**: https://github.com/openclaw/nix-openclaw
- **Module**: `modules/openclaw.nix` - NixOS service configuration
- **Storage**: `modules/openclaw-storage.nix` - AIStor S3 integration
- **Backups**: `modules/openclaw-backups.nix` - Automated cloud backups
- **Nginx**: `modules/openclaw-nginx.nix` - Reverse proxy with SSL

### Service Architecture

| Service | Port | Access | Purpose |
|---------|------|--------|---------|
| **openclaw** | 18789 | localhost only | AI agent gateway |
| **openclaw-storage** | 18800 | localhost only | AIStor S3 MCP |
| **nginx** | 80/443 | external | Reverse proxy with SSL |

**Note**: Direct access to ports 18789/18800 is blocked externally. Use nginx for secure access.

### Key Features
- **Built-in Auth**: No hardcoded API keys in configuration
- **Systemd Integration**: Native service management with hardening
- **Agent Isolation**: Dedicated `lobster` system user (no login, no sudo)
- **Environment Files**: Secrets managed via `/run/agenix/` (Agenix)
- **Health Monitoring**: Automatic service health checks every 30 seconds
- **Nginx Proxy**: SSL/TLS termination, rate limiting, IP allowlisting

### Security Model

**Lobster User (Service Account):**
- `isSystemUser = true` (not a login user)
- **No sudo access** (removed ALL privileges)
- **No wheel group** membership
- **No docker group** (prevents container escapes)
- Home: `/var/lib/lobster` (not `/home/lobster`)
- Shell: `/bin/bash` (non-interactive)

**Systemd Hardening:**
```nix
NoNewPrivileges = true;
PrivateTmp = true;
ProtectSystem = "strict";
ProtectHome = true;
ReadWritePaths = [ "/var/lib/openclaw" "/var/lib/lobster" ];
```

**Network Security:**
```nix
# Services only on localhost
interfaces.lo.allowedTCPPorts = [18789 18800];

# External access via nginx only
allowedTCPPorts = [80 443];
```

### Configuration Pattern

**Basic Setup:**
```nix
# In host configuration
services.openclaw = {
  enable = true;
  port = 18789;
  environmentFile = "/run/agenix/openclaw-env";
  settings = {
    gateway = {
      mode = "local";
      bind = "loopback";
      auth.mode = "token";
    };
  };
};
```

**With AIStor Storage:**
```nix
# 1. Enable storage service
services.openclaw-storage = {
  enable = true;
  aistorCredentialsFile = "/run/agenix/minio-cache-credentials";
};

# 2. Create the secret file:
# cd ~/@projects/infra/nixos/secrets
# agenix -e minio-cache-credentials.age
# Format:
# MINIO_ACCESS_KEY=your_access_key
# MINIO_SECRET_KEY=your_secret_key
```

**With Nginx Reverse Proxy:**
```nix
# Enable nginx for secure external access
services.openclaw.nginx = {
  enable = true;
  domain = "openclaw.local";  # Or your domain
  enableSSL = false;  # Set true for Let's Encrypt
  allowedIPs = [ "127.0.0.1" "::1" "10.0.0.0/8" ];
};
```

### Architecture Note (2026-02-02 Refactor)

**Problem:** The upstream nix-openclaw package has a missing `hasown` dependency (form-data@2.5.4 requires it, but it's not in the pnpm lockfile). This causes `Error: Cannot find module 'hasown'` when running OpenClaw.

**Solution:** We use a workaround overlay (`modules/openclaw-workaround-overlay.nix`) that:
1. Creates a minimal `hasown` stub package
2. Patches the OpenClaw package to include it in node_modules
3. Wraps the binary with proper NODE_PATH

**Important:** The Home Manager module (`nix-openclaw.homeManagerModules.openclaw`) is deliberately NOT imported in `home.nix`. This prevents binary shadowing where the HM binary (without the workaround) would shadow the system binary (with the workaround).

**CLI Access:** The `openclaw` command is provided by `environment.systemPackages` in the NixOS module, ensuring it uses the same overlayed package as the systemd service.

**Upstream Issue:** https://github.com/openclaw/nix-openclaw/issues/45

### Required Secrets

**File:** `secrets/age-secrets.nix`

| Secret | Purpose | Required For |
|--------|---------|--------------|
| `openclaw-env` | OpenClaw gateway environment | Always |
| `minio-cache-credentials` | AIStor S3 access | Storage service |
| `anthropic-api-key` | Claude API | Anthropic provider |
| `openai-api-key` | OpenAI API | OpenAI provider |

**Creating Secrets:**
```bash
cd ~/@projects/infra/nixos/secrets

# OpenClaw environment
agenix -e openclaw-env.age
# Add: OPENCLAW_GATEWAY_TOKEN=secret_token_here

# AIStor credentials (for storage service)
agenix -e minio-cache-credentials.age
# Add: MINIO_ACCESS_KEY=xxx
#      MINIO_SECRET_KEY=yyy
```

### Lobster User Account

The `lobster` system user is dedicated for OpenClaw bot operations:
- **Type**: `isSystemUser = true` (service account, no login)
- **Home**: `/var/lib/lobster`
- **Groups**: `lobster`, `rclone` (minimal)
- **Sudo**: **NONE** (intentionally removed)
- **Purpose**: Isolated AI agent execution with minimal privileges
- **Services**: `openclaw`, `openclaw-storage`, `openclaw-backups`

**Why No Sudo?**
The AI agent runs with only the permissions it needs. If compromised, it cannot:
- Escalate to root
- Access other user data
- Modify system configuration
- Install software

### Health Monitoring

All OpenClaw services have automatic health monitoring:

```bash
# Check service health
systemctl status openclaw-health.timer
systemctl status openclaw-storage-health.timer

# View health check logs
journalctl -u openclaw-health -f
journalctl -u openclaw-storage-health -f

# Manual health check
curl http://127.0.0.1:18789/health
curl http://127.0.0.1:18800/health
```

**Auto-restart:** Services automatically restart if health checks fail 3 times.

### Nginx Reverse Proxy

**Features:**
- SSL/TLS termination (with Let's Encrypt support)
- Rate limiting (10 req/sec, burst 20)
- IP allowlisting for security
- WebSocket support for gateway
- Security headers (X-Frame-Options, etc.)

**Endpoints:**
- `http://openclaw.local/gateway` - WebSocket gateway
- `http://openclaw.local/storage` - Storage MCP API
- `http://openclaw.local/health` - Health check

**Enable SSL (requires public domain):**
```nix
services.openclaw.nginx = {
  enable = true;
  domain = "openclaw.yourdomain.com";
  enableSSL = true;  # Enables Let's Encrypt
};
```

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
- **User**: `lobster` (OpenClaw bot account - no sudo)
- **Buckets**:
  - `ai-models` - Trained models and checkpoints
  - `training-data` - Datasets and corpora
  - `experiments` - ML experiment artifacts
  - `ai-logs` - Training logs and metrics
  - `nix-cache` - Nix binary cache

### Setup Instructions

**1. Create AIStor Credentials Secret:**
```bash
cd ~/@projects/infra/nixos/secrets
agenix -e minio-cache-credentials.age
```

**Content format:**
```
MINIO_ACCESS_KEY=your_access_key_here
MINIO_SECRET_KEY=your_secret_key_here
```

**2. Enable Storage Service:**
Already configured in `configuration.nix`:
```nix
services.openclaw-storage = {
  enable = true;
  aistorCredentialsFile = "/run/agenix/minio-cache-credentials";
};
```

**3. Rebuild and Test:**
```bash
just switch

# Test connection
mc alias set aistor http://10.1.1.120:9000 $MINIO_ACCESS_KEY $MINIO_SECRET_KEY
mc ls aistor
```

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
- **Port**: 18800 (localhost only)
- **User**: `lobster` (restricted service account)
- **Features**:
  - Natural language: "Store model from training run 47"
  - Direct AIStor S3 integration
  - Rclone cloud backup coordination
  - Zero license fees

**Access via Nginx:**
```bash
curl http://openclaw.local/storage/api/v1/buckets
```

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

### Environment File Format
```bash
# /run/agenix/openclaw-env (managed via Agenix)
OPENCLAW_GATEWAY_TOKEN=secret_token_here
ANTHROPIC_API_KEY=sk-...
OPENAI_API_KEY=sk-...
```

## Critical Gaps (TODO)
1. **Backups**: No borgbackup/restic configured
2. **Monitoring**: No Prometheus/Grafana
3. **Firewall**: SSH root enabled, no fail2ban
4. **Encryption**: No LUKS disk encryption

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

# OpenClaw
systemctl status openclaw                    # Check gateway
systemctl status openclaw-storage            # Check storage
systemctl status openclaw-health.timer       # Check health monitoring
journalctl -u openclaw -f                    # Follow gateway logs
journalctl -u openclaw-storage -f            # Follow storage logs

# Development
just check               # nix flake check
just dev-setup           # Full pipeline
```

## Security Notes
- ✅ **OpenClaw**: Service user has no sudo (fixed)
- ✅ **OpenClaw**: Services bind to localhost only (fixed)
- ✅ **OpenClaw**: Nginx reverse proxy with SSL available
- 🔴 **SSH**: Root login enabled (risk)
- 🔴 **SSH**: No fail2ban configured
- 🔴 **Mining**: API ports should be localhost-only

## Opencode Skills

**Project-specific skills** (located in `/etc/nixos/.opencode/skills/`):
- `nixos-manager` - NixOS rebuilds, packages, secrets management via MCP

**User-level skills** (located in `~/.config/opencode/skills/`):
- `api-testing` - REST/GraphQL/WebSocket API testing
- `docker-essentials` - Container management and Docker Compose
- `git-workflows` - Advanced Git operations and collaboration
- `system-monitor` - System monitoring and performance analysis

**Using Skills:**
```bash
# Load a skill
skill nixos-manager

# Use skill tools (MCP-based)
skill_mcp nixos-manager rebuild_system
```

## Recent Fixes (2026-02-02)

### Steam/Proton Gaming Fixes
- **Fixed duplicate `programs.steam` definitions** in `modules/gaming.nix`
- **Added vulkan-loader** for better Proton compatibility
- **Created reset script** at `/etc/nixos/scripts/reset-proton-prefixes.sh`
- **VRChat** now uses Proton-GE-RTSP correctly
- **Deadlock** configured for Proton Experimental

### OpenClaw Container Fixes
- **Updated environment variables** from deprecated `MOLTBOT_*/CLAWDBOT_*` to `OPENCLAW_*`
- **Fixed user ID** from 1000:1000 to 982:979 (lobster user)
- **Fixed container entrypoint** to use proper command execution
- **Moved nixos-manager skill** from user config to project directory

## Unique Features
- Custom `services.mining` option (not upstream)
- Smart mining pause (auto-detects VR/gaming)
- VRChat analytics blocking (18+ domains)
- WiVRn Quest Pro streaming (100Mbps HEVC)
- GameMode +150MHz NVIDIA overclock
- Systemd slices for workload isolation
- Multi-tier DNS with DoT
- MCP servers for AI assistants (kimi-code, kilo-code, opencode, claude-code, qwen-code)
- **OpenClaw AI agent orchestration (cluster-wide, hardened)**
- **OpenClaw nginx reverse proxy with SSL/TLS**
- **30-second health monitoring with auto-restart**

## Files
- **65+** nix files, **~7,000+** total lines
- **26+** modules, **320+** options
- **4** hosts in cluster

---
*Last updated: 2026-02-02 | Refactor: Steam/Proton fixes, OpenClaw container fixes, environment variables updated*
