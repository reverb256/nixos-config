---
name: nix
description: >
  Comprehensive Nix ecosystem expertise covering Nix language, flakes, Home Manager, NixOS configuration,
  nixpkgs packaging, overlays, and best practices. Use when writing Nix expressions, configuring
  NixOS systems, managing Home Manager, or packaging software with nixpkgs.
risk: low
version: 1.0.0
---

# Nix Ecosystem

Complete guide to Nix language, flakes, Home Manager, NixOS configuration, and packaging.

## When to Use

- **Nix Language**: Writing Nix expressions, derivations, attribute sets
- **Flakes**: Configuring flake.nix, inputs, outputs
- **Home Manager**: User configuration, programs.*, dotfiles
- **NixOS**: System configuration, modules, services
- **Packaging**: Creating derivations, buildGoModule, buildRustPackage
- **Overlays**: Extending nixpkgs, custom packages

## Nix Language Fundamentals

### Core Concepts

**Lazy Evaluation**: Expressions computed only when needed
```nix
let
  expensive = builtins.trace "Computing expensive" (1 + 1);
in
{ a = 1; b = expensive; }.a  # Does not compute expensive
```

**Pure Functions**: Same inputs always produce same outputs
```nix
double = x: x * 2;
```

**Attribute Sets**: Primary data structure
```nix
# Basic
{ attr1 = value1; attr2 = value2; }

# Access
set.attr
set."attr-with-dashes"

# Recursive
rec { a = 1; b = a + 1; }
```

### Key Patterns

**let-in**: Local bindings
```nix
let
  helper = x: x + 1;
  value = helper 5;
in
  value * 2
```

**with**: Bring attributes into scope
```nix
with pkgs; [ git vim tmux ]
```

**inherit**: Copy attributes from set
```nix
{ inherit (pkgs) git vim; inherit name version; }
```

**overlay**: Extend nixpkgs
```nix
final: prev: {
  myPackage = prev.myPackage.override { ... };
}
```

**callPackage**: Dependency injection
```nix
myPackage = pkgs.callPackage ./package.nix { };
```

## Flakes

### Basic Structure

```nix
{
  description = "Project description";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, ... }@inputs: {
    packages.x86_64-linux.default = pkgs.hello;
    devShells.x86_64-linux.default = pkgs.mkShell {
      packages = [ pkgs.nodejs ];
    };
  };
}
```

### Flake Outputs

| Output | Purpose | Example |
|--------|---------|---------|
| `packages` | Derivations for `nix build` | `packages.x86_64-linux.default` |
| `devShells` | Dev environments for `nix develop` | Shell with packages |
| `apps` | Runnable apps for `nix run` | User-facing commands |
| `overlays` | Extend nixpkgs | Custom packages |
| `nixosModules` | NixOS system modules | System configuration |
| `homeManagerModules` | Home Manager modules | User configuration |
| `nixosConfigurations` | Full system configs | Complete hosts |

### Flake Commands

```bash
nix flake update              # Update all inputs
nix flake update input-name   # Update specific input
nix flake show                # Display all outputs
nix flake check               # Validate flake
```

## Home Manager

### Module Structure

```nix
{ config, pkgs, lib, ... }:
{
  options.myFeature = {
    enable = lib.mkEnableOption "my feature";
  };

  config = lib.mkIf config.myFeature.enable {
    # Configuration when enabled
  };
}
```

### Program Configuration

```nix
programs.git = {
  enable = true;
  userName = "Your Name";
  userEmail = "email@example.com";
  extraConfig = ''
    [core]
    editor = nvim
  '';
};

programs.neovim = {
  enable = true;
  viAlias = true;
  vimAlias = true;
  plugins = with pkgs.vimPlugins; [
    vim-commentary
    vim-surround
  ];
};
```

### File Management

```nix
home.file.".config/app/config" = {
  source = ./config;
  # or
  text = ''
    key = value
  '';
};

xdg.configFile."app/config".source = ./config;
```

### Environment

```nix
home.sessionVariables = {
  EDITOR = "nvim";
  PAGER = "less";
};

home.sessionPath = [ "$HOME/.local/bin" ];
```

## NixOS Configuration

### Basic Configuration

```nix
nixosConfigurations.hostname = nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";
  modules = [
    ./configuration.nix
    home-manager.nixosModules.home-manager
  ];
  specialArgs = { inherit inputs; };
};
```

### Home Manager Integration

```nix
{
  imports = [ home-manager.nixosModules.home-manager ];

  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.users.username = import ./home.nix;

  # Overlay must be HERE when useGlobalPkgs = true
  nixpkgs.overlays = [ inputs.claude-code.overlays.default ];
}
```

### Overlay Scope (CRITICAL)

| useGlobalPkgs | Overlay Location | Affects |
|---------------|-----------------|---------|
| `true` | `home-manager.nixpkgs.overlays` | System + HM packages |
| `true` | `home.nix` with `nixpkgs.overlays` | **Nothing** (ignored!) |
| `false` | `home.nix` with `nixpkgs.overlays` | HM packages only |
| Any | System `nixpkgs.overlays` | System packages only |

## Packaging

### mkDerivation

```nix
pkgs.stdenv.mkDerivation {
  pname = "mypackage";
  version = "1.0.0";
  src = pkgs.fetchFromGitHub { ... };

  nativeBuildInputs = [ pkgs.cmake ];
  buildInputs = [ pkgs.openssl ];

  installPhase = ''
    mkdir -p $out/bin
    cp mypackage $out/bin/
  '';
}
```

### Language-Specific

**Go (buildGoModule)**:
```nix
buildGoModule {
  pname = "myapp";
  version = "1.0.0";
  src = fetchFromGitHub { ... };
  vendorHash = "sha256-...";
}
```

**Rust (buildRustPackage)**:
```nix
rustPlatform.buildRustPackage {
  pname = "myapp";
  version = "1.0.0";
  src = fetchFromGitHub { ... };
  cargoHash = "sha256-...";
}
```

## Common Patterns

### Options

```nix
options.myOption = lib.mkOption {
  type = lib.types.str;
  default = "value";
  description = "An option";
  example = "example";
};

enable = lib.mkEnableOption "my service";
```

### Conditional Configuration

```nix
config = lib.mkIf config.myFeature.enable {
  # Enable service, add packages, etc.
};
```

### Imports

```nix
imports = [
  ./programs/git.nix
  ./programs/neovim.nix
  ./shell/fish.nix
];
```

## NixOS vs Home Manager

### NixOS Configuration
- System-wide services
- System packages
- System overlays
- Location: `/etc/nixos/configuration.nix` or host files

### Home Manager (useGlobalPkgs=true)
- Uses system pkgs (includes system overlays)
- HM overlays affect both system and user packages
- Most efficient for single-user systems

### Home Manager (useGlobalPkgs=false)
- Separate pkgs instance
- HM overlays affect user packages only
- Useful for multi-user systems

## Best Practices

### Nix Language
- Use lib functions for complex operations
- Follow project's existing Nix patterns
- Maintain reproducibility (avoid impure paths)
- Avoid nested with statements
- Use explicit attribute access over nested with

### Flakes
- Use specific version tags (not `latest`)
- Use `follows` for shared inputs
- Define outputs for multiple systems when needed
- Use `nix flake check` for validation

### Home Manager
- Use programs.* when available
- Set stateVersion once, don't change
- Group related configurations in modules
- Prefer xdg.configFile for XDG-compliant apps
- Use home.packages for additional packages

### Security
- Never commit secrets to Git
- Use .env files (gitignored) for local config
- Provide .env.example as template

## Quick Commands

```bash
# Nix
nix build                      # Build flake output
nix develop                    # Enter dev shell
nix flake update              # Update inputs
nix flake check               # Validate
nix flake show                # Show outputs

# NixOS
sudo nixos-rebuild switch      # Apply and persist
sudo nixos-rebuild test        # Apply (rolls back on reboot)
sudo nixos-rebuild build       # Build without applying
nixos-rebuild dry-activate     # Show changes without applying

# Home Manager
home-manager switch           # Apply and persist
home-manager build            # Build without applying
```

## Anti-Patterns

❌ **Don't:**
- Put overlays in home.nix when useGlobalPkgs=true
- Use nested with statements
- Use absolute paths that break reproducibility
- Change stateVersion after initial setup
- Put secrets in configuration files

✅ **Do:**
- Define overlays in appropriate scope
- Use explicit attribute access
- Use fetchFromGitHub, fetchurl
- Set stateVersion once at initial setup
- Use .env files for secrets (gitignored)

## Related Skills

- `serena-usage` - Navigating Nix expressions
- `docker` - Containerizing Nix-built applications
- `kubernetes` - Deploying Nix-built containers
