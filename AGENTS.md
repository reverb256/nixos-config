# PROJECT KNOWLEDGE BASE

**Generated:** 2026-01-26
**Commit:** 88d3861
**Branch:** main
**Mode:** Update

## OVERVIEW
Production-ready NixOS 26.05 distributed build cluster with VR gaming, cryptocurrency mining, and AI assistant capabilities. 51-core distributed build pool across 4 hosts with comprehensive automation and testing framework.

## STRUCTURE
```
/etc/nixos/
├── flake.nix                      # Flake with 11 inputs + 4 host definitions
├── configuration.nix              # Main shared config (~456 lines)
├── hardware-configuration.nix     # Auto-generated, DO NOT EDIT
├── home.nix                       # Home Manager for j_kro user
├── colmena.nix                   # Multi-host deployment configuration
├── justfile                      # Automation commands (25+ management tools)
├── machines.nix                  # 51-core distributed build pool
├── hosts/                        # Cluster node configurations (76+ lines)
├── modules/                      # Modular configuration (23 files, 310+ options)
├── packages/                     # Custom Nix packages
├── test-projects/                # Mock projects for testing
├── test-fish-syntax.fish          # Fish shell functionality test suite
├── test-detection.fish            # Project detection test suite
├── build-and-test.sh             # Master build and test orchestrator
└── vm-config.nix                 # VM configuration for isolated testing
```

## WHERE TO LOOK
| Task | Location | Notes |
|------|----------|-------|
| System packages | modules/system-packages.nix | ONLY location for packages |
| User config | modules/users.nix | All users, groups, sudo, Fish shell |
| Hardware mounts | hardware-configuration.nix | Btrfs subvolumes (@, @home, /data) |
| NVIDIA GPU | configuration.nix | hardware.nvidia block |
| SSH config | modules/ssh.nix | Password auth enabled for j_kro & root |
| Mining services | modules/mining.nix | `services.mining` options |
| VR/SteamVR | modules/gaming.nix | programs.steam + WiVRn |
| WiVRn config | modules/gaming.nix | Quest Pro streaming (100Mbps HEVC) |
| Smart mining pause | modules/gaming.nix | Auto-pause during VR/gaming |
| GameMode | modules/gaming.nix | +150MHz NVIDIA overclock |
| Static IP | modules/networking.nix | systemd-networkd ethernet (10.1.1.110) |
| VRChat blocklist | modules/networking.nix | 18+ domains blocked in extraHosts |
| DNS (Unbound) | modules/networking.nix | DoT to Google/Cloudflare/Quad9 |
| Firewall | modules/networking.nix | VR ports (9757-9760, 27031, 27036) |
| Systemd slices | modules/systemd-slices.nix | Workload isolation (nix, gaming, mining) |
| Environment vars | modules/environment.nix | All system environment variables |
| Distributed builds | machines.nix | 51-core pool configuration |
| Cluster deployment | colmena.nix | Multi-host Colmena configuration |
| Build commands | justfile | 25+ automation commands |
| Testing | build-and-test.sh | Master test orchestrator |
| VM testing | vm-config.nix | Isolated test environment |

## CODE MAP
| Symbol | Type | Location | Role |
|--------|------|----------|------|
| flake.nix outputs | Function | flake.nix | Flake output definition |
| nixosConfigurations.zephyr | AttrSet | flake.nix | NixOS system def |
| config imports | List | configuration.nix | All modules |
| overlays | List | flake.nix | lolminer/xmrig + nixpkgs-xr |
| services.mining | AttrSet | modules/mining.nix | Custom mining option |
| services.claude-code | AttrSet | modules/environment.nix | Claude Code service |
| lolminer-nvidia service | AttrSet | modules/mining.nix | GPU mining service |
| xmrig service | AttrSet | modules/mining.nix | CPU mining service |
| mining-smart-pause | AttrSet | modules/gaming.nix | Auto-pause during VR/gaming |
| services.wivrn | AttrSet | modules/gaming.nix | VR streaming |
| systemd.network | AttrSet | modules/networking.nix | Static IP config |
| users.j_kro | AttrSet | modules/users.nix | Main user account |
| users.mining | AttrSet | modules/users.nix | Mining system user |
| security.sudo.extraRules | List | modules/users.nix | Passwordless mining controls |
| nix.settings.trusted-users | List | modules/users.nix | Nix build permissions |
| programs.fish | AttrSet | modules/users.nix | Shell configuration |
| VR slices | AttrSet | modules/gaming.nix | vr.slice, gaming.slice |
| systemd.services | AttrSet | modules/systemd-slices.nix | Workload isolation slices |
| builders config | String | machines.nix | Distributed build pool |

## CONVENTIONS
- **Flakes enabled**: `nix.settings.experimental-features = ["nix-command" "flakes"]`
- **Kernel**: `linuxPackages_zen` instead of default
- **Desktop**: KDE Plasma 6 with Wayland (SDDM)
- **GPU**: NVIDIA proprietary drivers (stable), 32-bit enabled
- **SSH**: Key-only auth, root login allowed (security risk)
- **Cache**: 5-tier Cachix substituters (cache.nixos.org, nix-community, ezkea, nixpkgs-wayland, nix-gaming)
- **Modular**: Features split into modules in `modules/`
- **Static IP**: Ethernet configured at 10.1.1.110/24
- **Packages**: ONLY use `modules/system-packages.nix` for system packages
- **Services**: Create dedicated modules, don't add to main config
- **Users**: ALL user settings in `modules/users.nix`
- **Distributed builds**: 51 cores across zephyr (32), nexus (8), forge (3), sentry (8)
- **Justfile**: Primary automation system with 25+ commands
- **Testing**: Multi-stage validation (check → build → test → deploy)
- **Colmena**: Multi-host deployment for cluster management

## ANTI-PATTERNS (THIS PROJECT)
- **NEVER edit** `hardware-configuration.nix` (auto-generated)
- **NEVER** duplicate packages - use `modules/system-packages.nix` only
- **NEVER** add services to main config - use dedicated modules
- **NEVER** make edits without reading the entire file first
- **NEVER** add user settings to main config - use `modules/users.nix`
- **NEVER USE WORKAROUNDS** - Always fix root causes directly
- **NEVER MODIFY COLMENA CONFIGURATION** - Colmena is critical infrastructure
- **NEVER BREAK COLMENA DEPLOYMENT** - Always use `just cluster-deploy` for remote nodes
- **NEVER EDIT flake.nix EXCEPT FOR COLMENA** - Colmena configuration must be preserved
- **ALWAYS USE COLMENA** - Deploy all remote nodes using `just deploy-[node]` or `just cluster-deploy`
- **ALWAYS PRESERVE COLMENA STRUCTURE** - Host definitions, overlays, and deployment targets are essential
- **PermitRootLogin = "yes"** in SSH config (security risk)
- **Passwordless sudo** for wheel group (security risk)
- **Mining API ports** - Restrict to localhost via firewall rules
- **AAGL Overlay Broken** - Use direct package references instead

## UNIQUE STYLES
- User `j_kro` has passwordless sudo (wheel group)
- Auto-login enabled for `j_kro` user (plasma session)
- Hostname: "zephyr"
- Btrfs subvolumes: @, @home, /data
- **Custom mining option**: `services.mining` (not in upstream)
- **Smart mining pause**: Auto-detects VR (WiVRn/SteamVR), games, high GPU (>70%)
- **VRChat analytics blocked**: 18+ domains via extraHosts
- **WiVRn for Quest Pro**: 100Mbps HEVC streaming, RTX 3090 optimizations
- **GameMode NVIDIA overclock**: +150MHz, maximum performance mode
- **systemd slices**: vr.slice, gaming.slice for priority scheduling
- **Custom packages**: lolminer/xmrig with steam-run wrapper pattern
- **Multi-tier DNS**: Local Unbound (port 53) → DoT to Google/Cloudflare/Quad9
- **Distributed builds**: 51-core cluster with `--builders-use-substitutes`
- **Justfile automation**: 25+ commands for cluster management
- **Comprehensive testing**: Multi-layer validation with VM isolation
- **Colmena deployment**: Multi-host management with rollback capabilities

## COMMANDS
```bash
# System Management
just switch              # Rebuild and switch system
just build               # Build system (dry run)
just test                # Test configuration temporarily
just update              # Update flake inputs and rebuild
just clean               # Clean old generations

# Distributed Builds
nix build --builders-use-substitutes nixpkgs#package-name

# Cluster Management
just cluster-info        # Cluster overview
just cluster-deploy      # Deploy to all hosts
just cluster-status      # Check cluster status
just cluster-resources   # Monitor resource usage

# Mining Operations
just mining-start        # Start mining services
just mining-stop         # Stop mining services
just mining-status       # Check mining status

# Gaming Mode
just gaming-start        # Enable gaming optimizations
just perf-monitor        # Performance monitoring

# Development
just check               # nix flake check
just format              # Format with alejandra
just lint                # Lint with statix
just dev-setup           # Full development pipeline

# Testing
./build-and-test.sh      # Master test orchestrator
./test-fish-syntax.fish  # Fish shell tests
./test-detection.fish    # Project detection tests
```

## CODE QUALITY STANDARDS

### Linting Tools
This codebase uses three primary linting tools:

| Tool | Purpose | Command |
|------|---------|---------|
| **deadnix** | Find dead/unused code | `deadnix .` |
| **statix** | Linting and best practices | `statix check .` |
| **alejandra** | Code formatting | `alejandra .` |

### Pre-commit Checklist
Before committing, always run:
```bash
just format   # alejandra .
just lint     # statix check .
deadnix .     # Check for dead code
```

### Common Issues Found

#### 1. Unused Lambda Patterns (deadnix)
**Issue**: Unused parameters in function arguments
```nix
# BAD - unused parameters
{ config, lib, pkgs, ... }: {  # config, lib not used
  # ...
}

# GOOD - only declare what you use
{ pkgs, ... }: {
  # ...
}
```

#### 2. Repeated Keys (statix W20)
**Issue**: Repeating attribute keys instead of grouping
```nix
# BAD - repeated keys
{
  networking.hostName = "zephyr";
  networking.networkmanager.enable = true;
  networking.firewall.enable = true;
}

# GOOD - grouped keys
{
  networking = {
    hostName = "zephyr";
    networkmanager.enable = true;
    firewall.enable = true;
  };
}
```

#### 3. Empty Patterns (statix W10)
**Issue**: Using `{...}` when `_` is clearer
```nix
# BAD
{ ... }: {
  # no arguments used
}

# GOOD
_: {
  # explicitly no arguments
}
```

### Project Statistics (Post-Audit)
- **Total Files**: 65 nix files
- **Lines of Code**: ~3,500 (after cleanup)
- **Modules**: 23 specialized modules
- **Hosts**: 4-node cluster
- **Options**: 310+ configuration options

## NOTES
- **This is a personal config**, not a library
- **Modular architecture**: features in `modules/`, custom pkgs in `packages/`
- **Channel**: nixos-unstable
- **Mining services** auto-pause when VR/gaming detected
- **WiVRn configured** for Quest Pro with RTX 3090 optimizations
- **VRChat analytics** blocked in /etc/hosts (privacy)
- **Home Manager**: user j_kro config with Zen Browser, development tools
- **Justfile**: Primary automation system (replaces Makefile)
- **Testing**: Comprehensive multi-layer validation with health monitoring
- **Distributed builds**: 51-core cluster with automatic load balancing
- **Security**: SSH root login enabled, passwordless sudo for mining controls
- **Performance**: Systemd slices for workload isolation, GPU overclocking
- **AI Assistant**: Clawdbot integration with multi-model support
- **Backup**: Nexus handles automated backup duties
- **Monitoring**: Sentry provides system metrics and alerting