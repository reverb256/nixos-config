# CUDA Setup & Troubleshooting Guide

**Last Updated:** 2026-03-16
**Status:** ✅ Working (resolved `allowUnsupportedSystem` issue)

---

## Quick Start: Enable CUDA on NixOS

### 1. Enable GPU Compute Module

```nix
# hosts/<hostname>/configuration.nix
hardware.gpu-compute = {
  enable = true;
  cuda.enable = true;   # For NVIDIA GPUs
  vulkan.enable = true; # Optional: Vulkan fallback
};
```

### 2. Verify CUDA Installation

```bash
# Check NVIDIA driver
nvidia-smi

# Check CUDA libraries
nix-build -E 'pkgs: pkgs.cudaPackages.cuda_cudart'

# Test with llama.cpp
llama-cli --help | grep cuda
```

---

## Common Issues & Solutions

### ❌ Issue: `cuda_compat: variable $src or $srcs should point to the source`

**Error Message:**
```
error: builder for '/nix/store/...-cuda12.8-cuda_compat-12.8.39468522.drv' failed with exit code 1;
> variable $src or $srcs should point to the source
```

**Root Cause:** `allowUnsupportedSystem = true;` in configuration

**Solution:** Remove `allowUnsupportedSystem` from `flake.nix`:

```nix
# ❌ WRONG - Causes cuda_compat build failure
{nixpkgs.config.allowUnsupportedSystem = true;}

# ✅ CORRECT - Remove this line
# (Nix correctly filters platform-specific packages)
```

**Background:** cuda_compat is Jetson/ARM64-only. With `allowUnsupportedSystem`, Nix ignores platform restrictions and tries to build it on x86_64, where it has no source.

**GitHub Issue:** https://github.com/NixOS/nixpkgs/issues/458799
**Status:** Closed (Nov 7, 2025) - User configuration issue, not nixpkgs bug

---

### ❌ Issue: CUDA package not found

**Error:** `error: attribute 'cudaPackages' missing`

**Solution:** Enable unfree packages:

```nix
nixpkgs.config.allowUnfree = true;
```

---

### ❌ Issue: CUDA version mismatch

**Symptoms:** Applications can't find CUDA libraries

**Solution:** Use CUDA binary cache:

```nix
nix.settings = {
  substituters = [ "https://cache.nixos-cuda.org" ];
  trusted-public-keys = [ "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M=" ];
};
```

---

## CUDA Package Reference

### Available Packages

| Package | Description |
|---------|-------------|
| `cudaPackages.cuda_cudart` | Core CUDA runtime (minimum for llama.cpp) |
| `cudaPackages.cuda_nvcc` | CUDA compiler (for building CUDA code) |
| `cudaPackages.cudnn` | cuDNN (for PyTorch/TensorFlow) |
| `cudaPackages.nccl` | NCCL (for multi-GPU communication) |

### Package Versions

```nix
# Use latest (default)
pkgs.cudaPackages.cuda_cudart

# Pin to specific version
pkgs.cudaPackages_12_6.cuda_cudart
pkgs.cudaPackages_12_8.cuda_cudart
```

---

## Multi-GPU CUDA Setup

### 1. Kernel Modules (Required for Multi-GPU)

```nix
boot.kernelModules = [
  "nvidia"      # Core driver
  "nvidia_uvm"  # Unified Memory (CRITICAL for multi-GPU)
];
```

### 2. Environment Variables

```nix
environment.sessionVariables = {
  CUDA_VISIBLE_DEVICES = "0,1";  # Which GPUs to use
  NCCL_P2P_LEVEL = "2";           # PCIe P2P level
};
```

### 3. Verify Multi-GPU Setup

```bash
# Check GPU topology
nvidia-smi topo -m

# Check for P2P support (look for PHB/PIX between GPUs)
```

---

## ROCm (AMD GPUs)

### Enable ROCm on Forge/Sentry

```nix
hardware.gpu-compute = {
  enable = true;
  rocm.enable = true;  # For AMD GPUs (RX 5700 XT, RX 5600 XT)
};
```

### Verify ROCm

```bash
rocminfo | grep -E "Name|Compute|Memory"
```

---

## Vulkan Compute (Universal Backend)

### Why Vulkan?

- **Universal:** Works on NVIDIA, AMD, Intel GPUs
- **Performance:** ~85-95% of CUDA performance on NVIDIA
- **No build issues:** Avoids cuda_compat complications entirely

### Enable Vulkan

```nix
hardware.gpu-compute.vulkan.enable = true;
```

### Test Vulkan

```bash
# Check Vulkan devices
vulkaninfo | grep -E "deviceName|driverVersion"

# Test with llama.cpp
llama-cli --gpu vulkan --help
```

---

## Cluster GPU Inventory

| Host | GPUs | CUDA | ROCm | Vulkan |
|------|------|------|------|--------|
| Zephyr | 2× NVIDIA (3090, 3060 Ti) | ✅ | - | ✅ |
| Nexus | 1× NVIDIA (3060 Ti) | ✅ | - | ✅ |
| Forge | 2× NVIDIA (4060) + 2× AMD (5700 XT) | ✅ | ✅ | ✅ |
| Sentry | 1× AMD (5600 XT) | - | ✅ | ✅ |

---

## Performance Tips

### 1. Enable Persistence Mode

```nix
systemd.services.nvidia-persistence-mode = {
  description = "Enable NVIDIA GPU persistence mode";
  serviceConfig.ExecStart = "${pkgs.linuxPackages.nvidiaPackages.beta}/bin/nvidia-smi -pm 1";
};
```

### 2. Enable GPU Direct (RDMA)

For systems with GPU-direct networking (data center GPUs only).

### 3. Optimize Tensor Core Usage

- Use FP16/BF16 where possible
- Enable Flash Attention (for compatible models)
- Use appropriate batch sizes

---

## References

- [NixOS CUDA Wiki](https://wiki.nixos.org/wiki/CUDA)
- [NixOS CUDA Maintainers](https://github.com/NixOS/cuda-maintainers)
- [CUDA Binary Cache](https://cache.nixos-cuda.org)
- [Issue #458799](https://github.com/NixOS/nixpkgs/issues/458799)
