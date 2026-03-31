# Monitor Brightness Control Status

## ✅ RESOLVED (2026-03-31)

All 4 displays now show in Plasma brightness slider reliably.

### ✅ Working in Plasma Slider
- **ZOWIE (DP-5)**: Shows in brightness slider, works perfectly
- **Samsung TV (HDMI-A-2)**: Shows in brightness slider, works perfectly
- **ASUS (DP-4)**: ✅ **NOW WORKING** - Shows in brightness slider
- **Acer (DP-6)**: ✅ **NOW WORKING** - Shows in brightness slider

## The Fix

**Root Cause**: Conflicting systemd service definitions between `desktop.nix` and `plasma6.nix` prevented the brightness fix from loading.

**Solution**: Set `UseDDCUtil=false` in PowerDevil configuration (via `plasma6.nix`). This tells PowerDevil to show **ALL displays** in the brightness slider, not just those that properly report DDC/CI support via EDID.

**Implementation**:
```nix
# modules/desktop/plasma6.nix
[BrightnessControl]
UseDDCUtil=false  # Show ALL displays, not just DDC/CI-capable

[DP-5][BrightnessControl]
brightnessEnable=true
brightnessValue=100

# ... DP-4, DP-6, HDMI-A-2 also configured
```

**Commit**: `4a84746` - "fix(plasma6): resolve brightness control for all 4 monitors"

## Historical Context

### Previous Issue (2026-03-21)

**Hardware/Firmware Limitation**: ASUS and Acer monitors don't properly advertise brightness control capability via their EDID (Extended Display Identification Data), even though they **DO support** DDC/CI brightness control.

KDE Plasma Powerdevil only shows displays in the brightness slider if:
1. DDC/CI is enabled (✅ it is)
2. The monitor **reports** brightness control support via EDID (❌ ASUS/Acer don't)

### Evidence from kscreen-doctor:
```
DP-4 (ASUS):   Brightness control: unsupported, DDC/CI: allowed
DP-5 (ZOWIE):  Brightness control: supported,   DDC/CI: allowed
DP-6 (Acer):   Brightness control: unsupported, DDC/CI: allowed
HDMI-A-2 (TV): Brightness control: supported,   DDC/CI: N/A
```

## Solutions (Historical - No Longer Needed)

The following workarounds were used before the fix. All monitors now work via Plasma brightness slider.

### 1. ✅ Keyboard Shortcuts (No Longer Needed)

Previously created keyboard shortcuts for ASUS and Acer - **now obsolete** since all monitors work in the Plasma slider.

### 2. ✅ Direct ddcutil Commands (Still Available)

You can control brightness from terminal:

```bash
# ASUS (DP-4, bus 8)
ddcutil --bus 8 setvcp 10 50   # Set to 50%
ddcutil --bus 8 getvcp 10      # Get current brightness

# ZOWIE (DP-5, bus 9)
ddcutil --bus 9 setvcp 10 75

# Acer (DP-6, bus 10)
ddcutil --bus 10 setvcp 10 80

# Samsung TV (HDMI-A-2, bus 7) - Use Plasma slider
```

### 3. ✅ NixOS-Managed Scripts

Your existing scripts work perfectly:

```bash
# Manual monitor configuration
~/.local/share/applications/apply-monitors.sh

# Or run the NixOS-provided script directly
plasma-monitor-setup
```

## NixOS Display Configuration

Your NixOS setup includes:

1. **`/etc/nixos/modules/desktop/plasma6.nix`**
   - Monitor setup script (`plasma-monitor-setup`)
   - TV monitor daemon (`tv-monitor-daemon`)
   - KScreen configuration

2. **Systemd Services:**
   - `plasma-monitor-setup.service` - Runs at login
   - `plasma-kscreen.service` - Active and running
   - `tv-monitor-daemon` - Autostart at login

3. **Configuration Files:**
   - `~/.config/powerdevilrc` - DDC/CI enabled
   - `~/.local/share/kscreen/control/outputs/` - Display configs

## Technical Details

### Display Bus Mapping (ddcutil)
```
Display 0: Samsung TV   - /dev/i2c-7  (bus 7)
Display 1: ASUS        - /dev/i2c-8  (bus 8)  ❌ No slider
Display 2: ZOWIE       - /dev/i2c-9  (bus 9)  ✅ Has slider
Display 3: Acer        - /dev/i2c-10 (bus 10) ❌ No slider
```

### Why This Happened

Your NixOS configuration includes this line (plasma6.nix:369):
```nix
# Disable KScreen KDED module
[Module-kscreen]
Enabled=false
```

This disables KScreen's automatic display detection module, which is why:
- ✅ Monitor positioning works (via `kscreen-doctor` scripts)
- ✅ ZOWIE/Samsung show in slider (they report support properly)
- ❌ ASUS/Acer don't show in slider (they don't report support)

### Testing Commands

```bash
# Check what monitors are detected
kscreen-doctor -o

# Check DDC/CI capabilities
kscreen-doctor -o | grep -E "Brightness control|DDC/CI"

# Test brightness control manually
ddcutil --bus 8 getvcp 10  # ASUS
ddcutil --bus 10 getvcp 10 # Acer

# Restart monitor setup
systemctl --user restart plasma-monitor-setup
```

## Summary

**Status:** ✅ **RESOLVED** - All 4 displays controllable via Plasma brightness slider

**Root Cause:** Conflicting systemd services between `desktop.nix` and `plasma6.nix` prevented the `UseDDCUtil=false` configuration from being applied.

**Solution:** Removed duplicate services (gpu-ready, plasma-monitor-setup, tv-monitor-daemon) from `desktop.nix`. The `plasma6.nix` module now provides:
- `UseDDCUtil=false` - Shows ALL displays in brightness slider
- Explicit brightness configuration for all 4 displays
- No module conflicts

**Configuration:** Declarative NixOS module at `/etc/nixos/modules/desktop/plasma6.nix`

**Persistence:** Fix will survive reboots and rebuilds - applied automatically via NixOS configuration.

**Historical Note:** ASUS and Acer monitors don't properly advertise brightness control via EDID, but `UseDDCUtil=false` bypasses this limitation by showing all displays regardless of EDID reporting.
