# CachyOS Kernel Configuration

This document describes the CachyOS kernel configuration for the Reverb-OS NixOS cluster.

## Overview

The cluster has been configured to use CachyOS kernels from [xddxdd/nix-cachyos-kernel](https://github.com/xddxdd/nix-cachyos-kernel), which provides x86_64-v2/v3/v4 variants with binary cache support.

## Kernel Variants per Host

| Host | CPU | Kernel Package | Rationale |
|-------|-----|----------------|-----------|
| **zephyr** | Ryzen 9 5950X (Zen 3) | `linuxPackages-cachyos-latest-x86_64-v3` | Zen 3 supports AVX2, BMI2, FMA - fully compatible with x86_64-v3 |
| **nexus** | Ryzen 9 3900X (Zen 2) | `linuxPackages-cachyos-latest-x86_64-v3` | Zen 2 supports AVX2, BMI2, FMA - fully compatible with x86_64-v3 |
| **sentry** | Ryzen 7 1700X (Zen 1) | `linuxPackages-cachyos-latest-x86_64-v3` | Zen 1 supports AVX2, BMI2, FMA - fully compatible with x86_64-v3 |
| **forge** | Intel pre-AVX2 CPU | `linuxPackages-cachyos-latest-x86_64-v2` | Intel CPU lacks AVX2 - requires x86_64-v2 (Nehalem-era optimizations) |

## x86_64-v3 vs x86_64-v2

### x86_64-v3
- **Required flags:** AVX, AVX2, BMI1, BMI2, F16C, FMA, LZCNT, MOVBE, XSAVE
- **Corresponds to:** Intel Haswell (2013+) or AMD Excavator (Zen 2+)
- **Benefits:**
  - 256-bit AVX2 vector instructions
  - Fused multiply-add (FMA) instructions
  - Enhanced bit manipulation (BMI1, BMI2)
  - ~10% performance improvement for SIMD workloads (reported by users)
- **Compatible with:** All Ryzen Zen 1/2/3 CPUs (all have AVX2)

### x86_64-v2
- **Required flags:** CMPXCHG16B, LAHF-SAHF, POPCNT, SSE3, SSE4.1, SSE4.2, SSSE3
- **Corresponds to:** Intel Nehalem (2008+) or AMD Jaguar
- **Benefits:** Still optimized over baseline x86_64
- **Compatible with:** Pre-AVX2 Intel CPUs and older AMD hardware

## CachyOS Features

- **BORE Scheduler:** Barr-O-based Reclaim Entirely scheduler for better desktop/gaming latency
- **LTO (Link-Time Optimization):** Available for improved performance (~10% Geekbench)
- **x86_64-v3 Optimizations:** AVX2, BMI2, FMA flags enabled by default
- **NVIDIA Driver Integration:** Pre-configured for stable and beta drivers
- **Latest Kernel Versions:** Tracks CachyOS's upstream patches
- **ZFS Support:** CachyOS-patched ZFS module available

## Configuration

### Flake Input
```nix
{
  inputs = {
    cachyos-kernel.url = "github:xddxdd/nix-cachyos-kernel/release";
  };
}
```

### Overlay
```nix
{
  nixpkgs.overlays = [
    inputs.cachyos-kernel.overlays.pinned  # Use pinned for binary cache
  ];
}
```

### Host Configuration
```nix
{
  boot.kernelPackages = pkgs.cachyosKernels.linuxPackages-cachyos-latest-x86_64-v3;
}
```

## Binary Cache

The xddxdd/nix-cachyos-kernel repository provides a binary cache:

```nix
{
  nix.settings.substituters = [ "https://attic.xuyh0120.win/lantian" ];
  nix.settings.trusted-public-keys = [ "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc=" ];
}
```

## Build Notes

- First build may take 10-20 minutes if binary cache is unavailable
- Using `release` branch ensures binary cache availability
- Using `overlays.pinned` guarantees exact kernel versions with binary cache

## Rollback Strategy

If issues arise, revert to previous kernel:
```nix
boot.kernelPackages = pkgs.linuxPackages_zen;  # or default kernel
```

Or use `nixos-rebuild switch --rollback` to select a previous generation.

## Available Kernel Variants

From xddxdd/nix-cachyos-kernel:
- `linuxPackages-cachyos-latest` - Base latest kernel
- `linuxPackages-cachyos-latest-x86_64-v2` - x86_64-v2 optimized
- `linuxPackages-cachyos-latest-x86_64-v3` - x86_64-v3 optimized
- `linuxPackages-cachyos-latest-x86_64-v4` - x86_64-v4 optimized (AVX-512)
- `linuxPackages-cachyos-latest-lto` - LTO enabled
- `linuxPackages-cachyos-lts` - LTS kernel
- `linuxPackages-cachyos-bore` - BORE scheduler variant
- `linuxPackages-cachyos-hardened` - Hardened security patches

## References

- [xddxdd/nix-cachyos-kernel](https://github.com/xddxdd/nix-cachyos-kernel)
- [CachyOS Kernel Wiki](https://wiki.cachyos.org/features/kernel/)
- [x86_64 Microarchitecture Levels](https://gitlab.com/x86-psABIs/x86-64-ABI)
