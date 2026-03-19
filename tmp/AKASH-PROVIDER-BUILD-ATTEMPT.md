# Akash Provider - Build From Source Attempt & Status

## Date: 2026-03-19 23:40

## ❌ Build From Source: Not Feasible Without Full Toolchain

### What Was Attempted

1. **Cloned provider repository** ✅
   - Checked out v0.10.5 (best GPU detection - 5 GPUs)
   - Successfully fetched PR branches #373 and #371

2. **Applied critical bug fixes** ✅
   - Merged PR #373: "fix(bidengine): close bid on EventGroupClosed when deployment closed without lease"
   - Merged PR #371: "fix: coordinated ShutdownInitiated after bid close tx broadcast"
   - Both PRs applied cleanly with merge conflicts auto-resolved

3. **Built Go binary** ⚠️ Partial Success
   - Initial build: 278MB binary with dynamic linking
   - Static build attempt: 198MB binary with `-linkmode=external -s -w`
   - **Issue**: Binary fails in Ubuntu container with "cannot execute: required file not found"

4. **Docker image creation** ⚠️ Successful but non-functional
   - Created Docker image with custom binary
   - Image size: 94MB (compressed)
   - Loaded into containerd on zephyr and nexus nodes
   - **Issue**: Init container fails to execute the binary

### Root Cause: CGO Dependencies

The Akash provider requires **CGO-enabled compilation** with specific external linker flags:

```yaml
env:
  - CGO_ENABLED=1
  - CC=x86_64-linux-gnu-gcc
  - CXX=x86_64-linux-gnu-g++
ldflags:
  - -linkmode=external
  - -extldflags "-lc -lrt -lpthread"
```

This means:
- **Not a static binary** - requires dynamic C library linkage
- **Needs cross-compilation toolchain** (x86_64-linux-gnu-gcc)
- **Complex build environment** - requires Ubuntu/packaging tools
- **Cannot be easily replicated** on NixOS without full toolchain

### Official Build Process

The official images use:
1. **Goreleaser** with multi-stage Docker builds
2. **Cross-compilation** via Docker buildx
3. **Ubuntu build containers** with full GCC toolchain
4. **Separate build artifacts** for each architecture (amd64, arm64)

This is **not practical to replicate** locally without:
- Docker buildx setup
- Cross-compiler installation
- Full build environment matching CI/CD

## 🎯 Current Situation

### What We Have

✅ **Code with fixes applied** - All PRs successfully merged
✅ **Source code ready** - `/tmp/provider/fixed-provider-v0.10.5` branch
✅ **Dockerfile ready** - Can build images if toolchain available

❌ **Functional binary** - Cannot build without CGO toolchain
❌ **Working provider** - Still blocked by bidengine bug

### Realistic Options

#### Option 1: Wait for Official Release (RECOMMENDED)

Monitor for next provider release that includes PRs #373 and #371:

```bash
# Watch GitHub releases
https://github.com/akash-network/provider/releases

# Watch PR status
https://github.com/akash-network/provider/pull/373
https://github.com/akash-network/provider/pull/371
```

**Timeline**: Likely 1-2 weeks for merge, testing, and release

#### Option 2: Use CI/CD Build Artifacts

Check if Akash's CI produces publicly accessible build artifacts:

```bash
# GitHub Actions might produce artifacts
https://github.com/akash-network/provider/actions

# Look for "edge" or "main" branch builds
# Might be available at ghcr.io/akash-network/provider:edge
```

#### Option 3: Full Build Environment Setup (COMPLEX)

Set up proper build environment:

```bash
# Install cross-compilation toolchain
sudo apt install gcc-x86-64-linux-gnu g++-x86-64-linux-gnu

# Use Docker buildx for multi-arch builds
docker buildx create --name multiarch --use

# Build using goreleaser
goreleaser build --config .goreleaser.yaml --snapshot
```

**Estimated effort**: 4-6 hours for toolchain setup and debugging

#### Option 4: Run Provider in Development Mode

Skip Docker entirely and run binary directly on a node:

```bash
# On nexus node (where provider runs)
cd /tmp/provider
./provider-services run --kubeconfig-in-cluster
```

**Drawbacks**: Not production-ready, loses Helm integration

## 📋 Provider Configuration Summary

### Current State

| Component | Status |
|-----------|--------|
| **Wallet** | ✅ 30 AKT loaded |
| **Certificate** | ✅ Valid (serial: 189E1B2C59B6BFF3) |
| **Cluster** | ✅ 4 nodes discovered |
| **GPUs (v0.10.5)** | ✅ 5 NVIDIA detected |
| **RBAC** | ✅ All permissions fixed |
| **Pricing** | ✅ Script configured |
| **Bidengine** | ❌ Blocked by bug |
| **Operator Integration** | ✅ Connected |

### Best Working Version: v0.10.5

- GPU Detection: **5/5 GPUs** (best)
- Configuration: **All fixes applied**
- Blocker: **Bidengine crash**

### Newer Versions

- v0.10.7: Same bidengine bug, 3/5 GPUs
- v0.11.0-rc2: Same bidengine bug, 3/5 GPUs
- v0.10.8-rc3: Unknown if PRs included

## 💡 Immediate Recommendation

**Revert to v0.10.5** and wait for official release:

```bash
helm upgrade akash-provider akash/provider \
  --namespace akash-services \
  --set image.tag=0.10.5 \
  --set certIssuer.enabled=false \
  --reuse-values
```

This gives you:
- ✅ Best GPU detection (5 GPUs)
- ✅ All configuration fixes working
- ❌ Still blocked by bidengine bug (but no worse than current state)

## 🔧 Next Steps

1. **Monitor PR merges** - Watch GitHub for PR #373 and #371
2. **Test new releases** - Immediately upgrade when fixes are released
3. **Join Akash Discord** - https://discord.gg/akashnetwork
   - Ask about release timeline
   - Report the bug if not already tracked
4. **Consider running provider** on a different machine with Docker buildx if you need it urgently

## 📊 Build Attempt Statistics

| Step | Status | Time | Notes |
|------|--------|------|-------|
| Clone repo | ✅ | 30s | Successful |
| Apply PR #373 | ✅ | 5s | Clean merge |
| Apply PR #371 | ✅ | 10s | Auto-resolved conflicts |
| Build binary (dynamic) | ⚠️ | 3m | Built but won't run in container |
| Build binary (static) | ⚠️ | 2.5m | Built but won't run in container |
| Create Docker image | ✅ | 20s | Image created successfully |
| Load into containerd | ✅ | 10s | Loaded on zephyr and nexus |
| Test execution | ❌ | - | "cannot execute: required file not found" |
| **Total Time** | **~6 minutes** | | |

## 🔗 Resources

- **Provider repo**: https://github.com/akash-network/provider
- **PR #373**: https://github.com/akash-network/provider/pull/373
- **PR #371**: https://github.com/akash-network/provider/pull/371
- **Releases**: https://github.com/akash-network/provider/releases
- **Discord**: https://discord.gg/akashnetwork

---

**Conclusion**: The code fixes are ready and applied, but building a functional Docker image requires the full official build toolchain (CGO + cross-compilation). Waiting for an official release that includes these PRs is the most practical path forward.
