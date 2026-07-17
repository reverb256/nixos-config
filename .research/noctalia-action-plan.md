# Noctalia Integration Action Plan

**Date**: 2026-03-29
**Status**: Ready for Implementation
**Priority**: High

---

## Current State
- No noctalia configuration found in current NixOS config
- No `builtins.storePath` workarounds detected
- Issue #22 in noctalia-qs repo is OPEN

- Fileset evaluation bug in upstream affects some users

## Root Cause
**Commit**: 0e3915156af34d6d80f5fb1fda3d59cc84aae313
**Problem**: `lib.fileset.gitTracked` causes evaluation errors
**Issue**: https://github.com/noctalia-dev/noctalia-qs/issues/22
**Status**: OPEN (unresolved)

## Recommended Solution

### Option 1: Use Nixpkgs Packages (RECOMMENDED)

**Steps**:
1. Add to system packages:
```nix
# In hosts/zephyr/default.nix or appropriate module
environment.systemPackages = with pkgs; [
    pkgs.noctalia-shell
  ];
```

2. Or use NixOS module if available:
```nix
services.noctalia-shell = {
  enable = true;
  package = pkgs.noctalia-shell;
};
```

**Pros**:
- Official, maintained by @iynaix, @spacedentist
- Stable, predictable builds
- No fileset issues
- Automatic security updates

**Cons**:
- May not have latest features
- Configuration options may be limited

### Option 2: Use Upstream Flake with Version Pinning

**Steps**:
1. Add flake input:
```nix
# In flake.nix
inputs = {
  noctalia-shell = {
    url = "github:noctalia-dev/noctalia-shell";
    ref = "v4.7.1";  # Pin to stable version
  };
};
```

2. Reference in configuration
```nix
# In hosts configuration
environment.systemPackages = [
  inputs.noctalia-shell.packages.${system}.default
];
```

**Pros**:
- Latest features immediately
- Control over version
- Official modules from upstream

**Cons**:
- Requires flake input maintenance
- May be affected by fileset bug if using unstable commits

### Option 3: Hybrid Approach (Best of Both Worlds)

**Steps**:
1. Use nixpkgs for stable base
2. Add upstream flake for testing new features
3. Switch when stable

```nix
inputs = {
  noctalia-shell-stable = {
    url = "github:noctalia-dev/noctalia-shell";
    ref = "v4.7.1";
  };
  noctalia-shell-latest = {
    url = "github:noctalia-dev/noctalia-shell";
    # No ref = latest
  };
};

# Configuration
environment.systemPackages = [
  pkgs.noctalia-shell  # Default to stable
];
```

## Implementation Checklist

- [ ] Choose approach (Option 1 recommended)
- [ ] Add noctalia-shell to system packages
- [ ] Test configuration: `just switch`
- [ ] Verify noctalia-shell starts correctly
- [ ] Check for issues after rebuild
- [ ] Monitor GitHub Issue #22 for resolution

## Files to Create/Modify

1. `/etc/nixos/hosts/zephyr/desktop/noctalia.nix` (if creating custom config)
2. `/etc/nixos/flake.nix` (if adding flake input)

## Testing Commands
```bash
# Test build
nix build .#noctalia-shell

# Test switch
just switch

# Verify running
ps aux | grep noctalia
```

## Monitoring
- GitHub Issue #22: https://github.com/noctalia-dev/noctalia-qs/issues/22
- Nixpkgs updates: https://github.com/NixOS/nixpkgs/pkgs/by-name/no/noctalia-shell
- Upstream releases: https://github.com/noctalia-dev/noctalia-shell/releases
