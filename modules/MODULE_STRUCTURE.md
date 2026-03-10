# NixOS Modules Structure

This document describes the organization and purpose of modules in this NixOS configuration.

## Overview

The module system follows a two-tier import pattern:
1. **Global imports** (`modules/default.nix`) - Imported via `flake.nix` for ALL hosts
2. **Host-specific imports** - Imported in individual `hosts/*/configuration.nix` files

## Module Organization

```
modules/
├── default.nix              # Global module aggregator (imported by flake.nix)
├── common-host.nix          # Shared imports for desktop/gaming hosts
├── common-host-defaults.nix # Default values shared across hosts
├── network-constants.nix    # Cluster-wide IP, port, and host definitions
│
├── desktop/                 # Desktop environment modules
│   ├── plasma6.nix          # KDE Plasma 6 configuration
│   ├── wayland-common.nix   # Wayland-specific settings
│   ├── flatpak.nix          # Flatpak integration
│   ├── lib/
│   │   └── spotify-common.nix  # Shared Spotify utilities
│   └── spotify-spotx.nix    # Spotify with SpotX patch
│
├── shell/                   # Shell configuration
│   ├── bash.nix             # Bash shell
│   └── fish.nix             # Fish shell (system-level enable + packages)
│
├── home-manager/            # Home Manager configuration (j_kro user)
│   ├── fish.nix             # Fish shell (user-level: aliases, functions, plugins)
│   └── starship.nix         # Starship prompt configuration
│
├── gaming/                  # Gaming modules
│   ├── gaming.nix           # Base gaming (Steam, Proton, etc.)
│   ├── gaming-hdr.nix       # HDR configuration for gaming
│   └── scopebuddy.nix       # ScopeBuddy HDR metadata injector
│
├── mining/                  # Mining modules
│   ├── mining.nix           # GPU/CPU mining configuration
│   └── mining-build-wrapper.nix  # Auto-pause mining during builds
│
├── development/             # Development tools
│   ├── tools.nix            # Base development tools
│   ├── lsp.nix              # Language servers
│   ├── programming-languages.nix  # Language-specific packages
│   ├── opencode.nix         # OpenCode AI assistant
│   └── web-testing.nix      # Web testing tools
│
├── services/                # Service modules
│   ├── ai-inference/         # AI inference gateway
│   │   ├── default.nix       # Main module
│   │   ├── auth/             # Authentication (Tailscale)
│   │   └── ai_inference_gateway/  # Python FastAPI code
│   ├── monitoring/           # Monitoring stack
│   │   ├── default.nix
│   │   ├── prometheus.nix
│   │   ├── grafana.nix
│   │   └── node-exporter.nix
│   ├── mcp-servers.nix       # MCP server configuration
│   ├── lm-studio.nix         # LM Studio (GUI)
│   ├── lm-studio-headless.nix # LM Studio (headless)
│   ├── stability-matrix.nix  # Stability Matrix AI manager
│   ├── nixos-share.nix       # NFS share of /etc/nixos
│   ├── spacebot.nix          # Spacebot CLI
│   ├── glitchtip-selfhosted.nix  # Error tracking
│   ├── nextcloud.nix         # Nextcloud hub
│   ├── service-gateway.nix   # Service gateway
│   ├── ci-runner.nix         # CI/CD runner
│   ├── gpu-exporters.nix     # GPU metrics exporters
│   ├── mining-exporter.nix   # Mining metrics exporter
│   ├── garnix.nix            # Garnix CI
│   ├── auto-update.nix       # Auto-update
│   ├── unbound-cluster.nix   # Unbound DNS cluster
│   ├── opencode-sync/        # OpenCode sync
│   └── podman-support.nix    # Podman container support
│
├── hardware/                # Hardware-specific modules
│   ├── nvidia-common.nix     # NVIDIA GPU base config
│   ├── nvidia-wayland.nix    # NVIDIA Wayland-specific
│   ├── amdgpu-wayland.nix    # AMD GPU Wayland
│   ├── corsair.nix           # Corsair AIO + RGB
│   └── monitoring.nix        # Hardware monitoring (lm-sensors)
│
├── system/                  # System-level modules
│   ├── nix-config.nix        # Nix settings
│   ├── nix-settings.nix      # Additional Nix configuration
│   ├── users.nix             # User accounts
│   ├── ssh.nix               # SSH configuration
│   ├── mosh.nix              # Mosh (mobile SSH)
│   ├── tailscale.nix         # Tailscale VPN
│   ├── polkit-rules.nix      # Polkit rules
│   ├── networking.nix        # NetworkManager settings
│   ├── distributed-builds.nix  # Distributed Nix builds
│   ├── nix-cache-server.nix  # Nix cache server
│   ├── security.nix          # Security hardening
│   ├── systemd-slices.nix    # Systemd resource limits
│   ├── services.nix          # Base system services
│   ├── system-packages.nix   # Base packages
│   ├── virtualisation.nix    # Virtualization
│   └── vm-tuning.nix          # VM performance tuning
│
├── multimedia/              # Multimedia modules
│   └── gstreamer.nix         # GStreamer codecs
│
├── network/                  # Network modules
│   └── cluster-hosts.nix     # Cluster host definitions
│
└── profiles/                # Profile system (composable features)
    ├── default.nix           # Profile aggregator
    ├── hardware/             # Hardware profiles
    │   ├── default.nix       # Hardware profile options
    │   └── implementations.nix  # Hardware profile implementations
    ├── role/                 # Role profiles
    │   ├── default.nix       # Role profile options
    │   └── implementations.nix  # Role profile implementations
    └── network/              # Network profiles
        └── default.nix       # Network profile options
```

## Import Strategy

### Global Imports (via flake.nix)

The following modules are imported for ALL hosts via `modules/default.nix`:

**Essential System**: nix-config, users, ssh, mosh, polkit-rules
**Desktop**: plasma6, wayland-common, flatpak, spotify-spotx
**Shell**: fish (system), fish + starship (Home Manager)
**Gaming**: gaming, gaming-hdr, scopebuddy
**Mining**: mining
**Development**: tools, lsp, programming-languages, opencode
**Services**: All services (mcp-servers, lm-studio, ai-inference, monitoring, etc.)
**Hardware**: nvidia-common, monitoring, corsair
**Profiles**: All profiles (hardware, role, network)

### Host-Specific Imports

Each host in `hosts/*/configuration.nix` imports:

1. **zephyr**: `modules/default.nix` (uses global imports)
2. **nexus, forge, sentry**: `modules/common-host.nix` (alternative path)

> **Note**: The dual import strategy is being standardized. All hosts should use `modules/default.nix` via `flake.nix`.

## Profile System

Profiles enable composable host definitions using declarative options:

### Hardware Profiles
```nix
hardware.profiles = {
  amd.zen = true;           # Zen CPU optimizations
  intel.enable = true;       # Intel CPU optimizations
  nvidia.enable = true;      # NVIDIA GPU support
  nvidia.multiGpu = true;    # Multi-GPU CUDA settings
  amdgpu.enable = true;      # AMD GPU support
  amdgpu.wayland = true;     # AMDGPU Wayland optimizations
  corsair.enable = true;     # Corsair AIO + RGB
  monitoring.enable = true;  # Hardware monitoring
};
```

### Role Profiles
```nix
profiles.role = {
  workstation = true;   # Desktop + development
  gaming = true;        # Steam, Lutris
  vr = true;            # WiVRn, SteamVR
  mining = true;        # GPU/CPU mining
  aiInference = true;   # AI gateway + MCP + RAG
  desktop = true;       # Plasma, Wayland
};
```

### Network Profiles
```nix
profiles.network.tailscale.enable = true;
profiles.network.tailscale.advertiseRoutes = ["10.1.1.0/24"];
```

## Adding New Modules

1. **Determine scope**: Should the module be:
   - Global (all hosts)? → Add to `modules/default.nix`
   - Host-specific? → Add to specific `hosts/*/configuration.nix`
   - Profile-based? → Add to appropriate `profiles/*/implementations.nix`

2. **Create module file** in the appropriate subdirectory

3. **Follow naming conventions**:
   - Use lowercase with hyphens: `my-new-module.nix`
   - Group related modules in subdirectories

4. **Add to imports** in the appropriate location

## Module Design Patterns

### Options Pattern (Best Practices)
```nix
options.services.my-service = {
  # Always use mkEnableOption for boolean enable options
  enable = lib.mkEnableOption "My service description";
  
  # Always include example field for discoverability
  setting = lib.mkOption {
    type = lib.types.str;
    default = "default-value";
    example = "custom-value";
    description = "Setting description";
  };
  
  # For package options, use defaultText with literalExpression
  package = lib.mkOption {
    type = lib.types.package;
    default = pkgs.myService;
    defaultText = lib.literalExpression "pkgs.myService";
    description = "The myService package to use.";
  };
  
  # Use proper types (port, int, bool, enum, etc.)
  port = lib.mkOption {
    type = lib.types.port;
    default = 8080;
    example = 9000;
    description = "Port for the service";
  };
  
  # For complex nested options, use submodule
  advanced = lib.mkOption {
    type = lib.types.submodule {
      options = {
        enabled = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Enable advanced feature";
        };
        timeout = lib.mkOption {
          type = lib.types.int;
          default = 30;
          description = "Timeout in seconds";
        };
      };
    };
    default = {};
    description = "Advanced configuration options";
  };
};
```

### Config Pattern
```nix
config = lib.mkIf cfg.enable {
  # Configuration when enabled
};
```

### Systemd Service Security Hardening Pattern
```nix
systemd.services.my-service = {
  description = "My Service";
  wantedBy = ["multi-user.target"];
  after = ["network.target"];
  serviceConfig = {
    ExecStart = "${pkgs.myService}/bin/my-service";
    Restart = "on-failure";
    
    # Security hardening (applied to all services)
    NoNewPrivileges = true;
    ProtectSystem = "strict";
    ProtectHome = true;
    PrivateTmp = true;
    RestrictRealtime = true;
    
    # For services that need network access:
    RestrictAddressFamilies = ["AF_UNIX" "AF_INET" "AF_INET6"];
  };
};
```

### Profile Implementation Pattern
```nix
(lib.mkIf cfg.profiles.role.myRole {
  # Enable services when role is active
})
```

## Best Practices Summary

### Option Declarations
- ✅ Always use `lib.mkEnableOption` for boolean enable options
- ✅ Always include `example` field for `lib.mkOption` declarations
- ✅ Use `lib.literalExpression` for `defaultText` on package-type options
- ✅ Use specific types (`lib.types.port`, `lib.types.enum`, etc.) instead of generic types
- ✅ Use `lib.types.submodule` for complex nested configurations

### Systemd Services
- ✅ Always add security hardening options to serviceConfig:
  - `NoNewPrivileges = true`
  - `ProtectSystem = "strict"`
  - `ProtectHome = true`
  - `PrivateTmp = true`
  - `RestrictRealtime = true`
- ✅ Add `RestrictAddressFamilies` for services that need network access
- ✅ Set proper `After` and `WantedBy` dependencies

### Module Structure
- ✅ Organize modules by function (hardware/, services/, system/)
- ✅ Use `lib.mkIf cfg.enable` for conditional configuration
- ✅ Use `lib.mkMerge` for complex conditional logic
- ✅ Add inline comments explaining non-obvious configurations

## Storage Configuration

Storage is configured directly in host configs via `fileSystems.*`, not via modules.
This is intentional - storage is highly host-specific and benefits from inline configuration.

See individual `hosts/*/configuration.nix` for storage examples.
