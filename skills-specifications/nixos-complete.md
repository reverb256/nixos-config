# NixOS Skill Consolidation Specification

**Target Name**: `nixos:complete`
**Sources to Merge**:
- `nixos-best-practices`
- `nix-ecosystem`

**Created**: 2026-03-07
**Status**: Specification ready for implementation

---

## Skill Manifest

```yaml
name: nixos:complete
description: Complete NixOS and Nix ecosystem expertise including flakes, modules, best practices, testing, and troubleshooting.

triggers:
  - User asks about NixOS configuration
  - User needs help with flakes
  - User wants to create NixOS modules
  - "How do I configure..."
  - "NixOS module for..."
  - "Flake not building..."
```

---

## Consolidated Content Structure

### 1. NixOS Best Practices

#### 1.1 Module Structure

```nix
# Standard module structure
{
  config,
  lib,
  pkgs,
  ...
}: {
  options = {
    # Declare options here
    myService.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable my service";
    };
  };

  config = lib.mkIf config.myService.enable {
    # Implementation here
  };
}
```

**Best Practices**:
- Always accept `config`, `lib`, `pkgs` as arguments
- Use `lib.mkOption` for configuration options
- Use `lib.mkIf` for conditional configuration
- Include descriptions for all options
- Use 2-space indentation

#### 1.2 Flake Patterns

```nix
{
  description = "My NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystemMap (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in {
        packages.default = pkgs.hello;
        devShells.default = pkgs.mkShell {
          buildInputs = [ pkgs.nixpkgs-fmt ];
        };
      }
    ) // {
      nixosConfigurations = {
        myhost = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [ ./configuration.nix ];
        };
      };
    };
}
```

#### 1.3 Testing Workflow

```bash
# Step 1: Syntax check (fastest)
nix flake check

# Step 2: Build validation
sudo nixos-rebuild build --flake .#hostname

# Step 3: Test configuration (rolls back on reboot)
sudo nixos-rebuild test --flake .#hostname

# Step 4: Apply persistently
sudo nixos-rebuild switch --flake .#hostname

# Step 5: Update inputs
nix flake update
```

### 2. Nix Ecosystem Overview

#### 2.1 Key Components

| Component | Purpose | URL |
|-----------|---------|-----|
| **Nix** | Package manager | https://nixos.org/manual/nix/stable/ |
| **NixOS** | Linux distribution | https://nixos.org/manual/nixos/stable/ |
| **nixpkgs** | Package repository | https://github.com/NixOS/nixpkgs |
| **Flakes** | Project structure | https://nixos.wiki/wiki/Flakes |
| **Home Manager** | User config | https://nix-community.github.io/home-manager/ |
| **Darwin** | macOS support | https://daiderd.com/nix-darwin/ |

#### 2.2 Common Nix Wrappers

| Wrapper | Purpose | When to Use |
|---------|---------|-------------|
| `nh` | Helper for NixOS/HM | Daily system management |
| `nixos-rebuild` | NixOS rebuilding | System configuration |
| `home-manager` | User config rebuilding | Home config changes |
| `nix-shell` | Ad-hoc environments | Temporary package access |
| `nix develop` | Flake dev shells | Project development |
| `direnv` | Automatic shell loading | Directory-based envs |

#### 2.3 Package Discovery

```bash
# Search packages
nix search nixpkgs packageName

# Search options
nix search nixpkgs options.optionName

# Find package by attribute
nix-env -qaP '.*packageName.*'  # (legacy)

# Via NixOS Options Search
# https://search.nixos.org/options
```

---

## When to Use This Skill

Trigger this skill when:

1. **Configuration Tasks**
   - Creating NixOS modules
   - Writing flake.nix files
   - Configuring services
   - Setting up virtualization/containers

2. **Build/Deploy Issues**
   - Flake won't evaluate
   - Build failures
   - Dependency conflicts
   - "NixOS rebuild failed"

3. **Best Practices Questions**
   - "Is this the right way to..."
   - "Should I use flakes or channels?"
   - "How do I structure my config?"

4. **Troubleshooting**
   - Module not found
   - Option not recognized
   - Hash mismatches
   - GC issues

---

## Common Patterns

### Service Module Pattern

```nix
# modules/services/my-service/default.nix
{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.services.myService;
in {
  options.services.myService = {
    enable = mkEnableOption "My Service";

    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Port to listen on";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Open firewall port";
    };
  };

  config = mkIf cfg.enable {
    # Systemd service
    systemd.services.my-service = {
      description = "My Service";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.my-package}/bin/my-service --port ${toString cfg.port}";
        DynamicUser = true;
      };
    };

    # Firewall
    networking.firewall.allowedTCPPorts = optional cfg.openFirewall cfg.port;
  };
}
```

### Profile Pattern

```nix
# modules/profiles/my-profile.nix
{ config, lib, pkgs, ... }:

{
  options = {
    my-profile.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };
  };

  config = lib.mkIf config.my-profile.enable {
    # Group related settings
    environment.systemPackages = with pkgs; [ ... ];
    services = { ... };
    systemd = { ... };
  };
}
```

### Override Pattern

```nix
# Package override
myPackage = pkgs.myPackage.override {
  featureFlag = true;
};

# Overlay pattern
overlay = final: prev: {
  myPackage = prev.myPackage.overrideAttrs (old: {
    patches = [ ./my-fix.patch ];
  });
};
```

---

## Debugging Workflow

### 1. Check Syntax
```bash
nix flake check --show-trace
```

### 2. Dry Run
```bash
sudo nixos-rebuild dry-activate --flake .#hostname
```

### 3. View Changes
```bash
sudo nixos-rebuild build --flake .#hostname
nix store diff-closures /run/current-system result
```

### 4. Inspect Store Path
```bash
nix-store -q -R result
nix path-info -rs result
```

### 5. Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| "infinite recursion" | Circular dependency | Check option references |
| "attribute not found" | Misspelled attribute | Use `nix flake show` to verify |
| "hash mismatch" | impure derivation | Clean build with `--check` |
| "out of space" | Too many GC roots | Run `nix-collect-garbage -d` |

---

## Quality Checklist

Before committing NixOS changes:

- [ ] `nix flake check` passes
- [ ] Indentation is 2 spaces
- [ ] Options have descriptions
- [ ] `inherit` used where appropriate
- [ ] Attribute sets have trailing commas
- [ ] Tested with `nixos-rebuild build`
- [ ] No hardcoded paths (use `config.` prefixes)
- [ ] Comments explain "why", not "what"

---

## Integration Notes

When implementing this consolidated skill:

1. **Combine complementary content**: best-practices and ecosystem overlap on flakes
2. **Preserve troubleshooting steps** from both sources
3. **Keep module examples** from best-practices
4. **Maintain ecosystem overview** from nix-ecosystem
5. **Cross-reference** concepts (e.g., flakes in both)

---

## References

- NixOS Manual: https://nixos.org/manual/nixos/stable/
- Nix Manual: https://nixos.org/manual/nix/stable/
- NixOS Wiki: https://nixos.wiki/
- Nix Pills: https://nixos.org/guides/nix-pills/
- NixOS & Flakes Book: https://nixos-and-flakes.thiscute.world/
