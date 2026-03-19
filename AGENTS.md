# NixOS Cluster - Agent Guidelines

## Quick Start

```bash
just check              # Quick flake validation (no build)
just test               # Build all hosts (verify config)
just switch             # Apply to local host
just deploy [<host>]    # Deploy to all or specific host
just rollback           # Rollback local host
```

## Project Overview

| Host | IP | Role |
|------|-----|------|
| Zephyr | 10.1.1.110 | Control plane, gaming, AI |
| Nexus | 10.1.1.120 | Storage, GPU computing |
| Forge | 10.1.1.130 | GPU computing, mining |
| Sentry | 10.1.1.140 | Monitoring, logging |

**Resources**: 78 cores, 123GB RAM, 7 GPUs, 8.4TB storage

## Project Structure

```
/etc/nixos/
├── flake.nix              # Main flake
├── colmena.nix            # Multi-host deployment
├── hosts/<hostname>/      # Host configs (never edit hardware-configuration.nix)
├── modules/               # Reusable modules (default.nix imports all)
│   ├── profiles/          # Hardware/role/network profiles
│   ├── system/            # Core system modules
│   └── services/          # Background services
└── secrets/               # Agenix encrypted secrets
```

## ⚠️ Critical Safety Rules

### mkOptionDefault (MANDATORY for extensible options)

```nix
# ❌ WRONG - Replaces node configs (breaks SSH!)
networking.firewall.allowedTCPPorts = [22 53 6443];

# ✅ CORRECT - Merges with node configs
networking.firewall.allowedTCPPorts = lib.mkOptionDefault [22 53 6443];
```

| Use `mkOptionDefault` | Use Direct Assignment |
|-----------------------|----------------------|
| Lists (ports, packages) | Booleans |
| Attrs that merge (systemd.services) | Strings (hostName) |

### Stop Immediately If
- SSH breaks on any node
- Multiple nodes affected
- `nix flake check` fails

## Code Style

- **2-space indentation**, trailing semicolons
- **kebab-case** for files: `gpu-exporters.nix`
- **Line length**: 80-100 chars

### Module Template

```nix
{ config, lib, pkgs, ... }:
let
  cfg = config.services.my-service;
  inherit (lib) mkEnableOption mkOption types mkIf;
in {
  options.services.my-service = {
    enable = mkEnableOption "My Service";
    port = mkOption { type = types.port; default = 8080; };
  };
  config = mkIf cfg.enable {
    networking.firewall.allowedTCPPorts = lib.mkOptionDefault [ cfg.port ];
    systemd.services.my-service = {
      wantedBy = [ "multi-user.target" ];
      serviceConfig.ExecStart = "${pkgs.my-package}/bin/my-service";
    };
  };
}
```

### Naming Conventions

| Namespace | Usage |
|-----------|-------|
| `services.*` | Background daemons |
| `programs.*` | Interactive GUI apps |
| `hardware.*` | Hardware config |
| `profiles.*` | Composable profiles |

## Deployment Workflow

1. Edit config on Zephyr (source of truth)
2. `git add` new files (Nix only sees git-tracked files!)
3. `just check` → `just switch` → `just deploy`

### Testing Checklist

| File Changed | Test On |
|--------------|---------|
| `modules/networking/*` | zephyr AND nexus |
| `modules/system/ssh.nix` | ALL 4 nodes |
| `modules/system/users.nix` | ALL 4 nodes |
| `modules/default.nix` | Entire cluster |

## Profile System

```nix
hardware.profiles = { amd.zen = true; nvidia.enable = true; };
profiles.role = { workstation = true; gaming = true; };
profiles.network.tailscale.enable = true;
```

## Reference

| Document | Purpose |
|----------|---------|
| `AGENT_INCIDENT_REPORT.md` | Post-mortems of past incidents |
| `ROADMAP.md` | Kubernetes migration plan |
| `modules/README.md` | Module development guide |

---

**Version**: 3.1 | **Updated**: 2026-03-18
