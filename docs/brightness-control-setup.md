# Monitor Brightness Control Status

## Current Status (2026-03-21)

### ✅ Working in Plasma Slider
- **ZOWIE (DP-5)**: Shows in brightness slider, works perfectly
- **Samsung TV (HDMI-A-2)**: Shows in brightness slider, works perfectly

### ❌ Not in Plasma Slider (but work via ddcutil)
- **ASUS (DP-4)**: Works via ddcutil, but not in Plasma slider
- **Acer (DP-6)**: Works via ddcutil, but not in Plasma slider

## Root Cause

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

## Solutions

### 1. ✅ Keyboard Shortcuts (Recommended)

I've created keyboard shortcuts for ASUS and Acer:

**ASUS Monitor:**
- `Ctrl+Alt+Shift+PageUp` - Brightness up
- `Ctrl+Alt+Shift+PageDown` - Brightness down

**Acer Monitor:**
- `Ctrl+Alt+Home` - Brightness up
- `Ctrl+Alt+End` - Brightness down

**To bind these shortcuts:**
1. Open System Settings → Shortcuts
2. Click "Custom Shortcuts"
3. Find "ASUS Brightness Up/Down" and "Acer Brightness Up/Down"
4. Click the "Configure" button to bind your preferred keys

### 2. ✅ Direct ddcutil Commands

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

**Root Cause:** ASUS and Acer monitors don't properly advertise brightness control capability via EDID, so KDE won't show them in the brightness slider - even though they support DDC/CI brightness control via ddcutil.

**User Requirement:** All 4 displays should be controllable via the Plasma brightness slider. This is NOT currently possible due to hardware/EDID limitations.

**Current Workaround:** While keyboard shortcuts and ddcutil commands work, they don't meet the user's requirement of slider-based control for all displays.

**Technical Note:** The monitoring modules (gaming-detection, gpu-profile-manager, mining-coordinator) did NOT cause this issue. They only manage NVIDIA GPUs via `nvidia-smi` and don't touch display configuration.
