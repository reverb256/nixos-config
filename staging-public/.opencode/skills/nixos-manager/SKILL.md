---
name: nixos-manager
description: NixOS system management with MCP tools for rebuild, packages, secrets, and health checks
version: "2.0.0"
license: MIT
compatibility: opencode
metadata:
  category: system
  tools: [nix, nixos-rebuild, agenix, nix-collect-garbage]
  mcp_server: true
---

## What I do
Comprehensive NixOS system management with **MCP (Model Context Protocol)** integration. Provides callable tools for system rebuilds, package management, secret encryption (agenix), garbage collection, and health monitoring.

## MCP Tools Available

This skill provides the following MCP tools that can be called directly:

### `rebuild_system`
Rebuild NixOS system configuration.
- **Parameters**: `flake`, `operation`, `max_jobs`, `cores`, `upgrade`
- **Operations**: switch, build, test, dry-build, dry-activate

### `search_packages`
Search for packages in nixpkgs.
- **Parameters**: `query`, `channel`

### `install_shell_packages`
Install packages temporarily in nix-shell.
- **Parameters**: `packages`, `command`, `pure`

### `manage_secrets`
Manage Agenix secrets (encrypt/decrypt/generate-key/rekey).
- **Parameters**: `operation`, `file`, `output`, `recipients`

### `collect_garbage`
Run Nix garbage collection.
- **Parameters**: `delete_older_than`, `optimise`

### `flake_update`
Update flake inputs.
- **Parameters**: `inputs`, `commit`

### `check_health`
Check NixOS system health.
- **Parameters**: `full`

## Quick Reference (Manual Commands)

### Essential Commands
```bash
# System rebuild
sudo nixos-rebuild switch

# Update flake and rebuild
sudo nixos-rebuild switch --upgrade

# Safe rebuild with limited resources
sudo nixos-rebuild switch --max-jobs 2 --cores 2

# Check what would change (dry run)
sudo nixos-rebuild dry-build
```

### Package Management
```bash
# Search for packages
nix search nixpkgs nodejs

# Install package temporarily
nix-shell -p nodejs

# Install multiple packages temporarily
nix-shell -p nodejs yarn python3 poetry

# Run command directly
nix-shell -p python3 --run "python3 script.py"

# Pure nix-shell (isolated from host)
nix-shell --pure -p nodejs
```

### Secret Management (Agenix)
```bash
# Generate age key
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt

# Get public key
age-keygen -y ~/.config/sops/age/keys.txt

# Encrypt a secret
age -r <public-key> -o secret.age < secret.txt

# Decrypt with private key
age -d -i ~/.config/sops/age/keys.txt -o secret.txt secret.age
```

### Binary Caches (Speed Up Builds)
```nix
nix.settings.substituters = [
  "https://cache.nixos.org"
  "https://cache.nixos-cuda.org"
  "https://nix-community.cachix.org"
  "https://nixpkgs-wayland.cachix.org"
  "https://nix-gaming.cachix.org"
  "https://ezkea.cachix.org"
  "https://zen-browser.cachix.org"
  "https://devenv.cachix.org"
  "https://cache.garnix.io"
  "https://magic.nixos.org"  # GitHub Magic Cache
];
```

### Memory-Safe Rebuilds
```bash
# For systems with low RAM (prevents OOM)
sudo nixos-rebuild switch --max-jobs 1 --cores 1
```

### Garbage Collection
```bash
# Delete old generations
sudo nix-collect-garbage --delete-older-than 30d

# Optimise store (deduplication)
sudo nix-store --optimise
```

## Troubleshooting

### Out of Memory
```bash
# Limit parallelism
sudo nixos-rebuild switch --max-jobs 1 --cores 1
sudo sysctl vm.swappiness=80
```

### Build Failures
```bash
# Show full trace
nixos-rebuild switch --show-trace

# Check build log
nix log /nix/store/...-package.drv
```

### MCP Server Issues
```bash
# Test MCP server manually
cat /home/j_kro/.config/opencode/skills/nixos-manager/mcp.json

# Check server script exists
ls -la /home/j_kro/.config/opencode/skills/nixos-manager/nixos-manager-server.sh
```

## Version History

### v2.0.0
- Added MCP (Model Context Protocol) server
- New tools: rebuild_system, search_packages, install_shell_packages
- New tools: manage_secrets, collect_garbage, flake_update, check_health
- JSON-RPC based communication for AI assistant integration
