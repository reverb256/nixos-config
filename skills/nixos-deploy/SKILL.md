---
name: nixos-deploy
description: Multi-host NixOS deployment using Colmena. Use when user asks to: deploy to cluster, apply to remote hosts, sync config, deploy to nexus/forge/sentry, or use colmena commands.
---

# NixOS Deploy

Multi-host NixOS deployment using Colmena for the 4-host cluster (zephyr, nexus, forge, sentry).

## When to Use This Skill

Use this skill when the user:
- Asks to "deploy to cluster", "deploy to all hosts", "push config"
- Wants to "deploy to nexus", "apply to forge", "update sentry"
- Mentions "colmena", "remote deployment", "multi-host"
- Needs to sync NixOS configuration from zephyr to remote hosts
- Asks about deployment status, remote builds, or applying changes

## Cluster Overview

| Host | Role | Hardware | Network | Access |
|------|------|----------|---------|--------|
| **zephyr** | Main workstation | AMD Zen, 2x NVIDIA | Local | Direct (sudo) |
| **nexus** | Primary server, storage, AI gateway | AMD Zen, 1x NVIDIA | Tailscale | Colmena SSH |
| **forge** | GPU compute, mining | Intel, 2x NVIDIA + 2x AMD | Tailscale | Colmena SSH |
| **sentry** | Monitoring, logging, Vulkan AI | AMD Zen, AMD GPU | Tailscale | Colmena SSH |

### Network Architecture
```
                ┌─────────────────────────────────────┐
                │           Tailscale VPN              │
                ├─────────────────────────────────────┤
                │                                     │
    ┌───────────▼──────────┐  ┌──────────▼──────────┐
    │      zephyr         │  │      nexus          │
    │  (workstation)      │  │  (gaming/mining)    │
    │  100.64.0.1         │  │  100.64.0.2         │
    └──────────────────────┘  └─────────────────────┘
                │
    ┌───────────▼──────────┐  ┌──────────▼──────────┐
    │      forge          │  │      sentry         │
    │  (mining/AI)        │  │  (mining/AI)        │
    │  100.64.0.3         │  │  100.64.0.4         │
    └──────────────────────┘  └─────────────────────┘
```

## Deployment Commands

### Justfile Recipes (Recommended)
```bash
just deploy          # Deploy to all hosts
just zephyr          # Deploy to zephyr only (local)
just nexus           # Deploy to nexus only
just forge           # Deploy to forge only
just sentry           # Deploy to sentry only
just check            # Fast flake validation
just build            # Build current host
just test-apply       # Temporary activation test
```

### Direct Colmena Commands
```bash
# Build all hosts (dry run)
nix run .#apps.x86_64-linux.colmena -- build

# Apply to specific host
nix run .#apps.x86_64-linux.colmena -- apply --on zephyr

# Apply to remote hosts (production path uses switch activation)
nix run .#apps.x86_64-linux.colmena -- apply --on nexus,forge,sentry

# Apply to all hosts
nix run .#apps.x86_64-linux.colmena -- apply
```

### SSH Access to Remote Hosts
```bash
# Access via Tailscale
ssh j_kro@100.64.0.2  # nexus
ssh j_kro@100.64.0.3  # forge
ssh j_kro@100.64.0.4  # sentry

# Or use hostnames if configured
ssh nexus
ssh forge
ssh sentry
```

## Deployment Workflow

### 1. Make Configuration Changes
Edit files on zephyr (`/etc/nixos/`):
```bash
# Edit shared modules
vim modules/services/ai-inference/gateway.nix

# Edit host-specific config
vim hosts/nexus/configuration.nix
```

### 2. Validate Configuration
```bash
# Fast syntax check
nix flake check

# Build the current host (Zephyr offloads to Nexus)
just build
```

### 3. Deploy to Remote Hosts
```bash
# Option A: Use Justfile (recommended)
just deploy

# Option B: Direct Colmena (only when the recommended just recipe is unsuitable)
nix --option pure-eval false run .#apps.x86_64-linux.colmena -- apply --on nexus,forge,sentry
```

### 4. Verify Remote Deployment
```bash
# Check remote service status
ssh nexus "systemctl status ai-inference-gateway"

# Check remote logs
ssh forge "journalctl -u ai-inference-gateway -n 20"
```

## Deployment Goals

### Goals Explained
| Goal | Behavior | Use Case |
|------|----------|----------|
| `switch` | Activate + persist | Production changes |
| `boot` | Activate for next boot | Avoids inhibitors (dbus) |
| `build` | Build only | Validation |
| `test` | Activate, rollback on reboot | Temporary testing |

### Deployment Activation Goal
The supported `just deploy` path activates remote generations immediately with
`switch-to-configuration switch` after copying the closure. It is not a
`boot`-only deployment. Use `boot` only for an intentional direct-Colmena
workflow when you explicitly want activation deferred until reboot.

## Mining and Deployment Impact

Deployment behavior is defined by the `justfile` and its preflight/build
scripts. Do not assume mining is paused unless the selected recipe or script
explicitly documents it; verify service impact before deploying to a mining
host.

## Sync Configuration from Zephyr

The cluster is configured from zephyr. To sync:

### Option A: Supported Deployment Sync
```bash
# From Zephyr, validate and deploy the canonical source checkout
just check
just build
just deploy
```

`just deploy` builds from the canonical source, copies the closure, activates
it on the target, and then synchronizes remote `/etc/nixos` checkouts to the
central repository. Do not use ad-hoc `git pull` on a remote host as a
replacement for deployment; use `just sync-nodes` when only checkout sync is
needed.

## Host-Specific Differences

### Zephyr (Local)
- Direct `sudo` access
- Uses `switch` goal (immediate activation)
- Development and testing done here

### Nexus (Remote)
- AMD Zen + 1x RTX 3060 Ti
- Storage + AI gateway + server workloads
- Accessed via Tailscale SSH
- `just deploy` uses immediate `switch` activation

### Forge (Remote)
- Intel + 2x RTX 4060 + 2x RX 5700 XT
- GPU compute + mining (multi-GPU CUDA + ROCm)
- Accessed via Tailscale SSH
- `just deploy` uses immediate `switch` activation

### Sentry (Remote)
- AMD Zen + RX 5600 XT
- Monitoring, logging, and Vulkan AI inference
- Accessed via Tailscale SSH
- `just deploy` uses immediate `switch` activation

## Troubleshooting Remote Deployment

### SSH Connection Issues
```bash
# Verify Tailscale connectivity
ping 100.64.0.2  # nexus
tailscale status

# Check SSH access
ssh -v j_kro@nexus

# Verify colmena can reach host
nix run .#apps.x86_64-linux.colmena -- eval --on nexus
```

### Build Failures on Remote
```bash
# Check Nix path on remote
ssh nexus "which nix"
ssh nexus "nix --version"

# Verify flake exists on remote
ssh nexus "ls -la /etc/nixos/flake.nix"

# Check for git untracked files issue
ssh nexus "cd /etc/nixos && git status"
```

### Service Failures After Deployment
```bash
# Check service status on remote
ssh nexus "systemctl --failed"

# View specific service logs
ssh forge "journalctl -u ai-inference-gateway -n 50"

# Rollback on remote
ssh sentry "sudo nixos-rebuild switch --rollback"
```

### Mining Not Restarting
```bash
# Check mining services on remote

# Manually restart mining
```

## Colmena Configuration

The unified `hosts` attribute set in `flake.nix` is the source of truth.
`colmena.nix` receives that set and derives the Colmena nodes, deployment
metadata, target hosts, tags, and shared modules. The checked-in root
`machines` file is passed to Colmena as `meta.machinesFile`; it is distinct
from the generated `/etc/nix/machines` used by the Nix daemon for distributed
builds.

## Quick Reference

| Task | Command |
|------|---------|
| Deploy all | `just deploy` |
| Deploy to nexus | `just nexus` |
| Deploy to forge | `just forge` |
| Deploy to sentry | `just sentry` |
| Check configuration | `just check` |
| Test build/activation | `just test-apply` |
| Check remote status | `ssh nexus "systemctl status ai-inference-gateway"` |
| View remote logs | `ssh forge "journalctl -u ai-inference-gateway -f"` |

## Related Skills
- **nix-rebuild**: For local NixOS rebuilds on zephyr
- **add-service**: For creating new services to deploy
- **ai-gateway-manager**: For managing gateway after deployment
