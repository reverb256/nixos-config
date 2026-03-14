# x86-64-v3 Microarchitecture Migration Design

**Status:** Design Approved | **Created:** 2026-03-13 | **Owner:** j_kro
**Target:** Migrate 4-node NixOS cluster from baseline x86-64 to x86-64-v3

## Executive Summary

Migrate the 4-node NixOS cluster (Zephyr, Nexus, Forge, Sentry) from baseline `x86_64-linux` to `x86-64-v3` microarchitecture level to enable SIMD performance improvements for AI, mining, and crypto workloads.

**Approach:** Single-node-first migration using Nexus as the build host, leveraging local Harmonia cache to distribute v3 packages to other nodes, with specialisations providing rollback safety.

**Timeline:** ~11-15 days (Nexus builds first, others fetch from cache)

---

## Objectives

### Primary Goals

1. **Performance**: Enable AVX2 and other SIMD instructions for 10-30% uplift in parallel workloads
2. **Learning**: Gain experience with microarchitecture-level NixOS migrations
3. **Workloads**: Direct benefit to GPU compute, mining, and crypto operations

### Success Criteria

- ✅ All 4 nodes boot into v3 successfully
- ✅ All systemd services run without errors
- ✅ 5 days stable operation per node
- ✅ Performance benchmarks show improvement (or neutral)
- ✅ Baseline specialisations removed

---

## CPU Compatibility Verification

All 4 nodes support x86-64-v3 requirements (ADX, AVX2, BMI1/2, F16C, FMA, MOVBE, XSAVE):

| Node | CPU | Cores | RAM | AVX2 | Status |
|------|-----|-------|-----|------|--------|
| Zephyr | Ryzen 9 5950X (Zen 3) | 32 | 31GB | ✅ | Compatible |
| Nexus | Ryzen 9 3900X (Zen 2) | 24 | 46GB | ✅ | Compatible |
| Forge | i5-9500 (Coffee Lake) | 6 | 15GB | ✅ | Compatible |
| Sentry | Ryzen 7 1700 (Zen 1) | 16 | 31GB | ✅ | Compatible |

**Key Finding:** Zen 1 (Ryzen 7 1700) DOES support AVX2, contrary to some documentation.

---

## Migration Architecture

### The "Nexus-First" Strategy

```
┌─────────────────────────────────────────────────────────────────┐
│                    PHASE 1: Nexus Builds Everything            │
├─────────────────────────────────────────────────────────────────┤
│  1. Configure Nexus with x86-64-v3                             │
│  2. Add baseline specialisation (fallback)                     │
│  3. Rebuild → Harmonia cache populates (~2000 packages)        │
│  4. Boot into v3, verify services, keep baseline for 5 days    │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                    PHASE 2: Other Nodes (Fast)                 │
├─────────────────────────────────────────────────────────────────┤
│  5. Zephyr, Forge, Sentry fetch from Harmonia (LAN speed)      │
│  6. Each node: add v3 config + baseline specialisation         │
│  7. Rebuild (mostly cache hits → ~30 min each)                 │
│  8. Boot v3, verify, 5-day stability period                    │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                    PHASE 3: Cleanup                            │
├─────────────────────────────────────────────────────────────────┤
│  9. Remove baseline specialisations from all nodes             │
│  10. Final verification, update documentation                  │
└─────────────────────────────────────────────────────────────────┘
```

### Why Nexus First?

| Factor | Rationale |
|--------|-----------|
| 24 cores + 46GB RAM | Excellent for parallel builds |
| Harmonia cache on Nexus | Zero network overhead for cache writes |
| 4.7TB storage | Ample space for v3 cache growth |
| Storage node role | Manageable downtime during build window |

---

## Configuration Changes

### 3.1 flake.nix - Add v3 variant

```nix
outputs = inputs @ {...}: let
  # Existing baseline
  system = "x86_64-linux";

  # NEW: x86-64-v3 variant
  systemV3 = "x86_64-linux";  # Same system, different gcc arch

  # v3-aware package set
  pkgsV3 = import nixpkgs {
    inherit systemV3;
    localSystem = {
      system = systemV3;
      gcc.arch = "x86-64-v3";  # The key change
    };
    config.allowUnfree = true;
  };

  # Helper to build v3 system
  mkNixosSystemV3 = {hostName, extraModules ? []}:
    nixpkgs.lib.nixosSystem {
      system = systemV3;
      specialArgs = {inherit inputs pkgsV3;};
      modules = commonModules ++ [
        ./hosts/${hostName}/configuration.nix
        {nixpkgs.hostPlatform.gcc.arch = "x86-64-v3";}
      ] ++ extraModules;
    };
```

### 3.2 colmena.nix - Update tunedNixpkgs

```nix
# Replace per-node microarch with v3
tunedNixpkgs = system:
  import inputs.nixpkgs {
    localSystem = {
      inherit system;
      gcc.arch = "x86-64-v3";  # Unified v3 for all nodes
    };
    config.allowUnfree = true;
  };
```

### 3.3 Specialisation Configuration (Per-Host)

Add to each host's `configuration.nix`:

```nix
specialisation = {
  baseline.configuration = {
    system.nixpkgs.hostPlatform.gcc.arch = lib.mkForce "x86-64";
  };
};
```

This creates a boot menu entry allowing rollback to baseline architecture.

---

## Migration Commands

### Pre-Migration Checklist

```bash
# 1. Verify Harmonia is running on Nexus
ssh j_kro@nexus "systemctl status harmonia"

# 2. Check available disk space (need ~50GB for v3 cache)
ssh j_kro@nexus "df -h /var/lib/harmonia"

# 3. Verify all CPUs support AVX2
for host in zephyr nexus forge sentry; do
  ssh $host "grep avx2 /proc/cpuinfo | wc -l"
done

# 4. Backup current configurations
git add -A && git commit -m "pre-x86-64-v3: baseline snapshot"
```

### Phase 1: Nexus Migration

```bash
# Build v3 on Nexus (4-8 hours)
ssh j_kro@nexus "cd /etc/nixos && just test"

# Review what will be built
ssh j_kro@nexus "nix path-info .#nixosConfigurations.nexus.config.system.build.toplevel"

# Apply (creates new boot entry)
ssh j_kro@nexus "sudo nixos-rebuild switch --flake .#nexus"

# Reboot into v3
ssh j_kro@nexus "sudo reboot"

# Verify v3 is active
ssh j_kro@nexus "uname -a"
```

### Phase 2: Other Nodes (Cache Hits)

```bash
# Zephyr, Forge, Sentry - same pattern, faster execution
for host in zephyr forge sentry; do
  ssh $host "sudo nixos-rebuild switch --flake .#$host && sudo reboot"
done
```

---

## Validation Plan

### Daily Validation Checklist (5 Days)

```bash
for host in nexus zephyr forge sentry; do
  echo "=== Checking $host ==="

  # 1. Can we SSH in?
  ssh $host "uptime"

  # 2. Are all systemd services running?
  ssh $host "systemctl --failed"

  # 3. Check for kernel errors
  ssh $host "dmesg | grep -i error | tail -20"

  # 4. Verify mining (if applicable)
  ssh $host "systemctl status xmrig 2>/dev/null || echo 'no xmrig'"
  ssh $host "systemctl status lolminer 2>/dev/null || echo 'no lolminer'"

  # 5. Check GPU/AI workloads
  ssh $host "nvidia-smi 2>/dev/null || echo 'no nvidia gpu'"
done
```

### Performance Comparison

```bash
# Benchmark on Day 1
echo "Day 1 baseline:"
ssh forge "xmrig --bench=1M"
ssh zephyr "openssl speed -evp aes-256-gcm"

# Compare on Day 5
echo "Day 5 comparison:"
ssh forge "xmrig --bench=1M"
ssh zephyr "openssl speed -evp aes-256-gcm"
```

---

## Cleanup (After 5 Days Stable)

```bash
# Remove baseline specialisation from each host
for host in nexus zephyr forge sentry; do
  ssh $host "cd /etc/nixos"
  # Edit config to remove specialisation.baseline
  # Rebuild and commit
  ssh $host "sudo nixos-rebuild switch --flake .#$host"
done

# Update documentation
git commit -am "x86-64-v3 migration: complete, baseline specialisations removed"
```

---

## Timeline

| Phase | Duration | Activity |
|-------|----------|----------|
| Nexus build | 4-8 hours | Initial v3 package builds |
| Nexus validation | 5 days | Stability period |
| Other nodes | ~1 hour each | Cache fetch from Harmonia |
| Staggered validation | 5 days each | Overlapping stability periods |
| Cleanup | ~30 minutes | Remove baseline specialisations |

**Total**: ~11-15 days (parallel validation shortens this)

---

## Risk Assessment

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| Build failure | Medium | Low | Fix config, rebuild (Harmonia caches successes) |
| Service breakage | Low-Medium | Low | Baseline specialisation for rollback |
| Performance regression | Low | Very Low | Benchmark first, revert if worse |
| Harmonia storage full | Low | Low | Monitor disk space during Nexus build |
| Kernel incompatibility | High | Very Low | All CPUs verified v3-compatible |

---

## References

- **NixOS x86-64 levels:** https://github.com/NixOS/nixpkgs/issues/262847
- **GCC x86-64 options:** https://gcc.gnu.org/onlinedocs/gcc/x86-Options.html
- **CPU flags reference:** https://en.wikipedia.org/wiki/CPUID
- **SIMD explained:** https://en.wikipedia.org/wiki/SIMD

---

**Next Steps:** Invoke writing-plans skill to create detailed implementation plan.

**Version:** 1.0 | **Last Updated:** 2026-03-13
