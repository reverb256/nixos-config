
**Date:** 2026-03-22
**Status:** Documented, Workaround Applied
**Impact:** CPU miner on sentry node (16 cores) not running in Kubernetes

## Problem


### Symptoms

```
```

- `ctr image ls` shows the image exists in containerd
- `crictl images` does NOT show the image
- kubelet cannot see the image via the CRI plugin

### Root Cause

Containerd uses **namespaces** to isolate images:
- **Default namespace**: Used by `ctr` command
- **k8s.io namespace**: Used by CRI plugin (kubelet/crictl)

When images are loaded with `ctr image import`, they go into the default namespace but are NOT visible to the CRI plugin.

Additionally, CRI-managed images have the label `io.cri-containerd.image=managed` which is missing from manually imported images.

## Investigation Steps Taken

1. ✅ Verified image exists with `ctr image ls`
2. ✅ Confirmed image missing from `crictl images`
3. ✅ Restarted kubelet (no effect)
4. ✅ Restarted containerd (no effect)
5. ✅ Retagged image with `ctr image tag`
6. ✅ Checked k8s.io namespace with `ctr -n k8s.io image ls`
7. ✅ Compared configs with working nodes (identical)
8. ✅ Checked containerd content blobs (image exists)

## Comparison: Working vs Broken Nodes

|------|----------------|-----------------|---------------|

## Workaround Applied

```bash
```

**Current Mining Capacity:**
- Zephyr: 32 cores @ ~4.3 kH/s ✅
- Nexus: 24 cores @ ~4.3 kH/s ✅
- Sentry: 16 cores (disabled) ⚠️
- **Total: 56 cores @ ~8.6 kH/s**

## Possible Solutions

### Option 1: Use CRI-Compatible Import (Recommended)
Need to import images using CRI plugin APIs instead of plain `ctr`:
```bash
# This doesn't work - crictl has no load command in this version

# Alternative: Use containerd CRI plugin
# (requires investigation of proper CRI import method)
```

```nix
# hosts/sentry/configuration.nix
  enable = true;
  settings = {
    url = "10.1.1.110:3333";
    user = "sentry-cpu";
    threads = 2;
  };
};
```

### Option 3: Fix Containerd Configuration
Ensure all images loaded with `ctr` are automatically tagged for CRI visibility. May require containerd config changes or using `ctr -n k8s.io image import`.

### Option 4: Investigate Blob Storage Issues
Sentry shows blob errors in containerd logs:
```
blob not found: not found
```
May need to:
1. Check `/var/lib/containerd/io.containerd.content.v1.content/blobs/`
2. Verify no storage corruption
3. Possibly rebuild containerd metadata

## Next Steps

2. **Medium-term**: Research proper CRI image import method (Option 1)
3. **Long-term**: Standardize container image distribution across cluster

## Files Referenced

- Image digest: `sha256:604c7949c15977a813ead3b732308679f71e8af59b55751bbe7daa47965ab229`

## Related Issues

- Similar to: https://github.com/containerd/containerd/issues/4273
- CRI plugin documentation: https://github.com/containerd/containerd/tree/main/pkg/cri
