# Host Configurations - Agent Context

**Parent:** `../AGENTS.md` | **Domain:** Per-host NixOS configs (31 .nix files, 4 hosts)

## Overview
Each host has 7-8 files under `hosts/<host>/`: `configuration.nix` (main body), `hardware-configuration.nix`
(auto-generated, NEVER edit), plus host-specific modules for services, desktop, firewall, hardware, monitoring.

The host *body* (`hosts/<host>/configuration.nix`) is wrapped by the dendritic registry entry
`modules/hosts/<host>/default.nix` (two-layer: content + evaluator). Shared modules are composed by
`lib/dendritic-host.nix` via `common-modules-list.nix` — see `../AGENTS.md` → "Host wiring (dendritic)".

## Host Files

| Host | Files | Role |
|------|-------|------|
| Zephyr | 9 files | Workstation, control plane, gaming |
| Nexus | 8 files | Primary server, AI, monitoring |
| Forge | 8 files | GPU computing, mining |
| Sentry | 7 files | Monitoring, logging |

Each host has: `configuration.nix`, `hardware-configuration.nix`, `hardware.nix`, `desktop.nix`, `firewall.nix`, `monitoring.nix`, `services.nix`.

## Where To Look

| Task | Location |
|------|----------|
| Host wiring (dendritic) | `modules/hosts/<host>/default.nix` |
| Host module imports | `<host>/configuration.nix` (top of file) |
| Host-specific services | `<host>/services.nix` |
| Host firewall ports | `<host>/firewall.nix` |
| Host hardware config | `<host>/hardware.nix` |
| Host desktop config | `<host>/desktop.nix` |
| Host monitoring | `<host>/monitoring.nix` |
| AI inference (Zephyr, Nexus) | `<host>/ai-inference.nix` |
| Mining proxy examples | `<host>/mining-proxy-example.nix` (Forge, Zephyr) |

## Host wiring (dendritic)

- `modules/hosts/<host>/default.nix` — the dendritic registry entry. Layer 1 sets
  `flake.modules.nixos.<host>Config = import ../../../hosts/<host>/configuration.nix;` (the body);
  Layer 2 sets `flake.nixosConfigurations.<host>` via `lib/dendritic-host.nix` `mkHost`.
- `common-modules-list.nix` → `modules/default.nix` is the shared module list, composed into every
  host by the evaluator (`commonModules ++ [hostConfig] ++ extraModules`).
- `contracts/host-inventory.nix` holds host identity/targetHost/tags/extraModules; colmena consumes it too.

## Import Order (per host body, `hosts/<host>/configuration.nix`)
1. `../../modules/default.nix` — shared modules (also supplied via common-modules-list.nix; NixOS dedupes)
2. `../../modules/hardware/*.nix` — host-specific hardware
3. `../../modules/services/k3s-cluster.nix` — K3s on all nodes
4. Host-specific modules (keepalived, security, etc.)

## Anti-Patterns
- NEVER edit `hardware-configuration.nix` — auto-generated, overwritten on `nixos-generate-config`
- Don't add host-specific logic to shared modules — use host files instead
- Don't import modules in configuration.nix that are already in `modules/default.nix` (double import)
