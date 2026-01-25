# ============================================================================
# NIXOS DISTRIBUTED BUILD CONTROLLER SKILL
# ============================================================================
# Skill for managing the 51-core distributed build cluster
---
name: distributed-build-controller
description: Manage distributed build cluster, node monitoring, and build orchestration
metadata: {"clawdbot":{"requires":{"bins":["just"],"os":["linux"],"emoji":"🏗"}}
---

## Capabilities

This skill provides comprehensive distributed build management:

### Cluster Management
- `just cluster-status` - Check status of all 51 cores
- `just cluster-info` - Get detailed cluster information
- `just cluster-resources` - Monitor resource usage
- `just cluster-update` - Update all cluster nodes

### Node Operations
- `just deploy zephyr` - Deploy to master node
- `just deploy nexus` - Deploy to build node 1
- `just deploy forge` - Deploy to build node 2
- `just deploy sentry` - Deploy to build node 3
- `just deploy-all` - Deploy to all cluster nodes

### Build Orchestration
- `nix build --builders-use-substitutes <package>` - Build using distributed pool
- `nix build -j 32 <package>` - Build with specific core count
- `just build-stats` - View build performance metrics
- `just clean-failed` - Clean failed build artifacts

### Monitoring & Health
- `just cluster-health` - Comprehensive health check
- `just node-monitor <hostname>` - Monitor specific node
- `just network-check` - Verify cluster connectivity
- `just load-balance` - Check load distribution

### Advanced Features
- `just emergency-stop` - Emergency shutdown of all nodes
- `just performance-tune` - Optimize build performance
- `just maintenance-mode` - Put cluster in maintenance mode
- `just rollback` - Rollback to previous configuration

## Usage Examples

### Cluster Status Check
```
> Check distributed build cluster status
> Show 51-core capacity and current utilization
```

### Package Building
```
> Build complex package using full cluster
> Distribute load across all 51 cores automatically
```

### Node Management
```
> Deploy updated configuration to specific node
> Monitor node health and performance
```

### Emergency Operations
```
> Emergency shutdown of entire cluster
> Safe rollback if deployment fails
```

## Safety Features

- **Read-only operations**: Never modifies configurations without confirmation
- **Cluster validation**: Checks node connectivity before operations
- **Rollback safety**: Automatic rollback on deployment failures
- **Load balancing**: Prevents node overload during builds
- **Permission checks**: Validates access rights before operations

## Integration Points

 This skill integrates with:
 - Colmena deployment system
 - Nix distributed builds
 - Justfile automation
 - Systemd service management
 - Network configuration monitoring

## Cluster Architecture Reference

```
zephyr (32 cores) - Master workstation
├── nexus (8 cores) - Build/backup server
├── forge (3 cores) - Build/development server  
└── sentry (8 cores) - Monitoring server

Total: 51 cores distributed build pool
```

Use for comprehensive distributed build cluster management, monitoring, and optimization tasks.