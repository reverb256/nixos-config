## Build & Test Commands

### Primary Workflow: Just Commands
```bash
just test              # Verify configuration
just switch            # Apply to local host (auto-pauses mining)
just deploy            # Deploy to all cluster hosts
just ci-local          # Run full CI pipeline locally
```

### Legacy Commands
```bash
nix flake check                               # Fast syntax check
sudo nixos-rebuild build --flake .#zephyr    # Build without applying
sudo nixos-rebuild test --flake .#zephyr     # Test (rollback safe)
nix flake update                              # Update flake inputs
```

### Critical Workflows
**Before Deployment**:
1. `just sync` - Ensure all nodes have same config
2. `just test` - Verify configuration builds
3. Check storage mounts
4. Review hookify warnings

**Git Workflow**:
1. Make changes
2. `git add` new files (Nix only packages git-tracked files!)
3. `git commit`
4. `just test`
5. `just sync`
6. `just deploy`
