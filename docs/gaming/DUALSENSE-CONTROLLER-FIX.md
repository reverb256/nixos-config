# DualSense Controller Camera Drift - Diagnosis & Fix

## Problem
**Symptom**: Camera in Honkai Star Rail (honkers-railway-launcher) continuously pulls to the **bottom-right**.

## Root Cause
The **DualSense touchpad** is being detected as a mouse device and sending input to the game, causing camera drift.

**Key Diagnostic Clue**: Issue **only occurs when controller is plugged in via USB**, not Bluetooth!
- **USB mode**: Creates full device tree including touchpad as `mouse1` device
- **Bluetooth mode**: Often simplifies device enumeration, touchpad may not be exposed
- This is why the issue appears in some games/configurations but not others

### Evidence
```bash
$ ls -la /dev/input/by-id/ | grep DualSense
...event261  # ← Touchpad exposed as "mouse"
...mouse1

$ cat /proc/bus/input/devices | grep -A 2 "DualSense.*Touchpad"
Handlers=event261 mouse1  # ← Being used as a mouse!
```

## Why This Happens

1. **DualSense has 3 separate input devices**:
   - `event25` (js0) - Main controller buttons/sticks
   - `event26` (js1) - Motion sensors (gyroscope/accelerometer)
   - `event261` (mouse1) - **Touchpad** ← THE PROBLEM

2. **Touchpads are hyper-sensitive**:
   - Detects light touches, dust, temperature changes
   - No physical deadzone like analog sticks
   - Sending constant input causes camera drift

3. **Game/Wine misinterprets touchpad**:
   - Touchpad X/Y → mapped to right stick/camera
   - Even slight pressure → camera moves constantly

## The Fix

### 1. Updated udev Rules ✅
**File**: `/etc/nixos/modules/gaming/gaming.nix`

**The Fix**:
```nix
# Match by device name from parent (ATTRS) and unique touchpad capabilities
SUBSYSTEM=="input", ATTRS{name}=="*DualSense*Touchpad*", ENV{LIBINPUT_IGNORE_DEVICE}="1"
SUBSYSTEM=="input", ATTRS{name}=="*DualShock*Touchpad*", ENV{LIBINPUT_IGNORE_DEVICE}="1"
# Fallback: Match by capability signature if name matching fails
SUBSYSTEM=="input", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="0ce6", ATTRS{capabilities/abs}=="260800000000003", ENV{LIBINPUT_IGNORE_DEVICE}="1"
```

**Why This Works**:
- **`ATTRS` (plural)**: Matches parent device attributes, not just the device itself
- **Capability signature**: The touchpad has unique `ABS=260800000000003` that no other DualSense input device has
- **Dual approach**: Name matching + capability matching = maximum reliability

**Previous Failed Attempts**:
- ❌ `KERNEL=="event*", ATTRS{name}=="..."` - Wrong device level
- ❌ `ATTR{name}=="..."` - Only matches device's own attributes, not parent

### 2. Apply the Fix
```bash
# Rebuild with new udev rules
sudo nixos-rebuild switch --flake .#zephyr

# Reload udev rules
sudo udevadm control --reload-rules
sudo udevadm trigger
```

### 3. Reconnect Controller ⚠️ CRITICAL STEP
```bash
# The new rules ONLY apply after reconnecting the controller!
# Unplug the DualSense USB cable and plug it back in
# Or if using Bluetooth: toggle Bluetooth off/on
```

**Why reconnect is required**: udev rules are applied when devices are initialized. The controller must re-initialize for new rules to take effect.

### 4. Verify in Game
- Launch Honkai Star Rail
- Open controller settings
- Check if camera still drifts
- Test right stick movement

## Additional Solutions (If Problem Persists)

### Solution A: Steam Input Controller Mapping
If the issue persists after the udev fix:

1. **Open Steam** → Big Picture Mode
2. **Settings** → **Controller** → **Desktop Configuration**
3. Select "Sony DualSense" → **Controller Layout**
4. **Disable touchpad** explicitly:
   - Uncheck "Use Touchpad as Mouse"
   - Or set touchpad mode to "Off"

### Solution B: SDL2 Game Controller Database
Create/override SDL2's controller mapping:

```bash
# Find SDL2 controller database
mkdir -p ~/.local/share/gamecontrollerdb

# Create SDL_gamecontrollerdb.txt with DualSense override
cat > ~/.local/share/gamecontrollerdb/SDL_gamecontrollerdb.txt << 'EOF'
# Sony DualSense Wireless - Disable Touchpad
0300000054c0ce6000000000000000,DualSense Wireless Controller,a:b0:b1:b2:b3:b4:b5:b6:b7:b8:b9:b10:b11:b12:b13:b14:b15:b16:b17:b18:b19:b20:b21:b22:b23:b24,b:255,b:255,b:255,platform:Linux,
EOF
```

### Solution C: Wine/Proton Controller Deadzone
Add controller deadzone configuration to Wine prefix:

```bash
# Edit Proton controller config
WINEPREFIX="/data/@games/hoyoverse/prefix"
cat > "$WINEPREFIX/user.reg" << 'EOF'
[Software\\Wine\\DirectInput\\Joysticks]
"Deadzone"=dword:00002000  # ~13% deadzone (0x2000)
EOF
```

### Solution D: Disable Touchpad via hidraw
If all else fails, disable the touchpad at kernel level:

```bash
# Temporarily disable touchpad (until reboot)
echo 0 | sudo tee /sys/module/hid_sony/parameters/touchpad_toggle

# Or add to kernel parameters (permanent):
# In /etc/nixos/hosts/zephyr/configuration.nix:
boot.kernelParams = [
  # ... existing params ...
  "hid_sony.touchpad_toggle=0"
];
```

## Verification Commands

### Check if Touchpad is Ignored
```bash
# Should show LIBINPUT_IGNORE_DEVICE=1
udevadm info --name=/dev/input/event261 | grep LIBINPUT

# Check device handlers
cat /proc/bus/input/devices | grep -A 5 "DualSense.*Touchpad"
# Should not show mouse1 handler if ignored
```

### Test Controller Input
```bash
# Install joystick testing tool
nix-shell -p joystick

# Test controller
jstest /dev/input/js0
# Move sticks and press buttons - check for ghost input

# Check for drift
jstest --event /dev/input/event25
# Watch for constant values (should all be 0 at rest)
```

### Monitor Input Events
```bash
# Monitor controller events in real-time
evtest /dev/input/event25

# Monitor touchpad specifically
evtest /dev/input/event261
# Should show NO events if touchpad is ignored
```

## Honkai Star Rail Specific Notes

### Wine Prefix Location
```bash
/data/@games/hoyoverse/prefix
```

### Launcher Config
```json
{
  "game": {
    "wine": {
      "prefix": "/data/@games/hoyoverse/prefix",
      "selected": "spritz-wine-tkg-staging-wow64-10.15-8"
    }
  }
}
```

### Known Issues with Wine Controllers
- Wine/Proton may map touchpad to right stick
- Some Wine versions ignore SDL2 controller database
- `sdl2-jstest` shows different mappings than actual game

## Preventing Future Issues

### 1. Always Rebuild After udev Changes
```bash
sudo nixos-rebuild switch --flake .#zephyr
```

### 2. Reconnect Controller After Changes
- Unplug USB or toggle Bluetooth off/on
- This forces udev to re-apply rules

### 3. Test with Multiple Tools
```bash
# Test with Steam
steam steam://open/1409980900842063  # Test with any game

# Test with native SDL2 tools
sdl2-jstest --list

# Test with kernel interface
evtest /dev/input/event25
```

## Other Controllers

If you use multiple controllers, you may need similar rules for each:

### DualShock 4 (PS4)
```nix
SUBSYSTEM=="input", ATTR{name}=="*DualShock*Touchpad*", ENV{LIBINPUT_IGNORE_DEVICE}="1"
```

### Xbox Series X|S
```nix
# Xbox controllers usually don't have touchpads, but if you have drift:
# Check for guide button being held down (common cause of drift)
```

### Nintendo Switch Pro Controller
```nix
# Switch Pro controllers have good native support, rarely drift
# If drift occurs, it's usually hardware calibration issue
```

## References

- [Steam Controller Configurations](https://github.com/ValveSoftware/linux-configs)
- [SDL2 Game Controller Database](https://github.com/gabomdq/SDL_GameControllerDB)
- [DualSense Linux Support](https://gitlab.freedesktop.org/hadley/dualsensectl)
- [Wine HID Joystick Documentation](https://wiki.winehq.org/Joystick)

## Status

- [x] Root cause identified (touchpad as mouse)
- [x] udev rules fixed in gaming.nix
- [x] NixOS build successful
- [ ] **Next: Rebuild system and test**

After running `sudo nixos-rebuild switch --flake .#zephyr`:
1. Reconnect your DualSense controller
2. Launch Honkai Star Rail
3. Test camera movement
4. Report back if drift persists
