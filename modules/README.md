# NixOS Modules Documentation

This directory contains reusable NixOS modules for system configuration. Modules are organized by functional domain and follow consistent patterns for maintainability.

## Table of Contents

- [Architecture](#architecture)
- [Module Structure](#module-structure)
- [Naming Conventions](#naming-conventions)
- [Common Patterns](#common-patterns)
- [Module Categories](#module-categories)
- [Creating New Modules](#creating-new-modules)
- [Firewall Ports](#firewall-ports)

---

## Architecture

### Module Aggregation

The `default.nix` file acts as the central module aggregator, importing all submodules:

```nix
# modules/default.nix
{ ... }:
{
  imports = [
    ./network-constants.nix
    ./system/nix-config.nix
    ./services/ai-inference/default.nix
    # ... more modules
  ];
}
```

### Host Configuration

Host-specific configurations in `hosts/<hostname>/configuration.nix` import the module aggregator:

```nix
# hosts/zephyr/configuration.nix
{ ... }:
{
  imports = [
    ../../modules/default.nix  # Import all modules
    ../../modules/multimedia/gstreamer.nix  # Optional host-specific modules
  ];
}
```

---

## Module Structure

### Standard Module Template

```nix
# Description of what this module does
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.<module-name>;
  inherit (lib) mkEnableOption mkOption types mkIf;

in
{
  options.services.<module-name> = {
    enable = mkEnableOption "<human-readable description>";

    # Additional options...
  };

  config = mkIf cfg.enable {
    # Configuration when enabled...
  };
}
```

### Submodules

For complex modules with multiple components, use submodules:

```
modules/services/ai-inference/
├── default.nix       # Main module with options
├── gateway.nix       # Gateway service
├── router.nix        # Routing logic
├── monitor.nix       # Monitoring service
└── auth/
    ├── default.nix   # Authentication subsystem
    └── tailscale.nix # Tailscale auth provider
```

---

## Naming Conventions

### Namespace Selection

| Namespace | Usage | Examples |
|-----------|-------|----------|
| `config.programs.*` | Interactive GUI applications | `programs.lm-studio`, `programs.stability-matrix` |
| `config.services.*` | Background daemons/systemd services | `services.ai-inference`, `services.gpu-exporters` |

### File Naming

- Use kebab-case for filenames: `spotify-spotx.nix`, `gpu-exporters.nix`
- Match directory structure to namespace:
  - `services/lm-studio.nix` → `programs.lm-studio`
  - `desktop/spotify-spotx.nix` → `services.spotify-spotx`

---

## Common Patterns

### 1. Systemd Service Creation

Use the helper functions from `lib/spotify-common.nix` for Spotify-related services:

```nix
systemd.services.<name> = {
  description = "Human-readable description";
  after = [ "network.target" "network-online.target" ];
  wants = [ "network-online.target" ];
  wantedBy = [ "multi-user.target" ];
  serviceConfig = {
    Type = "simple";
    ExecStart = "<command>";
    Restart = "on-failure";
    RestartSec = "10s";
    StandardOutput = "journal";
    StandardError = "journal";
  };
};
```

### 2. Firewall Port Declaration

Modules should declare their own firewall ports:

```nix
config = mkIf cfg.enable {
  networking.firewall.allowedTCPPorts = [ cfg.port ];
};
```

**Current exception**: Some ports are declared in host configs for documentation purposes. This should be gradually migrated to module-level declarations.

### 3. State Directory Management

```nix
# Create state directories with tmpfiles
systemd.tmpfiles.rules = [
  "d /var/lib/<module-name> 0755 root root -"
  "d /var/lib/<module-name>/backups 0755 root root -"
];
```

### 4. Shell Script Wrappers

Use `writeShellScriptBin` for CLI tools:

```nix
environment.systemPackages = [
  (pkgs.writeShellScriptBin "<tool-name>" ''
    #!${pkgs.bash}/bin/bash
    <script content>
  '')
];
```

### 5. User/Service Account Creation

```nix
users.users.<service-name> = {
  isSystemUser = true;
  group = "<service-name>";
  description = "<Human-readable description>";
};
users.groups.<service-name> = { };
```

---

## Module Categories

### Desktop (`desktop/`)

GUI applications and desktop environment components.

| Module | Namespace | Description |
|--------|-----------|-------------|
| `plasma6.nix` | `services.desktop.plasma6` | KDE Plasma 6 desktop |
| `wayland-common.nix` | - | Wayland compositor settings |
| `flatpak.nix` | `services.flatpak-kde` | Flatpak support |
| `spotify-spotx.nix` | `services.spotify-spotx` | Spotify ad removal |
| `spotify-spicetify.nix` | `services.spotify-spicetify` | Spotify theming |

### Development (`development/`)

Development tools and languages.

| Module | Namespace | Description |
|--------|-----------|-------------|
| `tools.nix` | - | CLI development tools |
| `lsp.nix` | - | Language server protocols |
| `programming-languages.nix` | - | Language runtimes |

### Gaming (`gaming/`)

Game launchers and optimizations.

| Module | Namespace | Description |
|--------|-----------|-------------|
| `gaming.nix` | `services.gaming` | Base gaming module |
| `gaming-hdr.nix` | - | HDR configuration |
| `scopebuddy.nix` | `programs.scopebuddy` | Gamescope wrapper |

### Hardware (`hardware/`)

Hardware-specific configurations.

| Module | Namespace | Description |
|--------|-----------|-------------|
| `nvidia-common.nix` | - | NVIDIA driver base config |

### Mining (`mining/`)

Cryptocurrency mining configuration.

| Module | Namespace | Description |
|--------|-----------|-------------|
| `mining.nix` | `services.mining` | Mining service aggregator |

### Multimedia (`multimedia/`)

Media codec and format support.

| Module | Namespace | Description |
|--------|-----------|-------------|
| `gstreamer.nix` | `services.multimedia.gstreamer` | GStreamer codecs |

### Services (`services/`)

Background services and daemons.

| Module | Namespace | Description |
|--------|-----------|-------------|
| `ai-inference/` | `services.ai-inference` | AI gateway with routing |
| `lm-studio.nix` | `programs.lm-studio` | LM Studio GUI |
| `stability-matrix.nix` | `programs.stability-matrix` | SD package manager |
| `gpu-exporters.nix` | `services.gpu-exporters` | GPU metrics |
| `monitoring/` | `services.monitoring.*` | Prometheus/Grafana |

### Shell (`shell/`)

Shell configuration.

| Module | Namespace | Description |
|--------|-----------|-------------|
| `fish.nix` | - | Fish shell |
| `starship.nix` | - | Starship prompt |

### System (`system/`)

Core system configuration.

| Module | Namespace | Description |
|--------|-----------|-------------|
| `nix-config.nix` | - | Nix settings |
| `users.nix` | - | User accounts |

---

## Creating New Modules

### Step-by-Step Guide

1. **Determine the namespace**:
   - Is it a GUI app? Use `programs.*`
   - Is it a daemon? Use `services.*`

2. **Create the module file**:
   ```bash
   # e.g., modules/services/my-service.nix
   ```

3. **Use the standard template**:
   ```nix
   { config, lib, pkgs, ... }:
   let
     cfg = config.services.my-service;
     inherit (lib) mkEnableOption mkOption types mkIf;
   in {
     options.services.my-service = {
       enable = mkEnableOption "My Service";
       # Add options...
     };
     config = mkIf cfg.enable {
       # Add configuration...
     };
   }
   ```

4. **Add to the aggregator** (if it should be available on all hosts):
   ```nix
   # modules/default.nix
   imports = [
     ./services/my-service.nix
   ];
   ```

5. **Enable in host config**:
   ```nix
   # hosts/<hostname>/configuration.nix
   services.my-service.enable = true;
   ```

---

## Firewall Ports

### Module-Declared Ports

These ports are automatically opened when the module is enabled:

| Port | Module | Service |
|------|--------|---------|
| 8080 | ai-inference | Gateway API |
| 9190 | ai-inference | Metrics endpoint |
| 9400 | gpu-exporters | NVIDIA GPU metrics |
| 9104 | gpu-exporters | AMD GPU metrics (via node-exporter) |

### Host-Declared Ports

These ports are documented in host configurations:

| Port | Service | Description |
|------|---------|-------------|
| 1234 | LM Studio | Inference API server |
| 8080 | ai-inference | API Gateway |
| 9757-9759 | WiVRn | VR streaming |
| 9947 | WiVRn | VR streaming |
| 18789-18790 | Steam | Remote Play |
| 19898 | Moonlight | GameStream |
| 27031/27036 | Steam | Network |
| 5353 | mDNS | Service discovery |

---

## Common Libraries

### `desktop/lib/spotify-common.nix`

Shared utilities for Spotify-related modules:

- `mkSpotifyLogging` - Colored log functions
- `mkSpotifyPaths` - Spotify Flatpak detection
- `mkSpotifyVersionDetector` - Version checking
- `mkSpotifyStateDir` - State directory path
- `mkSpotifyTmpfiles` - tmpfiles.rules generation
- `mkSpotifySystemdService` - Service template
- `mkSpotifySystemdTimer` - Timer template
- `mkSpotifyCliWrapper` - CLI tool wrapper

Usage:
```nix
spotifyLib = import ./lib/spotify-common.nix { inherit lib pkgs; };

# Use helpers
systemd.tmpfiles.rules = spotifyLib.mkSpotifyTmpfiles "spotx";
```

---

## Guidelines

### DO

- Use `mkEnableOption` for boolean enable options
- Provide sensible defaults for all options
- Document the purpose of each option
- Use `mkIf cfg.enable` for conditional config
- Declare firewall ports in modules when possible
- Follow the existing directory structure

### DON'T

- Hardcode hostnames in reusable modules
- Duplicate code - extract to libraries
- Mix namespaces inconsistently
- Skip option descriptions
- Forget to add users/groups for services
- Over-complicate simple configurations

---

## Related Files

- `flake.nix` - Flake inputs and outputs
- `hosts/*/configuration.nix` - Host-specific configs
- `network-constants.nix` - Network configuration shared across hosts
