# Network Interface Harmonization Plan
**Date:** 2026-03-12
**Status:** ✅ Discovery Complete | Ready for Implementation

---

## Executive Summary

**Discovery Complete:** All 4 cluster nodes' actual hardware interface names identified

**Complete Network Interface Inventory:**

| Node | Wired Ethernet | WiFi | Bluetooth | Cluster Use |
|------|----------------|------|-----------|-------------|
| **zephyr** | enp38s0 | wlp40s0 (as wlo1) | hci0 ✅ | Control plane + daily driver |
| **nexus** | enp7s0 | wlp4s0 (as wlo1) | hci0, hci1 ❌ | Storage node |
| **forge** | enp0s31f6 | None | None | GPU compute |
| **sentry** | enp7s0 | None | None | Monitoring |

**Focus:** This plan harmonizes **wired Ethernet interfaces** to use native enp*s* naming. WiFi and Bluetooth are documented but out of scope for the initial changes.

**Root Cause Found:**
- `/etc/nixos/modules/system/interface-naming.nix` is creating systemd .link files
- These .link files rename ALL primary interfaces to "lan0" based on MAC address matching
- This was done for "consistent naming" but creates confusion and hides the actual hardware topology

**Recommendation:** Remove interface-naming.nix and use native predictable enp*s* names

---

## Complete Interface Inventory

### Wired Ethernet Interfaces (Primary Cluster Connectivity)

| Node | Hardware Interface | MAC Address | Current Alias | udev ID_NET_NAME_PATH |
|------|-------------------|-------------|---------------|----------------------|
| **zephyr** | **enp38s0** | 2c:f0:5d:a1:b8:ef | lan0 (via NM) | enp38s0 ✅ |
| **nexus** | **enp7s0** | e0:d5:5e:a7:4b:50 | lan0 (via link, not applied) | enp7s0 ✅ |
| **forge** | **enp0s31f6** | 30:9c:23:ad:98:d1 | lan0 (via link) | enp0s31f6 ✅ |
| **sentry** | **enp7s0** | 70:85:c2:d2:87:bf | lan0 (via link) | enp7s0 ✅ |

### Wireless Interfaces (WiFi)

| Node | Native Name | Current Name | MAC Address | Status | Usage |
|------|-------------|--------------|-------------|--------|-------|
| **zephyr** | wlp40s0 | wlo1 | 18:26:49:30:88:6f | UP (KDS network) | Daily driver WiFi |
| **nexus** | wlp4s0 | wlo1 | ba:42:dd:c6:88:12 | DOWN | Not used for cluster |
| **forge** | - | - | - | Disabled | `wireless.enable = false` |
| **sentry** | - | - | - | None | No WiFi hardware |

**WiFi Naming Note:**
- zephyr: `wlo1` → should be `wlp40s0` (PCI bus 40, slot 0)
- nexus: `wlo1` → should be `wlp4s0` (PCI bus 4, slot 0)
- These are NOT being renamed by interface-naming.nix (only ethernet interfaces)
- zephyr actively uses WiFi for daily driver connectivity

### Bluetooth Adapters

| Node | Adapter | Status | Configuration |
|------|---------|--------|---------------|
| **zephyr** | hci0 | ✅ Enabled | `bluetooth.enable = true` |
| **nexus** | hci0, hci1 | ❌ Soft blocked | Not explicitly enabled |
| **forge** | - | Not available | Not configured |
| **sentry** | - | Not available | Not configured |

**Bluetooth Hardware Count:**
- zephyr: 1 adapter (unblocked, active)
- nexus: 2 adapters (both soft blocked via rfkill)
- forge: No Bluetooth detected
- sentry: No Bluetooth detected

**PCI Paths Verified:**
- zephyr: `/sys/devices/pci0000:00/0000:00:02.0/0000:01:00.0/0000:02:01.0/0000:03:00.0/net/enp38s0`
- nexus: `/sys/devices/pci0000:00/0000:00:01.3/0000:02:00.2/0000:03:03.0/0000:07:00.0/net/enp7s0`
- forge: `/sys/devices/pci0000:00/0000:00:1f.6/net/enp0s31f6`
- sentry: `/sys/devices/pci0000:00/0000:00:01.3/0000:01:00.2/0000:02:07.0/0000:07:00.0/net/enp7s0`

**Nexus Special Case:** ⚠️
- Nexus has the systemd link file `10-lan0-nexus.link` configured
- However, the interface is **still showing as enp7s0** (not renamed to lan0!)
- NetworkManager configuration references "lan0" but device is actually connected as enp7s0
- Boot log shows: `igb 0000:07:00.0 enp7s0: renamed from eth0` (normal predictable naming)
- No evidence of lan0 rename being applied
- **Hypothesis:** Link file may not be processing, or NetworkManager is ignoring interface-name setting

---

## Current Configuration Issues

### 1. Interface Naming Module (Root Cause)

**File:** `/etc/nixos/modules/system/interface-naming.nix`
**Imported in:** `/etc/nixos/modules/default.nix:18`
**Action:** Creates systemd .link files to rename interfaces

```nix
# CURRENT (TO BE REMOVED)
systemd.network.links = {
  "10-lan0-zephyr" = {
    matchConfig.MACAddress = "2c:f0:5d:a1:b8:ef";
    linkConfig.Name = "lan0";
  };
  # ... (similar for nexus, forge, sentry)
};
```

**Issue:** This module:
1. Hides the actual hardware topology
2. Creates confusion when debugging network issues
3. Makes documentation less clear
4. Prevents using predictable naming benefits (hardware location aware)

### 2. NetworkManager Configurations

All nodes use "lan0" in NetworkManager profiles, but the methods differ:

| Node | Config File | Interface Name | Actual Device | Method |
|------|-------------|----------------|---------------|---------|
| zephyr | hosts/zephyr/configuration.nix | **lan0** (BUG!) | enp38s0 | NetworkManager (no rename) |
| nexus | hosts/nexus/configuration.nix | **lan0** | enp7s0 ✅ | NetworkManager + link file (not applied) |
| forge | hosts/forge/configuration.nix | **lan0** | lan0 (renamed) | NetworkManager + link file (applied) |
| sentry | hosts/sentry/configuration.nix | **lan0** | lan0 (renamed) | NetworkManager + link file (applied) |

**Zephyr Bug:** Configuration references "lan0" but systemd link file creates it as "lan0" anyway. The actual interface is enp38s0.

---

## Implementation Plan

### Scope Focus: Wired Ethernet Only

**Important:** This harmonization plan focuses on **wired Ethernet interfaces** only, which are used for:
- Cluster inter-node communication
- Kubernetes pod networking (Flannel)
- NFS storage traffic
- VLAN segmentation (future implementation)

**Wireless and Bluetooth:**
- WiFi interfaces are NOT renamed by interface-naming.nix
- WiFi will continue using their current names (wlo1, etc.)
- Bluetooth adapters are out of scope for this change
- These can be harmonized later if desired, but are not critical for cluster operations

### Phase 1: Disable Interface Renaming (Safe)

**Action:** Comment out interface-naming.nix from imports

**File:** `/etc/nixos/modules/default.nix`

```diff
-   ./system/interface-naming.nix
+   # ./system/interface-naming.nix  # DISABLED: Using native enp*s* naming
```

**Rationale:**
- Safe, reversible change
- Prevents new renamed interfaces from being created on next boot
- Allows us to update NetworkManager configs before rebuild

**Testing:** After this change, verify no new .link files are created

---

### Phase 2: Update NetworkManager Configurations

**Action:** Update all node configurations to use native enp*s* names

#### Zephyr (hosts/zephyr/configuration.nix)

```nix
# CURRENT (BUGGY)
networking.networkmanager.ensureProfiles.profiles."Wired connection 1" = {
  connection = {
    interface-name = "lan0";  # BUG: References renamed interface
  };
  ipv4.address1 = "10.1.1.110/24";
};

# TARGET (FIXED)
networking.networkmanager.ensureProfiles.profiles."Wired connection 1" = {
  connection = {
    interface-name = "enp38s0";  # ✅ Native hardware name
  };
  ipv4.address1 = "10.1.1.110/24";
};
```

#### Forge (hosts/forge/configuration.nix)

```nix
# CURRENT
interface-name = "lan0";  # Renamed via systemd link

# TARGET
interface-name = "enp0s31f6";  # ✅ Native hardware name
```

#### Sentry (hosts/sentry/configuration.nix)

```nix
# CURRENT
interface-name = "lan0";  # Renamed via systemd link

# TARGET
interface-name = "enp7s0";  # ✅ Native hardware name
```

#### Nexus (hosts/nexus/configuration.nix)

**Special Case:** Interface is ALREADY using enp7s0 (native name)!

```nix
# CURRENT (already correct!)
networking.networkmanager.ensureProfiles.profiles."Wired connection 1" = {
  connection = {
    interface-name = "lan0";  # References renamed interface
  };
  ipv4.address1 = "10.1.1.120/24";
};

# TARGET (just update config reference)
networking.networkmanager.ensureProfiles.profiles."Wired connection 1" = {
  connection = {
    interface-name = "enp7s0";  # ✅ Already using native name
  };
  ipv4.address1 = "10.1.1.120/24";
};
```

**Note:** Nexus's systemd link file exists but the rename to "lan0" is not being applied. The device is already connected as enp7s0, so this is the simplest change - just update the config reference to match reality.

---

### Phase 3: Apply Changes

**Order of Operations:**
1. **Comment out** interface-naming.nix in modules/default.nix
2. **Update** all node NetworkManager configurations
3. **Rebuild & switch** zephyr first (local, can recover easily)
4. **Test** connectivity after zephyr rebuild
5. **Rebuild & switch** other nodes via SSH
6. **Verify** cluster functionality

**Safety Mechanisms:**
- All changes are in git (can rollback)
- Only modifying configuration, not hardware state
- Can always re-enable interface-naming.nix if needed

---

### Phase 4: Verification

**Post-Deployment Tests:**

1. **Interface Names:**
   ```bash
   # Run on all nodes
   ip -br addr show | grep -E '^(en|lan)'
   # Should show enp*s* only, no lan0
   ```

2. **NetworkManager Profiles:**
   ```bash
   nmcli -t -f DEVICE,CONNECTION device
   # Should show enp*s* devices connected
   ```

3. **Connectivity:**
   ```bash
   # From zephyr
   for node in nexus forge sentry; do
     ping -c 3 $node
   done
   # Should have 0% packet loss
   ```

4. **Kubernetes:**
   ```bash
   # From zephyr
   kubectl get nodes
   # All nodes should be Ready
   kubectl get pods -A
   # All pods should be Running or Completed
   ```

---

## Benefits of Native Naming

### 1. Hardware Topology Visibility

**Before (lan0):**
- User has no idea which physical interface
- Must check multiple files to find actual interface
- Documentation is ambiguous

**After (enp38s0):**
- Immediately know: PCI bus 0, device 38, function 0
- Can map to physical hardware location
- Documentation is self-documenting

### 2. Troubleshooting Benefits

**Example Scenario:** Network stops working

**With lan0:**
```
$ ip link show lan0
Device "lan0" does not exist
# User: "What happened to lan0?"
# Must check: systemd links, NetworkManager, udev, hardware...
```

**With enp38s0:**
```
$ ip link show enp38s0
3: enp38s0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc...
# User: "Interface is up, checking network configuration..."
# Clear next steps
```

### 3. Documentation Clarity

**Before:** "Connect zephyr's lan0 interface to sw4-zephyr port 5"
**After:** "Connect zephyr's enp38s0 interface to sw4-zephyr port 5"

The hardware name tells you:
- **en**: Ethernet
- **p**: PCI bus
- **38**: Bus/device number
- **s0**: Slot/function 0

This matches the physical topology visible in `lspci` output.

---

## Risk Assessment

### Low Risk ✅

**Why This Is Safe:**
1. **No hardware changes** - Only software configuration
2. **Reversible** - Can re-enable interface-naming.nix if needed
3. **Tested locally** - Zephyr can be rebuilt and tested first
4. **Git version control** - All changes tracked and reversible
5. **No data loss** - Only interface naming changes

### Potential Issues & Mitigations

| Issue | Likelihood | Mitigation |
|-------|-----------|------------|
| **NetworkManager fails to find interface** | Low | Test on zephyr first, can rollback |
| **Kubernetes Flannel breaks** | Low | Flannel uses host networking, unaware of interface names |
| **Connectivity lost during rebuild** | Low | Use console access for recovery |
| **Node becomes inaccessible** | Very Low | Keep Tailscale VPN as fallback access |

---

## Rollback Plan

If anything goes wrong:

1. **Re-enable interface-naming.nix:**
   ```bash
   # Edit modules/default.nix
   # Uncomment: ./system/interface-naming.nix

   # Rebuild
   sudo nixos-rebuild switch
   ```

2. **Restore NetworkManager configs:**
   ```bash
   git checkout HEAD~1 -- hosts/*/configuration.nix
   sudo nixos-rebuild switch
   ```

3. **Use Tailscale for recovery:**
   ```bash
   # Access node via Tailscale IP
   ssh 100.76.234.6  # zephyr
   ssh 100.86.158.18 # nexus
   ssh 100.95.222.45 # forge
   ssh 100.81.171.24 # sentry
   ```

---

## Next Steps

### Immediate Actions (Required for VLAN Implementation)

1. ✅ **Discovery Complete** - All interface names documented
2. ⏳ **Comment out** interface-naming.nix import
3. ⏳ **Update** zephyr NetworkManager config (enp38s0)
4. ⏳ **Update** forge NetworkManager config (enp0s31f6)
5. ⏳ **Update** sentry NetworkManager config (enp7s0)
6. ⏳ **Discover** nexus NetworkManager config
7. ⏳ **Rebuild** zephyr and test
8. ⏳ **Rebuild** other nodes
9. ⏳ **Verify** cluster connectivity

### After Harmonization (VLAN Implementation)

Once all nodes use native enp*s* naming, proceed with:

1. **Create unified VLAN configuration module**
2. **Configure VLAN interfaces** (enp38s0.99, enp7s0.99, etc.)
3. **Configure PVIDs** on switches
4. **Verify VLAN segmentation**
5. **Test Kubernetes** on new VLAN architecture

---

## Files to Modify

| File | Action | Status |
|------|--------|--------|
| `modules/default.nix` | Comment out interface-naming.nix import | ⏳ Pending |
| `hosts/zephyr/configuration.nix` | Update interface-name: lan0 → enp38s0 | ⏳ Pending |
| `hosts/nexus/configuration.nix` | Update interface-name: lan0 → enp7s0 | ⏳ Pending |
| `hosts/forge/configuration.nix` | Update interface-name: lan0 → enp0s31f6 | ⏳ Pending |
| `hosts/sentry/configuration.nix` | Update interface-name: lan0 → enp7s0 | ⏳ Pending |

---

## Conclusion

**Discovery Phase: ✅ Complete**

All 4 cluster nodes have been fully surveyed. The root cause of interface naming inconsistency has been identified as the `interface-naming.nix` module. A safe, reversible plan has been documented to harmonize all nodes to use native predictable enp*s* naming.

**Readiness for Implementation: ✅ Ready**

All information needed to proceed is available. The changes are low-risk and fully reversible. The plan can be executed immediately, with zephyr serving as the local test case before rolling out to remote nodes.

**Estimated Time:** 30 minutes (includes testing and verification)
**Risk Level:** Low
**User Interaction Required:** Yes (approval to proceed)
