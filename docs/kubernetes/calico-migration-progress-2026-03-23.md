# Calico CNI Migration - Progress Update

**Date:** 2026-03-23 22:52 UTC
**Status:** ⚠️ IN PROGRESS - Network Connectivity Issues Persist
**Branch:** feature/x86-64-v3-migration

---

## Summary

Significant progress has been made on the Calico CNI migration, but **critical DNS and pod-to-service networking issues remain unresolved**. The Calico pods are running, but CoreDNS cannot connect to the Kubernetes API server, causing DNS resolution failures.

---

## Completed Work

### ✅ Configuration Updates

**Files Modified:**
1. `modules/services/kubernetes.nix` - Fixed kube-proxy cluster CIDR configuration
   - Changed `proxy.extraOpts` from `--cluster-cidr=172.16.0.0/16` to `--cluster-cidr=10.244.0.0/16`
   - Changed `controllerManager.clusterCidr` from `172.16.0.0/16` to `10.244.0.0/16`
   - Updated comments to reflect Calico instead of Flannel

### ✅ Flannel Cleanup

- Removed all Flannel iptables rules (FLANNEL-FWD, FLANNEL-POSTRTG chains)
- Removed blackhole route for 10.244.158.128/26
- Old Flannel cni0 bridge already deleted

### ✅ Calico DaemonSet Fixed

**Environment Variables:**
- `CALICO_IPV4POOL_IPIP`: Changed from "Always" to "Never"
- `CALICO_IPV4POOL_VXLAN`: Changed from "Never" to "Always"

**Result:** All 4 Calico node pods restarted, now 3/4 Running:
- calico-node-2ccjx (zephyr): Running
- calico-node-q87wd (nexus): Running
- calico-node-qhltl (forge): Running
- calico-node-pwhsp (sentry): CrashLoopBackOff

### ✅ VXLAN Interface Fixed

**Current State:**
```
vxlan.calico: mtu 1450, local 10.1.1.110 dev enp38s0 (physical interface)
```

This is a **major improvement** - Calico is using the correct physical interface with proper MTU.

### ✅ kube-proxy Configuration

- Updated kube-proxy cluster CIDR to match Calico IPPool (10.244.0.0/16)
- kube-proxy restarted and synced
- iptables MASQ rules correctly configured (10.244.0.0/16 traffic not masqueraded)

---

## Current Issues

### ❌ Critical: CoreDNS Cannot Reach API Server

**Symptom:** DNS resolution returns NXDOMAIN
```
Server: 10.0.0.10
Address: 10.0.0.10:53
** server can't find kubernetes.default: NXDOMAIN
```

**Root Cause:** CoreDNS pods timing out when connecting to Kubernetes API
```
dial tcp 10.0.0.1:443: i/o timeout
```

**Impact:**
- No DNS resolution for cluster services
- Pods cannot discover services
- Cluster is non-functional for workloads

### ❌ Calico Node Pods Failing on Some Nodes

**Status:**
- zephyr: Running ✅
- nexus: Running ✅
- forge: Running ✅
- sentry: CrashLoopBackOff ❌

**Sentry Pod Error:**
``Readiness probe failed: calico/node is not ready: felix is not ready
Liveness probe failed: calico/node is not ready: bird/confd is not live
```

---

## Root Cause Analysis

### Issue 1: CoreDNS API Server Connectivity

CoreDNS pods (IP: 10.244.158.169) cannot reach the kubernetes service IP (10.0.0.1:443).

**Expected Flow:**
1. CoreDNS pod → 10.0.0.1:443 (service IP)
2. kube-proxy DNAT rule → 10.1.1.100:6443 (API server VIP)
3. API server responds

**Current State:**
- Step 1: ✅ CoreDNS can reach 10.0.0.10:53 (CoreDNS service itself)
- Step 2: ❌ Timeout reaching 10.0.0.1:443
- Step 3: N/A (never reaches API server)

**Hypothesis:** Calico VXLAN networking is not properly routing traffic from pods to service IPs.

### Issue 2: kube-proxy Dual Cluster-CIDR Flags

kube-proxy command line has TWO `--cluster-cidr` flags:
```
--cluster-cidr=10.1.0.0/16  (hardcoded in NixOS module, WRONG)
--cluster-cidr=10.244.0.0/16 (from extraOpts, CORRECT)
```

While the last flag should win, this may be causing confusion or inconsistent behavior.

---

## Next Steps

### Immediate (P0 - Critical)

1. **Fix CoreDNS API Server Connectivity**
   - Investigate why pods can't reach service IPs
   - Check Calico VXLAN routing tables
   - Verify kube-proxy iptables rules are correct
   - Test direct connectivity from pod to API server IP (10.1.1.100:6443)

2. **Fix Sentry Calico Node**
   - Check why sentry calico-node is in CrashLoopBackOff
   - Review logs for BGP/VXLAN configuration errors
   - Verify sentry node networking configuration

3. **Resolve kube-proxy Dual CIDR Issue**
   - Find and remove hardcoded `--cluster-cidr=10.1.0.0/16` in NixOS module
   - Ensure only correct CIDR (10.244.0.0/0/16) is used

### Short-term (P1 - High)

4. **Deploy Calico Configuration to Other Nodes**
   - Apply configuration fixes to nexus, forge, sentry
   - Verify all 4 nodes have correct cluster CIDR

5. **End-to-End Testing**
   - Test DNS resolution after fixes
   - Test pod-to-service communication
   - Test pod-to-pod communication

### Long-term (P2 - Medium)

6. **Update NixOS Module**
   - Remove hardcoded cluster CIDR from kube-proxy
   - Document Calico-specific configuration options
   - Add Calico-specific firewall rules

7. **Update Documentation**
   - Document Calico migration complete process
   - Create troubleshooting guide for common issues
   - Update CLAUDE.md with Calico workflows

---

## Technical Details

### Calico Configuration

**IPPool:**
```yaml
cidr: 10.244.0.0/16
ipipMode: Never
vxlanMode: Always
natOutgoing: true
```

**DaemonSet Environment Variables:**
```bash
CALICO_IPV4POOL_IPIP: "Never"   # ✅ Fixed
CALICO_IPV4POOL_VXLAN: "Always"  # ✅ Fixed
IP_AUTODETECTION_METHOD: "interface=enp38s0.*"  # ✅ Fixed
```

**VXLAN Interface:**
```
vxlan.calico: mtu 1450, local 10.1.1.110 dev enp38s0
```

**kube-proxy Configuration:**
```bash
--cluster-cidr=10.1.0.0/16  # ❌ Wrong (hardcoded)
--cluster-cidr=10.244.0.0/16  # ✅ Correct (from extraOpts)
```

### Network State

**Pod CIDR:** 10.244.0.0/16 (Calico IPPool)
**Service CIDR:** 10.0.0.0/24
**Physical Network:** 10.1.1.0/24

**iptables Rules:**
- MASQ correctly NOT applied to 10.244.0.0/16 traffic
- DNAT rules present for all services
- Calico cali-FORWARD and cali-INPUT chains active

---

## Troubleshooting Commands

```bash
# Check Calico node status
kubectl get pods -n kube-system -l k8s-app=calico-node

# Check CoreDNS logs
kubectl logs -n kube-system coredns-5ff4cf5f88-2nr6r --tail=20

# Test DNS resolution
kubectl run dns-test --rm -i --restart=Never --image=busybox:1.36 -- nslookup kubernetes.default

# Check kube-proxy command line
ps aux | grep kube-proxy

# Check iptables rules
sudo iptables -t nat -L KUBE-SERVICES -n | head -20
sudo iptables -L FORWARD -n -v | head -30

# Check VXLAN interface
ip link show vxlan.calico

# Check routing
ip route get 10.0.0.1
```

---

## Known Issues

1. **kube-proxy has dual --cluster-cidr flags** - Second flag should override, but may cause confusion
2. **CoreDNS cannot reach API server** - Network connectivity issue between pods and service IPs
3. **Sentry Calico node failing** - CrashLoopBackOff, needs investigation
4. **DNS returns NXDOMAIN** - CoreDNS can't query API server for service discovery

---

**Status:** ⚠️ BLOCKED on CoreDNS API server connectivity
**Priority:** P0 - Critical cluster functionality
**ETA:** 1-2 hours to diagnose and fix
**Resolution:** Investigate pod-to-service networking in Calico VXLAN
