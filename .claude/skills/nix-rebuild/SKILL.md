---
name: nix-rebuild
description: Safely rebuild NixOS following the testing workflow (flake check -> build -> test -> switch)
---

# NixOS Rebuild

Always follow this order when rebuilding NixOS:

## Workflow

### 1. Check Syntax (fastest - 5 seconds)
```bash
nix flake check
```

### 2. Build Only (validate without applying - 1-2 minutes)
```bash
sudo nixos-rebuild build --flake .#HOSTNAME
```

### 3. Test (apply temporarily, rolls back on reboot)
```bash
sudo nixos-rebuild test --flake .#HOSTNAME
```

### 4. Switch (persistent application)
```bash
sudo nixos-rebuild switch --flake .#HOSTNAME
```

## Available Hosts

| Host | Role | Deploy Command |
|------|------|----------------|
| zephyr | Local (main) | `sudo nixos-rebuild switch --flake .#zephyr` |
| forge | Remote GPU | `just forge` |
| nexus | Remote storage | `just nexus` |
| sentry | Remote monitor | `just sentry` |

## Quick Reference

```bash
# Rebuild zephyr (default)
nix flake check && sudo nixos-rebuild switch --flake .#zephyr

# Deploy to all remote hosts
just deploy

# Deploy to specific remote host
just forge  # or just nexus, just sentry
```

## Before Rebuilding

Ask the user: **Which host?** (default: zephyr)

## Common Issues

- **"attribute missing"**: Module not imported in `modules/default.nix`
- **"undefined variable"**: Check Nix string escaping with `''${}`
- **Build fails**: Run `nix flake check` first for syntax errors
- **Service fails to start**: Check logs with `journalctl -u SERVICE_NAME`
