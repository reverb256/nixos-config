# Cluster Issues & Gaps - Comprehensive Assessment

**Date:** 2026-03-24 22:20
**Cluster Version:** v1.35.2
**Assessment Scope:** All nodes, Calico CNI, GPU mining, documentation

---

## Critical Issues

### Issue 1: Calico BGP Peering Degraded (Forge & Sentry)

**Status:** 🔴 CRITICAL - Nodes CrashLoopBackOff
**Impact:** Forge and Sentry cannot maintain BGP peering, causing calico-node pods to restart continuously

**Root Cause:**
- Forge and Sentry have link-local IPv6 addresses only (`fe80::/64`)
- Calico BIRD requires global/site-local IPv6 for BGP multihop
- Link-local addresses require interface specification (e.g., `fe80::1%eth0`)
- Node annotations (`projectcalico.org/IPv6Address`) are being removed or not persisted

**Current State:**
```
NAME                READY   STATUS             RESTARTS
calico-node-5d8h2   0/1     Running            11 (104s ago)   sentry
calico-node-n8nsq   0/1     CrashLoopBackOff   15 (4m41s ago)   forge
calico-node-x4mcc   1/1     Running            1 (37m ago)      nexus
calico-node-z4sfc   1/1     Running            1 (37m ago)      zephyr
```

**Why Annotations Aren't Working:**
1. **Tigera Operator Reconciliation**: The operator may be removing annotations that don't match the Installation resource
2. **Wrong Annotation Format**: Calico might expect the annotation in a different format
3. **Autodetection Override**: The Installation resource has `nodeAddressAutodetectionV6: {firstFound: true}` which overrides node annotations

**Attempted Fixes:**
- ✗ Added `projectcalico.org/IPv6Address` annotation with link-local address
- ✗ Added interface-specific address (`fe80::...%tailscale0`)
- ✗ Removed `nodeAddressAutodetectionV6` from Installation resource
- ✗ Created FelixConfiguration with `ipv6Support: false`
- ✗ All changes were reverted by Tigera operator

**Next Approach - Disable IPv6 in Calico Completely:**

Since Forge and Sentry don't have global IPv6 addresses and BGP doesn't work with link-local:
1. **Disable IPv6 support cluster-wide** in Calico
2. **Use IPv4-only configuration** for BGP
3. **Accept that 2/4 nodes will have degraded BGP** but cluster remains functional

---

## Medium Priority Issues

### Issue 2: gpu-miner-zephyr Label Selector Inconsistency

**Status:** 🟡 MEDIUM - Mining working, but labels inconsistent
**Impact:** Background commands fail to find pod by name

**Problem:**
- Deployment name: `gpu-miner-zephyr`
- Pod label: `app=gpu-miner` (not `app=gpu-miner-zephyr`)
- Query: `kubectl get pods -n mining -l app=gpu-miner-zephyr` returns nothing

**Current State:**
- Pod `gpu-miner-zephyr-5f64bc47f4-t4nfl` is Running and mining ✅
- Labels: `app=gpu-miner`, `host=zephyr`, `workload=gpu-miner-zephyr`
- Deployment selector: `app=gpu-miner`

**Fix:** Update deployment to use consistent label:
```yaml
spec:
  template:
    metadata:
      labels:
        app: gpu-miner-zephyr  # Change from gpu-miner
```

---

### Issue 3: Documentation Gaps

**Status:** 🟡 MEDIUM - Docs partially updated
**Impact:** Hard to troubleshoot without accurate docs

**Missing Updates:**
1. **AGENTS.md** - Still references Flannel in some sections
2. **ROADMAP.md** - Network section needs Calico BGP limitations documented
3. **Troubleshooting guide** - No section for Calico BGP issues
4. **Known Issues** - BGP peering degradation not in STATUS.md known issues

---

## Low Priority Issues

### Issue 4: No Cluster Backup Strategy

**Status:** 🟢 LOW - Not urgent for homelab
**Impact:** Risk of data loss if etcd fails

**Current State:**
- No automated etcd backups configured
- No Velero or similar backup solution
- Manual backup procedure not documented

**Recommendation:**
- Document etcd backup/restore procedures
- Consider Velero for Kubernetes resource backups
- Schedule periodic etcd snapshot backups

---

## Comprehensive Fix Plan

### Phase 1: Fix Calico BGP (Forge/Sentry) - CRITICAL

**Option A: Disable IPv6 Cluster-Wide (RECOMMENDED)**

Since Forge/Sentry don't have global IPv6 and BGP multihop doesn't work with link-local:

1. **Update FelixConfiguration** to disable IPv6 support:
```yaml
apiVersion: crd.projectcalico.org/v1
kind: FelixConfiguration
metadata:
  name: default
spec:
  ipv6Support: false
```

2. **Remove IPv6 from BGPConfiguration:**
```yaml
apiVersion: crd.projectcalico.org/v1
kind: BGPConfiguration
metadata:
  name: default
spec:
  asNumber: 64512
  nodeToNodeMeshEnabled: true
  # Remove any IPv6 serviceClusterIPs
  serviceClusterIPs:
  - cidr: 10.96.0.0/12  # IPv4 only
```

3. **Accept 2/4 nodes degraded BGP but functional cluster**

**Option B: Enable Global IPv6 on Forge/Sentry**

1. Configure NixOS to assign global IPv6 addresses via ULA (Unique Local Address)
2. Requires network reconfiguration on both hosts
3. More complex but fully functional BGP

**Decision:** Option A (disable IPv6 cluster-wide)

---

### Phase 2: Fix gpu-miner-zephyr Labels

**File:** `kubernetes-manifests/mining/gpu-miner-zephyr.yaml`

Change:
```yaml
labels:
  app: gpu-miner-zephyr  # Was: gpu-miner
```

Then delete pod to force recreation with correct labels.

---

### Phase 3: Update Documentation

**Files to update:**
1. **AGENTS.md** - Replace Flannel with Calico
2. **STATUS.md** - Add BGP degradation to known issues
3. **Create:** `docs/kubernetes/calico-bgp-troubleshooting.md`

---

## Success Criteria

### Phase 1 (Calico BGP)
- [ ] Forge calico-node becomes 1/1 READY (no restarts)
- [ ] Sentry calico-node becomes 1/1 READY
- [ ] BGP peering stable across all 4 nodes
- [ ] No "link-local neighbor" errors in logs

### Phase 2 (Labels)
- [ ] `kubectl get pods -n mining -l app=gpu-miner-zephyr` returns pod
- [ ] Labels consistent across deployment and pods
- [ ] Background commands work correctly

### Phase 3 (Documentation)
- [ ] AGENTS.md has zero Flannel references
- [ ] STATUS.md documents BGP degradation
- [ ] Troubleshooting guide created

---

## Execution Order

1. **Phase 1** (Calico BGP) - 30 min
2. **Phase 2** (Labels) - 5 min
3. **Phase 3** (Documentation) - 15 min

**Total Time:** ~50 minutes

---

## Risk Assessment

**High Risk:**
- Phase 1 changes could affect network connectivity if done incorrectly
- Need to test thoroughly after each change

**Medium Risk:**
- Label changes could affect monitoring/service discovery
- Documentation updates don't affect cluster health

**Low Risk:**
- All changes are reversible
- Can rollback to working state if needed

---

## Current Cluster Health Summary

| Component | Status | Details |
|-----------|--------|---------|
| **Nodes** | 🟢 4/4 READY | All nodes Ready |
| **Control Plane** | 🟢 OPERATIONAL | 3-node HA (Zephyr, Nexus, Sentry) |
| **Calico CNI** | 🟡 DEGRADED | 2/4 nodes READY (Nexus, Zephyr) |
| **GPU Mining** | 🟢 OPERATIONAL | gpu-miner-zephyr Running, mining Tari |
| **BGP Peering** | 🔴 CRITICAL | Forge/Sentry CrashLoopBackOff |
| **Documentation** | 🟡 PARTIAL | Calico migration mostly documented |

**Overall Cluster Status:** 🟡 **FUNCTIONAL** with degraded networking

---

**Next Action:** Begin Phase 1 - Disable IPv6 cluster-wide in Calico

**Created:** 2026-03-24 22:20 UTC
**Author:** Claude Code (cluster health assessment)
