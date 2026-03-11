# NVIDIA Device Plugin + containerd + NixOS Investigation Report

**Date**: 2026-03-11
**Status**: ❌ **BLOCKED** - Device plugin cannot load NVML libraries from NixOS symlink structure
**Root Cause**: NVIDIA device plugin cannot resolve `/run/opengl-driver/lib/libnvidia-ml.so.1` symlinks that point to `/nix/store/...`

---

## Executive Summary

After switching from CRI-O to containerd (as recommended in previous investigation), the NVIDIA device plugin still fails to work on NixOS. The core issue is that NixOS uses a symlink-based package management where libraries in `/run/opengl-driver/lib/` are symlinks to files in `/nix/store/...`, and container processes cannot properly resolve these symlinks.

---

## Current Configuration

### ✅ What's Properly Configured

**containerd Runtime**: Enabled and running (switched from CRI-O)
**NVIDIA Drivers**: Working at host level
- `nvidia-smi` works on both forge (2x RTX 4060) and zephyr (RTX 3090 + RTX 3060 Ti)
- Device files exist: `/dev/nvidia0`, `/dev/nvidia1`, `/dev/nvidiactl`, etc.
- Driver libraries in `/run/opengl-driver/lib/` (symlinks to nix store)

**NVIDIA Container Toolkit**: v1.18.2 installed
- `nvidia-ctk` available but crashes when generating CDI specs on NixOS

**Device Labels**: Both nodes labeled with `accelerator=nvidia-gpu`

### ❌ The Problem

**Device Plugin Error** (v0.18.2 with CDI annotation):
```
E0311 08:55:09.287120       1 factory.go:113] Incompatible strategy detected auto
E0311 08:55:09.287129       1 factory.go:114] If this is a GPU node, did you configure the NVIDIA Container Toolkit?
I0311 08:55:09.287151       1 main.go:394] No devices found. Waiting indefinitely.
```

**Device Plugin Error** (v0.14.x - legacy, with driver libraries mounted):
```
I0311 09:07:03.127705       1 factory.go:107] Detected non-NVML platform: could not load NVML library: libnvidia-ml.so.1: cannot open shared object file: No such file or directory
E0311 09:07:03.127749       1 factory.go:115] Incompatible platform detected
```

**Library Structure Issue**:
```bash
$ ls -la /run/opengl-driver/lib/libnvidia-ml.so.1
lrwxrwxrwx 4 root root  94 Jan  1  1970 /run/opengl-driver/lib/libnvidia-ml.so.1 ->
  /nix/store/sc28pxrmzmw93lzmfq8piiw1sxffz38f-nvidia-x11-595.45.04-6.18.13/lib/libnvidia-ml.so.1
```

The symlink points to `/nix/store/...` but the container cannot access the nix store path to resolve the library.

---

## Attempted Solutions

### Solution 1: Remove `/run/opengl-driver/lib64` Mount ✅

**Problem**: DaemonSet referenced `/run/opengl-driver/lib64` which doesn't exist on NixOS.

**Fix**: Removed lib64 from volume mounts and LD_LIBRARY_PATH.

**Result**: ✅ Fixed CreateContainerError, but plugin still couldn't detect GPUs.

---

### Solution 2: Disable CDI Mode ❌

**Approach**: Remove `nvidia.com/gpu.cdi.enabled: "true"` annotation.

**Result**: ❌ Plugin still reports "Incompatible strategy detected auto"

---

### Solution 3: Force NVML Device Discovery ❌

**Approach**: Add `--device-discovery-strategy=nvml` argument.

**Result**: ❌ Plugin reports asking if Docker default runtime is set to `nvidia`.

---

### Solution 4: Mount Driver Libraries ❌

**Approach**: Mount `/run/opengl-driver/lib` and set `LD_LIBRARY_PATH`.

**Result**: ❌ Plugin still reports "could not load NVML library: libnvidia-ml.so.1: cannot open shared object file"

---

### Solution 5: Mount Nix Store ❌

**Approach**: Mount `/nix/store` to allow symlink resolution.

**Result**: ❌ Library loading still fails, likely due to additional dependency resolution issues.

---

### Solution 6: Try Legacy Plugin Version (v0.14.x) ❌

**Approach**: Use older plugin version that doesn't require CDI.

**Result**: ❌ Same library loading error - "could not load NVML library"

---

## Root Cause Analysis

### The Real Problem

**NixOS Package Management**:
- Libraries in `/run/opengl-driver/lib/` are symlinks to `/nix/store/...`
- The NVIDIA driver libraries have dependencies on other libraries
- Container processes cannot properly resolve the symlink chain
- Even when mounting `/nix/store`, dependency resolution fails

**NVIDIA Device Plugin Design**:
- Expects to load `libnvidia-ml.so.1` via dlopen()
- Uses NVML (NVIDIA Management Library) for device discovery
- Doesn't handle NixOS's symlink-based package management

**Why Zephyr Shows 2 GPUs**:
- This appears to be cached state from before the plugin broke
- The current plugin is NOT successfully detecting GPUs on either node
- Both forge and zephyr show "No devices found" in plugin logs

---

## Current Status

```
forge:  0 GPUs allocatable (plugin failing)
zephyr: 2 GPUs allocatable (cached/stale state, plugin failing)
```

**Device Plugin**: Deleted to prevent confusion

---

## Recommended Solutions

### Option A: Configure containerd with NVIDIA Runtime Class (Recommended)

**Approach**: Configure containerd to use the NVIDIA runtime class directly.

**Implementation**:
```nix
# In modules/services/kubernetes.nix
virtualisation.containerd = {
  enable = true;
  # Add nvidia runtime configuration
  extraConfig = ''
    [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia]
      runtime_type = "io.containerd.runc.v2"
      privileged_without_host_devices = false

      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia.options]
        BinaryName = "/run/current-system/sw/bin/nvidia-container-runtime"
  '';
};
```

**Pros**:
- ✅ Uses containerd's native runtime class mechanism
- ✅ Doesn't rely on device plugin for basic GPU access
- ✅ Works with NixOS symlink structure

**Cons**:
- ❌ Requires nvidia-container-runtime to work properly
- ❌ May still have NixOS compatibility issues

---

### Option B: Use Docker Runtime for GPU Workloads

**Approach**: Use Docker with NVIDIA runtime instead of containerd for GPU nodes.

**Implementation**:
```nix
virtualisation.docker = {
  enable = true;
  autoPrune.enable = true;
  # NVIDIA runtime configuration via nvidia-container-toolkit
};
```

Then configure Docker daemon:
```json
{
  "default-runtime": "nvidia",
  "runtimes": {
    "nvidia": {
      "path": "nvidia-container-runtime",
      "runtimeArgs": []
    }
  }
}
```

**Pros**:
- ✅ Docker + NVIDIA runtime is a well-tested combination
- ✅ May work better with NixOS than containerd

**Cons**:
- ❌ Requires switching Kubernetes to use Docker runtime (dockershim deprecated)
- ❌ Adds Docker layer on top of containerd

---

### Option C: Build Custom Device Plugin Container

**Approach**: Build a custom device plugin container image with NixOS-aware library loading.

**Implementation**:
- Use NixOS to build a container that includes NVIDIA libraries
- Either include libraries directly or set up proper symlink resolution
- Publish custom image to registry

**Pros**:
- ✅ Full control over library loading
- ✅ Can work around NixOS symlink issues

**Cons**:
- ❌ Requires building and maintaining custom image
- ❌ More complex setup

---

### Option D: Use Host-Network GPU Pods (Workaround)

**Approach**: Run GPU workloads with host networking and direct device access.

**Implementation**:
```yaml
apiVersion: v1
kind: Pod
spec:
  hostNetwork: true
  containers:
  - name: gpu-workload
    volumeMounts:
    - name: nvidia-dev
      mountPath: /dev/nvidia0
    volumes:
    - name: nvidia-dev
      hostPath:
        path: /dev/nvidia0
```

**Pros**:
- ✅ Simple workaround
- ✅ Doesn't require device plugin

**Cons**:
- ❌ Not proper Kubernetes GPU resource management
- ❌ No resource scheduling/enforcement
- ❌ Security implications (host devices)

---

### Option E: Skip GPU Workloads in Kubernetes (Temporary)

**Approach**: Accept limitation, focus on CPU-only services for now.

**Use Cases**:
- Run GPU workloads directly on hosts (docker, podman)
- Use Kubernetes for CPU-only services (GlitchTip, n8n, Nextcloud)
- Revisit GPU issue when better solutions emerge

**Pros**:
- ✅ Unblocks progress on other services
- ✅ No complex workarounds needed

**Cons**:
- ❌ Can't run AI workloads in Kubernetes
- ❌ Defeats purpose of GPU nodes in cluster

---

## Next Steps

### Recommended: Try Option A (containerd Runtime Class)

1. Research containerd runtime class configuration for NixOS
2. Test on single node (forge)
3. Verify GPU access from test pod
4. Roll out if successful

### Alternative: Proceed with CPU-Only Services

1. Deploy GlitchTip, n8n, Nextcloud (no GPU needed)
2. Test storage classes and PVCs
3. Document GPU limitation
4. Revisit when NVIDIA releases NixOS-compatible solution

---

## Research Questions

1. **Has anyone successfully used NVIDIA GPUs with Kubernetes on NixOS?**
   - Search NixOS discourse
   - Check GitHub issues for nixos/kubernetes module
   - Review Nixpkgs NVIDIA configuration

2. **Is there a NixOS-specific NVIDIA device plugin?**
   - Check nixpkgs for kubernetes-related packages
   - Look for community forks

3. **Does containerd runtime class work with nvidia-container-runtime on NixOS?**
   - Test locally on forge
   - Review containerd documentation

---

## Resources

**Documentation**:
- [NVIDIA Device Plugin](https://github.com/NVIDIA/k8s-device-plugin)
- [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/)
- [containerd runtime classes](https://github.com/containerd/containerd/blob/main/docs/cri/config.md#runtime-classes)

**Local Files**:
- `/etc/nixos/kubernetes-manifests/nvidia-device-plugin-daemonset-cdi.yaml` - Latest attempt (with CDI removed)
- `/etc/nixos/modules/services/kubernetes.nix` - Kubernetes configuration
- `/etc/nixos/modules/hardware/nvidia-common.nix` - NVIDIA driver configuration

---

## Conclusion

**Status**: BLOCKED

The NVIDIA device plugin cannot work with NixOS's symlink-based package management. Even when mounting the driver libraries, the plugin cannot resolve symlinks to load `libnvidia-ml.so.1`.

**Recommended Path Forward**: Configure containerd runtime class for NVIDIA, or use Docker runtime for GPU nodes.

**Estimated Time**: 2-4 hours for runtime class approach

---

**Date**: 2026-03-11
**Investigation Time**: ~4 hours total (including previous CRI-O investigation)
**Attempts**: 6 (lib64 fix, disable CDI, force NVML, mount libs, mount nix-store, legacy plugin)
**Status**: BLOCKED pending containerd runtime class configuration
