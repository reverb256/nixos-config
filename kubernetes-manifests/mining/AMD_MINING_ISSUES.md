# AMD GPU Mining Issues

## Status: NOT WORKING - GLIBC Incompatibility

### AMD Device Plugin: ✅ WORKING

The AMD device plugin is deployed and functioning correctly:
- DaemonSet: `amdgpu-device-plugin-daemonset` in `kube-system`
- Successfully detects 2x AMD Radeon RX 5700 XT GPUs
- Exposes `amd.com/gpu: 2` resource on Forge node
- Device plugin logs show healthy operation

### AMD Mining Pods: ❌ NOT WORKING

The lolMiner containers crash with segmentation fault when trying to use AMD GPUs.

### Root Cause: GLIBC ABI Incompatibility

```
NixOS host libraries (ROCm/AMDGPU) → compiled against GLIBC 2.42
lolMiner container (Ubuntu 18.04)    → has GLIBC 2.27
```

When trying to load NixOS AMD OpenCL libraries (`libamdocl64.so`) into the Ubuntu-based container:
```
Segmentation fault (core dumped)
```

### Why This Happens

1. **NixOS uses newer GLIBC** (2.42) for all packages
2. **Container uses older GLIBC** (Ubuntu 18.04 has GLIBC 2.27)
3. **Binary incompatibility**: Libraries compiled against newer GLIBC cannot be loaded into processes using older GLIBC
4. **AMD OpenCL requires NixOS libraries**: The AMDGPU/ROCm drivers on NixOS are in `/nix/store` and require the NixOS GLIBC

### Attempted Solutions (All Failed)

1. ✅ Mount `/dev` - devices accessible
2. ✅ Mount `/run/current-system/sw/share/nix-ld` - nix-ld accessible
3. ✅ Mount `/nix/store` - nix store accessible
4. ✅ Create OpenCL ICD file - doesn't help with GLIBC issue
5. ✅ Set `LD_LIBRARY_PATH` - doesn't fix GLIBC version mismatch
6. ✅ Use container's lolMiner binary - segfaults when loading NixOS OpenCL libs
7. ✅ Use host's lolMiner binary - fails to execute in container environment
8. ✅ Try explicit loader invocation - doesn't solve GLIBC mismatch

### Test Results Summary

| Approach | Result | Error |
|----------|--------|-------|
| Container lolMiner + NixOS OpenCL | ❌ | Segmentation fault |
| Host lolMiner in container | ❌ | Execution failure |
| nix-ld with NIX_LD_LIBRARY_PATH | ❌ | GLIBC symbol mismatch |

### Validation on Host

AMD mining **DOES WORK** on the host with nix-ld:
```bash
NIX_LD_LIBRARY_PATH=/run/current-system/sw/share/nix-ld/lib /tmp/mining/lolMiner \
  --algo=CR29 --pool=xtm-c29-us.kryptex.network:8040 --user=...
```
Successfully detects GPUs and connects to mining pool.

### Potential Solutions

#### Option 1: Build NixOS-based Container Image ⭐ RECOMMENDED
Create a custom lolMiner container based on NixOS or statically linked binaries.
- Use `nix-build` or `nix-bundle` to create a container image
- Include lolMiner and all dependencies statically linked
- This would allow the container to work with NixOS libraries

#### Option 2: Use Host-Based Mining
Run AMD mining directly on the host via systemd service (current working approach), while NVIDIA mining runs in Kubernetes.

#### Option 3: Different Mining Software
Find AMD mining software that:
- Works in containers
- Has statically linked binaries, OR
- Uses container-native AMD GPU drivers (ROCm in container)

#### Option 4: GPU Passthrough with VFIO
Use VFIO for direct GPU passthrough to a VM with proper AMD drivers.

### Current State

- **NVIDIA GPU mining**: ✅ Working in Kubernetes
- **AMD GPU mining**: ❌ Blocked by GLIBC incompatibility (host mining works)
- **AMD device plugin**: ✅ Working (just can't be used by lolMiner)

### Recommendation

For now, **keep AMD mining on host (systemd)** while NVIDIA mining runs in Kubernetes.
The AMD device plugin deployment is valuable for future AMD GPU workloads (AI/ML)
that might use different container images with proper AMD support.

To enable AMD GPU mining in Kubernetes, create a NixOS-based container image with lolMiner.

---

**Date**: 2026-03-20 (Updated)
**Tested**: lolMiner 1.98a (swamp7/lolminer:latest)
**Host**: NixOS with ROCm 7.2.0, GLIBC 2.42
