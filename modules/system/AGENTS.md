# System Modules - Agent Context

**Parent:** `../../AGENTS.md` | **Domain:** Core system modules (43 .nix files)

## Overview
Core NixOS system configuration: kernel, networking, storage, security, users, SSH.
Changes here affect ALL hosts — see testing checklist in root AGENTS.md.

## Where To Look

| Task | Location |
|------|----------|
| SSH config, keys, CA | `ssh.nix`, `ssh-ca.nix` |
| User accounts | `users.nix` |
| Firewall, interfaces | `networking.nix`, `cluster-firewall.nix` |
| Nix daemon settings | `nix-config.nix`, `nix-settings.nix` |
| Kernel hardening | `kernel-hardening.nix`, `security.nix`, `security-hardening.nix` |
| Storage (BTRFS, ZRAM) | `btrfs-compression.nix`, `btrfs-tuning.nix`, `zram-tuning.nix` |
| GPU profile management | `gpu-profile-manager.nix` |
| OOM protection | `oom-protection.nix` |
| Mining coordination | `mining-coordinator.nix`, `mining-inference-coordinator.nix` |
| Boot diagnostics | `boot-emergency-diagnostics.nix`, `boot-error-fixes.nix` |
| Home Manager setup | `home-manager.nix` |
| Agenix secrets | `agenix-fixes.nix`, `agenix-secrets-registry.nix` |
| Tailscale VPN | `tailscale.nix` |
| Gaming detection | `gaming-detection.nix` |
| Distributed builds | `distributed-builds.nix` |

## Critical Files (test on ALL 4 nodes after editing)

- `ssh.nix` — SSH breakage = cluster lockout
- `users.nix` — user changes affect all hosts
- `networking.nix` — network changes can break connectivity
- `cluster-firewall.nix` — firewall rules affect all nodes

## Anti-Patterns (THIS DIRECTORY)

| Pattern | Why | Fix |
|---------|-----|-----|
| Direct firewall assignment | Replaces node configs, breaks SSH | Use `lib.mkOptionDefault` |
| Editing `hardware-configuration.nix` | Overwritten by nixos-generate-config | Put custom config in host `default.nix` |
| Hardcoded IPs | Not portable across nodes | Use host configs or profiles |
