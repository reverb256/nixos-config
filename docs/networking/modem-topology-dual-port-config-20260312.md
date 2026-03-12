# Modem Topology & Dual-Port Configuration
**Date:** 2026-03-12
**Status:** Current Configuration

---

## Modem Hardware Configuration

**Device:** Modem/Router (10.1.1.1)
**Mode:** Gateway mode (NOT bridge mode)
**Ports:** 4 Ethernet ports

---

## Physical Connections

```
┌─────────────────────────────────────────┐
│          MODEM/ROUTER (10.1.1.1)        │
│                                         │
│  Port 1 ────── sw1-modem (10.1.1.10)  │
│  Port 2 ────── Deco XE75 #1 (WiFi AP)   │
│  Port 3 ────── [unused]                  │
│  Port 4 ────── [unused]                  │
└─────────────────────────────────────────┘
```

---

## Network Topology Impact

### Switched Network (Via sw1-modem Port 1)

**Devices on managed network:**
- sw1-modem (10.1.1.10) - Managed switch
- sw3-upstairs (10.1.1.12) - Distribution switch
- sw4-zephyr (10.1.1.13) - Zephyr switch
- sw2-tv (10.1.1.11) - TV area switch
- **All cluster nodes:** zephyr, nexus, forge, sentry

**VLAN Segmentation:**
- VLAN 99: Management (all cluster nodes)
- VLAN 10: Gaming (printer)
- VLAN 20: AI (forge workloads)
- VLAN 30: Storage (nexus NFS)
- VLAN 40: Mining (forge GPUs)
- VLAN 50: Monitoring (sentry)
- VLAN 60: Backup (nexus)

### Direct Modem Network (Via modem Port 2)

**Devices on modem network:**
- Deco XE75 #1 (WiFi AP)
- All WiFi clients (phones, laptops, etc.)

**Network Characteristics:**
- **NOT VLAN-segmented** - all on modem's NAT network
- **Bypasses managed switches** - no VLAN isolation
- **Uses separate subnet** - likely 192.168.x.x or 10.0.x.x
- **Guest network:** Uses VLAN 591 (internal to Deco/modem, not visible to sw1-modem)

---

## Implications for Network Design

### What This Means

**WiFi Devices:**
- ✅ Can access internet through modem
- ✅ Can access cluster services (if port forwarding enabled on modem)
- ⚠️ **NOT** on VLAN 99 management network
- ⚠️ **NOT** isolated by VLAN - all on same modem subnet
- ❌ **NO** VLAN segmentation (bypasses sw1-modem entirely)

**Cluster Nodes:**
- ✅ Properly segmented by VLAN via sw1-modem
- ✅ Isolated from WiFi network (unless modem forwards)
- ✅ Cannot reach WiFi devices directly (different subnet)
- ⚠️ **BUT** WiFi devices might reach nodes if modem has port forwarding

### Security Considerations

**Current Security Posture:**
1. **Cluster → WiFi:** Blocked (different subnets, no routing without explicit port forwarding)
2. **WiFi → Cluster:** Possible if modem forwards ports
3. **Guest WiFi:** Isolated by VLAN 591 (internal to Deco/modem)
4. **Main WiFi:** Same subnet as all modem devices

**Recommendation:**
- **DO NOT** enable port forwarding from modem to cluster nodes
- **DO NOT** expose cluster management (10.1.1.110:6443) to modem network
- Keep WiFi and managed networks **separate**

---

## Why This Architecture?

### Advantages of Dual-Port Modem Setup

**1. Separate Networks:**
- **Managed network:** Controlled, VLAN-segmented (sw1-modem)
- **WiFi network:** Consumer-friendly, plug-and-play (modem)
- **No interference:** Managed switches don't carry WiFi traffic

**2. Modem Performance:**
- **Less load on sw1-modem:** WiFi traffic doesn't flow through it
- **WiFi bandwidth doesn't compete with cluster traffic**
- **Simpler setup:** Deco directly connected to modem (as intended by vendor)

**3. Flexibility:**
- Can reset/replace managed switches without affecting WiFi
- Can reset/replace Deco without affecting managed network
- Two separate failure domains

### Disadvantages

**1. Reduced VLAN Control:**
- WiFi devices cannot be assigned to VLANs
- Guest WiFi isolation is limited to what Deco provides
- Cannot apply firewall policies between WiFi and specific VLANs

**2. Routing Complexity:**
- Two separate subnets (10.1.1.x for managed, modem subnet for WiFi)
- Inter-subnet communication requires modem configuration
- Port forwarding needed for WiFi to reach cluster services (if desired)

**3. Monitoring Blind Spot:**
- sw1-modem doesn't see WiFi traffic
- Cannot apply QoS/shaping to WiFi from managed switches
- WiFi devices are "invisible" to VLAN-based monitoring

---

## Comparison: Alternative Topologies

### Option A: Current Setup (Deco Direct to Modem) ✅ CURRENT

```
Modem ┬─ sw1-modem ──→ Managed network (VLANs)
       └─ Deco XE75  ──→ WiFi network (no VLANs)
```

**Pros:**
- Simple, vendor-recommended setup
- WiFi doesn't load managed switches
- Separate failure domains

**Cons:**
- WiFi not VLAN-segmented
- Cannot apply network policies to WiFi from switches
- Two separate subnets to manage

### Option B: Deco Through sw1-modem (NOT IMPLEMENTED)

```
Modem ── sw1-modem ─┬─→ Managed network (VLANs)
                      └─ Deco XE75  ──→ WiFi
```

**Pros:**
- All traffic flows through managed switches
- Can apply VLAN policies to WiFi
- Single point of control

**Cons:**
- WiFi traffic loads managed switches
- Deco may not like being behind a managed switch
- More complex single point of failure

---

## Modem Configuration Notes

### Gateway Mode vs Bridge Mode

**Current:** Gateway mode
- Modem acts as router
- NAT translation between modem network and ISP
- DHCP server for modem network devices
- Firewall between WAN and LAN

**Bridge Mode (Alternative):**
- Modem acts as simple bridge
- No NAT, no routing
- Would require separate router
- Not recommended for current setup

### Port Forwarding (If Needed)

**From modem to cluster:**
```
⚠️  CAUTION: Only forward if absolutely needed

Examples:
- Port 80 (HTTP) → zephyr (10.1.1.110) for web UI
- Port 6443 (Kubernetes API) → zephyr (10.1.1.110) for kubectl
- Port 30000-32767 (NodePort services) → zephyr

Recommendation: Use VPN/Tailscale for external access instead
```

---

## IP Addressing Summary

### Managed Network (Via sw1-modem)

| Subnet | Gateway | Devices |
|--------|---------|----------|
| 10.1.1.0/24 | 10.1.1.1 (modem) | All cluster nodes |

### Modem Network (Direct to modem)

| Subnet | Gateway | Devices |
|--------|---------|----------|
| **Unknown** | 10.1.1.1 (modem) | Deco XE75, WiFi clients |
| **Likely:** 192.168.1.0/24 or 10.0.0.0/24 | | (Check Deco interface) |

### How to Find Modem Subnet

**Options:**
1. Check Deco XE75 admin interface → Network settings
2. Connect WiFi client → Check IP address (ipconfig / ifconfig)
3. Login to modem web UI → DHCP client list
4. Check modem's LAN subnet configuration

---

## Deco XE75 Implications

### VLAN 591 (Guest Network)

**Current Understanding:**
- Deco XE75 uses VLAN 591 for guest network isolation
- This VLAN is **internal to Deco/modem**
- **NOT visible** to sw1-modem (Deco not connected to switch)
- **NOT part of** managed VLAN scheme (10, 20, 30, 40, 50, 60, 99)

**What This Means:**
- Guest WiFi clients are isolated from main WiFi
- Guest WiFi clients are on modem's subnet (not 10.1.1.x)
- Guest WiFi clients CANNOT reach 10.1.1.x network (unless modem forwards)

### Main WiFi Network

**Characteristics:**
- No VLAN tagging (uses modem's native network)
- All devices on same subnet
- Can potentially reach 10.1.1.x if modem allows routing
- Not managed by sw1-modem

---

## Files Updated

1. `/etc/nixos/docs/networking/pvid-configuration-plan-20260312.md` - Updated P3 as empty
2. `/etc/nixos/docs/networking/deco-xe75-guest-config-20260312.md` - Needs update for direct connection
3. `/etc/nixos/scripts/tplink-configure-pvids.py` - Updated PVID targets

---

## Recommendations

### For Current Setup (Keep as-is)

✅ **DO:**
- Keep Deco direct to modem (simpler, more reliable)
- **DO NOT** forward all ports from modem to cluster
- Use Tailscale VPN for external access to cluster services
- Monitor modem's port forwarding rules

❌ **DON'T:**
- Don't expose cluster management ports (6443, 10250) to modem network
- Don't enable UPnP on modem that might expose cluster services
- Don't expect WiFi devices to be on managed VLANs

### For Future Enhancement (If Desired)

**If better WiFi control is needed:**
1. Enable bridge mode on modem
2. Add dedicated router between modem and network
3. Move Deco to be managed switch device (or upgrade to enterprise AP)
4. Apply VLAN policies to WiFi through managed switches

---

**Status:** Documented and understood
**Impact:** Low - this architecture is functional and reasonable
**Action Required:** None - this is the intended design
