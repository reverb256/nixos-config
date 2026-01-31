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

## Structure
```
/etc/nixos/
├── flake.nix              # 11 inputs, 4 host definitions
├── configuration.nix      # Shared config (~167 lines)
├── hosts/                 # Per-host configs
│   ├── zephyr/           # Main workstation (RTX 3090)
│   ├── nexus/            # Backup server
│   ├── forge/            # Build worker
│   └── sentry/           # Monitoring
├── modules/              # 23 modular configs
├── secrets/              # Agenix encrypted secrets
└── justfile             # 25+ automation commands
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

## Files
- **65** nix files, **~6,935** total lines
- **23** modules, **310+** options
- **4** hosts in cluster

---
*Last updated: 2026-01-29 | Audit commit: MCP configuration added*
