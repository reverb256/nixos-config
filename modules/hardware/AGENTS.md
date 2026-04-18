# Hardware Modules - Agent Context

**Parent:** `../../AGENTS.md` | **Domain:** GPU and hardware config (7 .nix files)

## Overview
GPU driver configuration for NVIDIA and AMD, plus peripheral support (Corsair RGB, hardware monitoring).
Each host imports only the hardware modules it needs.

## Where To Look

| Task | Location |
|------|----------|
| NVIDIA base config | `nvidia-common.nix` |
| NVIDIA Wayland | `nvidia-wayland.nix` |
| AMD GPU Wayland | `amdgpu-wayland.nix` |
| GPU compute mode | `gpu-compute.nix` |
| Hardware monitoring | `monitoring.nix` (lm-sensors) |
| Corsair AIO/RGB | `corsair.nix` |
| RGB control | `rgb-control.nix` |

## Host Hardware Mapping

| Host | NVIDIA | AMD | Corsair | Monitoring |
|------|--------|-----|---------|------------|
| Zephyr | `nvidia-common.nix`, `nvidia-wayland.nix` | — | `corsair.nix` | `monitoring.nix` |
| Nexus | `nvidia-common.nix`, `nvidia-wayland.nix` | — | `corsair.nix` | `monitoring.nix` |
| Forge | `nvidia-common.nix`, `nvidia-wayland.nix` | `amdgpu-wayland.nix` | `corsair.nix` | `monitoring.nix` |
| Sentry | — | `amdgpu-wayland.nix` | `corsair.nix` | — |

## Anti-Patterns
- Don't enable both `nvidia-wayland.nix` and `amdgpu-wayland.nix` unless the host actually has both GPU types
- `gpu-compute.nix` is for compute-only headless setups — don't use with desktop
