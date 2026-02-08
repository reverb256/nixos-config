# NixOS Cluster - AI Agent Guide

Configuration and development guidelines for the Reverb-OS NixOS cluster.

---

## Project Overview

Reverb-OS is a production NixOS 26.05 cluster with 4 nodes managed centrally from zephyr.

**Architecture:**
- **OS:** NixOS 26.05 (flakes-based)
- **Container Engine:** Podman (declarative, rootless)
- **Networking:** Tailscale mesh VPN (100.x.x.x) + 1Gbps wired
- **Build System:** Distributed builds with GPU acceleration (70 total cores)

---

## Cluster Nodes

| Host | IP | Tailscale IP | Cores | GPU | Role |
|-------|----|--------------|-------|-----|------|
| zephyr | 10.1.1.110 | 100.81.182.5 | 32 | RTX 3090 | Master Workstation |
| nexus | 10.1.1.120 | 100.86.158.18 | 24 | 2x RTX 3060 Ti | Build/Backup |
| forge | 10.1.1.130 | 100.116.190.124 | 6 | 2x RTX 4060 + 2x RX 5700 XT | GPU Mining |
| sentry | 10.1.1.140 | 100.82.210.39 | 8 | RX 5600 XT | Monitoring |

---

## Configuration Management

**Source of Truth:** `/etc/nixos/` on zephyr (10.1.1.110)

All cluster configuration changes MUST be made here. Individual node configs do NOT exist independently - they are managed from the master repository.

**Deployment Commands:**
```bash
# Deploy to all nodes
just deploy

# Deploy to specific node
just zephyr    # Current node (builds locally)
just nexus      # Via SSH from zephyr
just forge      # Via SSH from zephyr
just sentry     # Via SSH from zephyr
```

**Workflow:**
1. Make configuration changes on zephyr
2. Test locally: `nix flake check` and `just switch`
3. Push to GitHub: `just push`
4. Deploy to cluster: `just deploy`

**Never** deploy to other nodes independently - all changes come from zephyr.

---

## File Structure

```
/etc/nixos/
├── flake.nix              # Main entry point
├── configuration.nix        # Common configuration
├── home.nix               # Home Manager config (user j_kro)
├── justfile               # Deployment commands
├── modules/               # Shared NixOS modules
│   ├── desktop.nix        # Plasma 6 + Wayland
│   ├── gaming.nix         # GameMode, Steam
│   ├── mining.nix         # lolminer, xmrig
│   ├── networking.nix      # Static IPs, Tailscale
│   ├── tailscale.nix      # VPN mesh
│   ├── ssh.nix            # SSH hardening
│   ├── system-packages.nix  # Central package list
│   ├── garnix.nix         # CI/CD caching
│   └── ...
├── hosts/                 # Per-host configs (managed from zephyr)
│   ├── zephyr/
│   ├── nexus/
│   ├── forge/
│   └── sentry/
├── secrets/               # Agenix encrypted secrets
└── docs/                 # Documentation
```

---

## Key Modules

| Module | Purpose | Location |
|--------|---------|----------|
| desktop.nix | Plasma 6 + Wayland, Flatpak, Fonts | modules/desktop.nix |
| gaming.nix | GameMode, Steam, Proton, Lutris | modules/gaming.nix |
| mining.nix | lolminer, xmrig (localhost APIs) | modules/mining.nix |
| networking.nix | Static IPs, firewall | modules/networking.nix |
| tailscale.nix | Tailscale mesh VPN | modules/tailscale.nix |
| ssh.nix | SSH hardening (no root login) | modules/ssh.nix |
| system-packages.nix | Central package management | modules/system-packages.nix |
| garnix.nix | CI/CD binary caching | modules/garnix.nix |
| mcp-servers.nix | Model Context Protocol servers | modules/mcp-servers.nix |

---

## Coding Patterns

**Nix Module Structure:**
```nix
{
  lib,
  pkgs,
  config,
  ...
}:
with lib; let
  cfg = config.<module-name>;
in {
  options.<module-name> = {
    # Define options
  };

  config = lib.mkIf cfg.enable {
    # Implementation
  };
}
```

**Common Patterns:**
- Use `lib.mkEnableOption` for boolean toggles
- Use `lib.mkOption` for typed options
- Wrap everything in `lib.mkIf cfg.enable` where applicable
- Import shared modules via `../../modules/module-name.nix`

**Service Security:**
- All services bind to `127.0.0.1` (localhost only)
- External access via nginx reverse proxy with SSL/TLS
- Use `systemd` hardening: `NoNewPrivileges`, `PrivateTmp`, `ProtectSystem`
- User accounts: Use `isSystemUser = true` for service accounts

---

## Quick Reference

**Local Testing (on zephyr):**
```bash
# Validate configuration
nix flake check

# Build without deploying
nix build .#zephyr

# Switch to new configuration
just switch
```

**Distributed Builds:**
- Total capacity: 70 cores across 4 nodes
- GPU acceleration: CUDA (nexus, forge, zephyr), ROCm (forge, sentry)
- Enabled for all nodes

**Secrets Management:**
- Tool: Agenix (age encryption)
- Public key: `/root/.config/sops/age/keys.txt`
- Secrets location: `secrets/` (encrypted)

---

## Security Principles

1. **No plaintext secrets** - All secrets use Agenix encryption
2. **Service isolation** - Services bind localhost, external via nginx
3. **SSH hardening** - No root login, key-based auth only
4. **Least privilege** - Service accounts are `isSystemUser = true` (no sudo)
5. **Network segmentation** - Management over Tailscale, service exposure via nginx only

---

## Common Tasks

**Add a user package:**
```bash
# Edit home.nix, add to home.packages list
# On zephyr: just switch
```

**Add a system package:**
```bash
# Edit modules/system-packages.nix
# On zephyr: just deploy
```

**Enable a service:**
```bash
# Create or edit module in modules/
# Add to host configuration in hosts/<host>/configuration.nix
# Deploy: just <hostname>
```

---

## Documentation

- **System Status:** docs/CLUSTER_STATUS.md
- **Deployment:** docs/DEPLOYMENT_INSTRUCTIONS.md
- **Security:** docs/security-policy.md

---

## Agent Guidelines

When making changes:

1. **Read existing code** - Understand current patterns before modifying
2. **Follow module structure** - Use established patterns in modules/
3. **Test on zephyr first** - Validate before deploying to cluster
4. **Use just commands** - Deploy via `just deploy`, not individual SSH
5. **Update docs** - Keep documentation in sync with code

**Do NOT:**
- Deploy to individual nodes independently
- Create per-node changes without updating zephyr
- Ignore existing patterns and conventions
- Add services that don't follow security model
