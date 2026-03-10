# CORRECTED Switch Documentation Summary

**Date**: 2026-03-10
**Status**: ✅ CORRECTED - All switches properly identified

## MAJOR CORRECTION

**Previous documentation had switches MISIDENTIFIED**. This has been corrected based on direct verification of switch configurations.

## Correct Switch Identification

| Switch Name | MAC Address | Correct IP | Previous (Wrong) IP | Status |
|-------------|-------------|------------|-------------------|--------|
| **sw1-modem** | 60:83:E7:F7:DF:C4 | **10.1.1.90** | 10.1.1.12 ❌ | ✅ CORRECTED |
| **sw2-tv** | 60:83:E7:F7:F4:6C | **10.1.1.95** | 10.1.1.90 ❌ | ✅ CORRECTED |
| **sw3-upstairs** | 8C:90:2D:AE:4D:27 | **10.1.1.12** | 10.1.1.95 ❌ | ✅ CORRECTED |
| **sw4-zephyr** | A8:29:48:02:2A:1D | **10.1.1.104** | 10.1.1.104 ✅ | ✅ (Was correct) |

## Correct Switch Details

### sw1-modem (10.1.1.90) - MAC: 60:83:E7:F7:DF:C4
**Role**: Modem/Gateway Switch (Root Switch)

**Port Configuration** (VERIFIED):
```
Port 1: 1000MF - Rogers modem (10.1.1.1)
Port 2: 100MF  - Printer ✅ (NORMAL - printers have 100Mbps NICs)
Port 3: 1000MF - Connected
Port 4: 1000MF - Connected
Port 5: 1000MF - Connected
```

**Key Characteristics**:
- ✅ **ALL 5 PORTS CONNECTED**
- ✅ Port 2 at 100Mbps for printer (expected behavior)
- ⚠️ **MOST CRITICAL SWITCH** - affects entire network
- 📁 Backup: `/tmp/switch-backup-sw1-modem/`

---

### sw2-tv (10.1.1.95) - MAC: 60:83:E7:F7:F4:6C
**Role**: TV Area Switch

**Port Configuration** (VERIFIED):
```
Port 1: 1000MF - Connected
Port 2: 1000MF - Connected
Port 3: 1000MF - Connected
Port 4: 1000MF - Connected
Port 5: Link Down - Empty ✅
```

**Key Characteristics**:
- ✅ Ports 1-4 all connected at 1000Mbps
- ✅ Port 5 empty and available
- 📁 Backup: `/tmp/switch-backup-sw2-tv/`

---

### sw3-upstairs (10.1.1.12) - MAC: 8C:90:2D:AE:4D:27
**Role**: Distribution Switch

**Port Configuration** (VERIFIED):
```
Port 1: 1000MF - Connected
Port 2: 1000MF - Connected
Port 3: Link Down - Empty ✅ (for "computers I'm working on")
Port 4: 1000MF - Connected
Port 5: 1000MF - Connected
```

**Key Characteristics**:
- ✅ Ports 1, 2, 4, 5 connected at 1000Mbps
- ✅ Port 3 reserved for work computers
- ⚠️ **DISTRIBUTION SWITCH** - carries cluster traffic
- 📁 Backup: `/tmp/switch-backup-sw3-upstairs/`

---

### sw4-zephyr (10.1.1.104) - MAC: A8:29:48:02:2A:1D
**Role**: Zephyr Room Switch

**Port Configuration** (VERIFIED):
```
Port 1: 1000MF - Connected
Port 2: Link Down - Empty ✅
Port 3: 1000MF - Connected
Port 4: Link Down - Empty ✅
Port 5: 1000MF - Connected
```

**Key Characteristics**:
- ✅ Ports 1, 3, 5 connected at 1000Mbps
- ✅ Ports 2 and 4 empty
- ✅ **MOST ISOLATED SWITCH** - ideal for Phase 1 testing
- 📁 Backup: `/tmp/switch-backup-sw4-zephyr/`

## All Switches - Baseline State

**Identical Configuration Across All Switches**:
- ✅ 802.1Q VLAN: DISABLED (flat network mode)
- ✅ All ports: Auto speed negotiation
- ✅ Flow Control: Disabled on all ports
- ✅ Same firmware version: 1.0.0 Build 20230214 Rel.63440
- ✅ Same hardware version: TL-SG105E 5.0

**This provides reliable rollback baseline** - simply disable 802.1Q VLAN on any switch to return to flat network mode.

## Port Status Summary

| Switch | P1 | P2 | P3 | P4 | P5 | Empty Ports | Notes |
|--------|----|----|----|----|-----|-------------|-------|
| sw1-modem | 1G | **100M** | 1G | 1G | 1G | None | P2=printer (normal) |
| sw2-tv | 1G | 1G | 1G | 1G | **Down** | P5 | TV area |
| sw3-upstairs | 1G | 1G | **Down** | 1G | 1G | P3 | Work computers |
| sw4-zephyr | 1G | **Down** | 1G | **Down** | 1G | P2, P4 | Zephyr room |

**Legend**: 1G = 1000Mbps, 100M = 100Mbps, Down = Link Down

## Key Insights from Verification

### ✅ Positive Findings

1. **All switches confirmed in identical baseline state**
   - 802.1Q VLAN disabled on all
   - Consistent configuration enables reliable rollback

2. **100Mbps on sw1-modem Port 2 is NORMAL**
   - Connected to printer
   - Printers typically have 10/100 NICs
   - 100Mbps is more than sufficient for printing
   - **NOT an issue - this is expected behavior**

3. **Complete backup documentation created**
   - All switches have full configuration backups
   - Rollback procedures clearly documented
   - Access credentials recorded

### ⚠️ Important Notes

1. **Switch Identification Corrected**
   - Previous documentation had wrong IP mappings
   - Now verified via direct switch interface access
   - MAC addresses confirm correct identification

2. **Hostname Confusion on sw3-upstairs**
   - Switch hostname shows as "sw1-modem"
   - But MAC address (8C:90:2D:AE:4D:27) confirms it's sw3-upstairs
   - This is just a label issue - doesn't affect operation

## Recommended VLAN Implementation Order

### Phase 1: sw4-zephyr (IDEAL FIRST SWITCH) ✅

**Why First**:
- ✅ Most isolated switch - only affects Zephyr workstation
- ✅ Low risk - cluster operations unaffected
- ✅ Ports 2 and 4 empty - flexible for testing
- ✅ Proves VLAN capability safely
- ✅ Easy rollback if issues occur

**Timeline**: ~30 minutes
**Risk**: LOW

---

### Phase 2: sw2-tv (TV AREA SWITCH)

**Why Second**:
- Affects TV area devices
- Medium risk
- Port 5 available for future use

**Timeline**: ~30 minutes
**Risk**: MEDIUM

---

### Phase 3: sw3-upstairs (DISTRIBUTION SWITCH)

**Why Third**:
- Carries cluster traffic
- Higher risk but not root switch
- Port 3 reserved for work computers

**Timeline**: ~45 minutes
**Risk**: MEDIUM-HIGH

---

### Phase 4: sw1-modem (ROOT/GATEWAY SWITCH) - LAST ⚠️

**Why Last**:
- **MOST CRITICAL SWITCH** - affects entire network
- All 5 ports connected
- Root switch connected to Rogers modem
- Only implement after all other switches successful

**Timeline**: ~60-90 minutes
**Risk**: HIGH

## Rollback Procedures

### Immediate Rollback (If ANY issues occur)

**Steps** (applies to any switch):
1. Access switch web interface
2. Navigate to: VLAN → 802.1Q VLAN
3. Select "Disable"
4. Click "Apply"
5. **Result**: Network returns to flat baseline mode
6. **Recovery time**: <2 minutes

### When to Rollback

**Immediate rollback if**:
- ❌ Any node loses connectivity
- ❌ Packet loss detected
- ❌ Latency increases significantly (>2x baseline)
- ❌ Kubernetes operations fail
- ❌ Any unexplained network issues

**DO NOT attempt to "fix it"** - restore baseline first, investigate later

## Documentation Files

### Corrected Backups
- **sw1-modem**: `/tmp/switch-backup-sw1-modem/` ✅ CORRECTED
- **sw2-tv**: `/tmp/switch-backup-sw2-tv/` ✅ CORRECTED
- **sw3-upstairs**: `/tmp/switch-backup-sw3-upstairs/` ✅ CORRECTED
- **sw4-zephyr**: `/tmp/switch-backup-sw4-zephyr/` ✅ (Was always correct)

### Old Incorrect Backups (Preserved)
- `/tmp/switch-backup-sw1-modem-OLD/` (was actually sw3-upstairs)
- `/tmp/switch-backup-sw2-tv-OLD/` (was actually sw1-modem)
- `/tmp/switch-backup-sw3-upstairs-OLD/` (was actually sw2-tv)

### Summary Documents
- **Phase 0 Baseline**: `/etc/nixos/docs/networking/phase-0-baseline.md`
- **Original Summary**: `/etc/nixos/docs/networking/switch-documentation-summary.md` (NEEDS UPDATE)
- **This Corrected Summary**: `/etc/nixos/docs/networking/switch-documentation-CORRECTED.md`

## Next Steps

### Option A: Proceed with Phase 1 (Recommended)

**Target**: sw4-zephyr VLAN implementation

**Prerequisites**:
- ✅ All documentation corrected
- ✅ Switches properly identified
- ✅ Baseline configuration confirmed
- ⚠️ User approval required

**Timeline**: ~30 minutes
**Risk**: LOW (only affects Zephyr)

### Option B: Verify Physical Connections

**Target**: Confirm which devices are connected to which ports

**Benefits**:
- Complete understanding of network topology
- Accurate VLAN planning
- Document actual vs planned connections

**Timeline**: ~20-30 minutes
**Risk**: NONE

## Conclusion

✅ **Switch Identification: CORRECTED**
✅ **All Switches: Properly Documented**
✅ **Baseline State: Confirmed**
✅ **Ready for Cautious VLAN Implementation**

**Key Corrections**:
- sw1-modem = 10.1.1.90 (not 10.1.1.12)
- sw2-tv = 10.1.1.95 (not 10.1.1.90)
- sw3-upstairs = 10.1.1.12 (not 10.1.1.95)
- sw4-zephyr = 10.1.1.104 ✅ (was correct)

**Recommended Next Action**: Option A (Proceed with Phase 1 on sw4-zephyr)

---

**Documentation Date**: 2026-03-10
**Correction Status**: ✅ COMPLETE
**Ready for Phase 1**: ⚠️ Awaiting user approval
