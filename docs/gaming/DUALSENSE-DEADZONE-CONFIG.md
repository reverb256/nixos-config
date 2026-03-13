# DualSense Deadzone Configuration (Fixed)

## Overview
**2% deadzone** applied to DualSense controller sticks at **kernel level via evdev** and **SDL2 environment variable**.

- **Left stick (X/Y)**: 2% deadzone (primary movement)
- **Right stick (Rx)**: 2% deadzone (camera horizontal)
- **Right stick (Ry)**: 5% deadzone (camera vertical - more drift prone)
- **Applied globally**: Affects all games and applications via kernel-level evdev

## How It Works

Your deadzone is configured at **two levels** for comprehensive coverage:

### 1. Kernel Level (evdev) - Primary
**Method**: udev rules calling `evdev-joystick`
**Applied**: When controller connects
**Affects**: All applications using evdev (`/dev/input/event*`)

```
Action: Controller connect → udev rule → evdev-joystick sets kernel flatness
```

### 2. SDL2 Level (environment variable)
**Method**: `SDL_JOYSTICK_AXIS_DEADZONE=2`
**Applied**: When SDL2 application starts
**Affects**: SDL2/SDL3 native games, Proton

## Configuration Files

### 1. udev Rules (`modules/gaming/gaming.nix`)
```nix
# Left stick (movement): 2% = 1310 raw units
ACTION=="add", SUBSYSTEM=="input", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="0ce6", \
  KERNEL=="event[0-9]*", RUN+="${pkgs.linuxconsole}/bin/evdev-joystick --evdev /dev/input/%k --axis 0 --deadzone 1310"

# Right stick: 2% horizontal, 5% vertical (3276 raw units)
ACTION=="add", SUBSYSTEM=="input", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="0ce6", \
  KERNEL=="event[0-9]*", RUN+="${pkgs.linuxconsole}/bin/evdev-joystick --evdev /dev/input/%k --axis 3 --deadzone 3276"
```

### 2. SDL2 Environment Variable
```nix
environment.sessionVariables = {
  # SDL2 joystick deadzone (0-100, default 15) - 2% for all joysticks
  SDL_JOYSTICK_AXIS_DEADZONE = "2";
  # SDL2 GameControllerDB path
  SDL_GAMECONTROLLERDB = "/etc/sdl2-dualsense-db";
};
```

### 3. SDL2 GameControllerDB (`/etc/sdl2-dualsense-db`)
```
# Standard DualSense mapping - NO Deadzone: hint (not valid in SDL2!)
0300000054c0ce60000000000000000,DualSense Wireless Controller,a:b0,b:b1,x:b2,y:b3,back:b4,guide:b5,start:b6,leftstick:b7,rightstick:b8,leftshoulder:b9,rightshoulder:b10,dpup:h0.1,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,leftx:a0,lefty:a1,rightx:a2,righty:a3,lefttrigger:a4,righttrigger:a5,platform:Linux,
```

**Important**: The `Deadzone:` hint in GameControllerDB is **NOT valid SDL2 format**. Deadzones are set via `SDL_JOYSTICK_AXIS_DEADZONE` environment variable instead.

### 4. Touchpad Disabled (udev)
```nix
# Prevents touchpad from causing "camera drift"
SUBSYSTEM=="input", ATTRS{name}=="*DualSense*Touchpad*", ENV{LIBINPUT_IGNORE_DEVICE}="1"
```

## Deadzone Scale Reference

| Deadzone | Raw Value | Feel | Best For |
|-----------|-----------|------|----------|
| 0% | 0 | None, raw input | Fighting games, precision tasks |
| 2% | 1310 | ✅ Minimal (our setting) | Most games, maintains sensitivity |
| 5% | 3276 | Small | Action games, casual play |
| 10% | 6553 | Medium | Racing games, less precise |
| 15% | 9830 | Large | Default SDL2, worn controllers |

## Right Stick Axes

| Axis | evdev Index | Linux Name | Typical Use | Deadzone | Raw Value |
|------|-------------|------------|-------------|----------|-----------|
| **Rx** | 2 | ABS_RX | Camera horizontal (left/right) | 2% | 1310 |
| **Ry** | 3 | ABS_RY | Camera vertical (up/down) | 5% | 3276 |

## Testing and Verification

### Check Current Deadzone Values
```bash
# View current evdev calibration
evdev-joystick --showcal /dev/input/by-id/usb-Sony_*-event-joystick

# Real-time axis testing
evdev-joystick --test /dev/input/by-id/usb-Sony_*-event-joystick

# SDL2 testing
sdl2-jstest --list  # List controllers
sdl2-jstest         # Real-time test
```

### Verify SDL2 Environment Variable
```bash
echo $SDL_JOYSTICK_AXIS_DEADZONE
# Should output: 2

echo $SDL_GAMECONTROLLERDB
# Should output: /etc/sdl2-dualsense-db
```

### Re-trigger udev Rules (without replug)
```bash
# Trigger rules for connected DualSense
sudo udevadm trigger --subsystem-match=input --attr-match=idVendor=054c --attr-match=idProduct=0ce6
sudo udevadm control --reload-rules
```

## For Wine/Proton Games

Add to Wine registry via `winecfg` or `regedit`:
```
[HKEY_CURRENT_USER\Software\Wine\DirectInput]
"DefaultDeadZone"="2000"
```
Values range from `0` (no deadzone) to `10000` (maximum, ~15%).

## Troubleshooting

### Deadzone Not Applying

**Check 1**: Verify udev rules are loaded
```bash
udevadm info --attribute-walk --name=/dev/input/event* | grep -i "054c.*0ce6"
```

**Check 2**: Verify calibration values
```bash
evdev-joystick --showcal /dev/input/by-id/usb-Sony_*-event-joystick
# Look for: flatness: 1310 (for 2%) or flatness: 3276 (for 5%)
```

**Check 3**: Rebuild and switch
```bash
sudo nixos-rebuild switch --flake .#zephyr
# Then reconnect controller or run:
sudo udevadm trigger --subsystem-match=input --attr-match=idVendor=054c
```

### Deadzone Too Large/Small

**Edit** `/etc/nixos/modules/gaming/gaming.nix`:

```nix
# Adjust raw values (2% = 1310, 5% = 3276, 1% = 655)
RUN+="${pkgs.linuxconsole}/bin/evdev-joystick --evdev /dev/input/%k --axis 0 --deadzone 655"  # 1%
```

Then rebuild:
```bash
sudo nixos-rebuild switch --flake .#zephyr
```

### Camera Drift Persists

1. **Verify touchpad is ignored**:
```bash
cat /proc/bus/input/devices | grep -A 5 "DualSense"
# Should see LIBINPUT_IGNORE_DEVICE="1" for touchpad
```

2. **Test with `jstest`**:
```bash
nix-shell -p linuxconsole
jstest /dev/input/js0
# Move stick slightly - values should stay at 0 in deadzone
```

3. **Increase deadzone** to 5-10% if controller hardware is worn

## Per-Game Override (Steam Input)

If you want game-specific deadzones:

1. Launch game via Steam
2. Open Steam Overlay (Shift+Tab)
3. Click **Controller Configuration**
4. Adjust deadzones per-axis

**Advantages**:
- Different deadzone per game
- Easy GUI, no editing files
- Takes effect immediately

**Disadvantages**:
- Must configure per-game
- Only works for Steam games

## Technical Details

### DualSense Precision
- **Resolution**: 16-bit (0-65535)
- **Physical precision**: Excellent (high-quality potentiometers)
- **2% deadzone**: ±1310 raw values (out of 65535)
- **At rest**: Should read 32767 (center)

### Deadzone Calculation
```
Raw Value = Percentage × 65535 × 0.01

For 2% deadzone:
- 2 × 65535 × 0.01 = 1310 raw values
- Center ±1310 = ignored
- Active range: 1310-64224 (96% of total)
```

### Why Different Values for Rx vs Ry?

The right stick vertical axis (Ry) often experiences more drift on DualSense controllers due to:
1. Physical wear patterns (thumb rests more on vertical)
2. Gravity effects on worn potentiometers
3. Manufacturing variances

The 5% setting on Ry compensates for this without making horizontal controls sluggish.

## Related Documentation

- **DUALSENSE-CONTROLLER-FIX.md** - Touchpad disable fix for camera drift
- **SCOPEBUDDY_GUIDE.md** - ScopeBuddy controller integration
- [Arch Wiki: Gamepad](https://wiki.archlinux.org/title/Gamepad) - Comprehensive Linux gamepad guide
- [SDL_GameControllerDB](https://github.com/gabomdq/SDL_GameControllerDB) - Community mappings

## Status

- [x] Kernel-level deadzone via evdev-joystick (udev rules)
- [x] SDL2 environment variable for native games
- [x] Touchpad disabled to prevent phantom input
- [x] GameControllerDB with valid mapping (no invalid Deadzone: hint)
- [x] linuxconsole package included for evdev-joystick tool
- [ ] **Next: Rebuild and test in-game**

After running `sudo nixos-rebuild switch --flake .#zephyr`, reconnect your DualSense and test in your favorite games.
