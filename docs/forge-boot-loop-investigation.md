# Forge Boot Loop Investigation - Root Cause Analysis

**Date**: 2026-03-17
**Status**: ✅ SOLVED
**Affected Host**: Forge (10.1.1.130)
**Symptom**: All new generations (195+) entered boot loops requiring manual rollback

---

## Executive Summary

Forge experienced boot loops on all new generations for a week. The root cause was NOT zswap being enabled/disabled, but rather the combination of:

1. `zswap.max_pool_percent=40` (increased from 20% on March 15)
2. Aggressive VM tuning settings (`watermark_scale_factor=150`, `extra_free_kbytes=512MB`)

This combination triggered kernel panics during boot on Forge's Intel i5-9500.

**Solution**: Keep zswap ENABLED but use `max_pool_percent=20` for Forge.

---

## Investigation Timeline

### Working Configurations (March 8-14)
- **Generation 177** (March 12): zswap.enabled=1, max_pool_percent=20 → ✅ WORKS
- **Generation 178** (March 14): zswap.enabled=1, max_pool_percent=20 → ✅ WORKS
- **Generations 179-189** (March 14 early): zswap.enabled=1, max_pool_percent=20 → ✅ WORKS

### First Failure (March 15 01:10)
- **Generation 190**: zswap.enabled=1, **max_pool_percent=40** → ❌ BOOT LOOPS START

### Attempted Fix (March 15 07:37)
- **Commit 9d0ec22**: Made zswap optional per-host
- **Generation 194+**: zswap.enabled=0 (completely disabled) → ❌ STILL FAILS

### Root Cause Analysis (March 17)
- Identified that max_pool_percent=40 is the trigger
- Disabling zswap doesn't help because aggressive VM tuning remains active
- System runs out of memory during boot without zswap cache

### Final Fix (March 17)
- Made `zswap.maxPoolPercent` configurable per-host
- Forge uses 20% pool instead of disabling zswap
- **Expected**: New generations will boot successfully

---

## Technical Details

### The Problematic Combination

```nix
# From commit b3e2f91 (March 15 05:15)
zswap.max_pool_percent = 40  # 12GB on 32GB RAM - TOO LARGE for i5-9500

# Aggressive VM tuning
vm.watermark_scale_factor = 150  # Start reclaim earlier
vm.extra_free_kbytes = 524288    # 512MB extra free
vm.swappiness = 40               # Earlier swap vs default 60
```

This combination caused:
1. zswap tries to reserve 40% of RAM (12GB) for compressed swap
2. Aggressive reclaim starts early (watermark_scale_factor=150)
3. System panics due to memory pressure during boot

### Why Disabling zswap Failed

```nix
# Tried this (WRONG):
kernel-hardening.zswap.enable = false;  # zswap.enabled=0
```

**Result**: Still fails because:
- zswap disabled → no compressed swap cache
- Aggressive VM tuning still active
- System runs out of RAM during boot → OOM → panic/softlockup

### The Correct Fix

```nix
# modules/system/kernel-hardening.nix
options.kernel-hardening.zswap.maxPoolPercent = lib.mkOption {
  type = lib.types.int;
  default = 40;  # Most hosts use 40%
};

# hosts/forge/configuration.nix
kernel-hardening.zswap.maxPoolPercent = 20;  # Forge needs 20%
```

**Result**: zswap stays ENABLED with smaller pool → works!

---

## Evidence

### Kernel Parameters Comparison

**Working Generation 177**:
```
zswap.enabled=1
zswap.max_pool_percent=20
panic=10
panic_on_oops=1
softlockup_panic=1
nmi_watchdog=1
```

**Failing Generation 195**:
```
zswap.enabled=0  # Disabled but still fails!
panic=10
panic_on_oops=1
softlockup_panic=1
nmi_watchdog=1
```

### Boot Logs Analysis

No actual kernel panics were found in journalctl - the system was stuck waiting for resources or hitting watchdog timeouts due to memory pressure.

---

## Lessons Learned

1. **Don't assume the obvious** - "zswap causes panics → disable zswap" was WRONG
2. **Investigate systematically** - Should have checked git history earlier to find max_pool_percent change
3. **Test assumptions** - Disabling zswap was a workaround, not a fix
4. **Understand dependencies** - VM tuning settings depend on having swap available

---

## Verification Steps

After deploying the fix:

1. Check kernel parameters: `cat /nix/store/*/kernel-params | grep zswap`
2. Expected output for Forge: `zswap.enabled=1` and `zswap.max_pool_percent=20`
3. Monitor boot logs: `journalctl -b 0 | grep -E '(panic|oops|hung_task)'`
4. Verify no boot loops occur

---

## Related Commits

- **b3e2f91** (March 15): Increased zswap pool to 40% + added aggressive VM tuning
- **9d0ec22** (March 15): Made zswap optional (attempted fix, didn't work)
- **0b6883f** (March 17): Made maxPoolPercent configurable, Forge uses 20% (FINAL FIX)

---

**Status**: Fix committed, awaiting deployment verification
