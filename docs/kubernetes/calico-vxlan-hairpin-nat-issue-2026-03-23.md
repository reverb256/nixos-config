# Calico VXLAN Hairpin NAT Failure - Root Cause Identified

**Date:** 2026-03-23 23:30 UTC
**Status:** 🔴 CRITICAL - Fundamental VXLAN dataplane issue
**Impact:** Complete cluster DNS failure, all services unreachable

---

## Root Cause Analysis

### The Problem

**CoreDNS pods cannot connect to the Kubernetes API server** because Calico VXLAN mode doesn't properly handle hairpin NAT for local services.

### Packet Flow Breakdown

**What SHOULD happen:**
1. CoreDNS pod (10.244.158.187) sends packet to 10.0.0.1:443 (kubernetes service IP)
2. Packet goes through Calico veth interface (calic9cee4ab3ef)
3. Packet hits iptables PREROUTING chain
4. Packet hits KUBE-SERVICES chain
5. Packet gets DNATed to 10.1.1.100:6443 (API server VIP)
6. **❌ BREAKPOINT**: Packet should be routed to API server, response should return to pod

**What ACTUALLY happens:**
1-5. ✅ Same as above
6. DNATed packet (dest: 10.1.1.100:6443) is routed through **loopback interface** (`lo`)
7. ❌ Loopback interface is NOT in Calico's VXLAN dataplane
8. ❌ Response packet from API server goes out through loopback
9. ❌ Response never reaches the Calico veth interface
10. ❌ CoreDNS times out after 30 seconds

### Evidence

```bash
# API server VIP routes through loopback
$ ip route get 10.1.1.100
local 10.1.1.100 dev lo table local src 10.1.1.110 uid 1000

# VIP is on enp38s0 as secondary address
$ ip addr show enp38s0
inet 10.1.1.110/24 brd 10.1.1.255 scope global enp38s0
inet 10.1.1.100/24 scope global secondary proto 0x12 enp38s0

# iptables DNAT is working (47 packets hit the rule)
$ sudo iptables -t nat -L KUBE-SERVICES -n -v | grep kubernetes
47  2820 KUBE-SVC-NPX46M4PTMTKRN6Y  tcp  --  *  *  0.0.0.0/0  10.0.0.1  tcp dpt:443

# But packets never reach the API server
$ kubectl logs -n kube-system coredns-5ff4cf5f88-gk97g
dial tcp 10.0.0.1:443: i/o timeout
```

### Why This Happens

**Calico VXLAN Architecture:**
- VXLAN creates an overlay network (tunnel) between pods across nodes
- Pod-to-pod traffic goes through VXLAN tunnel (vxlan.calico interface)
- Each pod has a veth pair connecting it to the host namespace

**Hairpin NAT Issue:**
- When a pod accesses a service on the **same node**, DNAT happens
- The DNATed destination (10.1.1.100) routes through loopback
- Loopback bypasses the VXLAN tunnel
- Return path is broken because the response doesn't go back through the veth interface

**This is a known limitation of VXLAN overlay networks** when used with Kubernetes services that have endpoints on the same node as the client pod.

---

## Solutions

### Option 1: Switch to Calico IPIP Mode (RECOMMENDED)

**Pros:**
- IPIP mode handles hairpin NAT correctly
- Simpler routing (no VXLAN encapsulation overhead)
- Better performance for local traffic
- Proven in production

**Cons:**
- Slightly higher overhead for cross-node traffic (IPIP encapsulation)
- Requires protocol 4 (IP-in-IP) which might be blocked by some firewalls

**Implementation:**
```yaml
apiVersion: crd.projectcalico.org/v1
kind: IPPool
metadata:
  name: default-ipv4-ippool
spec:
  cidr: 10.244.0.0/16
  ipipMode: Always  # Changed from Never
  vxlanMode: Never  # Changed from Always
  natOutgoing: true
```

**Apply with:**
```bash
kubectl patch ippool default-ipv4-ippool --type merge -p '{"spec":{"ipipMode":"Always","vxlanMode":"Never"}}'
```

### Option 2: Use hostNetwork for CoreDNS (QUICK FIX)

**Pros:**
- Immediate workaround
- CoreDNS bypasses Calico entirely
- No networking changes needed

**Cons:**
- Not a proper long-term solution
- CoreDNS pods use host network namespace
- Doesn't fix the underlying issue for other pods

**Implementation:**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: coredns
  namespace: kube-system
spec:
  template:
    spec:
      hostNetwork: true  # Add this
```

### Option 3: External Traffic Policy (NOT RECOMMENDED)

**Pros:**
- Routes traffic to endpoints on different nodes only
- Avoids hairpin NAT issue

**Cons:**
- Breaks service mesh patterns
- Uneven load distribution
- Doesn't work for all services

### Option 4: Switch Back to Flannel (ROLLBACK)

**Pros:**
- Flannel VXLAN handles this case correctly
- Known working configuration
- Minimal changes needed

**Cons:**
- Loses Calico's advanced features (network policies, fine-grained control)
- Step backward in capabilities

---

## Recommended Action Plan

### Immediate (Next 30 minutes)

1. **Switch Calico from VXLAN to IPIP mode:**
   ```bash
   kubectl patch ippool default-ipv4-ippool --type merge -p '{"spec":{"ipipMode":"Always","vxlanMode":"Never"}}'
   ```

2. **Restart all Calico node pods:**
   ```bash
   kubectl delete pod -n kube-system -l k8s-app=calico-node
   ```

3. **Test CoreDNS connectivity:**
   ```bash
   kubectl logs -n kube-system coredns-<pod> --tail=20
   ```

### If IPIP Doesn't Work (Fallback)

1. **Switch CoreDNS to hostNetwork:**
   ```bash
   kubectl patch deployment coredns -n kube-system --type=json -p='[{"op": "add", "path": "/spec/template/spec/hostNetwork", "value": true}]'
   ```

2. **Verify DNS resolution:**
   ```bash
   kubectl run test-dns --image=busybox --rm -it -- nslookup kubernetes.default
   ```

### Long-term (This Week)

1. **Test all workloads** with IPIP mode
2. **Monitor performance** (IPIP vs VXLAN)
3. **Update NixOS module** to use IPIP by default
4. **Document findings** in migration guide

---

## Technical Details

### Current Calico Configuration

```yaml
IPPool:
  cidr: 10.244.0.0/16
  ipipMode: Never      # ❌ PROBLEMATIC
  vxlanMode: Always    # ❌ PROBLEMATIC
  natOutgoing: true

FelixConfiguration:
  bpfConnectTimeLoadBalancing: TCP
  bpfHostNetworkedNATWithoutCTLB: Enabled  # Not actually used
  floatingIPs: Disabled
```

### Network State

**Pod CIDR:** 10.244.0.0/16 (Calico IPPool)
**Service CIDR:** 10.0.0.0/24
**Physical Network:** 10.1.1.0/24

**CoreDNS Pod:** 10.244.158.187 (zephyr node)
**API Server VIP:** 10.1.1.100 (Keepalived VIP on zephyr)
**Kubernetes Service IP:** 10.0.0.1 (should DNAT to 10.1.1.100:6443)

### iptables State

```
# DNAT rule (WORKING - 47 packets)
KUBE-SVC-NPX46M4PTMTKRN6Y: 47 packets DNATed to 10.1.1.100:6443

# But routing sends response through loopback
ip route get 10.1.1.100
local 10.1.1.100 dev lo table local src 10.1.1.110
```

---

## Files Modified

**Created:**
- `/etc/nixos/docs/kubernetes/calico-vxlan-hairpin-nat-issue-2026-03-23.md`

**Previously Created:**
- `/etc/nixos/docs/kubernetes/calico-migration-update-2026-03-23.md`
- `/etc/nixos/kubernetes-manifests/calico/coredns-network-policy-fix.yaml`

---

## Status

**Priority:** P0 - Critical cluster functionality
**ETA:** 30 minutes to apply IPIP fix
**Resolution:** Switch Calico from VXLAN to IPIP mode

**Next Steps:**
1. Apply IPPool patch to switch to IPIP
2. Restart Calico node pods
3. Test CoreDNS connectivity
4. Verify DNS resolution
5. Update documentation

---

**Created by:** Claude Code (Serena tools)
**Date:** 2026-03-23 23:30 UTC
