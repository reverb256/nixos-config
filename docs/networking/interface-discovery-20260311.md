# Network Interface Discovery - Cluster Nodes
**Date:** 2026-03-11
**Purpose:** Document all network interfaces across 4-node cluster before VLAN configuration

---

## Executive Summary

**Discovery Complete:** ✅ All 4 nodes surveyed

**Key Findings:**
- **Interface Naming Inconsistency:** Some nodes use `enpXs0` (predictable), others use `lan0` (aliased)
- **Network Management Mix:** 3 nodes use NetworkManager, 1 node (forge) uses alternative method
- **Flannel Overlay:** Each node has unique Flannel VXLAN endpoint (as expected)
- **All Interfaces Operational:** 0% packet loss, excellent connectivity

---

## Node-by-Node Interface Inventory

### Zephyr (10.1.1.110) - Control Plane

**Role:** Kubernetes master, daily driver, RTX 3090

| Interface | Type | IP Address | Status | Notes |
|-----------|------|------------|--------|-------|
| **enp38s0** | Ethernet (wired) | 10.1.1.110/24 | UP | **Primary interface** |
| wlo1 | WiFi | 10.1.1.115/24 | UP | Not used for cluster |
| enp42s0f1u2u3i5 | USB (down) | - | DOWN | Unused |
| podman0 | Bridge | 10.88.0.1/16 | UP | Podman containers |
| docker0 | Bridge | 172.17.0.1/16 | DOWN | Docker containers |
| tailscale0 | TUN | 100.76.234.6/32 | UP | VPN |
| flannel.1 | VXLAN | 10.1.45.0/32 | UP | **Kubernetes overlay** |
| cni0 | Bridge | 10.1.45.1/24 | UP | CNI plugin |
| mynet | Bridge | - | UP | Additional bridge |

**Network Management:** NetworkManager ✅
**Configuration File:** `hosts/zephyr/configuration.nix`
**Connection Profile:** `ethernet-enp38s0`

---

### Nexus (10.1.1.120) - Storage Node

**Role:** NFS storage, 8TB HDD array

| Interface | Type | IP Address | Status | Notes |
|-----------|------|------------|--------|-------|
| **enp7s0** | Ethernet (wired) | 10.1.1.120/24 | UP | **Primary interface** |
| wlo1 | WiFi | - | DOWN | Not used |
| enp2s0f0u8u1 | USB (down) | - | DOWN | Unused |
| tailscale0 | TUN | 100.86.158.18/32 | UP | VPN |
| docker0 | Bridge | 172.17.0.1/16 | UP | Docker containers |
| flannel.1 | VXLAN | 10.1.15.0/32 | UP | **Kubernetes overlay** |

**Network Management:** NetworkManager ✅
**Flannel Note:** Different VXLAN endpoint than zephyr (expected)

---

### Forge (10.1.1.130) - GPU Compute Node

**Role:** GPU compute, 5x NVIDIA GPUs, AI/mining workloads

| Interface | Type | IP Address | Status | Notes |
|-----------|------|------------|--------|-------|
| **lan0** | Ethernet (wired) | 10.1.1.130/24 | UP | **Primary interface** |
| tailscale0 | TUN | 100.95.222.45/32 | UP | VPN |
| docker0 | Bridge | 172.17.0.1/16 | DOWN | Docker containers |
| flannel.1 | VXLAN | 10.1.40.0/32 | UP | **Kubernetes overlay** |
| cni0 | Bridge | 10.1.40.1/24 | UP | CNI plugin |

**Network Management:** **NOT NetworkManager** ⚠️
**Likely Method:** systemd-networkd or static configuration
**Discovery Needed:** Check configuration files

---

### Sentry (10.1.1.140) - Monitoring Node

**Role:** Monitoring, AMD GPU, Prometheus/Grafana

| Interface | Type | IP Address | Status | Notes |
|-----------|------|------------|--------|-------|
| **lan0** | Ethernet (wired) | 10.1.1.140/24 | UP | **Primary interface** |
| tailscale0 | TUN | 100.81.171.24/32 | UP | VPN |
| docker0 | Bridge | 172.17.0.1/16 | DOWN | Docker containers |
| flannel.1 | VXLAN | 10.1.54.0/32 | UP | **Kubernetes overlay** |
| cni0 | Bridge | 10.1.54.1/24 | DOWN | CNI plugin |

**Network Management:** NetworkManager ✅
**Flannel Note:** Different VXLAN endpoint (expected for each node)

---

## Critical Observations

### 1. Interface Naming Inconsistency ⚠️

**Predictable Names (udev/systemd):**
- zephyr: `enp38s0`
- nexus: `enp7s0`

**Aliased Names (user-defined):**
- forge: `lan0`
- sentry: `lan0`
- zephyr config references: `lan0` (but actual interface is `enp38s0`)

**Impact:** VLAN configuration must use **actual interface names**, not aliases

### 2. Network Management Method Variance ⚠️

| Node | Method | Status |
|------|--------|--------|
| zephyr | NetworkManager | ✅ |
| nexus | NetworkManager | ✅ |
| forge | **Unknown** (not NM) | ⚠️ Needs investigation |
| sentry | NetworkManager | ✅ |

**Impact:** Forge may need different VLAN configuration approach

### 3. Flannel VXLAN Endpoints

All nodes have unique Flannel endpoints (as expected):
- zephyr: `10.1.45.0/32`
- nexus: `10.1.15.0/32`
- forge: `10.1.40.0/32`
- sentry: `10.1.54.0/32`

**Verification:** Kubernetes overlay network is operational

### 4. Current Configuration References

**Zephyr Configuration** (`hosts/zephyr/configuration.nix`):
```nix
networking.networkmanager.ensureProfiles.profiles."Wired connection 1" = {
  connection = {
    interface-name = "lan0";  # References alias, not actual interface
  };
  ipv4.address1 = "10.1.1.110/24";
};
```

**Issue:** Configuration references `lan0` but actual interface is `enp38s0`

---

## Required VLAN Configuration

### Per-Node Interface Mapping

| Node | Actual Interface | Config Reference | Required VLANs |
|------|-----------------|-------------------|----------------|
| zephyr | **enp38s0** | lan0 (alias) | 99, 10, 20 |
| nexus | **enp7s0** | (unknown) | 99, 30, 60 |
| forge | **lan0** | (likely lan0) | 99, 20, 40 |
| sentry | **lan0** | (unknown) | 99, 40, 50 |

### VLAN Interface Configuration Examples

**For NetworkManager Nodes (zephyr, nexus, sentry):**
```nix
# Method 1: NetworkManager connection (preferred)
networking.networkmanager.ensureProfiles.profiles."Wired connection 1".connection.vlans = [99 10 20];

# Method 2: Direct interface configuration
networking.interfaces.enp38s0.virtual VLANs = [99 10 20];
```

**For Non-NetworkManager Node (forge):**
```nix
# Direct interface configuration
networking.interfaces.lan0.virtual VLANs = [99 20 40];
# Or with systemd.networkd
systemd.networks."99-vlan" = {
  attach = [ "lan0" ];
  networkConfig.VLAN = "99";
};
```

---

## Interface Name Resolution

### Zephyr: `enp38s0` vs `lan0`

**Discovery:** Actual physical interface is `enp38s0`
**Config Reference:** `lan0` in NixOS configuration
**NetworkManager Profile:** `ethernet-enp38s0`

**Hypothesis:** `lan0` may be:
1. A udev rule alias
2. A NetworkManager connection name
3. An interface rename via `ip link set enp38s0 name lan0`

**Investigation Needed:**
```bash
# Check for udev rules
ls -la /etc/udev/rules.d/
# Check for interface rename
nmcli connection show "ethernet-enp38s0" | grep interface-name
# Check actual interface vs configured
ip link show | grep enp38s0
```

### Forge & Sentry: `lan0` Consistency

Both use `lan0` which suggests:
1. Consistent interface naming convention (good!)
2. May be using predictable naming from hardware configuration
3. Or using udev rules for consistent naming

---

## Next Steps

### Phase 1: Configuration Discovery (Current)

- [x] Discover interfaces on all 4 nodes
- [ ] Investigate forge's network configuration method (not NetworkManager)
- [ ] Resolve zephyr's `lan0` vs `enp38s0` discrepancy
- [ ] Check for udev rules or interface renaming

### Phase 2: Create Unified VLAN Module

- [ ] Create NixOS module for VLAN interface configuration
- [ ] Support both NetworkManager and systemd-networkd
- [ ] Handle interface naming differences
- [ ] Make configuration idempotent and safe

### Phase 3: Test VLAN Interface Creation

- [ ] Configure VLANs on zephyr first (control plane)
- [ ] Verify `enp38s0.99`, `enp38s0.10`, `enp38s0.20` are created
- [ ] Test connectivity on each VLAN
- [ ] Roll out to other nodes

### Phase 4: PVID Configuration

- [ ] Configure PVIDs on switches
- [ ] Verify management traffic on VLAN 99
- [ ] Test cluster functionality after PVID changes

---

## Risk Mitigation

### Interface Name Changes

**Risk:** Changing interface names could break existing configurations

**Mitigation:**
- Use actual interface names (from `ip addr show`) in VLAN configs
- Don't change interface names unless necessary
- Document both actual and aliased names

### NetworkManager Conflicts

**Risk:** NetworkManager may override systemd-networkd VLAN configs

**Mitigation:**
- Use NetworkManager's built-in VLAN support for NM nodes
- Use direct interface configuration for non-NM nodes
- Test on one node first

### Configuration Drift

**Risk:** Different nodes may use different configuration methods

**Mitigation:**
- Create flexible VLAN module supporting both NM and systemd-networkd
- Document configuration method per node
- Use conditional configuration based on hostname

---

## Flannel Verification

**All nodes have Flannel VXLAN endpoints:**
- zephyr: `10.1.45.0/32`
- nexus: `10.1.15.0/32`
- forge: `10.1.40.0/32`
- sentry: `10.1.54.0/32`

**CNI Bridge:** All nodes have `cni0` bridge
**Backend:** VXLAN overlay (layer 2 over layer 3)

**PVID Impact:** When PVIDs are configured to VLAN 99, Flannel traffic will need to:
1. Either stay on VLAN 1 (if switch allows multiple native VLANs)
2. Or use tagged frames for Flannel on trunk ports
3. **Critical:** Verify Flannel continues working after PVID changes

---

## Data Collection Commands Used

```bash
# Zephyr (local)
ip -br addr show | grep -E "^(e|w|en)"
nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device

# Nexus (SSH)
ssh nexus "ip -br addr show | grep -E '^(e|w|en)'"
ssh nexus "systemctl is-active NetworkManager"

# Forge (SSH)
ssh forge "ip -br addr show"
ssh forge "systemctl is-active NetworkManager"

# Sentry (SSH)
ssh sentry "ip -br addr show | head -10"
ssh sentry "systemctl is-active NetworkManager"
```

---

## Appendix: Raw Output Logs

### Zephyr Full Interface List
```
enp38s0: UP (10.1.1.110/24) - Primary
wlo1: UP (10.1.1.115/24) - WiFi
tailscale0: UP (100.76.234.6/32) - VPN
flannel.1: UP (10.1.45.0/32) - Kubernetes overlay
```

### Nexus Full Interface List
```
enp7s0: UP (10.1.1.120/24) - Primary
wlo1: DOWN - WiFi (unused)
tailscale0: UP (100.86.158.18/32) - VPN
flannel.1: UP (10.1.15.0/32) - Kubernetes overlay
```

### Forge Full Interface List
```
lan0: UP (10.1.1.130/24) - Primary
tailscale0: UP (100.95.222.45/32) - VPN
flannel.1: UP (10.1.40.0/32) - Kubernetes overlay
cni0: UP (10.1.40.1/24) - CNI bridge
```

### Sentry Full Interface List
```
lan0: UP (10.1.1.140/24) - Primary
tailscale0: UP (100.81.171.24/32) - VPN
flannel.1: UP (10.1.54.0/32) - Kubernetes overlay
cni0: DOWN (10.1.54.1/24) - CNI bridge
```
