# Contributing to Reverb-OS

Welcome! This document explains how to contribute to the Reverb-OS NixOS cluster configuration. This project manages a 4-node cluster with specialized roles for AI, gaming, mining, and monitoring workloads.

## Overview

Reverb-OS is a NixOS-based infrastructure project managing:
- **zephyr**: Master workstation (32 cores, RTX 3090) - Gaming, AI development
- **nexus**: Build/AIStor server (24 cores, dual RTX 3060 Ti) - Distributed builds, object storage
- **forge**: Mining/Compute worker (6 cores, 4 GPUs) - Mining, GPU compute
- **sentry**: Monitoring node (8 cores, RX 5600 XT) - Observability, light builds

Total distributed build capacity: 78 cores across all nodes.

## Prerequisites

- Basic understanding of Nix and NixOS
- Familiarity with flakes and declarative configuration
- Access to the cluster (physical or via Tailscale)
- SSH access with appropriate keys

## Development Environment

1. **Setup Development Shell**
   ```bash
   cd /etc/nixos
   direnv allow  # If using direnv
   # Or enter shell manually: nix develop
   ```

2. **Available Tools in Dev Shell**
   - `just` - Task runner for common operations
   - `colmena` - Multi-host deployment tool
   - `nix fmt` - Code formatting (alejandra)
   - `nix flake check` - Validation
   - `statix`, `deadnix` - Code quality tools
   - `mc` - MinIO client for AIStor

## Making Changes

### 1. Branch Strategy
- Always branch from `main` for new features/fixes
- Use descriptive branch names: `feature/new-module-name` or `fix/mining-config-issue`
- Create PR against `infra` branch (production)

### 2. Code Standards
- Keep modules focused (single responsibility)
- Use `lib.mkEnableOption` for boolean options
- Follow existing naming conventions
- Document new options with clear descriptions
- Use `types.submodule` for complex nested configurations

### 3. Module Development
- Place new modules in `/etc/nixos/modules/`
- Use descriptive names reflecting the module's purpose
- Include proper option definitions and documentation
- Follow the structure: options first, then config

### 4. Host Configuration
- Keep host-specific config minimal
- Use modules for shared functionality
- Only specify unique hardware/role configurations in host files

## Testing Changes

### 1. Local Validation
```bash
# Check syntax and evaluate flake
nix flake check

# Format code
just format

# Lint Nix files
just lint

# Check for dead code
just deadnix
```

### 2. Build Testing
```bash
# Build without applying (safer)
sudo nixos-rebuild build --flake .#zephyr

# Test only (runs in VM-like environment)
sudo nixos-rebuild dry-run --flake .#zephyr
```

### 3. Deployment
```bash
# Deploy to specific host
just deploy-zephyr      # Uses colmena
just deploy-nexus
just deploy-forge
just deploy-sentry

# Deploy to all hosts
just cluster-deploy     # Pulls from infra branch

# Deploy single host via direct command
sudo nixos-rebuild switch --flake .#zephyr
```

## Common Tasks

### Adding a New Module
1. Create `/etc/nixos/modules/new-module.nix`
2. Define options and config following existing patterns
3. Import in relevant host configuration if needed
4. Test with `nix flake check`

### Modifying Existing Module
1. Locate module in `/etc/nixos/modules/`
2. Make changes (maintaining backwards compatibility if possible)
3. Test affected hosts with `nix flake check`
4. Update documentation if needed

### Adding New Host
1. Create directory in `/etc/nixos/hosts/new-host/`
2. Create minimal `configuration.nix` importing common modules
3. Add hardware config and host-specific settings
4. Update flake.nix to include the new host
5. Add to colmena configuration

## Best Practices

### 1. Security
- Never commit secrets to version control
- Use agenix for sensitive data (`secrets/` directory)
- Use localhost-only binding for internal services
- Use nginx reverse proxy for external access to internal services
- Follow principle of least privilege

### 2. Reliability
- Use systemd services with proper dependencies
- Include health monitoring where appropriate
- Use declarative configuration over imperative scripts
- Test changes before deploying to production

### 3. Performance
- Use binary caches appropriately
- Consider build resource allocation
- Minimize rebuild time with careful dependency management
- Use distributed builds across cluster when applicable

### 4. Maintainability
- Keep modules focused and composable
- Use consistent naming conventions
- Document new options clearly
- Follow existing code style
- Keep host configs minimal

## Git Workflow

### Feature Development
1. Create feature branch: `git checkout -b feature/description`
2. Make changes and commit with clear messages
3. Test thoroughly (flake check, build test)
4. Push branch and create PR
5. PR gets reviewed and merged to `main`
6. Auto-merged to `infra` after validation

### Hotfix Process
1. Branch from `infra` for urgent fixes
2. Make minimal changes
3. Test immediately
4. PR directly to `infra`
5. Cherry-pick to `main` to maintain consistency

## Useful Commands

### Development
```bash
just check              # Run flake check
just format             # Format all Nix files
just lint               # Run Statix linter
just deadnix           # Find dead Nix code
just dev-setup         # Setup full development environment
```

### Cluster Management
```bash
just cluster-status    # Check all hosts
just cluster-deploy    # Deploy to all hosts
just cluster-update    # Update flake + deploy
just cluster-resources # Monitor cluster resources
```

### Service Management
```bash
just mining-start      # Start mining
just mining-status     # Check mining
just gaming-start      # Enable gaming mode
just gaming-status     # Check gaming mode
```

## Questions?

- Check existing documentation: `MASTER_DOCS.md`
- Review the flake.nix for system architecture
- Look at existing modules for patterns
- Ask in the team communication channels

Thank you for contributing to Reverb-OS!