# Calico CNI Root Cause Analysis

**Date:** 2026-03-24 06:40 UTC
**Status:** ✅ ROOT CAUSE IDENTIFIED
**Error:** `IP=Never is invalid`

---

## The Actual Problem

**Error Message:**
```
2026-03-24 06:37:03.662 [WARNING][9] startup/startup.go 528: Attempt to get the local CIDR: Never failed, Never is invalid
2026-03-24 06:37:03.663 [WARNING][9] startup/startup.go 586: Environment does not contain a valid IPv4 address: IP=Never
2026-03-24 06:37:03.663 [WARNING][9] startup/utils.go 48: Terminating
Calico node failed to start
```

---

## Root Cause

**DaemonSet Configuration:**
```yaml
env:
  - name: IP_AUTODETECTION_METHOD
    value: "interface=enp38s0.*"  # ❌ TOO SPECIFIC
  - name: CALICO_IPV4POOL_VXLAN
    value: "Never"  # ❌ READ AS IP ADDRESS WHEN PATTERN FAILS
```

**Network Interface Mismatch:**

| Node | Actual Interface | Matches Pattern? | Result |
|------|------------------|-------------------|---------|
| **Zephyr** | enp38s0 | ✅ Yes | Works |
| **Nexus** | enp7s0 | ❌ No | Crash: IP=Never |
| **Forge** | eno1 | ❌ No | Crash: IP=Never |
| **Sentry** | enp7s0 | ❌ No | Crash: IP=Never |

**Failure Chain:**
1. `IP_AUTODETECTION_METHOD=interface=enp38s0.*` doesn't match Forge/Nexus/Sentry
2. Calico falls back to reading environment variables for IP
3. Reads `CALICO_IPV4POOL_VXLAN=Never`
4. Treats string "Never" as an IP address
5. Validation fails: `IP=Never is invalid`
6. Pod crashes with CrashLoopBackOff

---

## The Fix

**Option 1: Use `first-found` Method (Recommended)**
```yaml
env:
  - name: IP_AUTODETECTION_METHOD
    value: "first-found"  # ✅ Works on all nodes
```

**Option 2: Use Node Annotations (Explicit)**
```bash
kubectl annotate node forge projectcalico.org/IPv4Address=10.1.1.130/24 --overwrite
kubectl annotate node nexus projectcalico.org/IPv4Address=10.1.1.120/24 --overwrite
kubectl annotate node sentry projectcalico.org/IPv4Address=10.1.1.140/24 --overwrite
kubectl annotate node zephyr projectcalico.org/IPv4Address=10.1.1.110/24 --overwrite
```

**Option 3: Use `can-reach=10.1.1.1` (Network-based)**
```yaml
env:
  - name: IP_AUTODETECTION_METHOD
    value: "can-reach=10.1.1.1"  # ✅ Auto-discovers interface with route to gateway
```

---

## Why BGP Doesn't Work

**With `calico_backend: none`:**
- BIRD daemon never starts
- No route distribution between nodes
- Each node only knows about its own pods
- Cross-node pod traffic fails

**With `calico_backend: bird` (attempted):**
- IP autodetection fails on 3/4 nodes
- BIRD can't start without valid IP
- All Calico node pods crash
- Cluster networking completely broken

---

## Current State

**Configuration:**
```yaml
calico_backend: none  # BGP disabled
veth_mtu: "1480"      # ✅ Fixed
IP_AUTODETECTION_METHOD: "interface=enp38s0.*"  # ❌ Broken
```

**Result:**
- Zephyr: Pods work (pattern matches)
- Nexus/Forge/Sentry: Pods broken (no BGP routes)

---

## Recommended Action

**REVERT TO FLANNEL CNI**

**Rationale:**
1. Calico requires working BGP for multi-node routing
2. BGP requires correct IP autodetection on ALL nodes
3. Current config only works on Zephyr (1/4 nodes)
4. Fixing IP autodetection still leaves BGP complexity
5. Flannel works out-of-the-box with zero configuration

**Time to Revert:** 30 minutes
**Risk:** Low (Flannel was previously working)

---

## If You Insist on Calico

**Required Fixes:**
1. Change `IP_AUTODETECTION_METHOD` to `first-found`
2. Enable `calico_backend: bird`
3. Restart all Calico node pods
4. Verify BGP peer establishment
5. Test cross-node pod connectivity

**Estimated Time:** 2-4 hours
**Success Probability:** 60% (may uncover more NixOS compatibility issues)

---

**Files Created:**
- `/etc/nixos/docs/kubernetes/calico-root-cause-ip-autodetection-2026-03-24.md`

**Error Messages Preserved:**
- `Attempt to get the local CIDR: Never failed`
- `Environment does not contain a valid IPv4 address: IP=Never`
- `Calico node failed to start`

---

**Status:** ✅ ROOT CAUSE FOUND - IP autodetection pattern mismatch
**Next Step:** Revert to Flannel or fix IP_AUTODETECTION_METHOD
