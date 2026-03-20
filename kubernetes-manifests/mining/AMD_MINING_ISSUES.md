# AMD GPU Mining Issues

## Status: NOT WORKING - GLIBC Incompatibility

### AMD Device Plugin: ✅ WORKING

The AMD device plugin is deployed and functioning correctly:
- DaemonSet: `amdgpu-device-plugin-daemonset` in `kube-system`
- Successfully detects 2x AMD Radeon RX 5700 XT GPUs
- Exposes `amd.com/gpu: 2` resource on Forge node
- Device plugin logs show healthy operation

### AMD Mining Pods: ❌ NOT WORKING

The lolMiner containers crash immediately when trying to access AMD GPUs.

### Root Cause: GLIBC ABI Incompatibility

```
NixOS host libraries (ROCm/AMDGPU) → compiled against GLIBC 2.38+
lolMiner container (Ubuntu 18.04)    → has GLIBC 2.27
```

When trying to load NixOS AMD OpenCL libraries (`libamdocl64.so`) into the Ubuntu-based container:
```
error: version `GLIBC_2.32' not found
error: version `GLIBC_2.34' not found
error: version `GLIBC_2.38' not found
```

### Why This Happens

1. **NixOS uses newer GLIBC** (2.38+) for all packages
2. **Container uses older GLIBC** (Ubuntu 18.04 has GLIBC 2.27)
3. **Binary incompatibility**: Libraries compiled against newer GLIBC cannot be loaded into processes using older GLIBC
4. **AMD OpenCL requires NixOS libraries**: The AMDGPU/ROCm drivers on NixOS are in `/nix/store` and require the NixOS GLIBC

### Attempted Solutions (All Failed)

1. ✅ Mount `/dev` - devices accessible
2. ✅ Mount `/nix/store` - symlinks resolve
3. ✅ Create OpenCL ICD file - doesn't help with GLIBC issue
4. ✅ Set `LD_LIBRARY_PATH` - doesn't fix GLIBC version mismatch
5. ✅ Try `LD_PRELOAD` - fails due to GLIBC symbols
6. ✅ Try TeamRedMiner image - image pull failed

### Potential Solutions

#### Option 1: Build NixOS-based Container Image
Create a custom lolMiner container based on NixOS or statically linked binaries.

#### Option 2: Use Host-Based Mining
Run AMD mining directly on the host via systemd service (original approach), while NVIDIA mining runs in Kubernetes.

#### Option 3: Different Mining Software
Find AMD mining software that:
- Works in containers
- Has statically linked binaries, OR
- Uses container-native AMD GPU drivers (ROCm in container)

#### Option 4: GPU Passthrough with VFIO
Use VFIO for direct GPU passthrough to a VM with proper AMD drivers.

### Current State

- **NVIDIA GPU mining**: ✅ Working in Kubernetes
- **AMD GPU mining**: ❌ Blocked by GLIBC incompatibility
- **AMD device plugin**: ✅ Working (just can't be used by lolMiner)

### Recommendation

For now, keep AMD mining on host (systemd) while NVIDIA mining runs in Kubernetes.
The AMD device plugin deployment is valuable for future AMD GPU workloads (AI/ML)
that might use different container images with proper AMD support.

---

**Date**: 2026-03-20
**Tested**: lolMiner 1.98a (swamp7/lolminer:latest)
**Host**: NixOS with ROCm 7.2.0
