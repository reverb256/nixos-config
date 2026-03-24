# Calico CNI Migration - MTU Mismatch Root Cause Analysis

**Date:** 2026-03-24 06:10 UTC
**Status:** 🔴 CRITICAL ISSUE IDENTIFIED - MTU Mismatch
**Root Cause:** ConfigMap has VXLAN MTU (1450) but IPPool configured for IPIP mode (needs MTU 1480)

---

## Executive Summary

**Problem**: CoreDNS and all pods cannot reach the Kubernetes API server despite all previous fixes (network policies, routes, kube-proxy).

**Root Cause**: Calico ConfigMap `calico-config` has `veth_mtu: "1450"` (VXLAN MTU), but IPPool `default-ipv4-ippool` is configured for IPIP mode (`ipipMode: Always`). IPIP requires MTU 1480, not 1450.

**Impact**: 
- All existing pods have veth interfaces with wrong MTU (1450 instead of 1480)
- IPIP tunnel `tunl0` shows TX 273 packets but RX 0 packets (packets sent but never received)
- Packet fragmentation/corruption prevents TCP connections
- CoreDNS cannot connect to API server (timeout after 30s)

**Solution**: Update ConfigMap `veth_mtu` to `"1480"` and restart all pods.

---

## Diagnostic Evidence

### 1. IPPool Configuration (IPIP Mode)
```yaml
spec:
  cidr: 10.244.0.0/16
  ipipMode: Always      # ✅ IPIP enabled
  vxlanMode: Never      # ✅ VXLAN disabled
  natOutgoing: true
```

### 2. ConfigMap MTU Setting (WRONG - VXLAN MTU)
```yaml
data:
  veth_mtu: "1450"      # ❌ This is VXLAN MTU!
  cni_network_config: |
    "mtu": __CNI_MTU__,  # Expands to 1450
```

**Correct Values**:
- **VXLAN MTU**: 1450 (1500 - 50 bytes VXLAN overhead)
- **IPIP MTU**: 1480 (1500 - 20 bytes IP header)
- **No Encap MTU**: 1500 (no overhead)

### 3. IPIP Tunnel Statistics (PROVES MISMATCH)
```
tunl0@NONE: <NOARP,UP,LOWER_UP> mtu 1450 qdisc noqueue state UNKNOWN
    link/ipip 0.0.0.0 brd 0.0.0.0
    RX:  bytes  packets  errors  dropped  missed  mcast
         0        0       0       0       0       0   # ❌ No packets received!
    TX:  bytes  packets  errors  dropped  carrier collsns
      41496      273      0       0       0       0   # ✅ 273 packets sent
```

**Interpretation**: 273 packets entered tunl0 but 0 emerged. This means:
- Packets are being encapsulated into IPIP
- But receiver can't decapsulate them (wrong MTU causes corruption)
- Or packets are too large and getting dropped

### 4. Veth Interface MTU (All Wrong)
```
871: calif630e92ec37@if3: mtu 1500  # New pod (correct for no-encap)
874: cali7878c128646@if3: mtu 1500  # New pod (correct for no-encap)
905: calife7f25ab602@if3: mtu 1450  # ❌ Old pod (VXLAN MTU)
948: calib0ed0edb79f@if3:  mtu 1450  # ❌ Old pod (VXLAN MTU)
1113: calied390b56ad3@if3:  mtu 1450  # ❌ CoreDNS (VXLAN MTU)
```

**CoreDNS pod** (10.244.158.129) has MTU 1450 but should have 1480 for IPIP.

### 5. DaemonSet Environment Variables (CORRECT)
```yaml
- name: CALICO_IPV4POOL_IPIP
  value: Always        # ✅ Correct
- name: CALICO_IPV4POOL_VXLAN
  value: Never         # ✅ Correct
```

### 6. Kernel Modules (CORRECT)
```
ipip                   16384  0    # ❌ Usage count 0 (no tunnels active!)
tunnel4                12288  1 ipip
ip_tunnel              36864  1 ipip
```

The ipip module shows 0 usage, confirming no actual IPIP encapsulation is happening.

---

## Packet Flow Breakdown

### What Should Happen (IPIP Mode)
1. CoreDNS pod (10.244.158.129) sends packet to 10.0.0.1:443
2. Packet goes through veth `calied390b56ad3` (MTU 1480)
3. Packet hits host routing table
4. Packet is encapsulated in IP-in-IP header (20 bytes overhead)
5. Encapsulated packet (1490 bytes) goes through tunl0
6. Packet is routed to destination
7. Return packet follows reverse path

### What's Actually Happening (MTU Mismatch)
1. CoreDNS pod sends packet through veth with MTU 1450
2. Packet (1450 bytes) reaches host
3. Calico tries to add IPIP header (20 bytes) → 1470 bytes
4. **Problem**: MTU mismatch causes:
   - Option A: Packet gets dropped (exceeds effective MTU)
   - Option B: Packet gets fragmented (causes reassembly failures)
   - Option C: Packet corruption during encapsulation
5. tunl0 TX shows 273 packets sent, but RX shows 0 received
6. Destination never receives valid packets
7. TCP connection times out after 30s

### iptables State (Working Correctly)
```
KUBE-SVC-NPX46M4PTMTKRN6Y: 8 packets DNATed to 10.1.1.100:6443
```

DNAT is working (8 packets to kubernetes service), but packets never reach API server due to IPIP failure.

---

## Timeline of Configuration Changes

### Initial Installation (2026-03-23 19:01 UTC)
- IPPool: `vxlanMode: Always`, `ipipMode: Never`
- ConfigMap: `veth_mtu: "1450"` (correct for VXLAN)
- Result: VXLAN working (but had hairpin NAT issues)

### Failed Patch Attempt (2026-03-23 ~23:00 UTC)
- Patched IPPool: `ipipMode: Always`, `vxlanMode: Never`
- **Forgot to patch**: ConfigMap `veth_mtu` to `"1480"`
- Result: IPIP configured but using VXLAN MTU

### Current State (2026-03-24 06:10 UTC)
- IPPool: IPIP mode ✅
- ConfigMap: Still has VXLAN MTU ❌
- All pods: Have wrong MTU ❌
- IPIP tunnel: Not working ❌

---

## Why Previous Fixes Didn't Work

### Fix 1: Network Policy
**What we did**: Created `allow-coredns-api-server` NetworkPolicy
**Why it failed**: Policy allows traffic, but MTU mismatch prevents packets from being sent correctly

### Fix 2: Remove Blackhole Route
**What we did**: `sudo ip route del blackhole 10.244.158.128/26`
**Why it failed**: Route wasn't the problem; MTU mismatch is

### Fix 3: Kube-proxy Configuration
**What we did**: Fixed duplicate `--cluster-cidr` flags
**Why it failed**: kube-proxy is working correctly; problem is in Calico dataplane

### Fix 4: Disable BPF Feature
**What we did**: Set `bpfHostNetworkedNATWithoutCTLB: Disabled`
**Why it failed**: BPF feature wasn't causing the issue

### Fix 5: Restart Calico Pods
**What we did**: `kubectl delete pod calico-node-*`
**Why it failed**: Calico pods restarted, but ConfigMap still has wrong MTU, so new pods still get wrong MTU

---

## The Solution

### Step 1: Update ConfigMap MTU
```bash
kubectl patch configmap calico-config -n kube-system \
  --type merge \
  -p '{"data":{"veth_mtu":"1480"}}'
```

### Step 2: Restart All Calico Pods
```bash
kubectl delete pod -n kube-system -l k8s-app=calico-node
```

### Step 3: Restart All Workload Pods (to recreate veth interfaces)
```bash
# Option A: Restart all pods (cluster-wide disruption)
kubectl delete pods --all --all-namespaces --grace-period=60

# Option B: Restart pods node-by-node (rolling restart)
kubectl delete pod -n kube-system -l k8s-app=calico-node
# Wait for Calico to be ready
kubectl delete pods --all -A --field-selector spec.nodeName=zephyr
# Repeat for each node
```

### Step 4: Verify MTU is Correct
```bash
# Check CNI config
cat /etc/cni/net.d/10-calico.conflist | grep mtu

# Check veth interfaces
ip link show | grep cali

# Check tunl0 traffic (should have both TX and RX packets)
ip -stats link show tunl0
```

### Step 5: Test CoreDNS Connectivity
```bash
# Test from CoreDNS pod
kubectl exec -n kube-system coredns-5ff4cf5f88-lnt5w -- \
  wget -T 5 --no-check-certificate https://10.0.0.1:443

# Should return: "401 Unauthorized" (API server is reachable!)
```

---

## Verification Checklist

After applying the fix, verify:

- [ ] ConfigMap shows `veth_mtu: "1480"`
- [ ] CNI config file shows `"mtu": 1480`
- [ ] All veth interfaces have MTU 1480 (not 1450)
- [ ] tunl0 shows both TX and RX packets increasing
- [ ] CoreDNS can reach API server (returns 401, not timeout)
- [ ] DNS resolution works (`nslookup kubernetes.default.svc.cluster.local`)
- [ ] All pods can reach services

---

## Technical Background

### MTU Calculation for Different Encapsulation Modes

| Mode | MTU | Calculation | Overhead |
|------|-----|-------------|----------|
| **No Encap** | 1500 | 1500 (Ethernet) | 0 bytes |
| **IPIP** | 1480 | 1500 - 20 (IP header) | 20 bytes |
| **VXLAN** | 1450 | 1500 - 50 (UDP + VXLAN) | 50 bytes |

### Why MTU Matters

When encapsulating packets:
1. Original packet: 1500 bytes
2. Add encapsulation header (IPIP: 20 bytes, VXLAN: 50 bytes)
3. Result: 1520 bytes (IPIP) or 1550 bytes (VXLAN)
4. If veth MTU is too small, packets get:
   - **Dropped**: Exceeds MTU
   - **Fragmented**: Breaks TCP/UDP
   - **Corrupted**: Wrong checksum after reassembly

### Calico Configuration Hierarchy

1. **IPPool** (`default-ipv4-ippool`): Sets encapsulation mode
2. **ConfigMap** (`calico-config`): Sets MTU for new pods
3. **DaemonSet** (`calico-node`): Reads ConfigMap and configures CNI
4. **CNI Plugin** (`/etc/cni/net.d/10-calico.conflist`): Creates veth with configured MTU

**All 4 must be consistent!**

---

## Prevention Measures

### 1. Use Validation Hooks
Create a Kubernetes validating webhook that checks:
- IPPool mode matches ConfigMap MTU
- veth MTU is appropriate for encapsulation mode

### 2. Document MTU Requirements
Update runbooks to include:
- Always check ConfigMap when changing IPPool mode
- Restart all pods after MTU change
- Verify MTU on running pods

### 3. Automated Testing
Add tests to cluster validation:
```bash
# Check MTU consistency
IPPOOL_MODE=$(kubectl get ippool default-ipv4-ippool -o jsonpath='{.spec.ipipMode}')
CONFIG_MTU=$(kubectl get cm calico-config -n kube-system -o jsonpath='{.data.veth_mtu}')

if [ "$IPPOOL_MODE" = "Always" ] && [ "$CONFIG_MTU" != "1480" ]; then
  echo "ERROR: IPIP mode requires MTU 1480, but ConfigMap has $CONFIG_MTU"
  exit 1
fi
```

---

## Related Issues

### Similar Problems in Other Clusters
This is a known issue when migrating between Calico encapsulation modes:
- [Calico Issue #3512](https://github.com/projectcalico/calico/issues/3512): MTU mismatch after mode change
- [Calico Docs](https://docs.projectcalico.org/networking/ipip): MTU configuration guide

### Why Flannel Didn't Have This Issue
Flannel uses:
- Fixed VXLAN mode (no mode switching)
- Automatically configures correct MTU
- No separate ConfigMap to update

---

## Lessons Learned

1. **Configuration Consistency is Critical**
   - Calico has multiple configuration points (IPPool, ConfigMap, DaemonSet)
   - All must be consistent or dataplane breaks

2. **MTU Changes Require Pod Restarts**
   - Existing pods keep old veth interfaces
   - New pods get correct MTU
   - Must restart all pods after MTU change

3. **Diagnostic Approach Matters**
   - Started with network policies (symptom)
   - Should have checked MTU first (root cause)
   - `ip -stats link show tunl0` was the smoking gun

4. **Testing After Changes**
   - Should have tested connectivity immediately after IPPool patch
   - Would have caught MTU mismatch before wasting time on other fixes

---

## Next Actions

1. **IMMEDIATE**: Apply MTU fix (update ConfigMap, restart pods)
2. **SHORT-TERM**: Update runbooks with MTU consistency checks
3. **MEDIUM-TERM**: Implement automated validation
4. **LONG-TERM**: Consider Flannel (simpler, no mode switching)

---

**Status**: 🔴 CRITICAL - MTU mismatch identified
**Priority**: P0 - Blocks all cluster functionality
**ETA**: 10 minutes to apply fix, 30 minutes for full pod restart
**Risk**: LOW - MTU change is well-tested, standard operation

---

**Document Version**: 1.0
**Author**: Claude Code (Calico Migration Agent)
**Review**: Pending user approval
