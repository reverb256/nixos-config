# GPU-Accelerated Distributed Builds - User Guide

## Overview

Your NixOS cluster now supports GPU-accelerated builds with automatic detection of CUDA and ROCm capabilities.

## Hardware Configuration

| Host | CPU | RAM | GPUs | GPU Type | Max Jobs | GPU Features |
|-------|------|------|-------|-----------|--------------|
| zephyr | 32 cores | 64GB | RTX 3090 (24GB) | 6 | cuda |
| nexus | 24 cores | 48GB | 2x RTX 3060 Ti (8GB each) | 12 | cuda |
| forge | 6 cores | 16GB | 2x RTX 4060 + 2x RX 5700 XT | 2 | cuda, rocm |
| sentry | 8 cores | 32GB | RX 5600 XT | 6 | rocm |

**Total Build Capacity:** 26 concurrent jobs across 4 nodes

## Mining Awareness

The build system is configured to work alongside mining operations:

- **zephyr**: CPU mining (16 threads) + GPU mining (RTX 3090 @ 250W)
- **nexus**: GPU mining (2x RTX 3060 Ti @ 130W each)
- **forge**: HEAVY mining (4 GPUs + 95% CPU) - Use sparingly
- **sentry**: CPU-only mining (8 threads)

## GPU Build Usage

### Automatic Detection

Nix will automatically route GPU builds to nodes with appropriate hardware:

```bash
# CUDA packages automatically route to nexus, forge, or zephyr
nix build .#cuda-package

# ROCm packages automatically route to forge or sentry
nix build .#rocm-package
```

### Manual GPU Selection

To force builds on specific GPU nodes:

```bash
# Build only on CUDA-capable nodes
nix build .#package --option system-features "cuda"

# Build only on ROCm-capable nodes
nix build .#package --option system-features "rocm"

# Build on local GPU (zephyr)
nix build .#cuda-package --builders ''
```

### Hybrid CPU/GPU Builds

Builds requiring both CPU and GPU compute will be distributed intelligently:

```bash
# PyTorch with CUDA support
nix build python311Packages.torch

# TensorFlow with GPU support
nix build python311Packages.tensorflowWithCuda

# GPU-accelerated ML packages
nix build .#gpu-ml-package
```

## Network Optimization

Your cluster is configured for 1Gbps networking with TP-Link Easy Smart switches:

- **HTTP Connections**: 100 parallel downloads
- **Connect Timeout**: 30 seconds
- **Silent Timeout**: 1 hour (kill stuck builds)
- **Build Log Lines**: 2000 lines per build

## Binary Cache Configuration

The following binary caches are configured for fast dependency resolution:

- **cache.nixos.org**: Official NixOS cache
- **nix-community.cachix.org**: Community packages
- **cuda.cachix.org**: NVIDIA CUDA packages
- **rocm.cachix.org**: AMD ROCm packages
- **nix-gaming.cachix.org**: Gaming-related packages

## Build Scheduling

Build jobs are scheduled based on:

1. **Feature requirements** (cuda, rocm, kvm, big-parallel)
2. **Node availability** (mining status)
3. **RAM capacity** (4GB per job)
4. **Speed factor** (nexus=3x, forge=2x, sentry=1x)

### Priority Order

1. **nexus**: High priority (48GB RAM, 24 cores)
2. **forge**: Medium priority (Hybrid CUDA+ROCm)
3. **sentry**: Low priority (32GB RAM)
4. **zephyr**: Conservative (active mining)

## Experimental Features

The following experimental Nix features are enabled:

- **nix-command**: Modern Nix CLI
- **flakes**: Reproducible Nix expressions
- **repl-flake**: Interactive flake evaluation
- **fetch-tree**: Improved flake fetching and caching

## Troubleshooting

### Build Fails on GPU Node

```bash
# Check GPU status on node
ssh nexus "nvidia-smi"
ssh forge "nvidia-smi"
ssh sentry "rocm-smi"

# Check if mining is interfering
ssh nexus "ps aux | grep lolminer"
ssh forge "ps aux | grep lolminer"
```

### Build Too Slow

```bash
# Check which node build is running on
nix build .#package --print-build-logs | grep "building.*on"

# View active build distribution
nix-build-herd --status
```

### GPU Memory Issues

If builds fail with "CUDA out of memory":

```bash
# Reduce concurrent jobs on GPU node
nix build .#package --max-jobs 2

# Build on node with more GPU memory
nix build .#package --builders "ssh://zephyr"
```

## Performance Tips

1. **Use binary caches** when possible to avoid rebuilding
2. **Schedule builds during low mining activity** if flexibility exists
3. **Avoid GPU builds on forge** during peak mining hours
4. **Use nexus for large CPU builds** (48GB RAM, 24 cores)
5. **Use zephyr for CUDA builds** when not gaming/mining (RTX 3090 with 24GB VRAM)

## Monitoring

### Real-time Build Status

```bash
# Check active builds
nix-build-herd --status

# Monitor node load
for node in nexus forge sentry zephyr; do
  echo "=== $node ==="
  ssh $node "uptime"
done
```

### GPU Utilization

```bash
# NVIDIA GPUs (nexus, forge, zephyr)
for node in nexus forge; do
  ssh $node "nvidia-smi --query-gpu=utilization.gpu,temperature.gpu --format=csv"
done

# AMD GPUs (forge, sentry)
for node in forge sentry; do
  ssh $node "rocm-smi --showuse"
done
```

## Configuration Files

- **Distributed builds**: `/etc/nixos/modules/distributed-builds.nix`
- **Graceful degradation**: `/etc/nixos/modules/distributed-builds-graceful.nix`
- **Binary cache**: `/etc/nixos/configuration.nix`
- **Network**: Configured in Nix settings

## Support

For issues with GPU builds, check:
1. Nix daemon logs: `journalctl -u nix-daemon -f`
2. SSH connectivity: `ssh nexus "echo test"`
3. GPU drivers: `nvidia-smi` or `rocm-smi`
4. Mining conflicts: Stop mining temporarily if needed

