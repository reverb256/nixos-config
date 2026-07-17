# Complete Network Map - 10.1.1.0/24 Subnet
**Generated**: 2026-03-10
**Total Active Devices**: 23

## Executive Summary

Scanned entire 10.1.1.0/24 subnet and identified all active devices. All 4 planned switches are **ONLINE** but at different IPs than expected. Network contains 8 TP-Link devices (4 switches + 4 other devices), 4 NixOS cluster nodes, and various smart home/IoT devices.

---

## Network Switches (Primary Focus)

### ✅ All Switches Configured - Sequential IPs

| Switch Name | IP Address | MAC Address | Model | Status |
|-------------|------------|-------------|-------|--------|
| **sw1-modem** | **10.1.1.10** | 8C:90:2D:AE:4D:27 | TL-SG105E 5.0 | ✅ Root/Gateway Switch |
| **sw2-tv** | **10.1.1.11** | 60:83:E7:F7:DF:C4 | TL-SG105E 5.0 | ✅ TV Area Switch (Nexus) |
| **sw3-upstairs** | **10.1.1.12** | 60:83:E7:F7:F4:6C | TL-SG105E 5.0 | ✅ Distribution Switch |
| **sw4-zephyr** | **10.1.1.13** | A8:29:48:02:2A:1D | TL-SG105E 5.0 | ✅ Zephyr Room Switch |

### 🔍 TP-Link Deco Mesh WiFi System (3 units)

| IP Address | MAC Address | Model | Connection Type | Role | Notes |
|------------|-------------|-------|-----------------|------|-------|
| **10.1.1.60** | 40:AE:30:5A:40:AC | Deco XE75 | **Wired to modem** | Main/Primary | Connected to Rogers CODA-4582 modem via Ethernet |
| **10.1.1.45** | 40:AE:30:5A:40:9D | Deco XE75 | **Wired to zephyr-switch** | Wired Satellite | Connected to switch near zephyr for wired backhaul |
| **10.1.1.191** | B0:95:75:13:09:40 | Deco X20 | **WiFi (wireless)** | Wireless Satellite | WiFi-connected mesh node, extends coverage |

**Mesh Topology**:
- **Main node** (.60) connects to modem for uplink
- **Wired satellite** (.45) connects via Ethernet to switch near zephyr
- **Wireless satellite** (.191) connects via WiFi for remote coverage
- This creates a **tri-band hybrid mesh** with both wired and wireless backhaul

### Other TP-Link Device
| IP Address | MAC Address | Vendor | Device Type |
|------------|-------------|--------|-------------|
| 10.1.1.14 | 5C:E9:31:18:94:B4 | TP-Link Limited | Smart home IoT (SHIP 2.0 protocol) |

---

## NixOS Cluster Nodes (All Operational)

| Hostname | IP Address | MAC Address | Hardware Vendor | Purpose |
|----------|------------|-------------|-----------------|---------|
| **zephyr** | 10.1.1.110 | Unknown | Unknown | Control plane / daily driver |
| **nexus** | 10.1.1.120 | E0:D5:5E:A7:4B:50 | Giga-byte Technology | Storage |
| **forge** | 10.1.1.130 | 30:9C:23:AD:98:D1 | Micro-Star Intl | GPU compute |
| **sentry** | 10.1.1.140 | 70:85:C2:D2:87:BF | ASRock Incorporation | Monitoring |

**Status**: ✅ All cluster nodes at correct IPs and operational

---

## Network Infrastructure

| Device | IP Address | MAC Address | Vendor | Role |
|--------|------------|-------------|--------|------|
| **Modem/Gateway** | 10.1.1.1 | 40:0F:C1:BF:42:F7 | Vantiva USA | Rogers CODA-4582 modem |
| **Unknown** | 10.1.1.6 | F4:6C:68:02:E6:B2 | Wistron Neweb | Investigation needed |

---

## Smart Home / IoT Devices

| Device Type | IP Address | MAC Address | Vendor | Notes |
|-------------|------------|-------------|--------|-------|
| **Philips Hue** | 10.1.1.19 | EC:B5:FA:1C:1D:03 | Philips Lighting BV | Smart lighting bridge |
| **Google Device** | 10.1.1.55 | F8:0F:F9:B1:AF:A3 | Google | Possibly Nest/Chromecast |
| **Samsung Device** | 10.1.1.66 | 24:FC:E5:21:33:07 | Samsung Electronics | Likely smart TV |
| **LG Device** | 10.1.1.92 | 00:51:ED:4C:DD:97 | LG Innotek | TV or appliance |
| **Smart Controller** | 10.1.1.189 | 00:09:16:BC:0B:7C | Listman Home Technologies | Possibly ceiling fan/light controller |

---

## Other Devices

| IP Address | MAC Address | Vendor | Device Type |
|------------|-------------|--------|-------------|
| 10.1.1.79 | 74:D4:35:E3:F8:EF | Giga-byte Technology | Unknown - investigation needed |
| 10.1.1.115 | - | - | No MAC available - unknown device |
| 10.1.1.150 | F0:2F:74:F4:C5:E4 | ASUSTek Computer | Unknown - investigation needed |
| 10.1.1.170 | 84:2A:FD:FB:3D:0A | HP | Likely printer or PC |

---

## IP Address Distribution

### Switch Range (10.1.1.10-13): Sequential Assignment ✅
- **10.1.1.10**: sw1-modem (Root/Gateway) ✅
- **10.1.1.11**: sw2-tv (TV Area/Nexus) ✅
- **10.1.1.12**: sw3-upstairs (Distribution) ✅
- **10.1.1.13**: sw4-zephyr (Zephyr Room) ✅

### All Switch IPs (Configured):
- **10.1.1.10**: sw1-modem
- **10.1.1.11**: sw2-tv
- **10.1.1.12**: sw3-upstairs
- **10.1.1.13**: sw4-zephyr

### Cluster Nodes (Correct):
- **10.1.1.110**: zephyr
- **10.1.1.120**: nexus
- **10.1.1.130**: forge
- **10.1.1.140**: sentry

---

## Physical Network Topology (Complete)

```
                    Internet
                       │
                   Modem (10.1.1.1)
                       │
              ┌────────┴────────┐
              │ sw1 Port 1      │
              │ (Trunk/Uplink)  │
         ┌────┴──────────────────┴────┐
         │                            │
    sw1-modem (10.1.1.10)  XE75 WiFi
    Root/Gateway Switch
    Port 3: Deco XE75 (.60)
         │
  ┌─────┼───────────┬────────────────────┐
  │     │           │                    │
  P2    P4          P5                  (trunk)
 Prn   sw3-uplink  sw2-tv (.11)         (to sw3)
       (10.1.1.12) Distribution
  │              │
  │         ┌────┴────────────────────┐
  │         │ Port 1: Trunk from sw1  │
  │         └────┬─────────┬───────────┘
  │              │         │
  │         ┌────┴────┐  ┌──┴──────────┐
  │         │         │  │             │
  │        Nexus   krash3 krash1.5   [blank]
  │        (.120)   (.66)   (.170)    (available)
  │
  └────────────────────┐
       P2           P4-P5
    sw4-zephyr     Sentry  Forge
   (10.1.1.13)     (.140)  (.130)
       │
  ┌────┴─────────┐
  │ P1    P3   P5
  │ Trk  Deco  Zephyr
  │      XE75   (.110)
  │      (.45)  Main WS
 [blank] [blank] (available)

DECOS:
  XE75 (.60) - Primary mesh node (sw1:P3)
  XE75 (.45) - 6GHz node (sw4:P3, Zephyr room)
  X20 (.191) - Wireless satellite
```

### Complete Switch Port Configuration

#### **sw1-modem** (10.1.1.10) ✅
**Root/Gateway Switch** - Main area distribution

| Port | Connected To | Type | Device IP | Purpose |
|------|--------------|------|-----------|---------|
| **P1** | Modem | Trunk (all VLANs) | 10.1.1.1 | Internet uplink |
| **P2** | Printer | Access (VLAN 10) | - | Gaming/work VLAN |
| **P3** | Deco XE75 | Hybrid (VLAN 10, 99) | 10.1.1.60 | Primary WiFi + management |
| **P4** | sw3-upstairs | Trunk (all VLANs) | 10.1.1.12 | Distribution to upstairs |
| **P5** | sw2-tv | Trunk (VLAN 99, 30, 60) | 10.1.1.11 | TV area trunk |

#### **sw2-tv** (10.1.1.11) ✅
**TV Area Switch** - Nexus + gaming PCs

| Port | Connected To | Type | Device IP | Purpose |
|------|--------------|------|-----------|---------|
| **P1** | sw1-modem | Trunk (VLAN 99, 30, 60) | 10.1.1.10 | Uplink from root |
| **P2** | Nexus | Trunk (VLAN 99, 30, 60) | 10.1.1.120 | Storage node |
| **P3** | krash3 | Access (VLAN 10, 40) | 10.1.1.66 | Gaming + mining PC |
| **P4** | krash1.5 | Access (VLAN 10, 40) | 10.1.1.170 | Gaming + mining PC |
| **P5** | [blank] | - | - | Available |

#### **sw3-upstairs** (10.1.1.12) ✅
**Upstairs Distribution Switch**

| Port | Connected To | Type | Device IP | Purpose |
|------|--------------|------|-----------|---------|
| **P1** | sw1-modem | Trunk (all VLANs) | 10.1.1.10 | Uplink from root |
| **P2** | sw4-zephyr | Trunk (all VLANs) | 10.1.1.13 | Distribution to Zephyr room |
| **P3** | WIP PC | Access (VLAN 99 or 10) | - | Spare PC |
| **P4** | Sentry | Trunk (VLAN 99, 40, 50) | 10.1.1.140 | Monitoring node |
| **P5** | Forge | Trunk (VLAN 99, 20, 40) | 10.1.1.130 | AI + mining node |

#### **sw4-zephyr** (10.1.1.13) ✅
**Zephyr Room Workstation Switch**

| Port | Connected To | Type | Device IP | Purpose |
|------|--------------|------|-----------|---------|
| **P1** | sw3-upstairs | Trunk (all VLANs) | 10.1.1.12 | Uplink from upstairs |
| **P2** | [blank] | - | - | Available |
| **P3** | Deco XE75 6GHz | Hybrid (VLAN 10, 99) | 10.1.1.45 | Quest Pro WiFi + management |
| **P4** | [blank] | - | - | Available |
| **P5** | Zephyr | Trunk (VLAN 99, 10, 20) | 10.1.1.110 | Main workstation |

### Device Connection Summary

**NixOS Cluster Nodes:**
- **zephyr** (.110) → sw4:P5 (via sw3)
- **nexus** (.120) → sw2:P2 (via sw1)
- **forge** (.130) → sw3:P5 (via sw1→sw3)
- **sentry** (.140) → sw3:P4 (via sw1→sw3)

**Deco Mesh WiFi:**
- **XE75 Primary** (.60) → sw1:P3
- **XE75 6GHz** (.45) → sw4:P3 (Zephyr room)
- **X20 Wireless** (.191) → WiFi mesh

**Gaming PCs:**
- **krash3** (.66) → sw2:P3
- **krash1.5** (.170) → sw2:P4

**Other Devices:**
- **Printer** → sw1:P2
- **WIP PC** → sw3:P3

### Connection Details:

**Modem (10.1.1.1)**:
- Rogers CODA-4582
- **Single connection**: sw1-modem Port 1 (trunk)
- All internet traffic flows through sw1-modem

**sw1-modem** (Root Switch):
- **Port 1**: Modem uplink
- **Port 2**: Printer (gaming/work VLAN)
- **Port 3**: Deco XE75 primary WiFi
- **Port 4**: sw3-upstairs (distribution trunk)
- **Port 5**: sw2-tv (TV area trunk)
- **Role**: Central hub, carries all VLANs

**sw2-tv** (TV Area):
- **Port 1**: From sw1-modem
- **Port 2**: Nexus (storage)
- **Port 3**: krash3 (gaming/mining)
- **Port 4**: krash1.5 (gaming/mining)
- **Port 5**: Available

**sw3-upstairs** (Distribution):
- **Port 1**: From sw1-modem
- **Port 2**: To sw4-zephyr
- **Port 3**: WIP PC
- **Port 4**: Sentry (monitoring)
- **Port 5**: Forge (AI/mining)
- **Role**: Distributes to upstairs and Zephyr room

**sw4-zephyr** (Workstation):
- **Port 1**: From sw3-upstairs
- **Port 2**: Available
- **Port 3**: Deco XE75 6GHz (Quest Pro)
- **Port 4**: Available
- **Port 5**: Zephyr (main workstation)

**Deco Mesh Topology:**
- **Primary (.60)**: On sw1-modem, main WiFi coverage
- **Wired Satellite (.45)**: On sw4-zephyr, 6GHz backhaul for Quest Pro
- **Wireless Satellite (.191)**: Extends coverage to remote areas

---

## Action Items

### ✅ Completed: Switch IP Reconfiguration (2026-03-10)
All 4 switches have been reconfigured to sequential IPs (.10, .11, .12, .13):
1. ✅ **sw1-modem** (.12 → .10) - Moved to 10.1.1.10
2. ✅ **sw2-tv** (.90 → .11) - Moved to 10.1.1.11
3. ✅ **sw3-upstairs** (.95 → .12) - Moved to 10.1.1.12
4. ✅ **sw4-zephyr** (.104 → .13) - Moved to 10.1.1.13

### Priority 2: Investigate Unknown Devices
- Determine what's at 10.1.1.45, .60, .191 (TP-Link devices)
- Identify device at 10.1.1.6 (Wistron Neweb)
- Check 10.1.1.79, .150, .170

### Priority 3: Fix Modem DHCP Reservations
- Update modem DHCP reservations to match actual switch locations
- Or remove reservations entirely and use static IPs on switches

---

## Technical Notes

### Switch Configuration Issues
- TP-Link switch web interfaces show **cached/template data** not real-time configuration
- Static IP configuration via web UI doesn't persist - forms revert to factory defaults
- May need alternative configuration method (SNMP, CLI, or firmware update)

### IP Assignment Strategy
**Option A: Static IPs on Switches** (original plan)
- Pros: Switches keep IPs even if modem is replaced
- Cons: Web UI not working reliably for configuration

**Option B: DHCP Reservations in Modem** (workaround)
- Pros: Uses current IPs, no switch reconfiguration needed
- Cons: Tied to specific modem, lost if modem replaced

**Option C: Hybrid Approach**
- Use DHCP reservations for now
- Investigate alternative switch configuration methods
- Migrate to static IPs once reliable method found

---

## Scan Methodology

- **Tool**: nmap 7.98
- **Scan Type**: Ping scan (sn) for host discovery
- **Subnet**: 10.1.1.0/24 (256 IPs)
- **Duration**: 11.68 seconds
- **Results**: 23 hosts up

---

**Next Update**: After switch reconfiguration or investigation of unknown devices
