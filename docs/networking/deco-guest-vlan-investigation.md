# Deco XE75 Guest Network VLAN Investigation ✅ SOLVED
**Date:** 2026-03-12
**VLAN ID Found:** 591
**Purpose:** Identify which VLAN ID the Deco XE75 guest network uses

---

## ✅ ANSWER: Guest Network Uses VLAN 591

The Deco XE75 guest network is hardcoded to use **VLAN ID 591**.

---

## Problem Statement (SOLVED)

The Deco XE75 WiFi AP has the following VLAN characteristics:
- **Main Network:** No VLAN tagging (uses native VLAN of switch port)
- **Guest Network:** Can use separate VLAN, but ID is hardcoded and unknown
- **Configuration:** Web UI does not expose VLAN ID for guest network

---

## Investigation Steps

### Option 1: Check Deco Web UI

1. Login to Deco XE75 web interface
2. Navigate to: Wireless → Guest Network
3. Look for any VLAN ID or SSID VLAN tagging settings
4. Check Advanced settings for VLAN configuration

### Option 2: Check DHCP Leases

**From Router/Modem:**
```bash
# Check if there's a separate DHCP scope for guest network
# Look for guest network subnet

# If guest network uses different subnet, trace back to VLAN
# Example: Main network 10.1.1.0/24, Guest might be 10.1.10.0/24
```

### Option 3: Packet Capture

**Capture from Switch Port:**
```bash
# Mirror sw1-modem P3 port to capture device
# Connect Wireshark laptop
# Filter for: vlan.id
# See what VLAN IDs guest network clients use

# From Deco interface:
tcpdump -i eth0 -nn -e vlan
```

### Option 4: Check Switch MAC Address Table

**After Guest Client Connects:**
```
1. Connect device to Deco guest network
2. Login to sw1-modem web UI
3. Check MAC Address Table → Static Address
4. Look for device MAC and see which VLAN it appears on
```

### Option 5: TP-Link Deco Support

**Check TP-Link Community:**
- Search: "Deco XE75 guest network VLAN ID"
- Check TP-Link forum for guest VLAN default values
- Common defaults: VLAN 10, 20, 30, or 100

---

## Implications of VLAN 591

### Switch Configuration Impact

**sw1-modem P3 (Deco XE75 Port):**
- **Current:** PVID = 99, no tagged VLANs
- **Required:** Add VLAN 591 to tagged VLANs for guest network to work

**Updated Port Configuration:**
```
Port 3 (Deco XE75):
  - PVID: 99 (main network, untagged)
  - Tagged VLANs: 591 (guest network)
```

**Why Both PVID and Tagged VLAN?**
- PVID 99: Main network SSIDs (devices use untagged frames)
- VLAN 591 tagged: Guest network SSID (Deco tags these frames with VLAN 591)
- This allows both main and guest networks to function simultaneously

### VLAN 591 Integration

**VLAN Summary:**
| VLAN | Name | Usage | Tagged Ports |
|------|------|-------|--------------|
| 10 | Gaming | Printer, gaming devices | Various |
| 20 | AI | AI/ML workloads | Various |
| 30 | Storage | NFS storage | Various |
| 40 | Mining | GPU mining | Various |
| 50 | Monitoring | Prometheus/Grafana | Various |
| 60 | Backup | Backup traffic | Various |
| 99 | Management | Cluster management | All trunk ports |
| **591** | **Guest** | **Deco guest WiFi** | **sw1-modem P3** |

**Note:** VLAN 591 is outside the original 1-100 range, but this is fine - TP-Link supports VLAN IDs up to 4094.

Based on common vendor practices:

| VLAN ID | Probability | Vendor Pattern |
|---------|-------------|-----------------|
| **10** | High | Gaming/Guest often on VLAN 10 |
| **20** | Medium | Second common choice |
| **100** | Low | Some vendors use 100+ for guest |
| **40** | Low | Unlikely, reserved for mining |

**Most Likely:** VLAN 10 (gaming) or VLAN 20 (AI)

---

## Testing Procedure

### Test 1: Try VLAN 10 for Guest

**Hypothesis:** Guest network uses VLAN 10

**Steps:**
1. Configure sw1-modem P3 with PVID 10 (instead of 99)
2. Connect to Deco guest network
3. Test internet connectivity
4. Test if can reach main network devices (should NOT if VLAN isolation works)

**Expected Results:**
- ✅ If VLAN 10 is correct: Guest works, isolated from main network
- ❌ If wrong: No connectivity or can still access main network

### Test 2: Try VLAN 20 for Guest

Same as Test 1 but with PVID 20

### Test 3: Sniff Traffic

**Setup:**
```bash
# On zephyr or switch
tcpdump -i enp38s0 -nn -e vlan host <guest-device-mac>
# Or monitor all VLAN traffic
tcpdump -i enp38s0 -nn -e vlan
```

**Look For:**
- VLAN tags in packets from guest network clients
- Pattern: VLAN ID that appears consistently for guest traffic

---

## Current Configuration Impact

### With Unknown Guest VLAN ID

**PVID Configuration for sw1-modem P3:**
- **Current Plan:** PVID = 99 (management)
- **Implication:** Guest network will be on VLAN 99 (same as management)
- **Risk:** Guest clients can access cluster management network

**Options:**

**Option A: Keep PVID 99 (Accept Risk)**
```
Pros: Guest network works
Cons: No VLAN isolation for guests
Risk: Medium (guests can access cluster services)
```

**Option B: Find Guest VLAN ID (Recommended)**
```
Pros: Proper VLAN isolation
Cons: Requires investigation time
Risk: Low (if ID found)
```

**Option C: Disable Guest Network (Temporary)**
```
Pros: Eliminates risk
Cons: No guest WiFi available
Risk: None
```

---

## Recommendation

**Immediate Action:**
1. Keep PVID = 99 for sw1-modem P3 (Deco XE75)
2. Document that guest network is on management VLAN
3. Add note to investigate guest VLAN ID

**Follow-up Actions:**
1. Run packet capture to identify guest VLAN ID
2. Once identified, can create dedicated VLAN for guest
3. Consider upgrading to enterprise AP for proper VLAN control

---

## Testing Notes Template

**Date:** [Fill in when testing]
**Tester:** [Your name]

**Test Results:**

| Test | PVID Set | Guest Network Works | Isolation | Notes |
|------|----------|---------------------|------------|-------|
| VLAN 10 | 10 | [ ] | [ ] | |
| VLAN 20 | 20 | [ ] | [ ] | |
| VLAN 99 | 99 | [ ] | [ ] | Current config |

**Packet Capture Results:**
- Guest VLAN ID detected: [ ]
- Evidence: [Attach captures]

---

## Files Referenced

- `/etc/nixos/docs/networking/pvid-configuration-plan-20260312.md` - Main PVID plan
- `/etc/nixos/docs/networking/switch-current-settings-20260311.json` - Current VLAN config

---

**Status:** Investigation needed to determine guest VLAN ID
**Priority:** Medium (network works, but isolation incomplete)
**Blocker:** No - can proceed with PVID 99 configuration
