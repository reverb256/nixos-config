# PROJECT KNOWLEDGE BASE

**Generated:** 2026-01-26
**Commit:** 88d3861
**Branch:** main
**Mode:** Update

## OVERVIEW
4-node distributed build cluster (zephyr, nexus, forge, sentry) with 51-core total capacity for NixOS development and deployment.

## WHERE TO LOOK
| Node | Location | Role | Cores |
|------|----------|------|-------|
| zephyr | hosts/zephyr/ | Master build node | 32 |
| nexus | hosts/nexus/ | Backup/storage node | 8 |
| forge | hosts/forge/ | Build worker | 3 |
| sentry | hosts/sentry/ | Monitoring node | 8 |

## CONVENTIONS
- **Distributed builds**: 51 cores across 4 hosts (zephyr:32, nexus:8, forge:3, sentry:8)
- **Node-specific configs**: Each host has dedicated configuration.nix and hardware-configuration.nix
- **Colmena deployment**: Multi-host management via flake.nix host definitions
- **Build coordination**: Centralized builders config in machines.nix
- **Hardware separation**: Each node optimized for specific workloads (build, storage, monitoring)

## ANTI-PATTERNS
- **NEVER modify hardware-configuration.nix** - Auto-generated per host
- **NEVER hardcode host-specific settings** in main configuration.nix
- **NEVER assume hardware consistency** across nodes
- **NEVER bypass Colmena deployment** for host-specific changes
- **NEVER mix node roles** - Keep build/storage/monitoring separate

## UNIQUE STYLES
- **Wayland-compatible config**: zephyr has separate Wayland-compatible configuration
- **Node-specific optimizations**: Each host tuned for its role
- **Centralized management**: Single flake.nix controls all 4 nodes
- **Distributed workload**: Automatic load balancing across 51 cores
- **Hardware diversity**: Different CPU configurations per node

## COMMANDS
```bash
# Multi-host deployment
just cluster-deploy      # Deploy to all 4 nodes
just deploy-zephyr       # Deploy to master node
just deploy-nexus        # Deploy to backup node
just deploy-forge        # Deploy to build worker
just deploy-sentry       # Deploy to monitoring node

# Cluster management
just cluster-info        # Show node status and core count
just cluster-resources   # Monitor distributed build pool
```

## NOTES
- **Node isolation**: Each host maintains separate hardware configuration
- **Build coordination**: machines.nix defines distributed build pool
- **Rollback support**: Colmena handles multi-host rollback scenarios
- **Monitoring**: Sentry node provides cluster-wide metrics
- **Backup strategy**: Nexus handles automated backup duties
- **Hardware diversity**: Different CPU configurations optimized per role