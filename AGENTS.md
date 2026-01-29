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

## Code Quality
```bash
just format    # alejandra .
just lint      # statix check .
deadnix .      # Find dead code
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

## Files
- **65** nix files, **~6,935** total lines
- **23** modules, **310+** options
- **4** hosts in cluster

---
*Last updated: 2026-01-28 | Audit commit: 83fd93b*
