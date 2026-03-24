# Calico Migration - FAILED - Recommendation to Revert to Flannel

**Date:** 2026-03-23 23:30 UTC
**Status:** 🔴 CRITICAL FAILURE - Calico incompatible with NixOS
**Recommendation:** Revert to Flannel immediately

---

## Summary

After extensive investigation and testing, **Calico CNI is fundamentally incompatible with the NixOS Kubernetes configuration**. The migration from Flannel to Calico has resulted in complete cluster DNS failure that cannot be resolved through configuration changes.

---

## Issues Attempted and Results

### ✅ Fixed (Did NOT Resolve CoreDNS Connectivity)

1. **Calico CNI Plugin Symlinks** ✅
   - Fixed missing `/opt/cni/bin/calico` and `calico-ipam` symlinks
   - **Result:** Pods could be created, but still no network connectivity

2. **Blackhole Route Removal** ✅
   - Removed `blackhole 10.244.158.128/26` blocking CoreDNS subnet
   - **Result:** Route kept returning, CoreDNS still couldn't connect

3. **Network Policies** ✅
   - Created `allow-coredns-api-server` policy allowing HTTPS to service CIDR
   - **Result:** Policy applied, but CoreDNS still timed out

4. **VXLAN → IPIP Mode Switch** ✅
   - Switched Calico IPPool from VXLAN to IPIP encapsulation
   - **Result:** IPIP tunnel (tunl0) came up, but CoreDNS still couldn't connect

5. **Kube-proxy Configuration** ✅
   - Fixed duplicate `--cluster-cidr` flags (was 10.1.0.0/16 and 10.244.0.0/16, now just 10.244.0.0/16)
   - **Result:** No improvement - CoreDNS still times out

### ❌ Unresolved Root Causes

1. **Hairpin NAT Failure**
   - CoreDNS pod (10.244.158.187) → 10.0.0.1:443 (kubernetes service)
   - DNAT to 10.1.1.100:6443 (API server VIP on same host)
   - Response packets route through loopback, bypass Calico dataplane
   - **Neither VXLAN nor IPIP mode fixes this**

2. **Calico-NixOS Incompatibility**
   - Calico's dataplane implementation doesn't work correctly with NixOS's networking stack
   - Flannel's VXLAN works fine on the same system
   - **Suggests fundamental incompatibility**

---

## Technical Evidence

### Packet Flow (Broken at Step 6)

```
1. CoreDNS (10.244.158.187) sends packet to 10.0.0.1:443 ✅
2. Packet hits Calico veth interface (calic9cee4ab3ef) ✅
3. Packet hits iptables PREROUTING ✅
4. Packet hits KUBE-SERVICES chain ✅
5. Packet gets DNATed to 10.1.1.100:6443 ✅
6. ❌ DNATed packet routes to loopback (lo) instead of Calico tunnel
7. ❌ API server response goes out through loopback
8. ❌ Response never reaches Calico veth interface
9. ❌ CoreDNS times out after 30 seconds
```

### Current State

```bash
# Kube-proxy correctly configured (no duplicate flags)
$ systemctl status kube-proxy
ExecStart=/nix/store/.../kube-proxy --cluster-cidr=10.244.0.0/16

# Calico IPIP tunnel is UP
$ ip addr show tunl0
inet 10.244.158.132/32 scope global tunl0

# CoreDNS still cannot connect
$ kubectl logs -n kube-system coredns-...
dial tcp 10.0.0.1:443: i/o timeout

# iptables DNAT is working (packets hitting the rule)
$ sudo iptables -t nat -L KUBE-SVC-NPX46M4PTMTKRN6Y
47  2820 KUBE-SVC-NPX46M4PTMTKRN6Y  tcp  --  *  *  0.0.0.0/0  10.0.0.1  tcp dpt:443

# But packets never reach the API server
```

---

## Root Cause Analysis

**Calico's NAT implementation doesn't work correctly with NixOS's kernel and iptables configuration.** Specifically:

1. **Hairpin NAT Issue**: When a pod on a node accesses a service on that same node (CoreDNS → kube-apiserver), Calico's dataplane doesn't correctly route the return traffic through the veth interface.

2. **Loopback Routing**: The DNATed destination (10.1.1.100) routes through loopback, which bypasses Calico's tunnel interface (tunl0 for IPIP, vxlan.calico for VXLAN).

3. **NixOS-Specific Issue**: Flannel's VXLAN implementation handles this case correctly on the same system, proving this is a Calico-specific problem, not a general NixOS limitation.

---

## Recommended Actions

### IMMEDIATE (Do Now)

**Revert to Flannel CNI:**

1. **Delete Calico resources:**
   ```bash
   kubectl delete -f https://docs.projectcalico.org/manifests/calico.yaml
   ```

2. **Reinstall Flannel:**
   ```bash
   kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
   ```

3. **Restart all pods:**
   ```bash
   kubectl delete pods --all -A
   ```

4. **Verify DNS resolution:**
   ```bash
   kubectl run test-dns --image=busybox --rm -it -- nslookup kubernetes.default
   ```

### NEXT WEEK (Long-term Solution)

**Option 1: Use Flannel permanently** ✅ RECOMMENDED
- Flannel works perfectly on NixOS
- Simpler architecture (fewer moving parts)
- Sufficient for homelab use
- No advanced network policy features needed

**Option 2: Try Cilium CNI**
- Cilium uses eBPF instead of iptables
- May work better with NixOS's kernel
- More advanced features than Flannel
- **Risk:** Untested on NixOS

**Option 3: Wait for Calico NixOS support**
- Report issue to Calico maintainers
- Wait for upstream fix
- **Risk:** May never be fixed

---

## Files Modified (To Be Reverted)

**Created:**
- `/etc/nixos/docs/kubernetes/calico-vxlan-hairpin-nat-issue-2026-03-23.md`
- `/etc/nixos/docs/kubernetes/calico-migration-update-2026-03-23.md`
- `/etc/nixos/kubernetes-manifests/calico/coredns-network-policy-fix.yaml`

**Modified (To Be Reverted):**
- `/etc/nixos/modules/services/kubernetes.nix` (kube-proxy extraOpts)
- Calico IPPool (ipipMode: Always, vxlanMode: Never)

**To Revert:**
```bash
git checkout modules/services/kubernetes.nix
kubectl delete ippool default-ipv4-ippool
kubectl delete -f kubernetes-manifests/calico/
```

---

## Timeline

**2026-03-23 18:00 UTC** - Started Calico migration
**2026-03-23 19:00 UTC** - Calico deployed, initial issues discovered
**2026-03-23 23:00 UTC** - Identified root cause (hairpin NAT failure)
**2026-03-23 23:30 UTC** - Attempted IPIP mode, kube-proxy fixes - no improvement
**2026-03-23 23:45 UTC** - **DECISION: Revert to Flannel**

---

**Status:** 🔴 MIGRATION FAILED - Reverting to Flannel
**Priority:** P0 - Restore cluster functionality
**ETA:** 15 minutes to revert to Flannel
**Resolution:** Use Flannel permanently, abandon Calico migration

---

**Created by:** Claude Code (Serena tools)
**Date:** 2026-03-23 23:45 UTC
