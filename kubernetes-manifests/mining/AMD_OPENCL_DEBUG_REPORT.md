# AMD OpenCL in k3s Containers - Debug Report

**Date**: 2026-04-06 | **Host**: forge | **Resolved**: YES ✅

## Executive Summary

OpenCL cannot detect AMD GPUs inside k3s pods due to **3 compounding issues**.
With all three fixed, all 4 GPUs (2x AMD 5700 XT + 2x NVIDIA 4060) are detected.

## The 3 Root Causes

### Issue 1: Missing OpenCL ICD File ❌ → ✅ FIXED
**Symptom**: libOpenCL.so has no idea where to find the AMD OpenCL driver.

The container had no `/etc/OpenCL/vendors/` directory. The AMD ICD file lives at:
```
/nix/store/6yvx83sa6iwhr6xnjjlfjg56jnki5mdn-clr-7.2.0-icd/etc/OpenCL/vendors/amdocl64.icd
```
Contents: `/nix/store/c7vv6nwwa8x2w1clrp05k4595wx6ix0l-clr-7.2.0/lib/libamdocl64.so`

**IMPORTANT**: Do NOT mount the host's `/etc/OpenCL/vendors/` — it contains a **dangling symlink**:
```
amdocl64.icd → /etc/static/OpenCL/vendors/amdocl64.icd
                  ^^^^^^^^^^ NixOS-specific, doesn't exist in containers
```

**Fix**: Mount the ICD directory directly from the nix store path:
```yaml
volumes:
  - name: opencl-icd
    hostPath:
      path: /nix/store/6yvx83sa6iwhr6xnjjlfjg56jnki5mdn-clr-7.2.0-icd/etc/OpenCL/vendors
      type: Directory
volumeMounts:
  - name: opencl-icd
    mountPath: /etc/OpenCL/vendors
    readOnly: true
```


scans the directory via `getdents64`, but concatenates the path + filename
**without a `/` separator**:

```
getdents64(... "amdocl64.icd") = OK
openat("/etc/OpenCL/vendorsamdocl64.icd") = ENOENT  ← BUG: missing "/"
```

**Fix**: Set `OCL_ICD_VENDORS` with a **trailing slash**:
```yaml
env:
  - name: OCL_ICD_VENDORS
    value: "/etc/OpenCL/vendors/"   # TRAILING SLASH IS CRITICAL
```

### Issue 3: GLIBC Version Too Old ❌ → ✅ FIXED
**Symptom**: ICD loads but `libamdocl64.so` fails with:
```
version `GLIBC_2.38' not found (required by libamdocl64.so)
```

The NixOS-built `libamdocl64.so` (from CLR 7.2.0) requires **GLIBC_2.38+**.
| Container Image | glibc | OpenCL Works? |
|----------------|-------|---------------|
| ubuntu:22.04 | 2.35 | ❌ GLIBC_2.38 not found |
| **ubuntu:24.04** | **2.39** | **✅ ALL GPUs DETECTED** |

**Fix**: Use a container image with glibc ≥ 2.38. Options:
1. **ubuntu:24.04** (glibc 2.39) — simplest, verified working
3. **Fedora 40+** — also has glibc ≥ 2.38

## What's Also Required

### /dev/kfd Mount
The AMD Kernel Fusion Driver device must be accessible:
```yaml
volumes:
  - name: kfd
    hostPath:
      path: /dev/kfd
volumeMounts:
  - name: kfd
    mountPath: /dev/kfd
```

### Privileged Security Context
Required for device access:
```yaml
securityContext:
  privileged: true
```

## The Complete Dependency Chain

```
  └─ dlopen("libOpenCL.so.1")           ← via LD_LIBRARY_PATH=/run/opengl-driver/lib
     └─ reads /etc/OpenCL/vendors/*.icd  ← via OCL_ICD_VENDORS (needs trailing /)
        └─ amdocl64.icd → libamdocl64.so
           ├─ libhsa-runtime64.so.1      ← via RUNPATH → /nix/store/...rocm-runtime-7.2.0/lib
           ├─ libamd_comgr.so.3           ← via RUNPATH → /nix/store/...rocm-comgr-22.0.0/lib
           ├─ libc.so.6 (GLIBC_2.38+)    ← via RUNPATH → /nix/store/...glibc-2.42-51/lib
           └─ communicates via /dev/kfd   ← AMD kernel fusion driver
```

## Verified Working Pod Spec

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: debug-opencl-verified
  namespace: mining
spec:
  nodeName: forge
  containers:
  - name: debug
    image: ubuntu:24.04
    command: ["/bin/sleep", "3600"]
    env:
    - name: LD_LIBRARY_PATH
      value: "/run/opengl-driver/lib"
    - name: OCL_ICD_VENDORS
      value: "/etc/OpenCL/vendors/"    # TRAILING SLASH!
    volumeMounts:
    - name: dri
      mountPath: /dev/dri
    - name: kfd
      mountPath: /dev/kfd
    - name: opengl
      mountPath: /run/opengl-driver/lib
      readOnly: true
    - name: nix-store
      mountPath: /nix/store
      readOnly: true
    - name: opencl-icd
      mountPath: /etc/OpenCL/vendors
      readOnly: true
    securityContext:
      privileged: true
  volumes:
  - name: dri
    hostPath:
      path: /dev/dri
  - name: kfd
    hostPath:
      path: /dev/kfd
  - name: opengl
    hostPath:
      path: /run/opengl-driver/lib
  - name: nix-store
    hostPath:
      path: /nix/store
  - name: opencl-icd
    hostPath:
      path: /nix/store/6yvx83sa6iwhr6xnjjlfjg56jnki5mdn-clr-7.2.0-icd/etc/OpenCL/vendors
      type: Directory
  restartPolicy: Never
```

## Test Results

```bash
# Inside the verified pod:

# OUTPUT:
# OpenCL driver detected. Number of OpenCL supported GPUs: 2
# Cuda driver detected. Number of Cuda supported GPUs: 2
# Device 0: AMD Radeon RX 5700 XT (OpenCL, 8176 MB)
# Device 1: AMD Radeon RX 5700 XT (OpenCL, 8176 MB)
# Device 2: NVIDIA GeForce RTX 4060 (Cuda, 7807 MB)
# Device 3: NVIDIA GeForce RTX 4060 (Cuda, 7807 MB)
```

## ⚠️ Deployment Note: Forge Memory Constraint

Forge has only 15Gi RAM. The existing NVIDIA mining pods already consume ~8Gi.
Deploying AMD pods alongside requires conservative memory settings:

```yaml
resources:
  requests:
    cpu: "500m"
  limits:
    memory: "2Gi"
    cpu: "2"
```

If deploying both AMD and NVIDIA pods simultaneously causes OOM, consider:
1. Reducing NVIDIA pod memory limits
2. Using a lighter container image (alpine won't work — needs glibc 2.38+)
3. Running AMD miners as systemd services on the host instead of in k3s

## Nix Store Paths Reference

| Component | Nix Store Path |
|-----------|---------------|
| AMD CLR (OpenCL driver) | `/nix/store/c7vv6nwwa8x2w1clrp05k4595wx6ix0l-clr-7.2.0` |
| OpenCL ICD file | `/nix/store/6yvx83sa6iwhr6xnjjlfjg56jnki5mdn-clr-7.2.0-icd` |
| ROCm Runtime (HSA) | `/nix/store/bcpsxd7saqx2141gj7z92a810vbv0pwh-rocm-runtime-7.2.0` |
| ROCm Comgr | `/nix/store/igyf5nccby5b385gql65p3qwjvpxcr30-rocm-comgr-22.0.0-rocm` |
| NixOS glibc 2.42 | `/nix/store/jms7zxzm7w1whczwny5m3gkgdjghmi2r-glibc-2.42-51` |
| NVIDIA OpenCL ICD | `/nix/store/ia20kw8xkfssyfjmk2kanm5nhxablfyz-nvidia-x11-595.45.04-6.18.13/etc/OpenCL/vendors/nvidia.icd` |
