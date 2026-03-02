# Infra Branch Workflow

## Branch Purpose

**`infra`** - Stable infrastructure baseline containing ONLY confirmed working commits.

This branch serves as your "known good" state. When master breaks, you can always fall back to infra.

## Workflow

### 1. Development happens on `master`
```bash
git checkout master
# Make changes, test, commit
```

### 2. Test thoroughly before merging to infra
Before merging to `infra`:
- ✅ Plasma 6 Wayland starts successfully
- ✅ Multi-GPU setup working (RTX 3060 Ti + RTX 3090)
- ✅ Vesktop runs without crashes
- ✅ Steam and gaming work
- ✅ No systemd failures or crashes
- ✅ Run for at least one session to verify stability

### 3. Merge to infra when confirmed working
```bash
git checkout infra
git merge master
git push origin infra  # If you have a remote
git checkout master
```

### 4. If master breaks
```bash
# Compare what changed
git diff infra..master

# Reset to last known good state
git reset --hard infra

# Or create a fix branch from infra
git checkout infra -b fix-issue
```

## Current State (infra branch)

✅ **Confirmed Working:**
- Plasma 6 Wayland on multi-NVIDIA GPUs
- Vesktop with nixcord plugins
- Steam with 32-bit game support
- Dual-GPU mining configuration
- Monitoring stack (Prometheus, Grafana)
- LM Studio and Stability Matrix

## Key Commits in infra

1. `f898d40` - Fix vesktop EROFS crash
2. `7871e55` - Remove nvidia-wayland module
3. `81b7a31` - Disable nvidia-wayland module (KWin EGL fix)
4. `ad9de9b` - Remove enable32Bit (multi-GPU Wayland fix)
5. `0bb1287` - Remove __NV_PRIME_RENDER_OFFLOAD
6. `18bccb3` - Restore to last working Plasma config

## Protection

Consider making `infra` a protected branch:
- Require PR reviews before merging
- Add status checks (CI/CD)
- Prevent force pushes

This ensures infra always stays stable.
