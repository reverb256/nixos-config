# Noctalia-Integration Research Findings

**Date**: 2026-03-29
**Researcher**: THE LIBRARIAN

**Classification**: TYPE D (Comprehensive)

---

## Executive Summary

**Root Cause**: Commit 0e39151 in noctalia-qs introduced `lib.fileset.gitTracked` into flake.nix, causing Nix evaluation errors when building with certain configurations. GitHub Issue [#22](https://github.com/noctalia-dev/noctalia-qs/issues/22) is OPEN.

**Nixpkgs Solution**: Packages both noctalia-qs and noctalia-shell using `fetchFromGitHub` - completely avoiding fileset issues.
**Community Approach**: Most users consume nixpkgs packages directly or use upstream flakes with version pinning.
**Workaround Status**: Some users employ `builtins.storePath` wrappers - these break on every rebuild.

**Recommendation**: **ADOPT NIXPKGS PACKAGES** - stable, maintained, and avoids fileset evaluation entirely.

---

## 1. Root Cause Analysis

### The Bug
**Commit**: 0e3915156af34d6d80f5fb1fda3d59cc84aae313 (Mar 2026)
**Change**: Switched from `builtins.path` to `lib.fileset.gitTracked` for source tracking
**Location**: [flake.nix L9](https://github.com/noctalia-dev/noctalia-qs/blob/0e3915156af34d6d80f5fb1fda3d59cc84aae313/flake.nix#L9)

**Impact**: Causes evaluation errors: "path does not exist" when fileset tries to access paths during evaluation
**Error Pattern**:
```
error: lib.fileset: path `/nix/store/...-source` does not exist
  at lib/fileset/default.nix:420:12
```

### The Working Version
**Commit**: 08058326f04e9b5e55c903b3702405a8d3556ac6
**Approach**: Simple `builtins.path` + `src` attribute
**No fileset usage** - just direct path references

---

## 2. How Nixpkgs Handles It
**Package Files**:
- `pkgs/by-name/no/noctalia-qs/package.nix`
- `pkgs/by-name/no/noctalia-shell/package.nix`

**Approach**: Uses `fetchFromGitHub` instead of fileset
```nix
stdenv.mkDerivation {
  pname = "noctalia-qs";
  version = "0.0.10";
  
  src = fetchFromGitHub {
    owner = "noctalia-dev";
    repo = "noctalia-qs";
    tag = "v${version}";
    hash = "sha256-...";
  };
  
  # Build with cmake, no fileset evaluation
}
```

**Benefits**:
- Stable store paths (never changes)
- Official packaging (maintained by @iynaix, @spacedentist)
- Includes patch for unnecessary reload issue
- Automatic updates via nixpkgs

---

## 3. Community Configurations Survey
### Successful Patterns

**Pattern 1: Use nixpkgs directly** (most common)
```nix
environment.systemPackages = [ pkgs.noctalia-shell ];
# OR
services.noctalia-shell.enable = true;
```

**Pattern 2: Upstream flake with version pinning**
```nix
inputs = {
  noctalia-shell = {
    url = "github:noctalia-dev/noctalia-shell";
    ref = "v4.7.1";  # Pin to stable version
  };
};
```

**Pattern 3: Overlay from nixpkgs**
```nix
nixpkgs.overlays = [ (final: prev: {
  noctalia-shell = final.callPackage ./path/to/custom.nix { };
})];
```

### Anti-Patterns (AVOID)

❌ **Using unstable commits without pinning**
❌ **Wrapping with builtins.storePath** (breaks on rebuild)
❌ **Direct git repository paths in production**

---

## 4. Why builtins.storePath Breaks
**Problem**: Hardcoded store paths in configuration
```nix
# This breaks on every rebuild!
environment.systemPackages = [
  (builtins.storePath "/nix/store/abc123-noctalia-shell")
];
```

**Why it fails**:
1. Store paths are content-addressed
2. Every rebuild generates new hash
3. Hardcoded path becomes invalid
4. Nix evaluation fails with "path does not exist"

**Correct approach**:
```nix
# Reference package via pkgs
environment.systemPackages = [ pkgs.noctalia-shell ];
```

---

## 5. Recommendations
### Option A: Use Nixpkgs (RECOMMENDED)
**Pros**:
- Official, maintained packages
- Stable, predictable builds
- No fileset issues
- Automatic security updates
- Home-manager/NixOS modules available

**Implementation**:
```nix
# In configuration.nix
environment.systemPackages = [ pkgs.noctalia-shell ];

# OR use the module (if available)
services.noctalia-shell = {
  enable = true;
  package = pkgs.noctalia-shell;
};
```

### Option B: Upstream Flake with Pinning
**Pros**:
- Latest features immediately
- Control over version
- Official modules from upstream

**Implementation**:
```nix
# In flake.nix
inputs = {
  noctalia-shell = {
    url = "github:noctalia-dev/noctalia-shell";
    ref = "v4.7.1";  # Pin to stable release
  };
};

outputs = { self, nixpkgs, ... }@ args: {
  inherit nixpkgs;
  inherit (nixpkgs) noctalia-shell;
  
  # In hosts configuration
  environment.systemPackages = [ 
    inputs.noctalia-shell.packages.${system}.default 
  ];
}
```

### Option C: Custom Overlay (if you need modifications)
```nix
# Only if you need custom patches/config
nixpkgs.overlays = [
  (final: prev: {
    noctalia-shell = final.callPackage ./pkgs/noctalia-shell.nix {
      # Custom modifications here
    };
  })
];
```

---

## 6. Action Items
1. **Immediate**: Remove `builtins.storePath` workarounds
2. **Short-term**: Switch to nixpkgs packages
3. **Long-term**: Consider upstream flake with version pinning for latest features

---

## 7. Resources
- **GitHub Issue #22**: https://github.com/noctalia-dev/noctalia-qs/issues/22
- **Nixpkgs PR**: Package was added in [commit details needed]
- **Upstream Flakes**:
  - https://github.com/noctalia-dev/noctalia-shell
  - https://github.com/noctalia-dev/noctalia-qs
- **Nixpkgs Packages**:
  - `pkgs.noctalia-qs`
  - `pkgs.noctalia-shell`

---

## 8. Next Steps
1. Check current noctalia configuration in `/etc/nixos`
2. Identify all `builtins.storePath` usages
3. Replace with `pkgs.noctalia-shell` or flake input
4. Test configuration: `just switch` or `just deploy`
5. Monitor GitHub Issue #22 for upstream fix

