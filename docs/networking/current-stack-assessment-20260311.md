# Current Stack Assessment - Cluster Nodes & Kubernetes
**Date:** 2026-03-11
**Branch:** feature/ci-cd-pipeline
**Status:** VLANs configured, PVIDs pending, all nodes operational

---

## Executive Summary

**Infrastructure Status:** ✅ Operational
- 4 NixOS cluster nodes running with full connectivity
- 4 TP-Link switches with 802.1Q VLANs configured
- Kubernetes using containerd runtime with Flannel networking
- **Critical Gap:** No VLAN interfaces configured on nodes (all traffic on VLAN 1)

---

## Cluster Node Inventory

| Node | IP | Role | Hardware | Status |
|------|-----|------|----------|--------|
| **zephyr** | 10.1.1.110 | Control Plane + Daily Driver | RTX 3090, Quest Pro | ✅ Online |
| **nexus** | 10.1.1.120 | Storage (NFS) | 8TB HDD array | ✅ Online |
| **forge** | 10.1.1.130 | GPU Compute (AI/Mining) | 5x NVIDIA GPUs | ✅ Online |
| **sentry** | 10.1.1.140 | Monitoring | AMD GPU | ✅ Online |

**Total Resources:** 78 cores, 123GB RAM, 7 GPUs, 8.4TB storage

---

## Network Configuration Stack

### Layer 1: Physical Switching ✅

**Switch Topology:**
```
Modem (10.1.1.1)
  └─ sw1-modem (10.1.1.10) - Root/Gateway
      ├─ sw3-upstairs (10.1.1.12) - Distribution
      │   └─ sw4-zephyr (10.1.1.13) - Zephyr Workstation
      └─ sw2-tv (10.1.1.11) - TV Area (Nexus)
```

**VLAN Configuration:**
- ✅ 802.1Q enabled on all 4 switches
- ✅ 7 VLANs created: 10(gaming), 20(ai), 30(storage), 40(mining), 50(monitoring), 60(backup), 99(management)
- ⚠️ **PVIDs: All ports set to VLAN 1 (default)**

### Layer 2: Node Network Interfaces ⚠️

**Current State:** All nodes using physical interfaces only

| Node | Interface | IP | VLAN Support | Configuration |
|------|-----------|-----|--------------|----------------|
| zephyr | enp38s0 (lan0) | 10.1.1.110/24 | None ❌ | NetworkManager |
| nexus | (unknown) | 10.1.1.120/24 | None ❌ | (needs investigation) |
| forge | (unknown) | 10.1.1.130/24 | None ❌ | (needs investigation) |
| sentry | (unknown) | 10.1.1.140/24 | None ❌ | (needs investigation) |

**Gap:** No `networking.interfaces.<interface>.virtual VLANs` configured anywhere

### Layer 3: Kubernetes Networking ✅

**Flannel Configuration:**
- Backend: **VXLAN** (default)
- Network: **10.244.0.0/16** (pod overlay network)
- **Critical:** Flannel operates on top of host networking, currently on VLAN 1
- **PVID Impact:** When PVIDs are configured, Flannel will need access to management VLAN (99)

---

## Kubernetes Stack Assessment

### Control Plane (Zephyr)

**Configuration Location:** `modules/services/kubernetes.nix`

```nix
services.kubernetes-module = {
  enable = true;
  masterAddress = "10.1.1.110";  # Zephyr
  roles = ["master" "node"];
};
```

**Components:**
- ✅ containerd runtime (switched from CRI-O for NVIDIA GPU support)
- ✅ Flannel VXLAN overlay network
- ✅ k3s as upstream Kubernetes distribution
- ✅ Service account tokens NOT auto-mounted (security)

**Current Services:**
- API Server: 10.1.1.110:6443
- Kubelet API: 10.1.1.110:10250
- Flannel VXLAN: UDP 8472

### Worker Nodes

**Nexus (Storage):**
- Role: Storage node
- Services: NFS likely for persistent storage
- Needs: VLAN 30 (storage), VLAN 60 (backup), VLAN 99 (management)

**Forge (GPU):**
- Role: GPU compute
- Hardware: 5x NVIDIA GPUs
- Needs: VLAN 20 (ai), VLAN 40 (mining), VLAN 99 (management)

**Sentry (Monitoring):**
- Role: Monitoring
- Hardware: AMD GPU
- Services: Prometheus/Grafana likely
- Needs: VLAN 40 (mining), VLAN 50 (monitoring), VLAN 99 (management)

---

## Critical Interface Configuration

### Current Zephyr Configuration

**File:** `hosts/zephyr/configuration.nix`

```nix
networking.networkmanager.ensureProfiles.profiles."Wired connection 1" = {
  connection = {
    interface-name = "lan0";  # Aliased to enp38s0
  };
  ipv4 = {
    method = "manual";
    address1 = "10.1.1.110/24";
    gateway = "10.1.1.1";
  };
};
```

**Required for VLANs:**
```nix
# NOT YET CONFIGURED - Example for Zephyr
networking.interfaces.lan0.virtual VLANs = [99 10 20];
# This would create:
# - lan0.99 (management)
# - lan0.10 (gaming)
# - lan0.20 (ai)
```

---

## VLAN Implementation Requirements

### Per-Node VLAN Configuration

| Node | Required VLANs | Interface | NixOS Configuration Needed |
|------|----------------|-----------|---------------------------|
| **zephyr** | 99, 10, 20 | lan0 | `virtual VLANs = [99 10 20];` |
| **nexus** | 99, 30, 60 | (unknown) | Needs interface discovery + config |
| **forge** | 99, 20, 40 | (unknown) | Needs interface discovery + config |
| **sentry** | 99, 40, 50 | (unknown) | Needs interface discovery + config |

### PVID Configuration (Switches)

| Switch | Port | Device | Required PVID | Current PVID |
|--------|------|--------|---------------|--------------|
| sw1-modem | P1 | Modem | 99 (management) | 1 ⚠️ |
| sw1-modem | P2 | Printer | 10 (gaming) | 1 ⚠️ |
| sw1-modem | P3 | Deco XE75 | 99 (management) | 1 ⚠️ |
| sw1-modem | P4 | sw3-upstairs | 99 (trunk) | 1 ⚠️ |
| sw1-modem | P5 | sw2-tv | 99 (trunk) | 1 ⚠️ |
| sw2-tv | P2 | Nexus | 99 (trunk) | 1 ⚠️ |
| sw3-upstairs | P4 | Sentry | 99 (trunk) | 1 ⚠️ |
| sw3-upstairs | P5 | Forge | 99 (trunk) | 1 ⚠️ |
| sw4-zephyr | P5 | Zephyr | 99 (trunk) | 1 ⚠️ |

**Impact:** With PVIDs = 1, untagged traffic goes to default VLAN. After PVID changes, untagged management traffic goes to VLAN 99.

---

## Implementation Strategy

### Phase 1: Interface Discovery (Current) ⏳

**Tasks:**
- [ ] Identify physical interface names on all 4 nodes
  - [ ] zephyr: `enp38s0` (lan0) ✅
  - [ ] nexus: (unknown)
  - [ ] forge: (unknown)
  - [ ] sentry: (unknown)
- [ ] Document current NetworkManager profiles
- [ ] Verify interface consistency

### Phase 2: VLAN Interface Configuration

**Tasks:**
- [ ] Add `virtual VLANs` to each node's configuration
- [ ] Rebuild and switch each node
- [ ] Verify VLAN interfaces are created (e.g., `lan0.99`)

**Example Configuration:**
```nix
# hosts/zephyr/configuration.nix
networking.interfaces.lan0.virtual VLANs = [99 10 20];
systemd.networks."99-lan0" = {
  matchConfig.Name = "lan0.99";
  networkConfig.Address = "10.1.1.110/24";  # Or different IP if using VLAN subnets
};
```

### Phase 3: PVID Configuration (Switches)

**Tasks:**
- [ ] Configure PVIDs on all 4 switches via web UI
- [ ] Set trunk ports to PVID 99
- [ ] Set access ports to their native VLAN
- [ ] Verify connectivity after PVID changes

### Phase 4: Kubernetes Verification

**Tasks:**
- [ ] Verify Flannel can communicate on management VLAN (99)
- [ ] Test pod-to-pod communication
- [ ] Verify services can reach cluster nodes
- [ ] Test storage access (NFS on nexus)

---

## Risk Assessment

### High Risk Areas

1. **Interface Name Inconsistency**
   - Risk: Different nodes use different interface naming schemes
   - Mitigation: Discover all interfaces before VLAN configuration

2. **NetworkManager vs systemd-networkd**
   - Risk: zephyr uses NetworkManager, other nodes might use different method
   - Mitigation: Check network configuration method on each node

3. **Kubernetes Service Discovery**
   - Risk: Changing IPs/VLANs might break kubelet registration
   - Mitigation: Test cluster functionality after VLAN changes

4. **PVID Configuration Error**
   - Risk: Wrong PVID could isolate a node
   - Mitigation: Test one switch at a time, have rollback plan ready

### Safety Mechanisms

✅ **Complete Backup:** `/etc/nixos/docs/networking/switch-current-settings-20260311.json`
✅ **Rollback Procedure:** Disable 802.1Q on switches
✅ **Test Baseline:** All nodes currently operational with 0% packet loss
✅ **Git History:** All changes committed in atomic groups

---

## Next Steps

### Immediate Actions

1. **Interface Discovery**
   ```bash
   # Run on each node to discover interfaces
   ip -br addr show
   nmcli device status
   ```

2. **Create VLAN Configuration Module**
   - Add per-node VLAN interface configuration
   - Ensure idempotency (safe to rebuild)

3. **Test Plan**
   - Configure one node (e.g., zephyr) first
   - Verify VLAN interfaces created
   - Test connectivity
   - Roll out to other nodes

### Architecture Decision Required

**Q:** Should each node get a VLAN-specific IP, or use same 10.1.1.x IPs on different VLANs?

**Option A: L2-only segmentation (current design)**
- All nodes keep same IPs on all VLANs
- VLANs isolate broadcast domains only
- Simpler IP management

**Option B: L3 routing with VLAN subnets**
- Each VLAN gets different subnet (e.g., 10.99.1.x for management)
- Requires router/gateway for inter-VLAN routing
- More complex but stronger isolation

**Recommendation:** Start with Option A (L2-only) as per original design

---

## Files Created

1. `/etc/nixos/docs/networking/switch-current-settings-20260311.json` - Complete VLAN state backup
2. `/etc/nixos/docs/networking/vlan-test-results-20260311.md` - Test results documentation
3. `/etc/nixos/scripts/tplink-current-settings.py` - Settings capture tool

---

## Commits Created

1. `d008a6b` - fix(switches): update backup scripts with sequential IP addresses
2. `05898d8` - feat(switches): add VLAN backup, rollback, and testing tools
