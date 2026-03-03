# NUR Integration Design

**Date:** 2026-03-02
**Author:** Claude (assisted by j_kro)
**Status:** Approved

## Overview

Integrate NUR (Nix User Repository) into the NixOS configuration to provide access to 1000+ community-maintained Nix packages, improve package management workflow, and enable exploration of the Nix ecosystem.

## Goals

1. **Access Additional Packages** - Tap into community-maintained packages not yet in nixpkgs
2. **Better Package Management** - Unified workflow for managing community packages via flakes
3. **Explore Ecosystem** - Easy discovery and experimentation with community tools

## Architecture

### Integration Pattern

```
flake.nix (input) → specialArgs → modules → configuration → system packages
```

Follows existing pattern used for other community flakes (zen-browser, aagl, nixcord, etc.)

### Component Structure

- **Input:** `nur.url = "github:nix-community/NUR"`
- **Module:** `nur.nixosModules.nur`
- **Access:** `inputs.nur.repos.<username>.<package>`

## Implementation

### Changes Required

**File:** `/etc/nixos/flake.nix`

1. Add NUR input with nixpkgs following
2. Add `nur` to outputs parameters
3. Include `nur` in `specialArgs.inputs.inherit`
4. Enable `nur.nixosModules.nur` in modules list

### Code Changes

```nix
inputs = {
  # ... existing inputs ...
  nur = {
    url = "github:nix-community/NUR";
    inputs.nixpkgs.follows = "nixpkgs";
  };
};

outputs = { self, nixpkgs, home-manager, zen-browser, firefox-addons, aagl,
            claude-native, nixpkgs-xr, scopebuddy, nixcord, nur }:
  {
    nixosConfigurations.zephyr = nixpkgs.lib.nixosSystem {
      specialArgs = {
        inputs = {
          inherit nixpkgs home-manager zen-browser firefox-addons aagl
                  claude-native nixpkgs-xr scopebuddy nixcord nur self;
        };
      };
      modules = [
        # ... existing modules ...
        nur.nixosModules.nur
      ];
    };
  };
```

## Usage Patterns

### Basic Usage

```nix
{ config, pkgs, inputs, ... }: {
  environment.systemPackages = with pkgs; [
    inputs.nur.repos.<username>.<package>
  ];
}
```

### Discovery Workflow

1. Visit [nur.nix-community.org](https://nur.nix-community.org/)
2. Search/browse for packages
3. Note repo username and package name
4. Add to configuration

### Example Packages

```nix
inputs.nur.repos.mic92.sops              # Secret management
inputs.nur.repos.iopq.spotify-adblock    # Spotify ad blocking
inputs.nur.repos.sternenseemann.texlive-small  # LaTeX distribution
```

## Error Handling

### Known Issues

| Issue | Mitigation |
|-------|------------|
| Package build failures | Check repo maintenance status |
| Evaluation time increase | Acceptable trade-off (<5 sec) |
| Conflicting dependencies | `inputs.nixpkgs.follows` ensures consistency |
| Unmaintained packages | Check "Last Updated" on NUR website |

### Rollback Plan

- Remove NUR module if issues occur
- Flake lock allows reversion to previous state
- NUR is non-invasive (doesn't modify existing packages)

## Testing

### Validation Steps

1. Update flake lock: `nix flake update`
2. Test evaluation: `sudo nixos-rebuild build --flake /etc/nixos#zephyr`
3. Verify NUR access via `nix repl`
4. Test sample package installation

### Success Criteria

- ✓ Flake update completes successfully
- ✓ `nixos-rebuild build` completes without errors
- ✓ Can access `inputs.nur.repos` in modules
- ✓ NUR website packages match available packages

## Trade-offs

### Chosen Approach: Full NUR Integration

**Why:**
- Immediate access to all packages
- Easy exploration via NUR website
- Follows existing flake patterns
- Minimal setup overhead

**Alternatives Considered:**
- Selective repos: More control but higher maintenance
- Manual integration: Maximum control but poor UX

## Risk Assessment

**Risk Level:** Low

- Non-invasive integration
- Reversible via git/flake rollback
- Well-documented package source
- No system-breaking changes

## References

- [NUR Website](https://nur.nix-community.org/)
- [NUR GitHub](https://github.com/nix-community/NUR)
- [NixOS Wiki: NUR](https://nixos.wiki/wiki/NUR)
