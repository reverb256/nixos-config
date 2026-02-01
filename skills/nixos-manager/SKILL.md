# ============================================================================
# NIXOS MANAGER SKILL FOR OPENCLAW
# ============================================================================
# Skill that allows Openclaw to manage NixOS configurations safely
---
name: nixos-manager
description: Manage NixOS configurations, packages, and system services
metadata: {"requires":{"bins":["nixos-rebuild"],"os":["linux"],"emoji":"🔧"}}
---

## Capabilities

This skill provides safe NixOS management capabilities:

### Configuration Management
- `nixos-rebuild switch` - Apply configuration changes
- `nixos-rebuild build` - Test configuration before applying  
- `nixos-rebuild test` - Temporary configuration test

### Package Management
- `nix search <package>` - Search for Nix packages
- `nix info <package>` - Get detailed package information
- `nix profile upgrade` - Update user packages

### System Service Management
- `systemctl status <service>` - Check service status
- `systemctl restart <service>` - Restart services safely
- `journalctl -u <service>` - View service logs

### Distributed Build Management
- `nix build --builders-use-substitutes` - Use distributed build pool
- `nix flake update` - Update flake inputs
- `just cluster-status` - Check distributed build cluster

### Security & Monitoring
- `nix doctor` - Check system configuration health
- `nix profile diff` - Show pending changes
- `nix-store --gc` - Clean up old generations

## Usage Examples

### Basic Configuration Changes
```
> Enable new package in system configuration
> Add steam-run to games package list
> Apply with nixos-rebuild switch
```

### System Service Management
```
> Check mining service status
> Restart networking if needed
> View logs for troubleshooting
```

### Distributed Build Operations
```
> Build package using 51-core cluster
> Check cluster node status
> Update distributed build configuration
```

## Safety Features

- **Read-only analysis**: Never modifies files without explicit confirmation
- **Configuration validation**: Checks syntax before applying changes
- **Service safety**: Confirms service operations before execution
- **Backup reminders**: Suggests configuration backup before major changes

## Integration Notes

This skill integrates with:
- NixOS configuration management
- Distributed build system
- System service control
- Package management workflows

Use for any NixOS administration task that requires safe, automated system management.