# Profile Modules - Agent Context

**Parent:** `../../AGENTS.md` | **Domain:** Composable hardware/role/network profiles

## Overview
Declarative profile system inspired by hlissner/dotfiles. Profiles compose per-host
to define hardware capabilities, node roles, and network settings.

## Structure
```
profiles/
├── default.nix              # Profile aggregator
├── hardware/
│   ├── default.nix          # Hardware profile options
│   └── implementations.nix   # Hardware profile implementations
├── role/
│   ├── default.nix          # Role profile options
│   └── implementations.nix   # Role profile implementations
├── network/
│   ├── default.nix          # Network profile options
│   └── networking.nix       # Network profile implementations
├── node-profiles.nix        # K8s node profiles
├── node-profiles-test.nix   # K8s node profile tests
└── monitoring.nix           # Monitoring profile
```

## Where To Look

| Task | Location |
|------|----------|
| Add hardware profile | `hardware/implementations.nix` |
| Add role profile | `role/implementations.nix` |
| Add network profile | `network/networking.nix` |
| K8s node labels | `node-profiles.nix` |
| Monitoring setup | `monitoring.nix` |

## Available Profiles

**Hardware**: `amd.zen`, `nvidia.enable`, `nvidia.multiGpu`, `amdgpu.wayland`, `corsair.enable`, `monitoring.enable`
**Role**: `workstation`, `server`, `gaming`, `vr`, `desktop`, `mining`, `aiInference`
**Network**: `tailscale.enable`, `tailscale.advertiseRoutes`

## Usage Pattern
```nix
# In host configuration.nix:
hardware.profiles = { nvidia.enable = true; amdgpu.wayland = true; };
profiles.role = { workstation = true; gaming = true; };
profiles.network.tailscale.enable = true;
```
