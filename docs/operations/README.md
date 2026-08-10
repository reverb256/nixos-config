# Operations Documentation

> **Status:** Active subsystem navigation
> **Last Verified:** 2026-08-09
> **Owner:** Cluster operations

This directory contains operational references for hardware and mining. Runtime state
must come from the NixOS configuration, Kubernetes API, systemd, and the guarded `just`
recipes—not from an unverified prose snapshot.

## Current entry points

| Need | Document | Authority |
|---|---|---|
| GPU identity and host capabilities | `contracts/host-inventory.nix`, host configuration | Checked-in Nix inventory |
| Mining configuration | `hosts/*/peakminer.nix`, `modules/services/peakminer.nix` | NixOS source of truth |
| Kubernetes GPU scheduling | [`../kubernetes/README.md`](../kubernetes/README.md), `kubernetes-manifests/AGENTS.md` | Nix/Easykubenix or explicitly owned YAML |
| Rescue and recovery | [`../runbooks/nixos-usb-rescue.md`](../runbooks/nixos-usb-rescue.md) | Verified rescue procedure |

## Legacy references

- [`gpu-inventory-corrected.md`](gpu-inventory-corrected.md) is a historical inventory
  snapshot and may not match current GPU identity or allocation.
- [`mining-management-guide.md`](mining-management-guide.md) is an incomplete historical
  proposal; its former blank commands and capacity figures are intentionally not treated
  as procedures.

Re-verify these documents against the current host configurations and live GPU/Kubernetes
state before promoting either into the active set.
