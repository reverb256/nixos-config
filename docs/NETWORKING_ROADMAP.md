# Network Management Roadmap

**Status**: Active | **Last Updated**: 2026-03-10 | **Version**: 1.0

## Executive Summary

This roadmap tracks the harmonization and standardization of network configuration across all cluster nodes (Zephyr, Nexus, Forge, Sentry). The goal is consistent, declarative networking with minimal manual intervention and clear separation of concerns.

---

## Completed Work ✅

### Phase 1: Interface Naming Harmonization (COMPLETED)

**Problem**: Cluster nodes had inconsistent ethernet interface names:
- Zephyr: `enp38s0`
- Nexus: `enp7s0`
- Forge: `eno1`
- Sentry: `enp7s0`

This caused confusion, hardcoded values in configs, and made VLAN planning difficult.

**Solution**: Implemented MAC address-based persistent interface naming using `systemd.network.links`.

**Deliverables**:
- ✅ Created `/etc/nixos/modules/system/interface-naming.nix`
  - Maps MAC addresses to consistent `lan0` name across all nodes
  - Uses `matchConfig.MACAddress` for reliable identification
  - Applied to all 4 cluster nodes

**Files Modified**:
- `modules/system/interface-naming.nix` (CREATED)
- `modules/default.nix` (added interface-naming.nix to imports)
- `modules/system/networking.nix` (updated Avahi allowInterfaces for transition)

**Deployment Status**:
- [ ] Zephyr (10.1.1.110) - Ready to deploy
- [ ] Nexus (10.1.1.120) - Ready to deploy
- [ ] Forge (10.1.1.130) - Ready to deploy
- [ ] Sentry (10.1.1.140) - Ready to deploy

**Next Action**: Deploy to all nodes and verify `lan0` appears in `ip link show`

---

### Phase 2: NetworkManager Profile Harmonization (COMPLETED)

**Problem**: NetworkManager configurations were inconsistent:
- Zephyr: No explicit NetworkManager profile (relying on DHCP/fallback)
- Nexus: Had profile with hardcoded `interface-name = "enp7s0"`
- Sentry: Had profile with hardcoded `interface-name = "enp7s0"`
- Forge: Had profile but missing explicit `interface-name`

This caused **complete network failure on Sentry** after reboot when systemd.link renamed the interface but NetworkManager couldn't find the old name.

**Solution**: Standardized all NetworkManager profiles with explicit `interface-name = "lan0"`

**Deliverables**:
- ✅ All nodes have consistent NetworkManager ensureProfiles configuration
- ✅ All profiles explicitly declare `interface-name = "lan0"`
- ✅ All profiles enable `autoconnect = true`
- ✅ All profiles configure IPv6 autoconfiguration
- ✅ All profiles point DNS to local Unbound (127.0.0.1, ::1)

**Files Modified**:
- `hosts/zephyr/configuration.nix` (added NetworkManager profile, updated firewall rules)
- `hosts/nexus/configuration.nix` (updated interface-name to "lan0")
- `hosts/sentry/configuration.nix` (updated interface-name to "lan0")
- `hosts/forge/configuration.nix` (added explicit interface-name, IPv6, autoconnect)

**Configuration Standard**:
```nix
networking.networkmanager.ensureProfiles.profiles."Wired connection 1" = {
  connection = {
    id = "Wired connection 1";
    type = "ethernet";
    interface-name = "lan0";  # Consistent across all nodes
    autoconnect = true;
  };
  ipv4 = {
    method = "manual";
    address1 = "10.1.1.XXX/24";
    gateway = "10.1.1.1";
    dns = "127.0.0.1,::1";
  };
  ipv6.method = "auto";
};
```

**Lessons Learned**:
- **Always bind NetworkManager to renamed interface**: Without explicit `interface-name`, NetworkManager binds to the kernel's original name (enp7s0) which disappears after systemd.link renames it
- **Avahi compatibility**: Updated Avahi `allowInterfaces` to accept both old (enp*, eno*) and new (lan0) names during transition period

**Deployment Status**: Same as Phase 1 (all nodes ready for deployment)

---

### Phase 3: DNS Unification (COMPLETED)

**Status**: All nodes already running Unbound DNS resolver via `modules/system/networking.nix`

**Configuration**:
- All nodes use local Unbound (127.0.0.1, ::1) as primary DNS
- Unbound forwards to Quad9 DNS-over-TLS for upstream resolution
- Tailscale Magic DNS handled via stub zone
- ASUS CDN forward zone for BIOS downloads

**No action required** - already harmonized across cluster.

---

## In Progress 🚧

### Phase 4: VLAN Implementation (IN PROGRESS - Full 7-VLAN Design)

**Objective**: Implement complete 7-VLAN segmentation for proper traffic isolation

**Full 7-VLAN Architecture**:

| VLAN ID | Name | Purpose | Traffic Type | Nodes/Devices |
|---------|------|---------|--------------|---------------|
| **10** | Gaming | VR streaming, Steam, gaming PCs | Low latency, bursty | Zephyr, Deco WiFi, gaming PCs |
| **20** | AI | AI/ML inference, model serving | High throughput | Zephyr, Forge |
| **30** | Storage | NFS, cluster storage, backups | High throughput, bulk | Nexus |
| **40** | Mining | Stratum traffic, mining operations | Continuous, low bandwidth | Forge, Sentry |
| **50** | Monitoring | Prometheus, Grafana, metrics | Periodic, queryable | Sentry |
| **60** | Backup | Backup operations, snapshots | Bulk, scheduled | Nexus |
| **99** | Management | K8s control plane, switch management | Cluster-critical | **ALL nodes and switches** |

**Corrected Switch Topology**:

```
Internet
  │
Modem (10.1.1.1)
  │
sw1-modem (10.1.1.90) ← ROOT/DISTRIBUTION SWITCH (TL-SG105E)
  │
  ├─ sw3-upstairs (10.1.1.12) ← DISTRIBUTION SWITCH
  │   │
  │   ├─ sw4-zephyr (10.1.1.104) ← ACCESS SWITCH (TL-SG2210)
  │   │   └─ Zephyr (10.1.1.110)
  │   │
  │   ├─ Forge (10.1.1.130)
  │   └─ Sentry (10.1.1.140)
  │
  └─ sw2-tv (10.1.1.95) ← ACCESS SWITCH (TL-SG105E)
      └─ Nexus (10.1.1.120)
```

**Node VLAN Assignments**:

| Node | IP | Primary VLAN | Trunked VLANs | Purpose |
|------|----|--------------|---------------|---------|
| **Zephyr** | 10.1.1.110 | 99 (mgmt) | 99, 10, 20 | Gaming + AI workloads |
| **Nexus** | 10.1.1.120 | 99 (mgmt) | 99, 30, 60 | Storage + Backup |
| **Forge** | 10.1.1.130 | 99 (mgmt) | 99, 20, 40 | AI + Mining |
| **Sentry** | 10.1.1.140 | 99 (mgmt) | 99, 40, 50 | Mining + Monitoring |

**Completed**:
- ✅ Scripts created with full 7-VLAN design
- ✅ VLAN design document complete

**Blocked by**:
- ⚠️ **Script IP addresses incorrect**: tplink-configure-vlans.py has wrong switch IPs
- ⚠️ **PVID isolation issue**: Changing PVID without complete trunk path causes isolation (learned the hard way)
- ⚠️ **Incomplete trunk path documentation**: Need to verify all trunk paths before PVID changes

**Critical Implementation Order**:

1. **Fix switch IPs in script** (sw1: 10.1.1.90, sw2: 10.1.1.95, sw4: 10.1.1.104)
2. **Enable VLAN + create all 7 VLANs** on all switches (DO NOT change PVIDs yet)
3. **Configure trunk paths FIRST** before touching host ports:
   - sw1-P4 ↔ sw3-P1: All 7 VLANs tagged
   - sw1-P5 ↔ sw2-P1: VLANs 99, 30, 60 tagged
   - sw3-P2 ↔ sw4-P1: All 7 VLANs tagged
4. **Verify trunk connectivity**: Each trunk shows all expected VLANs as tagged
5. **Configure access/hybrid ports** (with PVID=99, not changing yet)
6. **ONLY THEN**: Change PVIDs on host ports from 1 → 99 (one at a time)

**Lessons Learned**:
- **PVID determines native VLAN**: Changing PVID without proper trunk path isolates the host
- **Must verify trunk paths first**: Before changing PVID, ensure the new VLAN has a complete tagged path to destination networks
- **Complete trunk path mapping required**: Every VLAN must have a tagged path from source to destination
- **VLAN 99 is critical**: All switches and nodes need VLAN 99 for management/cluster traffic

**Next Steps**:
1. **Update script IPs**: Fix switch IP addresses in tplink-configure-vlans.py
2. **Verify accessibility**: Test login to all switches with corrected IPs
3. **Create trunk path diagram**: Document exact VLAN paths for each traffic type
4. **Implement phased approach**:
   - Phase 1: Enable VLAN + create 7 VLANs
   - Phase 2: Configure trunk paths (inter-switch)
   - Phase 3: Verify trunk paths are complete
   - Phase 4: Configure host ports
   - Phase 5: Change PVIDs (last step, one at a time)
5. **Configure host VLAN interfaces**: Add VLAN interfaces to NixOS configs (lan0.10, lan0.20, etc.)

**Relevant Documentation**:
- `docs/plans/2026-03-09-switch-vlan-design.md` - Complete 7-VLAN design specification
- `scripts/tplink-configure-vlans.py` - Automated VLAN configuration script (needs IP fixes)
- `docs/NETWORKING_ROADMAP.md` - This document (network implementation tracking)

---

### Complete VLAN Trunk Path Mapping

**CRITICAL**: These paths must be configured BEFORE any PVID changes. Each VLAN must have a complete tagged path from source to destination.

```
VLAN 10 (Gaming) - Low Latency Path:
  Modem → sw1-P1 (tagged) → sw3-P1 (tagged) → sw4-P1 (tagged) → Zephyr (tagged)
                              → sw3-P4 (tagged) → Sentry (tagged)
         → sw1-P3 (tagged) → Deco XE75 WiFi (tagged)
         → sw1-P5 (tagged) → sw2-P1 (tagged) → sw2-P3 (untagged) → krash3
                                           → sw2-P4 (untagged) → krash1.5

VLAN 20 (AI) - High Throughput Path:
  Modem → sw1-P1 (tagged) → sw3-P1 (tagged) → sw4-P1 (tagged) → Zephyr (tagged)
                              → sw3-P5 (tagged) → Forge (tagged)

VLAN 30 (Storage) - Bulk Transfer Path:
  Modem → sw1-P5 (tagged) → sw2-P1 (tagged) → sw2-P2 (tagged) → Nexus (tagged)

VLAN 40 (Mining) - Continuous Low Bandwidth Path:
  Modem → sw1-P1 (tagged) → sw3-P1 (tagged) → sw3-P4 (tagged) → Sentry (tagged)
                                           → sw3-P5 (tagged) → Forge (tagged)

VLAN 50 (Monitoring) - Query Path:
  Modem → sw1-P1 (tagged) → sw3-P1 (tagged) → sw3-P4 (tagged) → Sentry (tagged)

VLAN 60 (Backup) - Scheduled Bulk Path:
  Modem → sw1-P5 (tagged) → sw2-P1 (tagged) → sw2-P2 (tagged) → Nexus (tagged)

VLAN 99 (Management) - CRITICAL CLUSTER PATH:
  Modem → sw1-P1 (tagged) → sw3-P1 (tagged) → sw4-P1 (tagged) → Zephyr (tagged) ✓
                                           → sw4-P3 (tagged) → Deco XE75 (tagged)
                              → sw3-P4 (tagged) → Sentry (tagged) ✓
                              → sw3-P5 (tagged) → Forge (tagged) ✓
         → sw1-P5 (tagged) → sw2-P1 (tagged) → sw2-P2 (tagged) → Nexus (tagged) ✓
         → sw1-P3 (tagged) → Deco XE75 WiFi (tagged)
         → ALL SWITCH MANAGEMENT INTERFACES ✓
```

**Port-by-Port Trunk Configuration**:

```
sw1-modem (10.1.1.90) TRUNK PORTS:
  Port 1 → Modem: Tag VLANs 10, 20, 30, 40, 50, 60, 99 (ALL)
  Port 3 → Deco XE75: Tag VLANs 10, 99
  Port 4 → sw3-upstairs: Tag VLANs 10, 20, 30, 40, 50, 60, 99 (ALL) ← CRITICAL
  Port 5 → sw2-tv: Tag VLANs 30, 60, 99

sw2-tv (10.1.1.95) TRUNK PORTS:
  Port 1 → sw1-modem: Tag VLANs 30, 60, 99
  Port 2 → Nexus: Tag VLANs 30, 60, 99

sw3-upstairs (10.1.1.12) TRUNK PORTS:
  Port 1 → sw1-modem: Tag VLANs 10, 20, 30, 40, 50, 60, 99 (ALL) ← CRITICAL
  Port 2 → sw4-zephyr: Tag VLANs 10, 20, 30, 40, 50, 60, 99 (ALL) ← CRITICAL
  Port 4 → Sentry: Tag VLANs 40, 50, 99
  Port 5 → Forge: Tag VLANs 20, 40, 99

sw4-zephyr (10.1.1.104) TRUNK PORTS:
  Port 1 → sw3-upstairs: Tag VLANs 10, 20, 30, 40, 50, 60, 99 (ALL) ← CRITICAL
  Port 3 → Deco XE75: Tag VLANs 10, 99
  Port 5 → Zephyr: Tag VLANs 10, 20, 99
```

**Verification Steps** (before PVID changes):

1. **Enable 802.1Q VLAN** on all switches
2. **Create all 7 VLANs** (10, 20, 30, 40, 50, 60, 99) on each switch
3. **Configure trunk ports** with tagged VLANs as shown above
4. **Verify each trunk**:
   - Log into switch web interface
   - Navigate to VLAN → 802.1Q VLAN → Port Membership
   - Confirm each trunk port shows all expected VLANs as "Tagged"
   - Example: sw1-P4 should show VLANs 10, 20, 30, 40, 50, 60, 99 all tagged
5. **Test connectivity**:
   - Ping from switch to switch (using management IPs)
   - Verify each trunk path is operational
6. **ONLY THEN**: Configure host ports and change PVIDs

---

## Planned Work 📋

### Phase 5: Host VLAN Interface Configuration (PLANNED)

**Objective**: Configure VLAN interfaces on hosts that need them

**Architecture**: L2-only segmentation - all devices stay on 10.1.1.0/24 subnet

**Nodes requiring VLAN interfaces**:
- **Zephyr**: Needs VLAN 10 (gaming) + VLAN 20 (AI) interfaces
- **Nexus**: Needs VLAN 30 (storage) + VLAN 60 (backup) interfaces
- **Forge**: Needs VLAN 20 (AI) + VLAN 40 (mining) interfaces
- **Sentry**: Needs VLAN 40 (mining) + VLAN 50 (monitoring) interfaces

**Implementation approach**:
```nix
# Example: VLAN interfaces on Zephyr for gaming and AI workloads
networking = {
  # VLAN 10: Gaming traffic (low latency)
  interfaces."lan0.10" = {
    virtual = true;
    connection = {
      type = "vlan";
      interface-name = "lan0.10";
      parent = "lan0";
      vlan.id = 10;
    };
    ipv4.addresses = [{ address = "10.1.1.110"; prefixLength = 24; }];
  };

  # VLAN 20: AI/ML workloads (high throughput)
  interfaces."lan0.20" = {
    virtual = true;
    connection = {
      type = "vlan";
      interface-name = "lan0.20";
      parent = "lan0";
      vlan.id = 20;
    };
    ipv4.addresses = [{ address = "10.1.1.110"; prefixLength = 24; }];
  };
};

# QoS prioritization for gaming traffic
systemd.network.networks."lan0.10" = {
  priority = 1000;  # Higher priority for gaming
  qos = {
    throughput = 1000M;  # Full 1Gbps for gaming
  };
};
```

**Note**: All VLAN interfaces use the same 10.1.1.0/24 subnet addresses. The switch handles VLAN segregation at layer 2, so no routing or IP reconfiguration is needed.

**Dependencies**:
- Phase 1 must be deployed (lan0 interface must exist)
- Phase 4 must be complete (switch VLAN trunking configured)

---

### Phase 6: Network Policy Documentation (PLANNED)

**Objective**: Document network policies, firewall rules, and security boundaries

**Deliverables**:
- Network policy document
- Firewall rule matrix
- Inter-node traffic flow documentation
- VLAN traffic segregation policies

---

### Phase 7: Monitoring and Observability (PLANNED)

**Objective**: Implement network monitoring and alerting

**Tools to evaluate**:
- Prometheus node exporter (already configured)
- Network traffic analysis
- VLAN-aware monitoring
- Switch port monitoring

---

## Technical Decisions

### Interface Naming: MAC-Based systemd.network.links

**Decision**: Use MAC address-based persistent naming instead of predictable kernel names (enp*, eno*)

**Rationale**:
- Hardware independent: Survives PCI reconfiguration
- Consistent across reboots: MAC addresses don't change
- Declarative: Easy to specify in NixOS config
- Human-readable: `lan0` is clearer than `enp38s0`

**Alternatives Considered**:
- ✗ Predictable kernel names (enp38s0, eno1): Not consistent across hardware
- ✗ udev rules: More complex than systemd.network.links
- ✗ Manual renaming: Not declarative, requires manual intervention

### NetworkManager: Declarative Profiles

**Decision**: Use NetworkManager `ensureProfiles` for all nodes

**Rationale**:
- Declarative: Configured in NixOS, applied automatically
- Fallback: NetworkManager handles DHCP/manual fallback
- GUI-friendly: Can use nm-connection-editor for troubleshooting
- Tailscale compatible: Works well with Tailscale VPN

**Alternatives Considered**:
- ✗ systemd-networkd: More complex configuration, no GUI tools
- ✗ Pure DHCP: No static IP control, no fallback
- ✗ Manual network scripts: Not declarative, error-prone

### DNS: Local Unbound Resolver

**Decision**: All nodes run local Unbound DNS resolver

**Rationale**:
- Privacy: DNS-over-TLS to upstream resolvers
- Performance: Local caching reduces latency
- Redundancy: No single point of failure
- Security: Blocks analytics/telemetry domains

**Configuration**:
- Upstream: Quad9 DNS-over-TLS (9.9.9.9@853)
- Fallback: Google DNS-over-TLS (8.8.8.8@853)
- Special: ASUS CDN forward zone for BIOS downloads
- Tailscale: Stub zone for Magic DNS

---

## Troubleshooting Guide

### Network Failure After Interface Renaming

**Symptoms**:
- Host boots but has no network connectivity
- `ip link show` shows `lan0` exists
- NetworkManager shows "disconnected" or "no carrier"

**Diagnosis**:
```bash
# Check if NetworkManager is trying to bind to old interface
nmcli connection show
# Look for "Wired connection 1" with interface-name pointing to old name (enp7s0, etc.)

# Check if lan0 is up
ip link show lan0
# Should show "state UP" with carrier

# Check NetworkManager logs
journalctl -u NetworkManager -n 50
```

**Solution**:
- Update host's NetworkManager profile to explicitly set `interface-name = "lan0"`
- Rebuild and switch: `sudo nixos-rebuild --flake .#hostname switch`

**Prevention**:
- Always use explicit `interface-name` in NetworkManager profiles
- Test configuration on non-critical nodes first

### VLAN Isolation After PVID Change

**Symptoms**:
- Host loses connectivity to all networks
- Can't reach gateway (10.1.1.1)
- Can't reach other cluster nodes

**Diagnosis**:
```bash
# Check which VLAN untagged traffic is using
tcpdump -i lan0 -e -n vlan
# Look for untagged frames (no VLAN tag) being sent to wrong VLAN

# Log into switch and check PVID
# Navigation: VLAN -> 802.1Q VLAN -> PVID Configuration
```

**Solution**:
- Access switch via alternate path (WiFi, serial console, etc.)
- Restore original PVID (usually 1 for native VLAN)
- Reboot host or reconfigure network

**Prevention**:
- Always verify trunk path exists before changing PVID
- Test VLAN configuration on non-production switch first
- Document complete VLAN paths before making changes

### Avahi Not Discovering Services

**Symptoms**:
- Avahi mDNS not working
- Can't discover services on local network
- `avahi-browse -a` shows no results

**Diagnosis**:
```bash
# Check Avahi status
systemctl status avahi-daemon

# Check Avahi configuration
avahi-daemon --check

# Check if interface is allowed
cat /etc/avahi/avahi-daemon.conf | grep allow-interface
```

**Solution**:
- Update `modules/system/networking.nix` to include new interface name
- Ensure interface is in `allowInterfaces` list
- Rebuild and switch

---

## Deployment Checklist

### Pre-Deployment
- [ ] Review all configuration changes
- [ ] Test configuration on one node (recommend: Sentry or Forge)
- [ ] Verify rollback plan (NixOS generations)
- [ ] Document current interface names for all nodes

### Deployment
- [ ] Deploy to Zephyr (control plane, higher risk)
- [ ] Deploy to Nexus (storage, medium risk)
- [ ] Deploy to Forge (mining, low risk)
- [ ] Deploy to Sentry (monitoring, low risk)

### Post-Deployment Verification
For each node, verify:
- [ ] `ip link show` displays `lan0` interface
- [ ] `lan0` has correct IP address (10.1.1.XXX)
- [ ] Default gateway is 10.1.1.1
- [ ] DNS resolver (127.0.0.1) is responding
- [ ] Can reach other cluster nodes
- [ ] Can reach internet (test: `curl https://google.com`)
- [ ] Services are running (NFS, Kubernetes, Tailscale, etc.)

### Rollback Plan
If network fails after deployment:
1. Reboot into previous generation (GRUB → Advanced options → Previous generation)
2. Or: `sudo nixos-rebuild --rollback switch`
3. Investigate failure in logs: `journalctl -xe`
4. Fix configuration and retry deployment

---

## References

### Internal Documentation
- `AGENTS.md` - Universal cluster patterns and build commands
- `CLAUDE.md` - Claude Code agent patterns
- `DOCUMENTATION_INDEX.md` - Complete documentation index
- `docs/plans/2026-03-09-switch-vlan-design.md` - VLAN design specification
- `docs/security/SECURITY_AUDIT_REPORT.md` - Security audit
- `docs/security/HARDENING_SUMMARY.md` - Security hardening status

### External Resources
- NixOS Networking: https://nixos.org/manual/nixos/stable/#ch-networking
- NetworkManager: https://networkmanager.dev/docs/
- systemd.link: https://www.freedesktop.org/software/systemd/man/systemd.link.html
- Unbound DNS: https://nlnetlabs.nl/projects/unbound/about/
- VLAN 802.1Q: https://en.wikipedia.org/wiki/IEEE_802.1Q

---

## Changelog

### 2026-03-10
- Created NETWORKING_ROADMAP.md
- Documented Phase 1 (Interface Naming Harmonization) as completed
- Documented Phase 2 (NetworkManager Profile Harmonization) as completed
- Documented Phase 3 (DNS Unification) as completed
- Documented Phase 4 (VLAN Implementation) as in progress
- Added troubleshooting guide for common network issues
- Added deployment checklist
- **Updated to full 7-VLAN design** (was incorrectly showing 4-VLAN plan)
- Added complete trunk path mapping for all 7 VLANs
- Added port-by-port trunk configuration matrix
- Corrected switch IP addresses (sw1: 10.1.1.90, sw2: 10.1.1.95, sw4: 10.1.1.104)
- Added critical implementation order to prevent PVID isolation
- Fixed VLAN interface configuration examples (L2-only segmentation, same subnet)

---

**Maintainer**: j_kro | **Review Frequency**: Monthly | **Next Review**: 2026-04-10
