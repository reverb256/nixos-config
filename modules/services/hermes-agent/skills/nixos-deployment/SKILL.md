---
name: nixos-deployment
description: Deploy NixOS configurations across the 4-host cluster using just commands
version: 1.0.0
author: j_kro
license: MIT
metadata:
  hermes:
    tags: [NixOS, Colmena, Deployment, Cluster]
---

# NixOS Cluster Deployment

Deploy NixOS flake configurations across zephyr, nexus, forge, sentry.

## Quick Commands

### Validate Configuration
```bash
nix flake check        # Quick validation (~5 seconds)
just build              # Build local configuration (~2 minutes)
```

### Deploy to All Hosts
```bash
just deploy            # Deploy to all hosts via Colmena
```

### Apply to Local Host Only
```bash
just switch            # Apply to local host (auto-pauses mining)
```

## Safety Rules

CRITICAL: Always follow these rules:
1. **ALWAYS** run `nix flake check` before committing
2. **Run** `just build` to verify configuration builds
3. If SSH breaks on any node, STOP immediately
4. Check `modules/networking/*` changes affect zephyr AND nexus
5. Read commit messages before deploying

## Troubleshooting

### Build Failures
```bash
# Check error details
nix log .#nixosConfigurations.zephyr

# Fix and rebuild
just build
```

### SSH Issues
```bash
# Test SSH to each node
ssh zephyr "echo OK"
ssh nexus "echo OK"
ssh forge "echo OK"
ssh sentry "echo OK"
```

## Related Skills
- k8s-migration: For Kubernetes deployment steps
- cluster-management: For multi-host operations
