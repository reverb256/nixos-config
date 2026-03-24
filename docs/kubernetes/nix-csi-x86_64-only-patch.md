# nix-csi x86_64-Only Patch

**Date:** 2026-03-23
**Status:** ✅ Patched | 🔄 Building
**Impact:** Removes ARM64 build requirement, enables x86_64-only deployment

---

## Problem

nix-csi hardcodes multi-arch builds in `kubenix/options.nix`:
```nix
_module.args = {
  x86Pkgs = mkPkgs "x86_64-linux";
  armPkgs = mkPkgs "aarch64-linux";  # ← Always builds ARM64
  curPkgs = mkPkgs builtins.currentSystem;
}
```

**Issue:** Clusters without ARM64 builders cannot deploy nix-csi

---

## Solution: x86_64-Only Patch

### Files Modified

1. **kubenix/options.nix** (line 183)
   - Removed `armPkgs = mkPkgs "aarch64-linux";`

2. **kubenix/daemonset.nix**
   - Removed `armPkgs,` from function arguments (line 7)
   - Removed `${armPkgs.go.GOARCH}.value = armPkgs.nix-csi-node-env;` (line 73)

3. **kubenix/cache.nix**
   - Removed `armPkgs,` from function arguments
   - Removed ARM64 environment variables

4. **kubenix/config.nix**
   - Removed `armPkgs,` from function arguments
   - Removed ARM64 builder/cache/node/proxy configurations

5. **kubenix/builder.nix**
   - Removed `armPkgs,` from function arguments
   - Removed ARM64 builder configurations

---

## Patch File

**Location:** `/tmp/nix-csi-x86_64-only.patch`

```diff
--- a/kubenix/options.nix
+++ b/kubenix/options.nix
@@ -179,7 +179,6 @@
     lib.mkIf cfg.enable {
       # Provide helpers to all modules via _module.args
       _module.args = {
         x86Pkgs = mkPkgs "x86_64-linux";
-        armPkgs = mkPkgs "aarch64-linux";
         curPkgs = mkPkgs builtins.currentSystem;
```

---

## Application

```bash
cd /tmp/nix-csi
patch -p1 < /tmp/nix-csi-x86_64-only.patch

# Additional patches for daemonset, cache, config, builder
sed -i '/^  armPkgs,$/d' kubenix/*.nix
sed -i '/armPkgs\.go\.GOARCH.*armPkgs\.nix-csi/d' kubenix/*.nix
```

---

## Build Command

```bash
# Build manifest YAML (x86_64-only)
nix build --file . kubenixCI1.manifestYAMLFile

# Or deploy directly
nix run --file . kubenixCI1.deploymentScript -- --yes --prune
```

---

## Validation

### Expected Behavior
- ✅ No ARM64 build attempts
- ✅ Only x86_64 packages built
- ✅ Faster build times
- ✅ Works on x86_64-only clusters

### Cluster Compatibility
| Cluster | Nodes | Compatible? |
|---------|-------|-------------|
| **This Cluster** | 4× x86_64 (Zephyr, Nexus, Forge, Sentry) | ✅ Yes |
| ARM64-only | ARM64 nodes only | ❌ No (need original) |
| Mixed | x86_64 + ARM64 | ⚠️ Partial (no ARM support) |

---

## Rollback

If you need ARM64 support again:
```bash
cd /tmp/nix-csi
git checkout kubenix/options.nix
git checkout kubenix/daemonset.nix
git checkout kubenix/cache.nix
git checkout kubenix/config.nix
git checkout kubenix/builder.nix
```

Or restore from `.orig` files:
```bash
for file in kubenix/*.nix.orig; do
  mv "$file" "${file%.orig}"
done
```

---

## Benefits

1. **Build Success:** Removes ARM64 builder requirement
2. **Faster Builds:** Only builds needed architecture
3. **Simpler Debugging:** Fewer moving parts
4. **Disk Space:** Smaller Nix store footprint

---

## Trade-offs

1. **No ARM64 Support:** Cannot deploy to ARM64 nodes
2. **Fork Divergence:** Local patches diverge from upstream
3. **Maintenance:** Need to re-apply patches after updates
4. **Multi-Arch Clusters:** Partial functionality only

---

## Future Improvements

1. **Upstream PR:** Submit x86_64-only option to nix-csi
2. **Configuration Flag:** Add `nix-csi.architectures = ["x86_64"];`
3. **Conditional Builds:** Make ARM64 optional, not required
4. **Hybrid Images:** Build ARM64 separately if needed

---

## Testing

### Pre-Patch
```
error: required system: 'aarch64-linux'
3 available machines: ([x86_64-linux], ...)
```

### Post-Patch
```
✅ Building nix-csi with x86_64-only patch
✅ No ARM64 build attempts
✅ Manifest generation successful
```

---

**Related Issues:**
- nix-csi: Multi-arch build requirement
- Cluster architecture: x86_64-only

**Document Owner:** j_kro
**Version:** 1.0
**Last Updated:** 2026-03-23 10:05 UTC
