# NixOS Cluster - AI Agent Guide

Configuration and development guidelines for the Reverb-OS NixOS cluster.

---

## Project Overview

Reverb-OS is a production NixOS 26.05 cluster with 4 nodes managed centrally from zephyr.

**Architecture:**
- **OS:** NixOS 26.05 (flakes-based)
- **Container Engine:** Podman (declarative, rootless)
- **Networking:** Tailscale mesh VPN (100.x.x.x) + 1Gbps wired
- **Build System:** Distributed builds with GPU acceleration (28 parallel jobs)

**Codebase Statistics (2026-02-12):**
- Nix files: 82
- Modules: 53
- Total Nix lines: ~14,500

---

## Cluster Nodes

| Host | IP | Tailscale IP | Cores | GPU | Role |
|------|----|--------------|-------|-----|------|
| zephyr | 10.1.1.110 | 100.81.182.5 | 32 | RTX 3090 | Master Workstation |
| nexus | 10.1.1.120 | 100.86.158.18 | 24 | 2x RTX 3060 Ti | Build/Backup |
| forge | 10.1.1.130 | 100.95.222.45 | 6 | 2x RTX 4060 + 2x RX 5700 XT | GPU Mining |
| sentry | 10.1.1.140 | 100.82.210.39 | 16 | RX 5600 XT | Monitoring |

---

## Configuration Management

**Source of Truth:** `/etc/nixos/` on zephyr (10.1.1.110)

All cluster configuration changes MUST be made here.

**Deployment Commands:**
```bash
just deploy          # Deploy current branch to all nodes
just zephyr          # Deploy to zephyr only
just nexus           # Deploy to nexus only
just forge           # Deploy to forge only
just sentry          # Deploy to sentry only
just switch          # Local switch (current node)
just test            # Validate configuration
```

---

## File Structure

```
/etc/nixos/
├── flake.nix              # Main entry point
├── common-base.nix        # Shared configuration
├── home.nix               # Home Manager config (user j_kro)
├── justfile               # Deployment commands
├── modules/               # Shared NixOS modules (53 files)
├── hosts/                 # Per-host configs
│   ├── zephyr/
│   ├── nexus/
│   ├── forge/
│   └── sentry/
├── secrets/               # Agenix encrypted secrets
├── docs/                  # Operational documentation
└── doc-archive/           # Historical documentation
```

---

## CI/CD Pipeline

### GitHub Actions Workflows

| Workflow | Trigger | Action |
|----------|---------|--------|
| test-and-merge.yml | Push to `main` | Test + auto-merge to `infra` |
| deploy-prod.yml | Push to `infra` | Build + colmena deploy |

### Branching Strategy

- **`main`** - Development branch
- **`infra`** - Production branch (auto-created from main)

**Workflow:** main → test → auto-merge → infra → deploy

---

## Key Modules

| Module | Purpose |
|--------|---------|
| desktop.nix | Plasma 6 + Wayland, Flatpak |
| gaming.nix | GameMode, Steam, Proton |
| mining.nix | lolminer, xmrig |
| networking.nix | Static IPs, firewall |
| tailscale.nix | VPN mesh |
| ssh.nix | SSH hardening |
| distributed-builds.nix | Multi-node builds |
| system-packages.nix | Central packages |
| mcp-servers.nix | MCP servers |

---

## Coding Patterns

**Nix Module Structure:**
```nix
{ lib, pkgs, config, ... }:
with lib; let
  cfg = config.<module-name>;
in {
  options.<module-name> = {
    enable = mkEnableOption "description";
  };
  config = mkIf cfg.enable {
    # Implementation
  };
}
```

**Patterns:**
- Use `lib.mkEnableOption` for boolean toggles
- Wrap in `lib.mkIf cfg.enable`
- Import via `../../modules/module-name.nix`

**Service Security:**
- Bind to `127.0.0.1` only
- External access via nginx reverse proxy
- Systemd hardening: `NoNewPrivileges`, `PrivateTmp`, `ProtectSystem`
- Service accounts: `isSystemUser = true`

---

## Distributed Builds

**Status:** ENABLED

| Node | Max Jobs | Features |
|------|----------|----------|
| zephyr | 6 | cuda |
| nexus | 12 | cuda |
| forge | 2 | cuda, rocm |
| sentry | 8 | rocm |

**Total:** 28 parallel jobs

---

## Security Principles

1. **No plaintext secrets** - Agenix encryption
2. **Service isolation** - Localhost binding, nginx proxy
3. **SSH hardening** - No root login, key-based only
4. **Least privilege** - System users without sudo

---

## Common Tasks

**Add user package:**
```bash
# Edit home.nix, add to home.packages
just switch
```

**Add system package:**
```bash
# Edit modules/system-packages.nix
just deploy
```

**Enable service:**
```bash
# Add to hosts/<host>/configuration.nix
just <hostname>
```

---

## Agent Guidelines

**When making changes:**

1. Read existing code first
2. Follow module structure
3. Test on zephyr first
4. Use `just` commands
5. Update docs if needed

**Do NOT:**
- Deploy to nodes independently
- Ignore existing patterns
- Add insecure services

---

## Troubleshooting

### Python Package Builds (UV/pip on NixOS)

**Problem:** Packages like `insightface` fail to build because UV's isolated build environments can't find C++ compilers (NixOS doesn't have `/usr/bin/c++`).

**Solution:** The `stability-matrix.nix` module installs compiler symlinks in `/run/current-system/sw/bin/`:

```nix
# modules/stability-matrix.nix
(pkgs.runCommand "compiler-symlinks" {} ''
  mkdir -p $out/bin
  ln -s ${pkgs.gcc}/bin/g++ $out/bin/c++
  ln -s ${pkgs.gcc}/bin/gcc $out/bin/gcc
  ln -s ${pkgs.gcc}/bin/g++ $out/bin/g++
'')
```

This allows UV's isolated builds to:
1. Keep build isolation ON (setuptools provided by UV)
2. Find `c++`/`gcc` via standard PATH lookup

**Key insight:** Do NOT disable build isolation (`UV_NO_BUILD_ISOLATION=1`) because the venv won't have setuptools. Instead, provide compilers at discoverable paths.

---

## Documentation

| Doc | Location |
|-----|----------|
| Status | docs/CLUSTER_STATUS.md |
| Deployment | docs/DEPLOYMENT_INSTRUCTIONS.md |
| Security | docs/security-policy.md |
| Mining | docs/MINING_STATUS.md |
| Troubleshooting | docs/MINING_TROUBLESHOOTING.md |

---
**Last Updated:** 2026-02-13
