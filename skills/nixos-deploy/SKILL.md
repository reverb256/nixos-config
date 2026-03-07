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
| **nexus** | Gaming/mining | AMD Zen, 2x NVIDIA | Tailscale | Colmena SSH |
| **forge** | Mining/AI | Intel, NVIDIA + AMD | Tailscale | Colmena SSH |
| **sentry** | Mining/AI | AMD Zen, AMD GPU | Tailscale | Colmena SSH |

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
just sentry          # Deploy to sentry only
just test            # Dry-run build test
```

### Direct Colmena Commands
```bash
# Build all hosts (dry run)
nix run .#apps.x86_64-linux.colmena -- build

# Apply to specific host
nix run .#apps.x86_64-linux.colmena -- apply --on zephyr

# Apply to remote hosts (uses boot goal)
nix run .#apps.x86_64-linux.colmena -- apply --on nexus,forge,sentry boot

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

# Test build on zephyr
nbuild  # Auto-pauses mining
```

### 3. Deploy to Remote Hosts
```bash
# Option A: Use Justfile (recommended)
just deploy

# Option B: Direct colmena
nix run .#apps.x86_64-linux.colmena -- apply --on nexus,forge,sentry boot
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

### Remote Hosts Use `boot` Goal
Remote hosts (nexus, forge, sentry) use the `boot` goal by default to avoid switch inhibitors like dbus changes. This means:
- Changes activate on next reboot
- Safer for remote deployment
- Can manually reboot to apply: `ssh nexus "sudo reboot"`

## Mining Auto-Pause

All deployment commands automatically pause mining on remote hosts:
```bash
# The justfile recipes handle this:
# 1. Stop xmrig@* and lolminer-* services on target host
# 2. Run deployment
# 3. Restart mining services (even if deployment fails)
```

## Sync Configuration from Zephyr

The cluster is configured from zephyr. To sync:

### Option A: Git-Based Sync
```bash
# On zephyr, commit and push changes
cd /etc/nixos
git add .
git commit -m "feat: update gateway config"
git push

# On remote host, pull changes
ssh nexus "cd /etc/nixos && git pull"
ssh forge "cd /etc/nixos && git pull"
ssh sentry "cd /etc/nixos && git pull"
```

### Option B: Colmena Auto-Sync
```bash
# Colmena automatically syncs the flake during deployment
just deploy  # Syncs and applies to all hosts
```

## Host-Specific Differences

### Zephyr (Local)
- Direct `sudo` access
- Uses `switch` goal (immediate activation)
- Development and testing done here

### Nexus (Remote)
- AMD Zen + 2x RTX 3060 Ti
- Gaming + VR + Mining + AI
- Accessed via Tailscale SSH
- Uses `boot` goal

### Forge (Remote)
- Intel + 2x RTX 4060 + AMD GPU
- Mining + AI (multi-GPU CUDA + ROCm)
- Accessed via Tailscale SSH
- Uses `boot` goal

### Sentry (Remote)
- AMD Zen + AMD GPU (Wayland)
- Mining + AI (ROCm)
- Accessed via Tailscale SSH
- Uses `boot` goal

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
ssh nexus "systemctl status xmrig@nvidia0"

# Manually restart mining
ssh forge "sudo systemctl restart lolminer-nvidia"
```

## Colmena Configuration

Located in `flake.nix`:
```nix
colmena = {
  meta = {
    nixpkgs = import inputs.nixpkgs {
      system = "x86_64-linux";
      overlays = [ overlays.default ];
    };
    specialArgs = { inherit inputs outputs; };
  };

  # Hosts defined here
  zephyr = { name, nodes, ... }: {
    imports = [ ./hosts/zephyr/configuration.nix ];
  };

  nexus = { name, nodes, ... }: {
    imports = [ ./hosts/nexus/configuration.nix ];
  };

  forge = { name, nodes, ... }: {
    imports = [ ./hosts/forge/configuration.nix ];
  };

  sentry = { name, nodes, ... }: {
    imports = [ ./hosts/sentry/configuration.nix ];
  };
};
```

## Quick Reference

| Task | Command |
|------|---------|
| Deploy all | `just deploy` |
| Deploy to nexus | `just nexus` |
| Deploy to forge | `just forge` |
| Deploy to sentry | `just sentry` |
| Test build | `just test` |
| Check remote status | `ssh nexus "systemctl status ai-inference-gateway"` |
| View remote logs | `ssh forge "journalctl -u ai-inference-gateway -f"` |

## Related Skills
- **nix-rebuild**: For local NixOS rebuilds on zephyr
- **add-service**: For creating new services to deploy
- **ai-gateway-manager**: For managing gateway after deployment
