---
name: nixos-developer
description: NixOS configuration development patterns and workflows. Use when working on the NixOS codebase: adding modules, creating profiles, understanding flake architecture, or Nix language patterns.
---

# NixOS Developer

Guide for developing and maintaining the NixOS flake-based configuration with profile system.

## When to Use This Skill

Use this skill when:
- Adding new modules or profiles
- Creating host configurations
- Working with the flake architecture
- Understanding Nix language patterns in this codebase
- Creating or modifying services

## Project Structure

```
/etc/nixos/
├── flake.nix                    # Main flake (inputs & outputs)
├── flake.lock                   # Auto-generated, DO NOT EDIT
├── justfile                     # Just commands
├── AGENTS.md                    # Agent guidelines
├── CLAUDE.md                    # Claude Code patterns
├── hosts/                       # Host configurations
│   ├── zephyr/                  # Main workstation
│   ├── nexus/                   # Gaming/mining
│   ├── forge/                   # Mining/AI
│   └── sentry/                  # Mining/AI
├── lib/                         # Nix utilities
│   ├── attrs.nix                # Attribute helpers
│   └── modules.nix              # Module discovery
├── modules/                     # NixOS modules
│   ├── default.nix              # Module aggregator
│   ├── profiles/                # Profile system
│   │   ├── hardware/            # Hardware profiles
│   │   ├── role/                # Role profiles
│   │   └── network/             # Network profiles
│   ├── common-host.nix          # Shared host imports
│   ├── desktop/                 # Desktop modules
│   ├── gaming/                  # Gaming modules
│   ├── hardware/                # Hardware configs
│   ├── mining/                  # Mining modules
│   ├── services/                # Service modules
│   └── shell/                   # Shell configs
├── scripts/                     # Utility scripts
│   └── nixos-rebuild-safe.sh    # Mining-aware rebuild
├── secrets/                     # Agenix secrets
└── skills/                      # Custom skills
```

## Flake Architecture

### Inputs (flake.nix)
```nix
{
  description = "NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    agenix.url = "github:ryantm/agenix";
    # ... other inputs
  };

  outputs = { self, nixpkgs, home-manager, agenix, ... }: {
    # Outputs defined here
  };
}
```

### Outputs
```nix
outputs = { self, nixpkgs, ... }: {
  # nixosConfigurations: For nixos-rebuild
  nixosConfigurations = {
    zephyr = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [ ./hosts/zephyr/configuration.nix ];
    };
  };

  # colmena: For multi-host deployment
  colmena = {
    meta = { ... };
    zephyr = { ... };
    nexus = { ... };
  };

  # packages: Custom packages
  packages.x86_64-linux = {
    # Custom packages
  };

  # overlays: Package overlays
  overlays = {
    default = import ./overlays;
  };
};
```

## Profile System

The profile system enables composable, reusable configurations.

### Hardware Profiles

Located in `modules/profiles/hardware/`:

| Profile | Description |
|---------|-------------|
| `amd.enable` | AMD CPU IOMMU |
| `amd.zen` | Zen CPU optimizations |
| `intel.enable` | Intel CPU optimizations |
| `nvidia.enable` | NVIDIA GPU support |
| `nvidia.multiGpu` | Multi-GPU CUDA settings |
| `amdgpu.enable` | AMD GPU support |
| `corsair.enable` | Corsair AIO+RGB control |
| `monitoring.enable` | lm-sensors |

### Role Profiles

Located in `modules/profiles/role/`:

| Profile | Description |
|---------|-------------|
| `workstation` | Desktop + development tools |
| `gaming` | Steam, Lutris, game launchers |
| `vr` | WiVRn, SteamVR |
| `mining` | xmrig, lolminer |
| `aiInference` | AI gateway + MCP |
| `desktop` | Plasma, Wayland |

### Network Profiles

Located in `modules/profiles/network/`:

| Profile | Description |
|---------|-------------|
| `tailscale.enable` | Enable Tailscale VPN |
| `tailscale.advertiseRoutes` | Routes to advertise |

## Creating a New Host

### 1. Create Host Directory
```bash
mkdir -p hosts/new-host
```

### 2. Create Configuration
```nix
# hosts/new-host/configuration.nix
{ lib, pkgs, ... }: {
  imports = [
    ../../modules/default.nix
    ../../modules/common-host.nix
  ];

  # Hardware profiles
  hardware.profiles = {
    amd.zen = true;
    nvidia.enable = true;
    monitoring.enable = true;
  };

  # Role profiles
  profiles.role = {
    workstation = true;
    gaming = true;
    mining = true;
  };

  # Network profiles
  profiles.network.tailscale.enable = true;

  # Host-specific configuration
  networking.hostName = "new-host";
  system.stateVersion = "26.05";
};
```

### 3. Generate Hardware Configuration
```bash
# On the target host
sudo nixos-generate-config --root /mnt --show-hardware-config > hardware-configuration.nix
```

### 4. Add to Flake
```nix
# flake.nix outputs
nixosConfigurations.new-host = nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";
  modules = [ ./hosts/new-host/configuration.nix ];
};

# colmena
colmena.new-host = { name, nodes, ... }: {
  imports = [ ./hosts/new-host/configuration.nix ];
};
```

## Creating a New Profile

### Hardware Profile Example

```nix
# modules/profiles/hardware/new-hardware.nix
{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.hardware.profiles.new-hardware;
in
{
  options.hardware.profiles.new-hardware = {
    enable = mkEnableOption "New Hardware Profile";
  };

  config = mkIf cfg.enable {
    # Hardware-specific configuration
    hardware.enableRedistributableFirmware = true;
    # ... more config
  };
}
```

### Role Profile Example

```nix
# modules/profiles/role/new-role.nix
{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.profiles.role.new-role;
in
{
  options.profiles.role.new-role = {
    enable = mkEnableOption "New Role Profile";
  };

  config = mkIf cfg.enable {
    # Role-specific configuration
    services = {
      # Enable services
    };

    environment.systemPackages = with pkgs; [
      # Add packages
    ];
  };
}
```

## Module System

### Module Structure

```nix
# modules/services/example-service/default.nix
{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.services.example-service;
in
{
  options.services.example-service = {
    enable = mkEnableOption "Example Service";

    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Port to listen on";
    };

    extraConfig = mkOption {
      type = types.str;
      default = "";
      description = "Extra configuration";
    };
  };

  config = mkIf cfg.enable {
    # Implementation
    systemd.services.example-service = {
      description = "Example Service";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.example-package}/bin/example --port ${toString cfg.port}";
      };
    };
  };
}
```

### Register Module

Add to `modules/default.nix`:
```nix
{
  imports = [
    # ... other modules
    ./services/example-service
  ];
}
```

## Nix Language Patterns

### Attribute Sets
```nix
# With inherit
{
  inherit (pkgs) python3 nodejs;
}

# With let...in
let
  myPackage = pkgs.callPackage ./package.nix {};
in
{
  environment.systemPackages = [ myPackage ];
}
```

### List Operations
```nix
# Concatenate lists
environment.systemPackages = with pkgs; [
  vim
  git
] ++ lib.optionals cfg.enableGUI [
  plasma5
];

# Filter lists
builtins.filter (p: p ? python3) pkgs
```

### String Manipulation
```nix
# Concatenate
"${cfg.package}/bin/${cfg.binary}"

# Multi-line
''
  Line 1
  Line 2
''

# Indented multi-line
''
  Line 1
  ${indent "    " nestedConfig}
''
```

### Conditionals
```nix
# mkIf
config = mkIf cfg.enable { ... };

# mkMerge
config = mkMerge [
  (mkIf cfg.enable { ... })
  (mkIf cfg.disable { ... })
];

# mkDefault
settings = mkDefault { value = "default"; };
```

## Common Patterns

### Systemd Service
```nix
systemd.services.my-service = {
  description = "My Service";
  wantedBy = [ "multi-user.target" ];
  after = [ "network.target" ];

  serviceConfig = {
    ExecStart = "${pkgs.my-package}/bin/my-app";
    Restart = "on-failure";
    DynamicUser = true;
  };

  environment = {
    MY_VAR = "value";
  };
};
```

### User Configuration
```nix
users.users.j_kro = {
  isNormalUser = true;
  description = "Jeremy Kroeker";
  extraGroups = [ "networkmanager" "wheel" "docker" ];
  shell = pkgs.fish;
};

# Home Manager
home-manager.users.j_kro = { pkgs, ... }: {
  home.stateVersion = "26.05";
  programs.git = {
    enable = true;
    userName = "j_kro";
  };
};
```

### Package Overlay
```nix
# overlays/default.nix
final: prev: {
  my-package = prev.callPackage ./pkgs/my-package { };
}

# Use in config
nixpkgs.config.packageOverrides = pkgs: {
  my-custom = pkgs.callPackage ./mypackage { };
};
```

## Testing & Validation

### Syntax Check
```bash
# Fast syntax validation
nix flake check

# Show available configurations
nix flake show

# Evaluate configuration
nix eval .#nixosConfigurations.zephyr.config.system.build.toplevel
```

### Build Test
```bash
# Build without applying
sudo nixos-rebuild build --flake .#zephyr

# Test (temporary, rolls back on reboot)
sudo nixos-rebuild test --flake .#zephyr

# Dry activate (show changes without applying)
sudo nixos-rebuild dry-activate --flake .#zephyr
```

### Debugging
```bash
# Show derivation
nix derivation show $(nix-build -A nixosConfigurations.zephyr.config.system.build.toplevel)

# Print config value
nix eval .#nixosConfigurations.zephyr.config.services.ai-inference.enable
```

## Code Style

### Indentation
- 2 spaces (no tabs)
- Trailing commas on multi-line lists/attrs

### Comments
- Use `#` prefix
- Place above setting, not inline
- Blank lines between sections

### Naming
- Hostnames: lowercase (`zephyr`)
- Usernames: underscores (`j_kro`)
- Modules: lowercase with hyphens (`ai-inference`)
- Options: camelCase nested (`hardware.profiles.amd.zen`)

## Git Workflow

### Commit Format
```bash
# Conventional commits
feat: add new profile for X
fix: resolve Y issue
docs: update AGENTS.md
refactor: simplify module structure

# Atomic commits
git add modules/services/new-service
git commit -m "feat: add new service module"

git add AGENTS.md CLAUDE.md
git commit -m "docs: update agent guidelines"
```

### New Files Must Be Tracked
```bash
# IMPORTANT: Always git add new files before rebuild
touch modules/services/new-service/module.py
git add modules/services/new-service/module.py
sudo nixos-rebuild switch  # Now works!
```

## Quick Reference

| Task | Command |
|------|---------|
| Syntax check | `nix flake check` |
| Build | `nbuild` |
| Test | `ntest` |
| Switch | `nswitch` |
| Show config | `nix flake show` |
| Evaluate value | `nix eval .#nixosConfigurations.zephyr.config...` |
| Format .nix files | `nixpkgs-fmt **/*.nix` |

## Related Skills
- **nix-rebuild**: For rebuild workflow and commands
- **add-service**: For creating systemd service modules
- **nixos-deploy**: For multi-host deployment
