# CachyOS Kernel Configuration

This document describes the CachyOS kernel configuration for zephyr.

## Overview

Zephyr uses the CachyOS kernel from [xddxdd/nix-cachyos-kernel](https://github.com/xddxdd/nix-cachyos-kernel), which provides x86_64-v3 optimizations with binary cache support.

Other hosts (nexus, sentry, forge) use the Zen kernel for stability.

## Kernel Configuration

| Host | CPU | Kernel Package | Reason |
|------|-----|----------------|--------|
| **zephyr** | Ryzen 9 5950X (Zen 3) | `cachyosKernels.linuxPackages-cachyos-latest-x86_64-v3` | Gaming workstation with AVX2 |
| **nexus** | Ryzen 9 3900X (Zen 2) | `linuxPackages_zen` | Backup/Build server |
| **sentry** | Ryzen 7 1700X (Zen 1) | `linuxPackages_zen` | Monitoring server |
| **forge** | Intel pre-AVX2 | `linuxPackages_zen` | GPU mining rig |

## x86_64-v3 Optimizations

Zephyr's CachyOS kernel includes:
- **Required flags:** AVX, AVX2, BMI1, BMI2, F16C, FMA, LZCNT, MOVBE, XSAVE
- **BORE Scheduler:** Better desktop/gaming latency
- **Binary Cache:** Pre-built kernels from xddxdd's Hydra CI

## Binary Cache

Add these settings to use pre-built CachyOS kernels:

```nix
{
  nix.settings.substituters = [ "https://attic.xuyh0120.win/lantian" ];
  nix.settings.trusted-public-keys = [ "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc=" ];
}
```

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
  nixpkgs.overlays = [ inputs.cachyos-kernel.overlays.pinned ];
}
```

### Host Configuration
```nix
{
  boot.kernelPackages = pkgs.cachyosKernels.linuxPackages-cachyos-latest-x86_64-v3;
}
```

## Rollback

To revert to Zen kernel:
```nix
boot.kernelPackages = pkgs.linuxPackages_zen;
```

## References

- [xddxdd/nix-cachyos-kernel](https://github.com/xddxdd/nix-cachyos-kernel)
- [CachyOS Kernel Wiki](https://wiki.cachyos.org/features/kernel/)
