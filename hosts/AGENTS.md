# Host Configurations - Agent Context

**Parent:** `../AGENTS.md` | **Domain:** Per-host NixOS configs (31 .nix files, 4 hosts)

## Overview
Each host has 7-8 files: `configuration.nix` (main), `hardware-configuration.nix` (auto-generated, NEVER edit),
plus host-specific modules for services, desktop, firewall, hardware, monitoring.

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
| Host module imports | `<host>/configuration.nix` (top of file) |
| Host-specific services | `<host>/services.nix` |
| Host firewall ports | `<host>/firewall.nix` |
| Host hardware config | `<host>/hardware.nix` |
| Host desktop config | `<host>/desktop.nix` |
| Host monitoring | `<host>/monitoring.nix` |
| AI inference (Zephyr, Nexus) | `<host>/ai-inference.nix` |
| Mining proxy examples | `<host>/mining-proxy-example.nix` (Forge, Zephyr) |

## Import Order (per host)
1. `../../modules/default.nix` — shared modules
2. `../../modules/hardware/*.nix` — host-specific hardware
3. `../../modules/services/k3s-cluster.nix` — K3s on all nodes
4. Host-specific modules (keepalived, security, etc.)

## Anti-Patterns
- NEVER edit `hardware-configuration.nix` — auto-generated, overwritten on `nixos-generate-config`
- Don't add host-specific logic to shared modules — use host files instead
- Don't import modules in configuration.nix that are already in `modules/default.nix` (double import)
