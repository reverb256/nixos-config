# Calico CNI Migration - Critical Update

**Date:** 2026-03-23 23:15 UTC
**Status:** ⚠️ PARTIAL PROGRESS - DNS Still Blocked

---

## Issues Identified and Fixed

### ✅ Fixed Issues

1. **Calico CNI Plugin Missing**
   - **Problem:** Calico CNI binaries not present in `/opt/cni/bin/`
   - **Root Cause:** NixOS calico-cni-setup service creates symlinks, but they were deleted
   - **Fix:** Manually recreated symlinks:
     ```bash
     /opt/cni/bin/calico -> /nix/store/.../calico-cni-plugin-3.31.3/bin/calico
     /opt/cni/bin/calico-ipam -> /nix/store/.../calico-cni-plugin-3.31.3/bin/calico
     ```
   - **Note:** Both symlinks point to the same `calico` binary (behaves differently based on invocation name)

2. **Blackhole Route Blocking CoreDNS Subnet**
   - **Problem:** Blackhole route for `10.244.158.128/26` (CoreDNS pod subnet)
   - **Fix:** Removed blackhole route with `sudo ip route del blackhole 10.244.158.128/26`

3. **Network Policy Blocking API Server Access**
   - **Problem:** `allow-coredns-external-dns` policy only allowed DNS traffic (port 53)
   - **Fix:** Created new policy `allow-coredns-api-server` allowing HTTPS to service CIDR (10.0.0.0/24)
   - **Additional:** Removed old restrictive policy

4. **Calico DaemonSet Environment Variables**
   - **Problem:** IPIP/VXLAN mismatch (IPIP=Always, VXLAN=Never vs IPPool: ipipMode=Never, vxlanMode=Always)
   - **Fix:** Patched DaemonSet to set IPIP=Never, VXLAN=Always

### ❌ Remaining Issues

1. **CoreDNS Cannot Connect to API Server (CRITICAL)**
   - **Symptom:** DNS resolution returns NXDOMAIN
   - **Root Cause:** CoreDNS pods timeout connecting to `10.0.0.1:443` (kubernetes service IP)
   - **Attempts:**
     - ✅ Fixed network policies to allow HTTPS traffic
     - ✅ Verified iptables DNAT rules are being hit (526 packets)
     - ✅ Confirmed API server is listening on port 6443
     - ✅ Removed blackhole route
     - ✅ Fixed Calico CNI plugin symlinks
     - ❌ **STILL FAILING** - Connection times out persist

2. **Calico Node Pods Unstable**
   - **Status:** 2/4 pods in CrashLoopBackOff (forge, sentry)
   - **Errors:** "felix is not ready", "bird/confd is not live"

3. **NixOS Module Issues**
   - **calico-ipam symlink** points to wrong binary in module definition
   - **calico-cni-setup.service** runs but symlinks get deleted later
   - Need to make symlinks persistent across reboots

---

## Next Steps (IMMEDIATE)

### Priority 1: Debug CoreDNS API Server Connectivity

**Hypothesis:** Calico VXLAN dataplane blocking pod-to-local-service traffic

**Diagnostic Commands:**
```bash
# Check if CoreDNS pod can reach host network
kubectl exec -n kube-system coredns-<pod> -- ping -c 2 10.1.1.110

# Check conntrack entries for CoreDNS connections
sudo conntrack -L | grep 10.244.158.187

# Check Calico Felix logs for dropped packets
kubectl logs -n kube-system calico-node-2ccjx | grep -i drop

# Test from pod to service IP
kubectl run test-connect --image=nicolaka/netshoot --restart=Never -it -- curl -v https://10.0.0.1:443
```

**Potential Fixes:**
1. Disable Calico network policies temporarily to isolate the issue
2. Check if Calico is blocking traffic to host loopback interface
3. Verify VXLAN encapsulation is working correctly
4. Check if there's a host-endpoint policy blocking the traffic

### Priority 2: Fix NixOS Module

**File:** `/etc/nixos/modules/services/kubernetes.nix`

**Required Changes:**
1. Fix calico-ipam symlink to point to calico binary (not calico-ipam)
2. Make calico-cni-setup.service symlinks persistent
3. Consider adding systemd path unit to watch /opt/cni/bin and recreate symlinks if deleted

### Priority 3: Fix Calico Node Pods on Forge/Sentry

**Investigation Needed:**
- Check BGP peering status
- Verify node networking configuration
- Review Calico node logs for specific errors

---

## Technical Details

### Current Calico Configuration

**IPPool:**
```yaml
cidr: 10.244.0.0/16
ipipMode: Never
vxlanMode: Always
natOutgoing: true
```

**DaemonSet Environment Variables (PATCHED):**
```bash
CALICO_IPV4POOL_IPIP: "Never"   # ✅ Changed from "Always"
CALICO_IPV4POOL_VXLAN: "Always"  # ✅ Changed from "Never"
IP_AUTODETECTION_METHOD: "interface=enp38s0.*"
```

**VXLAN Interface:**
```
vxlan.calico: mtu 1450, local 10.1.1.110 dev enp38s0
```

### Network State

**Pod CIDR:** 10.244.0.0/16 (Calico IPPool)
**Service CIDR:** 10.0.0.0/24
**Physical Network:** 10.1.1.0/24

**CoreDNS Pod IP:** 10.244.158.187 (zephyr node)
**API Server VIP:** 10.1.1.100 (Keepalived VIP on zephyr)
**Kubernetes Service IP:** 10.0.0.1 (should DNAT to 10.1.1.100:6443)

### iptables Rules Status

**DNAT Rule (WORKING):**
```
KUBE-SVC-NPX46M4PTMTKRN6Y: 526 packets DNATed to 10.1.1.100:6443
```

**Packet Flow:**
1. CoreDNS pod (10.244.158.187) sends packet to 10.0.0.1:443 ✅
2. Packet hits iptables PREROUTING ✅
3. Packet hits KUBE-SERVICES chain ✅
4. Packet hits KUBE-SVC-NPX46M4PTMTKRN6Y chain ✅
5. Packet gets DNATed to 10.1.1.100:6443 ✅
6. **❌ BLOCKED somewhere after DNAT**
7. API server receives no traffic
8. CoreDNS times out after 30 seconds

---

## Files Created/Modified

**Created:**
- `/etc/nixos/kubernetes-manifests/calico/coredns-network-policy-fix.yaml`
- `/etc/nixos/docs/kubernetes/calico-migration-update-2026-03-23.md`

**Modified:**
- `/etc/nixos/modules/services/kubernetes.nix` (kube-proxy cluster CIDR)
- Calico DaemonSet (patched environment variables)
- Calico IPPool (vxlanMode changed to Always)

---

**Status:** ⚠️ BLOCKED on pod-to-service networking in Calico VXLAN
**Priority:** P0 - Critical cluster functionality
**ETA:** 2-4 hours to diagnose and fix
**Resolution:** Investigate Calico VXLAN dataplane and conntrack state
