# Calico CNI Migration - Final Status

**Date:** 2026-03-23 21:45 UTC
**Status:** ⚠️ INCOMPLETE - Configuration Blocking Cluster Functionality
**Branch:** feature/x86-64-v3-migration

---

## Summary

The NixOS Kubernetes module has been successfully updated for Calico CNI support, and significant progress has been made on network configuration. However, **the cluster is currently non-functional** due to a complex configuration mismatch between Calico components.

---

## Completed Work

### ✅ NixOS Module Updates

**Files Modified:**
1. `modules/services/kubernetes.nix` - Updated cluster CIDR, removed Flannel, added Calico ports
2. `modules/services/monitoring/grafana.nix` - Fixed systemd-helpers import
3. `hosts/zephyr/configuration.nix` - Added 8GB swap to prevent OOM
4. `modules/system/distributed-builds.nix` - Reduced zephyr max-jobs to prevent OOM

### ✅ Calico Deployment

- **All 4 nodes Ready:** zephyr, nexus, forge, sentry
- **Calico pods deployed:** 4/4 calico-node DaemonSet pods running
- **CoreDNS running:** 2/2 CoreDNS pods Running
- **Flannel annotations cleaned:** Old podCIDR annotations removed

### ✅ VXLAN Interface Fixed

**Current State:**
```
vxlan.calico: mtu 1450, local 10.1.1.110 dev enp38s0 (physical interface)
```

**Previous State:**
```
vxlan.calico: mtu 1230, local 100.76.234.6 dev tailscale0 (VPN interface)
```

This is a **major improvement** - Calico is now using the correct physical interface with proper MTU.

---

## Current Issues

### ❌ Critical: Calico Readiness Probes Failing

**Symptom:** All calico-node pods stuck in `Ready: 0/1` state

**Error:**
```
Readiness probe failed: calico/node is not ready: BIRD is not ready:
BGP not established with 10.1.1.120,10.1.1.140,10.1.1.110
```

**Root Cause:** Configuration mismatch between:
- **IPPool:** `vxlanMode: CrossSubnet`, `ipipMode: Never`
- **DaemonSet:** `CALICO_IPV4POOL_IPIP: "Always"`, `CALICO_IPV4POOL_VXLAN: "Never"`

**Impact:** Cluster is non-functional for workloads - no DNS, no pod-to-pod communication

---

## Root Cause Analysis

### The Configuration Mismatch

The issue stems from conflicting encapsulation settings:

1. **IPPool Configuration** (correct):
   ```yaml
   spec:
     cidr: 10.244.0.0/16
     ipipMode: Never      # ✅ VXLAN mode, not IPIP
     vxlanMode: CrossSubnet  # ✅ VXLAN enabled
   ```

2. **DaemonSet Environment Variables** (wrong):
   ```bash
   CALICO_IPV4POOL_IPIP=Always      # ❌ Forces IPIP mode
   CALICO_IPV4POOL_VXLAN=Never     # ❌ Disables VXLAN
   ```

This mismatch causes Calico to:
- Try to establish BGP peering (because backend is "bird")
- But also try to use IPIP encapsulation (because CALICO_IPV4POOL_IPIP=Always)
- While the IPPool expects VXLAN encapsulation
- Result: BGP fails, readiness probes fail, pods never become ready

---

## Solutions Attempted

### ❌ Attempt 1: Update IPPool CIDR
Changed from 10.244.0.0/16 to 172.16.0.0/16
- **Result:** No improvement - created CIDR mismatch with existing pods

### ❌ Attempt 2: Configure IP autodetection
Set `IP_AUTODETECTION_METHOD` to skip Tailscale
- **Result:** Partial success - now uses enp38s0 instead of tailscale0

### ❌ Attempt 3: Update veth MTU
Set `veth_mtu: "1450"` in ConfigMap
- **Result:** VXLAN MTU now correct (1450), but pods still failing

### ❌ Attempt 4: Change Calico backend
Changed `calico_backend` from "bird" to "vxlan"
- **Result:** Failed - "vxlan" is not a valid backend value

### ❌ Attempt 5: Fix interface selection
Set `IP_AUTODETECTION_METHOD: "interface=enp38s0.*"`
- **Result:** ✅ SUCCESS - VXLAN now uses correct physical interface

### ❌ Attempt 6: Fix IPIP/VXLAN environment mismatch
Tried to update DaemonSet environment variables
- **Result:** Patch failed - variables use `valueFrom` (ConfigMap refs)

---

## Required Solution

### Fix the DaemonSet Environment Variables

The DaemonSet environment variables are **read-only** and should be auto-detected from the IPPool, but they're hardcoded in the manifest. The original Calico installation manifest has incorrect values.

**Option 1: Delete and Recreate DaemonSet (RECOMMENDED)**

Delete the existing DaemonSet and recreate it with correct environment variables:

```bash
# Save the current DaemonSet config
kubectl get daemonset -n kube-system calico-node -o yaml > calico-node-ds-backup.yaml

# Edit the file to fix environment variables:
# CALICO_IPV4POOL_IPIP: "Never"   # Changed from "Always"
# CALICO_IPV4POOL_VXLAN: "Always"  # Changed from "Never"

# Delete the old DaemonSet
kubectl delete daemonset -n kube-system calico-node

# Apply the corrected manifest
kubectl apply -f calico-node-ds-backup.yaml
```

**Option 2: Edit Manifest Directly**

If the DaemonSet was deployed from YAML manifests (not Helm), find and edit the source manifest:

```bash
# Find Calico manifests
ls /etc/nixos/kubernetes-manifests/kube-flannel/

# Edit the DaemonSet manifest
vim /etc/nixos/kubernetes-manifests/calico/calico-node.yaml

# Re-apply
kubectl apply -f /etc/nixos/kubernetes-manifests/calico/
```

**Option 3: Use kubectl edit (TEMPORARY FIX)**

```bash
kubectl edit daemonset -n kube-system calico-node
# Change:
#   - name: CALICO_IPV4POOL_IPIP
#     value: "Never"   # Was "Always"
#   - name: CALICO_IPV4POOL_VXLAN
#     value: "Always"  # Was "Never"
```

Note: This will be reverted if the DaemonSet is recreated from manifests.

---

## Verification Steps

After applying the fix, verify:

1. **Check Calico pods:**
   ```bash
   kubectl get pods -n kube-system -l k8s-app=calico-node
   # Expected: 4/4 Running, READY 1/1
   ```

2. **Check BGP status:**
   ```bash
   kubectl logs -n kube-system calico-node-xxxxx | grep "BGP.*established"
   # Expected: Should show 0 BGP peers (VXLAN mode doesn't use BGP)
   ```

3. **Test DNS:**
   ```bash
   kubectl run test-dns --rm -i --restart=Never --image=busybox:1.36 -- nslookup kubernetes.default
   # Expected: Should resolve to 10.0.0.10
   ```

4. **Test pod-to-pod communication:**
   ```bash
   kubectl run test-ping --rm -i --restart=Never --image=busybox:1.36 -- ping -c 2 10.0.0.10
   # Expected: 2 packets transmitted, 2 received, 0% packet loss
   ```

---

## Next Steps

### Immediate (P0 - Critical)

1. **Fix DaemonSet environment variables** using Option 1, 2, or 3 above
2. **Verify Calico pods become ready**
3. **Test DNS and pod connectivity**

### Short-term (P1 - High)

4. **Deploy Calico config to other nodes** (nexus, forge, sentry)
5. **Fix build failures** (logprof.conf, pipewire-extra-config on forge)
6. **Complete cluster-wide testing**

### Long-term (P2 - Medium)

7. **Update NixOS module** to include Calico DaemonSet configuration
8. **Document Calico workflows** in CLAUDE.md
9. **Consider migrating to 172.16.0.0/16** pod CIDR range for production

---

## Lessons Learned

1. **Interface selection is critical:** Calico's IP autodetection can choose wrong interfaces (Tailscale, docker0, etc.)
2. **Environment variables matter:** Hardcoded `CALICO_IPV4POOL_*` variables can override IPPool settings
3. **VXLAN vs IPIP vs BGP:** Three different encapsulation/routing mechanisms that must be configured consistently
4. **Readiness probes hide issues:** Calico pods can be "Running" but not "Ready" due to BGP/VXLAN configuration issues
5. **MTU is important:** VXLAN MTU must match underlying network (1450 for standard 1500 MTU networks)

---

## Technical Details

### VXLAN Interface State (Current)

```
947: vxlan.calico: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1450 qdisc noqueue
    vxlan id 4096 local 10.1.1.110 dev enp38s0 srcport 0 0 dstport 4789
```

**✅ Correct:**
- MTU 1450 (proper for VXLAN over 1500 MTU network)
- Using enp38s0 (physical interface, not Tailscale)
- Local IP 10.1.1.110 (correct cluster IP)

### Configuration State (Current)

**IPPool:** ✅ Correct
```yaml
cidr: 10.244.0.0/16
ipipMode: Never
vxlanMode: CrossSubnet
```

**DaemonSet:** ❌ Wrong
```bash
CALICO_IPV4POOL_IPIP=Always    # Should be "Never"
CALICO_IPV4POOL_VXLAN=Never   # Should be "Always"
```

---

## References

- **Calico Documentation:** https://docs.projectcalico.org/networking/vxlan-ip-in-udp
- **IP Autodetection:** https://docs.projectcalico.org/networking/ip-autodetection
- **VXLAN Mode:** https://docs.projectcalico.org/networking/vxlan-ip-in-udp#vxlan-mode
- **BIRD vs VXLAN:** https://docs.projectcalico.org/reference/resources/bgp

---

**Status:** ⚠️ BLOCKED on DaemonSet environment variable configuration
**Priority:** P0 - Critical cluster functionality
**ETA:** 30 minutes to fix and verify
**Resolution:** Update CALICO_IPV4POOL_* environment variables in DaemonSet
