# Switch MAC Address Reference

This document tracks the MAC addresses and IP assignments for all TP-Link switches in the network.

## Switch Inventory

### sw1-modem
- **MAC Address**: `8C:90:2D:AE:4D:27`
- **Reserved IP**: `10.1.1.10`
- **Current Hostname**: `SPARE-ROOM` (INCORRECT - needs renaming)
- **Location**: Connected directly to Rogers modem
- **Physical Access**: Modem location

### sw2-tv
- **MAC Address**: `60:83:E7:F7:DF:C4`
- **Reserved IP**: `10.1.1.11` ✓
- **Current Hostname**: `sw2-tv` ✓
- **Location**: TV area
- **Physical Access**: TV area

### sw3-upstairs
- **MAC Address**: `60:83:E7:F7:F4:6C`
- **Reserved IP**: `10.1.1.12`
- **Current Hostname**: `TL-SG105E-23` (INCORRECT - needs renaming)
- **Location**: Spare room / upstairs
- **Physical Access**: Spare room

### sw4-zephyr
- **MAC Address**: `A8:29:48:02:2A:1D`
- **Reserved IP**: `10.1.1.13` ✓
- **Current Hostname**: `sw4-zephyr` ✓
- **Location**: Zephyr's room
- **Physical Access**: Zephyr's room

### Mystery IoT Device
- **MAC Address**: `5C:E9:31:18:94:B4`
- **Current IP**: `10.1.1.14`
- **Device Type**: TP-Link Smart Home device (SHIP 2.0 protocol)
- **Service**: HTTP on port 80 only (port 443, 8080 closed)
- **Likely Device**: Smart plug, smart bulb, or smart wall switch
- **Status**: ⚠️ Needs investigation - not a network switch!

## IP Assignment Plan

| Switch | MAC Address | Intended IP | **Current IP** | Status |
|--------|-------------|-------------|---------------|--------|
| sw1-modem | 8C:90:2D:AE:4D:27 | 10.1.1.10 | **10.1.1.12** | ❌ Wrong IP - needs reconfigure |
| sw2-tv | 60:83:E7:F7:DF:C4 | 10.1.1.11 | **10.1.1.90** | ❌ Wrong IP - needs reconfigure |
| sw3-upstairs | 60:83:E7:F7:F4:6C | 10.1.1.12 | **10.1.1.95** | ❌ Wrong IP - needs reconfigure |
| sw4-zephyr | A8:29:48:02:2A:1D | 10.1.1.13 | **10.1.1.104** | ❌ Wrong IP - needs reconfigure |

## TP-Link Deco Mesh WiFi System

| Model | IP Address | MAC Address | Connection Type | Role |
|-------|------------|-------------|-----------------|------|
| Deco XE75 | 10.1.1.60 | 40:AE:30:5A:40:AC | Wired to modem | Primary mesh node |
| Deco XE75 | 10.1.1.45 | 40:AE:30:5A:40:9D | Wired to zephyr-switch | Wired satellite (backhaul) |
| Deco X20 | 10.1.1.191 | B0:95:75:13:09:40 | WiFi (wireless) | Wireless satellite |

## Other TP-Link Device

| Device Type | IP Address | MAC Address | Notes |
|-------------|------------|-------------|-------|
| Smart Home IoT | 10.1.1.14 | 5C:E9:31:18:94:B4 | SHIP 2.0 protocol (smart plug/bulb) |

## Required Actions

1. **Rename TL-SG105E-23 → sw3-upstairs**
   - Change hostname in modem web interface
   - Update this document

2. **Rename SPARE-ROOM → sw1-modem**
   - Change hostname in modem web interface
   - Update this document

## Notes

- All switches are TP-Link brand
- All IPs are sequential (10-13) for easy management
- MAC addresses are unique identifiers - use these for positive identification
- Hostnames are cosmetic but important for human readability
- IP assignments are reserved in the Rogers modem DHCP settings

## Verification

To verify switch identity:
1. Check MAC address against this table
2. Physically locate the switch (see location column)
3. Confirm hostname in modem interface matches intended hostname

## Current Situation (2026-03-10)

**Discovery Process**: Network scan revealed actual switch locations differ from modem DHCP reservation list.

**Key Findings**:
- **Only 2 devices reachable**: 10.1.1.12 (sw1-modem) and 10.1.1.14 (IoT device)
- **3 switches missing**: sw2-tv, sw3-upstairs, sw4-zephyr not at expected IPs
- **Web interface issue**: TP-Link switch web UI shows cached/template data, not real-time configuration
- **Static IP config problem**: Changes via web interface don't persist - form reverts to factory defaults

**Root Cause Analysis**:
The web interface at 10.1.1.12 showed incorrect MAC address (00-0A-EB-00-13-01) instead of real MAC (8C:90:2D:AE:4D:27), suggesting the UI displays cached data rather than real-time configuration.

**Recommended Next Steps**:
1. **Physical verification**: Check each location to confirm switch identities
2. **Alternative configuration**: Consider using DHCP reservations in modem instead of switch static IPs
3. **Web interface troubleshooting**: Investigate why configuration changes don't persist
4. **Scan entire subnet**: Find where sw2-tv, sw3-upstairs, and sw4-zephyr are actually located

**Last Updated**: 2026-03-10
