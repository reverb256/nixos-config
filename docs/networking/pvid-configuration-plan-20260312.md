# PVID Configuration Plan - TP-Link Switches
**Date:** 2026-03-12
**Status:** Ready for Implementation
**Current State:** All PVIDs = 1 (default VLAN)

---

## Executive Summary

**Goal:** Configure Port VLAN IDs (PVIDs) on all 4 TP-Link switches to direct untagged traffic to the appropriate VLANs. This completes the VLAN segmentation implementation.

**Current State:**
- ✅ 802.1Q enabled on all switches
- ✅ All 7 VLANs created (10, 20, 30, 40, 50, 60, 99)
- ❌ All PVIDs set to 1 (default) - **needs configuration**

**Impact:**
- Untagged management traffic currently goes to VLAN 1
- After PVID config: Untagged traffic goes to VLAN 99 (management)
- Tagged trunk ports carry all necessary VLANs

---

## VLAN Design Reference

| VLAN | Name | Purpose | Native/Untagged Devices |
|------|------|---------|------------------------|
| **99** | Management | Cluster management, nodes | All cluster nodes |
| **10** | Gaming | Gaming network | Printer |
| **20** | AI | AI/ML workloads | None (tagged only) |
| **30** | Storage | NFS storage | None (tagged only) |
| **40** | Mining | GPU mining | None (tagged only) |
| **50** | Monitoring | Prometheus/Grafana | None (tagged only) |
| **60** | Backup | Backup traffic | None (tagged only) |
| **1** | Default | Fallback VLAN | **Unused after migration** |

---

## Switch-by-Switch PVID Configuration

### SW1-MODEM (10.1.1.10) - Root/Gateway Switch

**Role:** Top of tree, connects to modem and distribution switches

| Port | Device | Current PVID | Target PVID | VLANs Tagged | Rationale |
|------|--------|--------------|-------------|--------------|-----------|
| **P1** | Modem (10.1.1.1) | 1 | **99** | - | Management traffic |
| **P2** | Printer | 1 | **10** | 99 (tagged) | Gaming VLAN, mgmt access |
| **P3** | **EMPTY/UNUSED** | 1 | **1** | - | Previously Deco, now unused |
| **P4** | sw3-upstairs | 1 | **99** | All | Trunk - all VLANs |
| **P5** | sw2-tv | 1 | **99** | 30,60,99 | Trunk - storage VLANs |

**PVID Commands (via web UI or API):**
```
Port 1: PVID = 99
Port 2: PVID = 10
Port 3: PVID = 1  # UNUSED - leave as default
Port 4: PVID = 99
Port 5: PVID = 99
```

**Special Notes:**
- **P3 is now EMPTY** - Deco XE75 moved to direct modem connection
- P2 (Printer): Access port for VLAN 10, but VLAN 99 tagged for management access
- P4, P5: Trunk ports carry multiple VLANs, PVID = 99 for management

---

### SW2-TV (10.1.1.11) - TV Area Branch

**Role:** Connects nexus (storage node)

| Port | Device | Current PVID | Target PVID | VLANs Tagged | Rationale |
|------|--------|--------------|-------------|--------------|-----------|
| **P1** | sw1-modem | 1 | **99** | 30,60,99 | Trunk uplink |
| **P2** | Nexus (storage) | 1 | **99** | 30,60,99 | Trunk - storage node |

**PVID Commands:**
```
Port 1: PVID = 99
Port 2: PVID = 99
```

**Special Notes:**
- Nexus needs VLAN 30 (storage), VLAN 60 (backup), and VLAN 99 (management)
- PVID = 99 ensures untagged management traffic works

---

### SW3-UPSTAIRS (10.1.1.12) - Distribution Switch

**Role:** Distributes to forge, sentry, and sw4-zephyr

| Port | Device | Current PVID | Target PVID | VLANs Tagged | Rationale |
|------|--------|--------------|-------------|--------------|-----------|
| **P1** | sw1-modem (uplink) | 1 | **99** | All | Trunk uplink to root |
| **P2** | sw4-zephyr | 1 | **99** | All | Trunk to Zephyr switch |
| **P3** | Spare for projects | 1 | **1** | 99 | Spare port, default VLAN |
| **P4** | Sentry (monitoring) | 1 | **99** | 40,50,99 | Monitoring node |
| **P5** | Forge (GPU) | 1 | **99** | 20,40,99 | GPU compute node |

**PVID Commands:**
```
Port 1: PVID = 99
Port 2: PVID = 99
Port 3: PVID = 1
Port 4: PVID = 99
Port 5: PVID = 99
```

**Special Notes:**
- P2: Trunk port to sw4-zephyr (carries all VLANs for Zephyr)
- P3: Spare port for future projects, PVID 1 (default) with VLAN 99 tagged for management access
- All cluster nodes use PVID 99 for management traffic

---

### SW4-ZEPHYR (10.1.1.13) - Zephyr End Switch

**Role:** Connects zephyr workstation and WiFi AP

| Port | Device | Current PVID | Target PVID | VLANs Tagged | Rationale |
|------|--------|--------------|-------------|--------------|-----------|
| **P1** | sw3-upstairs (uplink) | 1 | **99** | All | Trunk uplink |
| **P3** | WiFi AP | 1 | **99** | - | Access point management |
| **P5** | Zephyr (control plane) | 1 | **99** | 10,20,99 | Control plane + daily driver |

**PVID Commands:**
```
Port 1: PVID = 99
Port 3: PVID = 99
Port 5: PVID = 99
```

**Special Notes:**
- P3: WiFi AP for coverage (same as sw1-modem P3)
- Both APs on PVID 99 for consistent management

**Special Notes:**
- Zephyr is the Kubernetes master node
- Needs management (99), gaming (10), AI (20) VLANs
- PVID 99 ensures cluster management works

---

## PVID Configuration Summary

### Before Configuration
```
All switches: PVIDs = [1, 1, 1, 1, 1]
All untagged traffic → VLAN 1 (default)
```

### After Configuration

| Switch | P1 | P2 | P3 | P4 | P5 |
|--------|-----|-----|-----|-----|-----|
| **sw1-modem** | 99 | 10 | **1** (unused) | 99 | 99 |
| **sw2-tv** | 99 | 99 | - | - | - |
| **sw3-upstairs** | 99 | 99 | 1 | 99 | 99 |
| **sw4-zephyr** | 99 | - | 99 | - | 99 |

**All untagged traffic → VLAN 99 (management)**

---

## Implementation Strategy

### Phase 1: Preparation (Current)

✅ **Complete:**
- Current state backed up (switch-current-settings-20260311.json)
- VLAN configuration verified
- PVID plan documented
- Rollback procedure documented

⏳ **Pending:**
- [ ] Review plan with user
- [ ] Schedule maintenance window (optional, changes are non-disruptive)

---

### Phase 2: PVID Configuration

**Order of Operations:**
1. **Start with leaf switches** (sw4-zephyr, sw2-tv)
2. **Move to distribution** (sw3-upstairs)
3. **Finish with root** (sw1-modem)

**Rationale:** Changes at leaf switches have less impact if issues arise

**Configuration Method:**
- **Option A:** Web UI (VLAN → 802.1Q PVID Configuration)
- **Option B:** API calls (for automation)
- **Recommended:** Web UI for safety and verification

---

### Phase 3: Verification

**Per-Switch Tests:**

```bash
# After each switch PVID change
echo "Testing connectivity..."

# Test switch management
ping -c 3 10.1.1.10  # sw1-modem
ping -c 3 10.1.1.11  # sw2-tv
ping -c 3 10.1.1.12  # sw3-upstairs
ping -c 3 10.1.1.13  # sw4-zephyr

# Test cluster nodes
ping -c 3 10.1.1.110  # zephyr
ping -c 3 10.1.1.120  # nexus
ping -c 3 10.1.1.130  # forge
ping -c 3 10.1.1.140  # sentry

# Test Kubernetes (from zephyr)
kubectl get nodes
kubectl get pods -A
```

**Expected Results:**
- ✅ All switches reachable on 10.1.1.x (VLAN 99)
- ✅ All cluster nodes reachable
- ✅ Kubernetes cluster functional
- ✅ 0% packet loss

---

### Phase 4: VLAN Verification (Optional)

**If VLAN interfaces configured on nodes:**

```bash
# On zephyr (after VLAN interfaces configured)
ip addr show enp38s0.99
ping -c 3 10.1.1.120  # Should work on VLAN 99

# Test gaming VLAN isolation (if enp38s0.10 configured)
ip addr show enp38s0.10
# Verify printer access on VLAN 10
```

---

## Risk Assessment

### Low Risk ✅

**Why This Is Safe:**

1. **Non-Disruptive:** PVID changes affect untagged traffic only
2. **Backward Compatible:** Cluster already works on VLAN 1
3. **Easy Rollback:** Can set PVIDs back to 1 in <2 minutes
4. **No Data Loss:** Only affects VLAN tagging, not data
5. **Tested Baseline:** Current configuration fully functional

### Potential Issues & Mitigations

| Issue | Likelihood | Impact | Mitigation |
|-------|-----------|--------|------------|
| **Switch becomes unreachable** | Low | Medium | Use console cable or power cycle |
| **Cluster connectivity lost** | Very Low | High | Rollback PVIDs to 1 immediately |
| **VLAN mismatch** | Low | Low | Verify port membership before changing |
| **Printer inaccessible** | Low | Low | Reconfigure P2 PVID or add VLAN 99 |

---

## Rollback Procedure

### Quick Rollback (< 2 minutes)

**If any issues occur:**

1. **Access switch web UI:** http://10.1.1.XX
2. **Navigate:** VLAN → 802.1Q PVID Configuration
3. **Reset all PVIDs:** Set all ports back to PVID = 1
4. **Apply changes**
5. **Verify:** Ping all switches and nodes

**Or via API:**
```bash
# Reset all PVIDs to 1
curl "http://10.1.1.10/pvidSet.cgi?port1Pvid=1&port2Pvid=1&port3Pvid=1&port4Pvid=1&port5Pvid=1&pvid_apply=Apply"
# Repeat for other switches
```

---

## Configuration Steps (Web UI)

### For Each Switch:

1. **Login:** http://10.1.1.XX (admin credentials)
2. **Navigate:** VLAN → 802.1Q PVID Configuration
3. **For each port:**
   - Find the row for the port
   - Change PVID value to target VLAN
   - Example: Port 1 → PVID = 99
4. **Click:** Apply
5. **Wait:** 3-5 seconds for switch to process
6. **Verify:** Switch remains reachable

**Configuration Time:** ~2 minutes per switch
**Total Time:** ~8-10 minutes for all 4 switches

---

## Expected Behavior After Configuration

### What Will Change 🔄

1. **Untagged Traffic:** Now goes to VLAN 99 instead of VLAN 1
2. **Switch Management:** Still on 10.1.1.x (VLAN 99)
3. **Cluster Traffic:** Now on management VLAN (proper segmentation)
4. **Broadcast Domains:** Separated by VLAN (better security)

### What Will Stay The Same ✅

1. **IP Addresses:** All devices keep 10.1.1.x IPs
2. **Tagged VLANs:** Unchanged (already configured)
3. **Port Membership:** Tagged/untagged port assignments unchanged
4. **Cluster Services:** Kubernetes, NFS, etc. continue working
5. **Internet Access:** Unaffected

---

## Post-Configuration Checklist

### Immediately After PVID Changes

- [ ] All 4 switches reachable (ping 10.1.1.10-13)
- [ ] All 4 cluster nodes reachable (ping 10.1.1.110, 120, 130, 140)
- [ ] 0% packet loss in all tests
- [ ] Switch web UIs accessible

### Cluster Verification

- [ ] Kubernetes: `kubectl get nodes` shows all Ready
- [ ] Kubernetes: `kubectl get pods -A` shows Running/Completed
- [ ] Flannel: VXLAN endpoints communicating (UDP 8472)
- [ ] NFS: Storage accessible on nexus
- [ ] Tailscale: VPN connections active

### Documentation

- [ ] Update switch-current-settings-YYYYMMDD.json with new PVIDs
- [ ] Document actual PVIDs applied
- [ ] Update network topology diagrams
- [ ] Commit changes to git

---

## Deco XE75 VLAN Limitations

### Current Constraints

The Deco XE75 WiFi access point has significant VLAN limitations:
- **No VLAN tagging support** for main network SSIDs
- **Guest network only** can be assigned to separate VLAN (hardcoded, unknown ID)
- **Consumer-grade equipment** designed for home use, not enterprise segmentation

### Impact on Network Design

**WiFi Traffic Segmentation:**
- ✅ **Wired devices**: Properly segmented by VLAN (nodes, storage, mining, etc.)
- ❌ **WiFi devices**: NOT properly segmented - all on same broadcast domain (VLAN 99)
- ⚠️ **Guest WiFi**: May be on separate VLAN but ID unknown, cannot configure

**Security Implications:**
- WiFi clients (phones, laptops, IoT) can reach all cluster services on VLAN 99
- No isolation between different types of WiFi devices
- Guest devices may have access to management network

### Recommendations

**Short-term (Current Setup):**
1. Document Deco XE75 limitations
2. Keep PVID 99 for Deco (ensures it works)
3. Monitor WiFi network access
4. Consider using wired connections for sensitive workloads

**Long-term (Future Upgrade):**
1. **Replace Deco XE75** with enterprise AP:
   - **TP-Link Omada EAP** series (same ecosystem, proper VLAN support)
   - **Ubiquiti UniFi** APs (mature VLAN tagging, roaming)
   - **Aruba Instant** (enterprise-grade, affordable)
2. **Configure multiple SSIDs** mapped to VLANs:
   - "Cluster-Mgmt" → VLAN 99 (administration)
   - "Cluster-Gaming" → VLAN 10 (gaming/entertainment)
   - "Cluster-IoT" → VLAN 99 or isolated IoT VLAN
3. **Enable VLAN tagging** on AP trunk port

**Cost Estimate (Enterprise AP Upgrade):**
- TP-Link Omada EAP670: ~$150-200
- Ubiquiti UniFi U6 Pro: ~$350-400
- Aruba Instant On AP22: ~$150-200

---

## Next Steps After PVID Configuration

### Phase 5: VLAN Interface Configuration (Nodes)

**Once PVIDs are configured and verified:**

1. **Configure VLAN interfaces on nodes:**
   ```nix
   # Example for zephyr
   networking.interfaces.enp38s0.virtual VLANs = [99 10 20];
   ```

2. **Test VLAN isolation:**
   - Verify management traffic on VLAN 99
   - Test gaming VLAN (10) connectivity
   - Test AI VLAN (20) connectivity

3. **Update documentation:**
   - Mark PVID configuration complete
   - Document VLAN interface assignments

---

## VLAN Trunk Summary

### Trunk Ports (Carry Multiple VLANs)

| Switch | Port | Connected To | VLANs Tagged | PVID |
|--------|------|--------------|--------------|------|
| sw1-modem | P4 | sw3-upstairs | All | 99 |
| sw1-modem | P5 | sw2-tv | 30,60,99 | 99 |
| sw3-upstairs | P1 | sw1-modem | All | 99 |
| sw4-zephyr | P1 | sw3-upstairs | All | 99 |
| sw2-tv | P1 | sw1-modem | 30,60,99 | 99 |

**Note:** All trunk ports use PVID 99 for management traffic

---

## Access Port Summary

### Access Ports (Single VLAN + Management Tagged)

| Switch | Port | Device | Native VLAN | Tagged VLANs | Notes |
|--------|------|--------|-------------|--------------|-------|
| sw1-modem | P2 | Printer | 10 (gaming) | 99 (mgmt) | - |
| sw4-zephyr | P3 | WiFi AP | 99 (mgmt) | - | - |

**Deco XE75 WiFi AP:**
- **Location:** Directly connected to modem port 2 (NOT via sw1-modem)
- **Bypasses managed switches:** Not part of VLAN segmentation
- **Guest VLAN:** Uses VLAN 591 (handled by modem, not sw1-modem)
- **Main network:** Uses modem's NAT/gateway mode
- **Implication:** WiFi devices NOT on managed network VLANs

**Deco XE75 Limitations:**
- Consumer-grade AP with limited VLAN support
- Guest network uses **VLAN 591** (hardcoded, not configurable)
- Main network is untagged (uses native VLAN of switch port, will be PVID 99)
- Cannot properly segment WiFi traffic by VLAN
- Recommendation: Upgrade to enterprise AP (UniFi, Omada, etc.) for proper VLAN support

**Note:** Access ports provide device-specific VLAN while maintaining management access

---

## Files Created/Updated

1. `/etc/nixos/docs/networking/pvid-configuration-plan-20260312.md` - This document
2. `/etc/nixos/docs/networking/switch-current-settings-20260311.json` - Current state backup

**Will Create After Configuration:**
3. `/etc/nixos/docs/networking/switch-pvid-configured-20260312.json` - Post-configuration state
4. `/etc/nixos/docs/networking/pvid-test-results-20260312.md` - Test results

---

**Status:** ✅ Ready for implementation
**Estimated Time:** 10-15 minutes for all 4 switches
**Risk Level:** Low (fully reversible)
**User Approval Required:** Yes
