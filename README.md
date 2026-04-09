# NixOS Cluster Configuration

Flake-based multi-host NixOS configuration for a 4-node cluster.

## Quick Start

```bash
# Rebuild local host
just switch

# Deploy to all nodes
just deploy

# Deploy to specific node
just switch <hostname>

# Test configuration without applying
just test
```

## Cluster Architecture

**Nodes:**
- **Zephyr** (10.1.1.110) - Control plane, gaming, AI inference
- **Nexus** (10.1.1.120) - Storage, GPU computing
- **Forge** (10.1.1.130) - GPU computing, mining
- **Sentry** (10.1.1.140) - Monitoring, logging

**Resources:** 78 cores, 123GB RAM, 7 GPUs, 8.4TB storage

## Configuration Structure

```
/etc/nixos/
├── flake.nix                    # Main flake with host definitions
├── overlay.nix                  # Custom package overlays
├── hosts/                       # Host-specific configurations
│   ├── zephyr/
│   ├── nexus/
│   ├── forge/
│   └── sentry/
├── modules/                     # Reusable NixOS modules
│   ├── common-host-defaults.nix
│   ├── system/
│   ├── services/
│   ├── desktop/
│   └── gaming/
└── scripts/                     # Utility scripts
```

## Key Documentation

- **CLAUDE.md** - Agent patterns and best practices
- **AGENTS.md** - Universal cluster patterns and workflows
- **ROADMAP.md** - Kubernetes migration plan
- **AGENT_INCIDENT_REPORT.md** - Post-mortem of SSH breakage incident

## Safety First

⚠️ **Before making changes to shared modules:**
1. Read CLAUDE.md "Critical Agent Safety Constraints"
2. Use `lib.mkOptionDefault` for extensible options
3. Test on nodes with custom configs (nexus, forge) before deploying
4. Verify SSH port 22 is never blocked

## CI/CD

- **Colmena** for multi-host deployment
- **GitHub Actions** for CI/CD pipeline
- **Distributed builds** across cluster nodes

## See Also

- [NixOS Manual](https://nixos.org/manual/nixos/stable/)
- [Home Manager Manual](https://nix-community.github.io/home-manager/)
- [Flakes Guide](https://nixos.wiki/wiki/Flakes)
