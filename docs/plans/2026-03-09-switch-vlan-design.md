# TP-Link Switch VLAN Configuration Design

**Date:** 2026-03-09
**Status:** Design Review
**Author:** j_kro

## Executive Summary

Design 7-VLAN segmentation for 4 TP-Link TL-SG105E switches supporting Kubernetes cluster migration. Uses L2-only segmentation (same 10.1.1.0/24 subnet) for optimal 1Gbps performance without routing bottlenecks.

## Network Topology

### Physical Layout (ACTUAL)

```
                    Internet
                       │
                   Modem (10.1.1.1)
                       │
              ┌────────┴────────┐
              │  sw1 Port 1     │
         ┌────┴──────────────────┴────┐
         │                            │
    sw1-modem (10.1.1.10)         XE75 WiFi
    Port 3: Deco XE75
         │
  ┌─────┼───────────┬────────────────────┐
  │     │           │                    │
 P2    P4          P5                  (trunk)
Prn   sw3-uplink  sw2-tv
(10.1.1.12)  (10.1.1.11)
  │              │
  │         ┌────┴────────────────────┐
  │         │ Port 1: Trunk from sw1  │
  │         └────┬─────────┬───────────┘
  │              │         │
  │         ┌────┴────┐  ┌──┴──────────┐
  │         │         │  │             │
  │        Nexus   krash3 krash1.5   [blank]
  │        (10.1.1.120)
  │
  └────────────────────┐
       P2           P4-P5
    sw4-zephyr     Sentry  Forge
   (10.1.1.13)    (10.1.1.140) (10.1.1.130)
       │
  ┌────┴─────────┐
  │ P1    P3   P5
  │ Trk  Deco  Zephyr
  │      XE75   (10.1.1.110)
 [blank] [blank]
```

### Switch Names (CORRECTED - 2026-03-10)

| IP | Name | Location | Notes |
|----|------|----------|-------|
| 10.1.1.90 | sw1-modem | Main area | Root switch ⚠️ CORRECTED |
| 10.1.1.95 | sw2-tv | TV area | Nexus + PCs ⚠️ CORRECTED |
| 10.1.1.12 | sw3-upstairs | Upstairs | Distribution ✅ (was correct) |
| 10.1.1.104 | sw4-zephyr | Zephyr room | Workstation ⚠️ CORRECTED |

### Switch Roles (CORRECTED - 2026-03-10)

| Switch | IP | Role | VLANs Carried |
|--------|-----|------|---------------|
| sw1-modem | 10.1.1.90 | Root/Gateway | All (distribution) ⚠️ |
| sw2-tv | 10.1.1.95 | Access (Nexus) | 99, 30, 60 ⚠️ |
| sw3-upstairs | 10.1.1.12 | Distribution | All ✅ |
| sw4-zephyr | 10.1.1.104 | Access (Zephyr) | All ⚠️ |

## VLAN Design

### VLAN Definitions

| VLAN ID | Name | Purpose | IP Range | Nodes/Devices |
|---------|------|---------|----------|---------------|
| 10 | gaming | VR streaming, gaming | 10.1.1.x | Deco WiFi, gaming PCs |
| 20 | ai | AI/ML workloads | 10.1.1.x | Zephyr, Forge |
| 30 | storage | NFS/cluster storage | 10.1.1.x | Nexus |
| 40 | mining | GPU mining | 10.1.1.x | Forge, Sentry |
| 50 | monitoring | Prometheus/Grafana | 10.1.1.x | Sentry |
| 60 | backup | Backup operations | 10.1.1.x | Nexus |
| 99 | management | K8s control plane | 10.1.1.x | All cluster nodes |

### Node VLAN Membership

| Node | Primary VLAN | Secondary VLANs | Trunked VLANs |
|------|--------------|-----------------|---------------|
| Zephyr | 99 (mgmt) | 10 (gaming), 20 (ai) | 99, 10, 20 |
| Nexus | 99 (mgmt) | 30 (storage), 60 (backup) | 99, 30, 60 |
| Forge | 99 (mgmt) | 20 (ai), 40 (mining) | 99, 20, 40 |
| Sentry | 99 (mgmt) | 40 (mining), 50 (monitoring) | 99, 40, 50 |

### IP Addressing Strategy

**Single Subnet (L2-only segmentation):**
- All devices: `10.1.1.0/24`
- VLANs isolate broadcast domains only
- No inter-VLAN routing required
- Full 1Gbps wire speed maintained

**Benefits:**
- No IP reconfiguration needed
- Kubernetes Flannel works seamlessly
- No routing bottleneck
- Simpler firewall rules

## Port Configuration

### Port Configuration Principles

1. **Trunk Ports** (between switches):
   - Carry multiple VLANs with 802.1Q tags
   - Tagged for all VLANs they carry
   - Native VLAN 99 (untagged) for management

2. **Access Ports** (end devices):
   - Untagged traffic to native VLAN
   - Device primarily on one VLAN

3. **Hybrid Ports** (cluster nodes):
   - Trunked to management + workload VLANs
   - Untagged on management VLAN (99) for switch management access

### ACTUAL Port Configuration

```
sw1-modem (10.1.1.90) - ROOT SWITCH ⚠️ CORRECTED IP
  Port 1: Modem/Gateway (trunk: all VLANs)
  Port 2: Printer (VLAN 10 - gaming/work)
  Port 3: Deco XE75 WiFi (VLAN 10, 99 - gaming + management)
  Port 4: sw3-upstairs TRUNK (trunk: all VLANs)
  Port 5: sw2-tv TRUNK (trunk: 99, 30, 60 - management + storage + backup)

sw2-tv (10.1.1.95) - TV AREA SWITCH ⚠️ CORRECTED IP
  Port 1: sw1-modem TRUNK (trunk: 99, 30, 60)
  Port 2: Nexus (trunk: 99, 30, 60 - management + storage + backup)
  Port 3: krash3 PC (VLAN 10 - gaming)
  Port 4: krash1.5 PC (VLAN 10 - gaming)
  Port 5: [blank - available]

sw3-upstairs (10.1.1.12) - UPSTAIRS SWITCH
  Port 1: sw1-modem TRUNK (trunk: all VLANs)
  Port 2: sw4-zephyr TRUNK (trunk: all VLANs)
  Port 3: WIP PC (VLAN 10 - gaming, or 99 for management)
  Port 4: Sentry (trunk: 99, 40, 50 - management + mining + monitoring)
  Port 5: Forge (trunk: 99, 20, 40 - management + AI + mining)

sw4-zephyr (10.1.1.104) - ZEPHYR ROOM SWITCH ⚠️ CORRECTED IP
  Port 1: sw3-upstairs TRUNK (trunk: all VLANs)
  Port 2: [blank - available]
  Port 3: Deco XE75 WiFi 6GHz (VLAN 10, 99 - Quest Pro + management)
  Port 4: [blank - available]
  Port 5: Zephyr (trunk: 99, 10, 20 - management + gaming + AI)
```

### Device-to-VLAN Mapping

| Device | Location | Port | VLAN(s) | Tagged | Notes |
|--------|----------|------|---------|--------|-------|
| Modem | sw1:P1 | sw1:1 | all | yes | Uplink to internet |
| Printer | sw1:P2 | sw1:2 | 10 | no | Gaming/work VLAN |
| Deco XE75 | sw1:P3 | sw1:3 | 10, 99 | yes | WiFi + management |
| sw3-upstairs | sw1:P4 | sw1:4 | all | yes | Distribution trunk |
| sw2-tv | sw1:P5 | sw1:5 | 99, 30, 60 | yes | TV area trunk |
| Nexus | sw2:P2 | sw2:2 | 99, 30, 60 | yes | Storage node |
| krash3 | sw2:P3 | sw2:3 | 10, 40 | yes | Gaming + mining PC |
| krash1.5 | sw2:P4 | sw2:4 | 10, 40 | yes | Gaming + mining PC |
| sw4-zephyr | sw3:P2 | sw3:2 | all | yes | Distribution trunk |
| WIP PC | sw3:P3 | sw3:3 | 99 (or 10) | no | Spare PC |
| Sentry | sw3:P4 | sw3:4 | 99, 40, 50 | yes | Monitoring node |
| Forge | sw3:P5 | sw3:5 | 99, 20, 40 | yes | AI + mining node |
| Deco XE75 6GHz | sw4:P3 | sw4:3 | 10, 99 | yes | Quest Pro WiFi |
| Zephyr | sw4:P5 | sw4:5 | 99, 10, 20 | yes | Main workstation |

## Implementation Plan

### Phase 1: Discovery ✓ COMPLETE
- [x] Explore switch configurations
- [x] Verify switch accessibility
- [x] Identify VLAN capabilities
- [x] Map physical port connections
- [x] Document all connected devices

### Phase 2: Pre-Configuration Backup
- [ ] Take screenshots of all switch configuration pages
- [ ] Document current state
- [ ] Save switch configurations locally

### Phase 3: Configuration
- [ ] Enable 802.1Q VLAN on all switches
- [ ] Create 7 VLANs on each switch (10, 20, 30, 40, 50, 60, 99)
- [ ] Configure trunk ports (inter-switch links):
  - [ ] sw1:P4 → sw3:P2 (all VLANs)
  - [ ] sw1:P5 → sw2:P1 (VLANs 99, 30, 60)
  - [ ] sw3:P2 → sw4:P1 (all VLANs)
- [ ] Configure access ports:
  - [ ] Printer → VLAN 10
  - [ ] krash3, krash1.5 → VLAN 10
  - [ ] WIP PC → VLAN 99
- [ ] Configure hybrid ports (cluster nodes):
  - [ ] Nexus (sw2:P2) → VLANs 99, 30, 60 (trunked)
  - [ ] Sentry (sw3:P4) → VLANs 99, 40, 50 (trunked)
  - [ ] Forge (sw3:P5) → VLANs 99, 20, 40 (trunked)
  - [ ] Zephyr (sw4:P5) → VLANs 99, 10, 20 (trunked)
- [ ] Configure WiFi APs:
  - [ ] Deco XE75 (sw1:P3) → VLANs 10, 99 (tagged)
  - [ ] Deco XE75 6GHz (sw4:P3) → VLANs 10, 99 (tagged)

### Phase 4: Verification
- [ ] Test connectivity between all cluster nodes
  - [ ] Zephyr ↔ Nexus
  - [ ] Zephyr ↔ Forge
  - [ ] Zephyr ↔ Sentry
  - [ ] All-to-all ping test
- [ ] Verify VLAN segmentation (cross-VLAN isolation)
- [ ] Test Kubernetes Flannel overlay
- [ ] Verify service discovery
- [ ] Test internet connectivity through modem

### Phase 5: Documentation
- [x] Update network diagrams
- [x] Document port mappings
- [ ] Create runbook for switch management
- [ ] Update CLAUDE.md with VLAN workflows

## Configuration Commands

### Enable VLAN on Single Switch

```bash
# Using the automation script
python3 /etc/nixos/scripts/tplink-configure-vlans.py --verify
python3 /etc/nixos/scripts/tplink-configure-vlans.py --apply
```

### Manual Web UI Steps

1. Login to switch web interface
2. Navigate to VLAN > 802.1Q VLAN
3. Enable 802.1Q VLAN
4. Create each VLAN with ID and name
5. Configure port membership for each VLAN

## Rollback Plan

If VLAN configuration causes issues:

1. **Immediate Rollback:**
   - Access switch via web interface
   - Disable 802.1Q VLAN globally
   - All ports return to default VLAN

2. **Factory Reset:**
   - Hold reset button for 10 seconds
   - Reconfigure with working settings

3. **Backup Before Apply:**
   - Screenshot each configuration page before changes
   - Document current settings

## Success Criteria

- [ ] All cluster nodes can communicate on VLAN 99
- [ ] Kubernetes cluster functions normally
- [ ] Cross-VLAN isolation verified
- [ ] Service discovery working
- [ ] No performance degradation
- [ ] Documentation complete

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| VLAN misconfiguration isolates cluster | HIGH | Screenshot before changes, have rollback plan |
| TP-Link UI limitations | MEDIUM | Use Playwright automation for consistency |
| Port mapping errors | MEDIUM | Verify physical connections before apply |
| Flannel overlay issues | LOW | Test thoroughly after configuration |
| Lost switch access | MEDIUM | Keep one port on native VLAN for management |

## Open Questions

1. **Exact port mappings** - Pending physical verification
2. **WiFi devices** - How are Deco gateways configured for VLANs?
3. **Non-cluster PCs** - Which VLAN should they be on?
4. **Additional devices** - Any other wired devices to account for?

## References

- ROADMAP.md - Kubernetes migration plan
- modules/services/tplink-switches.nix - Switch automation module
- scripts/tplink - Switch CLI tool
- docs/tplink-switches.md - Switch documentation

---

**Next Steps:**
1. User verifies physical port connections
2. Update port mapping section above
3. Review and approve design
4. Run configuration script
5. Verify cluster functionality
