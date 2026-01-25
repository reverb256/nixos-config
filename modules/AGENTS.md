# MODULES KNOWLEDGE BASE

**Generated:** 2026-01-24
**Scope:** NixOS Service Modules Architecture
**Complexity:** High (23 modules, 310+ options)

## OVERVIEW
Modular NixOS configuration with 23 specialized service modules covering gaming, mining, networking, storage, AI assistant, and system management.

## STRUCTURE
```
modules/
├── clawdbot-enhanced.nix     # AI assistant service (464 lines)
├── clawdbot-config.nix       # AI assistant configuration
├── environment.nix           # System environment variables
├── fish-starship.nix         # Fish shell configuration (261 lines)
├── gaming.nix                # VR/SteamVR/WiVRn + mining pause (372 lines)
├── mining.nix                # Custom mining services (222 lines)
├── mining-config.nix         # Mining service parameters
├── mining-overlay.nix        # Shared mining packages
├── networking.nix            # Network + DNS + firewall (253 lines)
├── ssh.nix                   # SSH server configuration
├── storage.nix               # Storage + rclone + backups (361 lines)
├── system-packages.nix       # Centralized packages (159 lines)
├── systemd-slices.nix        # Workload isolation
├── users.nix                 # User accounts + sudo (113 lines)
├── nexus-backups.nix         # Backup-specific module (96 lines)
├── lib/
│   └── mining-services.nix    # Mining service generators
└── gaming-trigger.sh         # Gaming detection script
```

## WHERE TO LOOK
| Task | Location | Notes |
|------|----------|-------|
| Service options | modules/*.nix:options | All use lib.mkOption pattern |
| System packages | modules/system-packages.nix | ONLY location for packages |
| Environment vars | modules/environment.nix | Centralized env variables |
| User management | modules/users.nix | Accounts, groups, sudo |
| Mining services | modules/mining.nix | Custom services.mining option |
| VR/Gaming | modules/gaming.nix | SteamVR, WiVRn, GameMode |
| Network config | modules/networking.nix | Static IP, DNS, firewall |
| Storage/Backups | modules/storage.nix | Local + rclone + timers |
| AI assistant | modules/clawdbot-enhanced.nix | Multi-model, multi-channel |

## CONVENTIONS
- **Option pattern**: `lib.mkOption { type = lib.types.<type>; default = <value>; }`
- **Enable pattern**: `lib.mkEnableOption "description"`
- **Config pattern**: `config = lib.mkIf cfg.enable { ... }`
- **Service pattern**: `systemd.services.<name> = { ... }`
- **Lib inherit**: `inherit (lib) types mkOption mkIf` or `with lib;`
- **Submodules**: `types.attrsOf (types.submodule { ... })` for nested options

## ANTI-PATTERNS (MODULES)
- **NEVER** add packages outside system-packages.nix
- **NEVER** create services without proper systemd integration
- **NEVER** use hardcoded paths - use cfg.stateDir pattern
- **NEVER** skip health monitoring for long-running services
- **ALWAYS** use mkOption for complex options
- **ALWAYS** provide enable option with mkEnableOption
- **ALWAYS** use mkIf guard for config section

## UNIQUE STYLES
- **Service generators**: mkMiningService factory pattern
- **Dynamic services**: mapAttrs' for rclone mounts/backups
- **Health monitoring**: 5-minute timer with API checks
- **Multi-model AI**: 7 providers, 11 tool categories
- **Smart mining pause**: Auto-detects VR/gaming/GPU usage
- **Declarative storage**: Btrfs/ZFS + rclone + automated backups
- **VRChat blocking**: 18+ domains blocked for privacy
- **ezKEa Overlay Workaround**: Direct package references bypass broken overlay system for AAGL launchers