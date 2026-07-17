---
name: nixos-best-practices
description: Comprehensive Nix and NixOS expertise including flakes, overlays, unfree package handling, binary overlays, Home Manager integration, system configuration structuring, and overlay scope management with useGlobalPkgs. Use when writing Nix expressions, configuring NixOS systems, managing Home Manager, structuring configurations, or packaging software with nixpkgs. (Now includes Nix best practices from deprecated nix-best-practices skill)
version: 2.0.0
license: MIT
metadata:
  author: chumeng
  critical: READ_DOCUMENTATION_FIRST
---

# Nix & NixOS Best Practices

Comprehensive guide for Nix language fundamentals, NixOS configuration with flakes, overlay management, Home Manager integration, and system configuration structuring.

## When to Use

- **NixOS Configuration** - Configuring systems with flakes and Home Manager
- **Overlay Management** - Adding overlays that don't seem to apply
- **useGlobalPkgs Issues** - Using `useGlobalPkgs = true` with custom overlays
- **Host Organization** - Structuring NixOS configurations across multiple hosts
- **Package Installation** - Installing packages with overlays
- **Nix Language** - Writing Nix expressions, derivations, attribute sets
- **Flakes** - Configuring flake.nix, inputs, outputs
- **Unfree Packages** - Enabling proprietary software
- **Binary Caches** - Configuring substituters for faster builds

---

## ⚠️ CRITICAL: Read Before Making Changes

**BEFORE making ANY NixOS configuration changes, you MUST:**

1. **Review relevant rule files** from Quick Reference below
2. **Check common-mistakes.md** to avoid known pitfalls
3. **Check troubleshooting.md** for systematic debugging approach
4. **Follow existing patterns** in codebase

**Do NOT start coding until you've read applicable documentation.**

Most configuration errors happen from not reading the rules first. The 5 minutes you spend reading will save hours of debugging.

---

## Nix Language Fundamentals

### Core Concepts

**Lazy Evaluation** - Expressions computed only when needed:

```nix
let
  expensive = builtins.trace "Computing expensive" (1 + 1);
in
{ a = 1; b = expensive; }.a  # Does not compute expensive
```

**Pure Functions** - Same inputs always produce same outputs:

```nix
double = x: x * 2;
```

**Attribute Sets** - Primary data structure:

```nix
# Basic attribute set
{ attr1 = value1; attr2 = value2; }

# Access
set.attr
set."attr-with-dashes"

# With operator
with set; attr1  # Equivalent to set.attr1

# Let binding
let inherit (set) attr1 attr2; in
  attr1
```

**Lists** - Ordered collections:

```nix
# Create list
[1 2 3]

# Access by index
builtins.elemAt list 0

# List operations
builtins.length list
builtins.head list
builtins.tail list
```

### Derivations

A derivation is a build description:

```nix
stdenv.mkDerivation {
  pname = "mypackage";
  version = "1.0.0";
  src = ./src;
  buildPhase = ''
    gcc -o myapp main.c
  '';
  installPhase = ''
    mkdir -p $out/bin
    cp myapp $out/bin/
  '';
}
```

### Let and Let-Binding

```nix
# let binding
let
  x = 1;
  y = 2;
in
x + y

# inherit keyword
let
  config = { a = 1; b = 2; };
in
{
  inherit (config) a b;  # Same as a = config.a; b = config.b;
}
```

### Functions and Partial Application

```nix
# Simple function
add = x: y: x + y;

# Apply
add 1 2  # Returns 3

# Partial application
addOne = add 1;
addOne 2  # Returns 3

# Argument destructuring
{ a, b ? 0 }: a + b  # b defaults to 0
```

---

## Flakes

### Basic flake.nix Structure

```nix
{
  description = "My NixOS configuration";
  
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    home-manager = {
      url = "github:nix-community/home-manager/release-24.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  
  outputs = { self, nixpkgs, home-manager, ... }@inputs: {
    # NixOS configurations
    nixosConfigurations = {
      hostname = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./configuration.nix
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.users.john = ./home.nix;
          }
        ];
      };
    };
    
    # Packages
    packages.x86_64-linux.myapp = nixpkgs.legacyPackages.x86_64-linux.hello;
    
    # Dev shells
    devShells.x86_64-linux.default = nixpkgs.mkShell {
      buildInputs = with nixpkgs; [ nodejs python ];
    };
  };
}
```

### Flake Inputs and Following

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    
    # Use nixpkgs from flake registry
    # nixpkgs.url = "nixpkgs";
    
    # Follow another flake's nixpkgs
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    # Use specific branch/tag
    # nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    
    # Use local path
    # my-local-input.url = "/path/to/local/flake";
    
    # Use Git URL
    # nixpkgs.url = "git+https://github.com/NixOS/nixpkgs?ref=master";
  };
}
```

### Flake Commands

```bash
# Update all inputs
nix flake update

# Update specific input
nix flake update nixpkgs

# Show metadata
nix flake metadata

# Check for updates
nix flake check

# Build from flake
nix build .#myapp

# Run from flake
nix run .#myapp

# Switch to flake configuration
nixos-rebuild switch --flake .#hostname

# Home Manager switch
home-manager switch --flake .#hostname
```

---

## Overlays

### Creating Overlays

```nix
# Simple overlay
myOverlay = final: prev: {
  mypackage = prev.callPackage ./my-package {};
};

# Overriding existing package
myOverlay2 = final: prev: {
  neovim = prev.neovim.overrideAttrs (old: {
    buildInputs = old.buildInputs ++ [ prev.tree-sitter ];
  });
};

# Overriding with function
myOverlay3 = final: prev: {
  myapp = prev.myapp.override {
    featureFlag = true;
  };
};
```

### Applying Overlays in Flakes

```nix
{
  outputs = { self, nixpkgs, ... }: {
    # Apply overlay to all packages
    nixosConfigurations.hostname = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        {
          nixpkgs.overlays = [ self.overlays.default ];
        }
        ./configuration.nix
      ];
    };
    
    overlays = {
      default = final: prev: {
        mypackage = prev.callPackage ./my-package {};
      };
    };
  };
}
```

---

## Unfree Packages

### Enabling Unfree Packages

```nix
# In flake.nix or configuration.nix
{
  nixpkgs.config.allowUnfree = true;
}
```

### Selective Unfree Allowlist

```nix
{
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
    "vscode"
    "slack"
    "steam"
  ];
}
```

### Unfree Package Issues

```nix
# Check if package is unfree
nix search --eval-name nixpkgs.vscode

# View package metadata
nix eval nixpkgs#vscode.meta.license
```

---

## Binary Caches

### Using Cachix

```bash
# Install cachix
nix-env -iA cachix -f https://cachix.org/api/v1/install

# Use a cache
cachix use mycache
```

### Manual Cache Configuration

```nix
{
  nix.settings = {
    substituters = [
      "https://cache.nixos.org"
      "https://mycache.cachix.org"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gNypC9URx2w7wOQ1z4zD8w0c="
      "mycache.cachix.org-1:..."
    ];
  };
}
```

### Building Without Binary Cache

```bash
# Build locally without cache
nix build --no-substitutes .#myapp

# Show what would be substituted
nix build --dry-run .#myapp
```

---

## Overlay Scope & useGlobalPkgs

### Core Principle

**When `useGlobalPkgs = true`, overlays must be defined at the NixOS configuration level, not in Home Manager configuration files.**

### Correct vs Incorrect

```nix
# ❌ WRONG: Overlay in home.nix (doesn't apply)
# home-manager/home.nix
{
  nixpkgs.overlays = [ inputs.claude-code.overlays.default ];  # Ignored!
  home.packages = with pkgs; [ claude-code ];  # Not found!
}

# ✅ CORRECT: Overlay in NixOS home-manager block
# hosts/home/default.nix
{
  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.users.john = import ./home.nix;
  home-manager.extraSpecialArgs = { inherit inputs pkgs-stable system; };
  # Overlay must be HERE when useGlobalPkgs = true
  nixpkgs.overlays = [ inputs.claude-code.overlays.default ];
}
```

### Overlay Scope Decision Matrix

| useGlobalPkgs | Overlay Definition Location | Affects |
|---------------|---------------------------|---------|
| `true` | `home-manager.nixpkgs.overlays` | System + Home Manager packages |
| `true` | `home.nix` with `nixpkgs.overlays` | **Nothing** (ignored!) |
| `false` | `home.nix` with `nixpkgs.overlays` | Home Manager packages only |
| `false` | `home-manager.nixpkgs.overlays` | Home Manager packages only |
| Any | System `nixpkgs.overlays` | System packages only |

---

## Host Configuration Organization

### Multiple Hosts Structure

```
flake.nix
├── hosts/
│   ├── desktop/
│   │   ├── configuration.nix
│   │   └── hardware-configuration.nix
│   ├── laptop/
│   │   ├── configuration.nix
│   │   └── hardware-configuration.nix
│   └── server/
│       ├── configuration.nix
│       └── hardware-configuration.nix
├── modules/
│   ├── common.nix
│   ├── desktop.nix
│   └── server.nix
├── home/
│   └── default.nix
└── flake.nix
```

### Importing Shared Modules

```nix
# hosts/desktop/configuration.nix
{
  imports = [
    ../../modules/common.nix
    ../../modules/desktop.nix
    ./hardware-configuration.nix
  ];
}
```

---

## Common Mistakes

### Red Flags - STOP Before Coding

- "I can just try this option" → Check if it exists in nixpkgs/Home Manager first
- "Let me experiment with different approaches" → Read docs, don't guess
- "This should work" → Verify syntax and availability in nixpkgs
- "Making multiple rebuild attempts" → You're missing systematic debugging
- "I remember this works" → Docs change, verify current approach

### Common Pitfalls

1. **Overlay in wrong scope** when `useGlobalPkgs = true`
2. **Forgetting to update flake inputs** after adding new ones
3. **Mixing `import` and `import from paths`** inconsistently
4. **Not pinning nixpkgs versions** in production
5. **Not using `inherit`** where appropriate
6. **Creating impure derivations** when pure alternatives exist

---

## Troubleshooting

### Systematic Debugging

```bash
# Check configuration syntax
nix flake check

# Show configuration diff
nixos-rebuild switch --dry-build --flake .#hostname

# View package paths
nix-store -q --references $(nix-store -q -R $(which mypackage))

# Check what depends on a package
nix-store -q --referrers /nix/store/...

# Clear failed builds
nix-store --gc
```

### Common Issues

**"Package not found"**
- Check overlay scope vs useGlobalPkgs
- Verify package exists in pinned nixpkgs version
- Update flake inputs with `nix flake update`

**"Changes don't apply after rebuild"**
- Verify overlay is in correct location
- Check useGlobalPkgs setting
- Rebuild with `--show-trace` for debugging

**"Unfree package not allowed"**
- Add `allowUnfree = true` to nixpkgs config
- Or use selective allowlist with `allowUnfreePredicate`

---

## Related Skills

- `nix` - Comprehensive Nix ecosystem expertise
- `devenv-ecosystem` - Devenv development environments
- `nix-best-practices` - (DEPRECATED - merged into this skill)

---

## Resources

- [Nix Manual](https://nixos.org/manual/nix/stable/)
- [NixOS Manual](https://nixos.org/manual/nixos/stable/)
- [Nix Pills](https://nixos.org/guides/nix-pills/)
- [NixOS & Flakes Wiki](https://nixos.wiki/wiki/Flakes)
- [Home Manager Manual](https://nix-community.github.io/home-manager/)
