# Deco XE75 Guest Network Configuration Guide
**Date:** 2026-03-12
**VLAN ID:** 591
**Status:** Configuration required

---

## Summary

The TP-Link Deco XE75 guest network uses **VLAN ID 591** for client isolation. This is a hardcoded value that cannot be changed in the Deco interface.

---

## Required Switch Configuration

### SW1-MODEM Port 3 (Deco XE75)

**Current State:**
```
Port 3:
  - PVID: 99 (main network)
  - Tagged VLANs: None
  - Current member VLANs: Default (1), 10, 20, 30, 40, 50, 60, 99
```

**Required Configuration:**
```
Port 3:
  - PVID: 99 (main network, untagged)
  - Tagged VLANs: ADD 591
  - VLAN 591 member ports: Tagged on P3
```

### Configuration Steps (Web UI)

1. **Login to sw1-modem:** http://10.1.1.10
2. **Navigate:** VLAN → 802.1Q VLAN → Advanced
3. **Find/Create VLAN 591:**
   - If exists: Select it
   - If not exists: Click "Add" → VLAN ID = 591 → Name = "Guest" → Create
4. **Configure Port 3 Membership:**
   - Find row for VLAN 591
   - Check "Tagged" for Port 3
   - Click Apply/Save
5. **Verify:** Deco guest network should work for clients

---

## How Deco XE75 Uses VLAN 591

### Traffic Flow

**Main Network SSIDs (e.g., "YourNetwork"):**
```
Client Device → [untagged] → Deco XE75 → [untagged] → sw1-modem P3 → VLAN 99
```
- Devices use untagged frames
- Switch assigns to PVID 99 (management VLAN)

**Guest Network SSID (e.g., "YourNetwork-Guest"):**
```
Guest Device → Deco tags with VLAN 591 → sw1-modem P3 → VLAN 591
```
- Deco adds VLAN 591 tag to frames
- Switch routes to VLAN 591 (isolated from main network)

### Why Both PVID and Tagged VLAN?

The Deco XE75 needs **both**:
- **PVID 99:** For main network traffic (untagged)
- **VLAN 591 tagged:** For guest network traffic (tagged by Deco)

This allows the Deco to support multiple SSIDs with different VLAN assignments.

---

## Security Implications

### Guest Network Isolation

**With VLAN 591 configured:**
- ✅ Guest clients **cannot** access main network devices (on VLAN 99)
- ✅ Guest clients **cannot** access cluster management (on VLAN 99)
- ✅ Guest clients **can** access internet (via modem routing)
- ✅ Main network clients **cannot** access guest clients (unless router allows)

**Without VLAN 591 configured:**
- ❌ Guest clients would be dropped (nowhere to go)
- ❌ Or fallback to PVID 99 (no isolation, bad security)

### Firewall Rules (Recommended)

**On Router/Modem (10.1.1.1):**

Consider adding inter-VLAN firewall rules:
```
Block: VLAN 591 → VLAN 99 (management)
Block: VLAN 591 → VLAN 10 (gaming)
Block: VLAN 591 → VLAN 30 (storage)
Allow: VLAN 591 → WAN (internet)
```

This ensures guest WiFi can only reach the internet, not cluster resources.

---

## VLAN 591 vs Standard VLAN Range

### Non-Standard VLAN ID

**VLAN 591 is outside the typical 1-100 range:**
- Standard VLANs: 1-100 (common practice)
- Extended range: 1-4094 (802.1Q standard)
- TP-Link supports full range, so 591 is valid

**Why TP-Link Chose 591:**
- Avoid conflicts with common VLANs (1-100)
- Reduces chance of collision with user-configured VLANs
- Consumer equipment often uses high VLAN IDs for guest/isolated networks

**Impact on Our Network:**
- VLAN 591 doesn't conflict with our VLAN 10, 20, 30, 40, 50, 60, 99
- Just another VLAN in the switch database
- No special handling required

---

## Testing Procedure

### Test 1: Create VLAN 591 on sw1-modem

**Web UI Steps:**
1. Access http://10.1.1.10
2. Navigate: VLAN → 802.1Q VLAN
3. Click "Add"
4. Enter:
   - VLAN ID: 591
   - VLAN Name: Guest
   - Tagged Ports: Check box for Port 3
5. Click Apply

**Verify:**
```
VLAN list should show:
ID: 591, Name: Guest, Tagged: [3]
```

### Test 2: Connect to Guest Network

**From WiFi Client:**
1. Connect to "YourNetwork-Guest" SSID
2. Open browser (should redirect to captive portal or just work)
3. Test connectivity:
   ```
   ping 8.8.8.8  # Should work (internet)
   ping 10.1.1.110  # Should FAIL (isolation)
   ```

**Expected Results:**
- ✅ Can reach internet (8.8.8.8)
- ✅ Cannot reach cluster nodes (10.1.1.110, 120, 130, 140)
- ✅ Cannot access switch web UI (10.1.1.10)

### Test 3: Verify Isolation

**From Cluster Node (zephyr):**
```bash
# Try to reach guest network client
ping <guest-client-ip>

# Should fail or timeout unless router allows inter-VLAN routing
```

---

## Switch Configuration Summary

### After PVID + VLAN 591 Configuration

**sw1-modem Final State:**

| Port | PVID | Device | Tagged VLANs |
|------|------|--------|---------------|
| P1 | 99 | Modem | - |
| P2 | 10 | Printer | 99 |
| P3 | 99 | Deco XE75 | **591** |
| P4 | 99 | sw3-upstairs | All VLANs |
| P5 | 99 | sw2-tv | 30, 60, 99 |

**VLAN 591 Member Ports:**
- sw1-modem P3: Tagged (Deco guest traffic)

---

## Troubleshooting

### Guest Network Not Working After PVID Change

**Symptom:** Guests can't connect after changing PVIDs

**Solution:** Ensure VLAN 591 is created and P3 is tagged member

**Check:**
1. VLAN 591 exists in switch VLAN list
2. Port 3 is tagged member of VLAN 591
3. Deco XE75 is connected to Port 3

### Guests Can Access Cluster Resources

**Symptom:** Guest devices can reach 10.1.1.x IPs

**Possible Causes:**
1. Router allows inter-VLAN routing
2. VLAN 591 not properly isolated
3. Firewall rules not configured

**Solution:** Configure firewall rules on router to block VLAN 591 → other VLANs

---

## Files Updated

1. `/etc/nixos/docs/networking/deco-guest-vlan-investigation.md` - Investigation complete
2. `/etc/nixos/docs/networking/pvid-configuration-plan-20260312.md` - Updated with VLAN 591
3. `/etc/nixos/docs/networking/deco-xe75-guest-config-20260312.md` - This file

---

## Next Steps

1. ✅ **VLAN 591 ID identified**
2. ⏳ **Create VLAN 591** on sw1-modem (via web UI or script)
3. ⏳ **Tag Port 3** for VLAN 591
4. ⏳ **Test guest network** connectivity and isolation
5. ⏳ **Configure PVIDs** on all switches per main plan
6. ⏳ **Verify** guest network isolation after PVID changes

---

**Status:** VLAN 591 identified, configuration documented, ready to implement
**Risk:** Low - Adding VLAN 591 is non-disruptive to existing traffic
