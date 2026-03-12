# CRITICAL: SSH Broken on Nexus and Sentry
**Date:** 2026-03-12 00:25
**Severity:** CRITICAL - Nodes unreachable via SSH
**Status:** Root cause identified

---

## Problem Summary

**Symptom:** SSH closes immediately after authentication on nexus and sentry

**Root Cause:** Nodes are running UNSTABLE NixOS build (`26.05pre-git`) with broken SSH daemon

**Affected Nodes:**
- ✅ **Nexus (10.1.1.120)** - SSH BROKEN - Build: `26.05pre-git`
- ✅ **Sentry (10.1.1.140)** - SSH BROKEN - Build: `26.05pre-git`
- ✅ **Zephyr (10.1.1.110)** - Working - Build: `26.05.20260308.9dcb002`
- ✅ **Forge (10.1.1.130)** - Working - Build: `26.05.20260308.9dcb002`

---

## Immediate Fix Required

**On Nexus (10.1.1.120) - Physical Console Access:**

```bash
# 1. List available generations
sudo nixos-rebuild --list-generations

# 2. Identify a STABLE generation (look for 26.05.20260308.9dcb002)
# 3. Rollback to stable generation
sudo nixos-rebuild switch --profile /nix/var/nix/profiles/system --rollback

# OR manually switch to specific generation:
# sudo nix-env -p /nix/var/nix/profiles/system --switch-generation <NUMBER>

# 4. Reboot into stable generation
sudo reboot

# 5. After reboot, verify:
#    - SSH works from zephyr/forge
#    - nixos-version shows stable build
```

**On Sentry (10.1.1.140) - Physical Console Access:**

Same procedure as nexus above.

---

## How This Happened

The cluster-networking module was added and nodes were rebuilt, but:
1. Nexus and sentry rebuilt to an **unstable pre-git** build
2. Zephyr and forge remained on **stable** builds
3. The unstable build has SSH compatibility issues

**Likely cause:** Recent networking changes triggered a rebuild that pulled in unstable dependencies.

---

## Prevention After Fix

### 1. Disable Auto-Update on Affected Nodes

Check if `nixos-auto-update` is enabled:

```nix
# In hosts/nexus/configuration.nix and hosts/sentry/configuration.nix:
services.nixos-auto-update.enable = false;
```

### 2. Pin to Stable Channel

Ensure nodes are pinned to stable NixOS channel:

```bash
# On each node:
sudo nix-channel --add nixos https://nixos.org/channels/nixos-26.05
sudo nix-channel --update
```

### 3. Verify Build Consistency

After fix, verify all nodes have same build:

```bash
for node in zephyr nexus forge sentry; do
  echo "=== $node ==="
  ssh $node "nixos-version"
done
```

Should all show: `26.05.20260308.9dcb002 (Yarara)`

---

## Network Status Summary

| Node | IP | SSH | Network | NixOS Build | Action Needed |
|------|-----|-----|---------|-------------|---------------|
| Zephyr | 10.1.1.110 | ✅ WORKING | UP | Stable | None |
| Nexus | 10.1.1.120 | ❌ BROKEN | UP | **UNSTABLE** | **ROLLBACK NOW** |
| Forge | 10.1.1.130 | ✅ WORKING | UP | Stable | None |
| Sentry | 10.1.1.140 | ❌ BROKEN | UP | **UNSTABLE** | **ROLLBACK NOW** |

**Note:** All nodes have network connectivity (pings work, node exporter works). Only SSH is broken on unstable builds.

---

## Alternative: Fix Unstable Build (NOT RECOMMENDED NOW)

Instead of rollback, could try to fix SSH on unstable build, but:
- Risk of other issues
- Takes time to debug
- Rolling back is safer and faster

**Recommendation:** Rollback first, fix SSH issue later if needed.

---

**NEXT STEPS:**
1. User needs physical access to nexus and sentry consoles
2. Roll back both nodes to stable generation
3. Verify SSH works after rollback
4. Investigate why they rebuilt to unstable version
5. Ensure they don't auto-rebuild to unstable again
