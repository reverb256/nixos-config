## Multi-Host Deployment (Colmena)

### Colmena Commands
```bash
nix run .#apps.x86_64-linux.colmena -- build          # Build all hosts
nix run .#apps.x86_64-linux.colmena -- apply --on <host>  # Apply to host
nix run .#apps.x86_64-linux.colmena -- apply --on nexus,forge,sentry boot  # Remote deploy (boot goal)
just deploy                                     # Deploy to all hosts
```

### Remote Deployment Notes
- Remote hosts use `boot` goal to avoid switch inhibitors
- Local host (zephyr) uses `switch` goal
- Mining auto-pauses during deployment

### Cluster Storage Verification
The `modules/system/cluster-storage.nix` module ensures all storage mounts are active on boot.

```bash
systemctl status ensure-cluster-storage
/data/@projects/infra/nixos/verify-cluster-storage.sh
```

### Important Notes
- Keep `system.stateVersion` and `home.stateVersion` current
- Never edit `hardware-configuration.nix` or `flake.lock`
- Always use `just` commands for CI/CD integration
- Never suppress build errors (no `|| true`)
- Check storage mounts after deployment
- Hookify rules enforce safe patterns (see `.claude/hookify-*.md`)
