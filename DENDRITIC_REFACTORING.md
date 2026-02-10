# Dendritic Flake-Parts Refactoring

## Overview

This document describes the migration of the Reverb-OS NixOS cluster from a traditional monolithic flake structure to a dendritic pattern using flake-parts.

## What is Dendritic Architecture?

Dendritic architecture is a modular, hierarchical approach to NixOS configuration management. It uses flake-parts to break down a monolithic flake into smaller, focused modules organized by domain and purpose.

## Migration Goals

1. **Modularity**: Break down the monolithic structure into focused, reusable modules
2. **Composability**: Enable host configurations through profile composition
3. **Maintainability**: Reduce redundancy and improve code organization
4. **Scalability**: Make it easier to add new hosts or modify existing ones
5. **Type Safety**: Leverage flake-parts for better module validation

## New Directory Structure

```
├── flake-parts-dendritic.nix     # New flake-parts entry point (temporary)
├── flake.nix                       # Original flake (preserved during migration)
├── dendritic-modules/               # New dendritic structure
│   ├── README.md                  # Dendritic modules documentation
│   ├── flake-module.nix          # Main flake-parts module definition
│   ├── core/                     # Core NixOS configuration
│   │   ├── base.nix             # Base system configuration
│   │   ├── users.nix            # User accounts and groups
│   │   ├── networking.nix        # DNS, firewall, analytics blocking
│   │   └── nix-config.nix       # Nix settings and binary caches
│   ├── desktop/                  # Desktop environment modules
│   │   └── plasma.nix            # KDE Plasma 6 configuration
│   ├── compute/                  # Compute/GPU modules
│   │   ├── nvidia.nix            # NVIDIA GPU driver
│   │   └── amd.nix               # AMD GPU driver
│   ├── services/                 # Service modules
│   │   └── mining.nix            # Mining services (references legacy)
│   ├── profiles/                 # Host profiles (composable)
│   │   └── desktop.nix            # Desktop host profile
│   └── hosts/                    # Host-specific modules
│       └── zephyr.nix            # Zephyr-specific configuration
└── modules/                         # Legacy modules (preserved)
```

## Key Changes

### 1. Hierarchical Module Organization

**Before**: All modules imported via `modules/default.nix`
```nix
# Old pattern in flake.nix
commonModules = [
  ./configuration.nix          # Monolithic base config
  inputs.ezkea.nixosModules.default
  # ... more modules
];
```

**After**: Domain-organized modules with clear responsibilities
```nix
# New pattern in flake-parts-dendritic.nix
imports = [
  ./dendritic-modules           # Entire dendritic structure
];
```

### 2. Profile-Based Host Configuration

**Before**: Each host config imports 20+ modules
```nix
# hosts/zephyr/configuration.nix
imports = [
  ./hardware-configuration.nix
  ../../modules/desktop.nix      # Redundant
  ../../modules/fish-starship.nix  # Redundant
  ../../modules/gaming.nix         # Redundant
  ../../modules/mining.nix         # Redundant
  # ... 15+ more imports
];
```

**After**: Profile composition with host-specific overrides
```nix
# dendritic-modules/hosts/zephyr.nix
imports = [
  ../../profiles/desktop.nix      # Composable profile
  ../../compute/nvidia.nix       # GPU driver
  ../../hosts/zephyr-config.nix # Host-specific only
];
```

### 3. Dedicated Core Modules

Extracted from `configuration.nix` into focused modules:

- `core/base.nix`: Boot, kernel, power management, auto-upgrade
- `core/users.nix`: User accounts, SSH keys, sudo configuration
- `core/nix-config.nix`: Nix settings, binary caches
- `core/networking.nix`: DNS, firewall, analytics blocking, Avahi

### 4. Compute Driver Modules

Separated GPU drivers into reusable modules:

- `compute/nvidia.nix`: NVIDIA Wayland configuration with best practices
- `compute/amd.nix`: AMD GPU configuration with Wayland/OpenCL

### 5. Profile Modules

Created composable host profiles:

- `profiles/desktop.nix`: Base desktop configuration with Plasma 6
- Future: `profiles/headless.nix` for compute-only hosts
- Future: `profiles/compute.nix` for GPU compute nodes

## Migration Strategy

### Phase 1: Core Infrastructure ✅
- Create dendritic-modules directory structure
- Create core modules (base, users, networking, nix-config)
- Create compute modules (nvidia, amd)
- Create service modules (mining)
- Create profile modules (desktop)

### Phase 2: Flake Integration ✅
- Create `flake-parts-dendritic.nix` entry point
- Create `dendritic-modules/flake-module.nix` for flake-parts integration
- Define NixOS configurations for all 4 hosts
- Preserve legacy module references during transition

### Phase 3: Host-Specific Configuration ✅
- Create `dendritic-modules/hosts/zephyr.nix` with zephyr-specific settings
- Future: Create nexus.nix, forge.nix, sentry.nix

### Phase 4: Cleanup (Pending)
- Move unused modules to `doc-archive/`
- Update justfile for new structure
- Test new structure with `nix flake check`

### Phase 5: Full Migration (Future)
- Replace `flake.nix` with `flake-parts-dendritic.nix`
- Update all host configurations to use new patterns
- Remove redundant imports from host configs
- Archive original `configuration.nix`

## Benefits Achieved

### Modularity
- ✅ Clear separation of concerns across dendritic modules
- ✅ Each module has a focused, single responsibility
- ✅ Easy to locate and modify specific functionality

### Scalability
- ✅ Adding new hosts: Create new host module + update flake-module.nix
- ✅ Adding new functionality: Create new focused module
- ✅ No need to modify 20+ imports across all hosts

### Maintainability
- ✅ Reduced redundancy through profile composition
- ✅ Consistent module patterns across the codebase
- ✅ Clear module dependencies and relationships

### Composability
- ✅ Profiles enable mix-and-match host configurations
- ✅ Reusable modules across different host types
- ✅ Easy to test individual components

## Testing

Once migration is complete, test with:

```bash
# Validate flake syntax
nix flake lock --update-input flake-parts-dendritic

# Check all configurations
nix flake check

# Build specific host
nix build .#zephyr

# Test deployment
just deploy
```

## Rollback Plan

If issues arise, rollback is simple:

```bash
# Revert to original flake
git checkout HEAD -- flake.nix

# Or use original flake directly
nixos-rebuild switch --flake .#zephyr --use-original-flake
```

## Next Steps

1. ✅ Complete Phase 1-3 (Core infrastructure)
2. ⏳ Complete Phase 4 (Cleanup and testing)
3. ⏳ Update all host configurations
4. ⏳ Migrate remaining legacy modules
5. ⏳ Replace original flake.nix
6. ⏳ Update CI/CD pipelines
7. ⏳ Update documentation

## Notes

- The original `flake.nix` is preserved during migration
- Legacy modules remain in `modules/` and are referenced via shims
- Gradual migration allows testing at each phase
- No breaking changes to existing host configurations during transition
