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

### Test Configuration
```bash
just test
```

### Deploy to All Hosts
```bash
just deploy
```

### Apply to Local Host Only
```bash
just switch
```

## Safety Rules

CRITICAL: Always follow these rules:
1. **ALWAYS** run `just test` before `just deploy`
2. If SSH breaks on any node, STOP immediately
3. Check `modules/networking/*` changes affect zephyr AND nexus
4. Read commit messages before deploying

## Troubleshooting

### Build Failures
```bash
# Check error details
nix log .#nixosConfigurations.zephyr

# Fix and rebuild
just test
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
