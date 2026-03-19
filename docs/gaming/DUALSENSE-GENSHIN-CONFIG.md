# DualSense Controller Configuration for Genshin Impact

## Status: ✅ WORKING

**Last Updated**: 2026-03-19
**Game**: Genshin Impact (via official launcher or Steam)
**Controller**: Sony DualSense PS5 (USB & Bluetooth)

---

## Problem

Genshin Impact shows Xbox controller icons instead of PlayStation icons when using a DualSense controller on Linux/Proton.

## Solution

User-space SDL2 GameControllerDB mappings (no kernel-level deadzone configuration).

---

## Current Configuration

### 1. User GameControllerDB ✅ PRIMARY FIX

**Location**: `~/.local/share/gamecontrollerdb/SDL_gamecontrollerdb.txt`

This is the **primary solution** for Genshin Impact controller recognition.

**What it does**:
- Tells SDL2/Proton that the controller is a "DualSense Wireless Controller"
- Maps buttons to PlayStation layout (✖ ○ △ □ icons)
- Covers multiple GUID formats (Linux evdev, Proton/Wine XInput)

**GUIDs included**:
```bash
# Linux evdev (USB)
0300000054c0ce60000000000000000

# Linux evdev (Bluetooth)
0500000054c0ce60000000000000000

# Proton/Wine XInput (multiple firmware variants)
0300000054c00000921000000000000
0300000054c00000921000016000000
0300000054c00000921000000010000
```

**Why user location, not system?**
- Proton reads from `~/.local/share/gamecontrollerdb/SDL_gamecontrollerdb.txt`
- System-wide `/etc/sdl2-dualsense-db` is often ignored by Proton
- User location is the SDL2 standard for per-user overrides

### 2. SDL2 Environment Variables

**Location**: `/etc/nixos/modules/gaming/gaming.nix`

```nix
environment.sessionVariables = {
  # Global joystick deadzone (5% = all joysticks)
  SDL_JOYSTICK_AXIS_DEADZONE = "5";

  # System-wide SDL2 database (fallback, may not work with Proton)
  SDL_GAMECONTROLLERDB = "/etc/sdl2-dualsense-db";
};
```

**Note**: `SDL_JOYSTICK_AXIS_DEADZONE=5` is a global setting for all joysticks, not DualSense-specific.

### 3. Touchpad Disable (Camera Drift Fix)

**Location**: `/etc/nixos/modules/gaming/gaming.nix`

```nix
# Disable DualSense/DS4 touchpad to prevent phantom input
SUBSYSTEM=="input", ATTRS{name}=="*DualSense*Touchpad*", ENV{LIBINPUT_IGNORE_DEVICE}="1"
SUBSYSTEM=="input", ATTRS{name}=="*DualShock*Touchpad*", ENV{LIBINPUT_IGNORE_DEVICE}="1"
```

**Why this is critical**:
- DualSense touchpad is hyper-sensitive (detects dust, temperature changes)
- Without this rule, touchpad sends phantom input → camera drift
- Game misinterprets touchpad X/Y as right stick movement

---

## Broken Features (Do Not Use)

### ❌ Kernel-Level Deadzone (evdev-joystick)

**Status**: BROKEN - `linuxconsole` package removed from nixpkgs

**What was supposed to happen**:
```nix
# This DOES NOT WORK - linuxconsole package was removed
RUN+="${pkgs.linuxconsole}/bin/evdev-joystick --evdev /dev/input/%k --axis 0 --deadzone 1310"
```

**Why this matters**:
- The `evdev-joystick` tool was the ONLY truly global deadzone solution for Linux
- It set deadzone at the kernel level using `EVIOCSABS` ioctl
- This affected ALL games and applications uniformly
- No replacement exists in nixpkgs or elsewhere

**Current situation**:
- ❌ NO global deadzone solution exists on Linux anymore
- ⚠️ Only framework-specific workarounds available:
  - SDL2 environment variables (native games only)
  - Wine registry (Proton games only)
  - Steam Input (Steam games only)

**Workarounds**:
- Use `SDL_JOYSTICK_AXIS_DEADZONE=5` environment variable (global, not per-axis)
- Use `set-wine-deadzone` script for Proton games (like Genshin Impact)
- Configure per-game deadzones via Steam Input

### ❌ System-Wide GameControllerDB for Proton

**Status**: UNRELIABLE - Proton often ignores `/etc/sdl2-dualsense-db`

**Why user location works better**:
- Proton explicitly reads `~/.local/share/gamecontrollerdb/SDL_gamecontrollerdb.txt`
- System-wide database is hit-or-miss with Proton

---

## Wine/Proton Deadzone (For Genshin Impact)

**Status**: ⚠️ WORKAROUND - Framework-specific, not global

### How It Works

Genshin Impact runs via Proton (Wine), which does NOT respect SDL2 environment variables. Instead, deadzone must be set via the Wine registry.

### Quick Setup

```bash
# Run the deadzone configuration script
set-wine-deadzone 5000  # Sets ~7.5% deadzone

# Values range from 0 (no deadzone) to 10000 (~15% deadzone)
# 3276 = 5% deadzone
# 5000 = ~7.5% deadzone (recommended)
# 6553 = 10% deadzone
```

**Important**: This script requires that Genshin Impact has been launched at least once to create the Proton prefix.

### What It Does

The script sets the Wine registry key:
```
HKEY_CURRENT_USER\Software\Wine\DirectInput\DefaultDeadZone = 5000
```

This affects ALL Wine/Proton games, not just Genshin Impact.

### Manual Configuration

If the script doesn't work, you can set it manually:

```bash
# Find your Genshin Impact Proton prefix
GENSHIN_PREFIX="$HOME/.steam/steam/steamapps/compatdata/955960/pfx"

# Set the deadzone registry value
reg add "$GENSHIN_PREFIX" \
  "HKCU\\Software\\Wine\\DirectInput" \
  /v DefaultDeadZone /t REG_DWORD /d 5000 /f
```

### Limitations

- ⚠️ **NOT global**: Only affects Wine/Proton games
- ⚠️ **NOT per-axis**: Sets same deadzone for all axes
- ⚠️ **Requires game launch**: Proton prefix must exist first
- ✅ **Works for Genshin Impact**: The game runs via Proton

---

## Testing & Verification

### Check Controller Detection

```bash
# Run the diagnostic script
diagnose-controller

# Or manually check:
ls -la /dev/input/by-id/ | grep -i dualsense

# Verify SDL2 sees the controller
export SDL_GAMECONTROLLERDB=~/.local/share/gamecontrollerdb/SDL_gamecontrollerdb.txt
sdl2-jstest --list
```

### Verify Touchpad is Disabled

```bash
# Check udev rules are loaded
udevadm info --export-db | grep -i "LIBINPUT_IGNORE_DEVICE.*DualSense"

# Check device handlers (should NOT show mouse1 for touchpad)
cat /proc/bus/input/devices | grep -A 5 "DualSense.*Touchpad"
```

### Test in Genshin Impact

1. **Close Genshin Impact completely**
2. **Relaunch Genshin Impact**
3. **Go to Settings → Controls**
4. **Check for PlayStation icons** (✖ ○ △ □ instead of ABXY)

If you still see Xbox icons:
- Verify `~/.local/share/gamecontrollerdb/SDL_gamecontrollerdb.txt` exists
- Check what GUID Proton sees (run game, check Proton logs)
- Try launching via Steam (Steam Input may override)

---

## Diagnostic Tool

**Location**: `~/.local/bin/diagnose-controller`

Comprehensive diagnostic script that checks:
- Physical controller detection
- SDL2 database locations
- Environment variables
- udev rules (touchpad disable)
- Available testing tools

**Usage**:
```bash
diagnose-controller
```

---

## Wine/Proton Registry Configuration

**Optional** - Only if you need Wine-specific controller tweaks.

### Disable HID Raw Mode (Force XInput)

If Genshin still shows Xbox icons after applying GameControllerDB:

```bash
# Add to Wine registry
WINEPREFIX="$HOME/.steam/steam/steamapps/compatdata/955960/pfx"
reg add "$WINEPREFIX" \
  "HKLM\\System\\CurrentControlSet\\Services\\winebus" \
  /v DisableHidraw /t REG_DWORD /d 1 /f
```

**What this does**:
- Forces Wine to expose controller as XInput device
- May help with older games that don't support native DualSense

**Note**: Genshin Impact supports DualSense natively, so this should NOT be needed if GameControllerDB is working.

---

## Per-Game Configuration (Steam Input)

If you want game-specific controller settings:

1. **Launch Genshin via Steam** (not direct launcher)
2. **Open Steam Overlay** (Shift+Tab)
3. **Controller Configuration → Desktop Configuration**
4. **Select "Sony DualSense" template**

**Advantages**:
- Per-game button mappings
- Custom deadzones per axis
- Takes effect immediately

**Disadvantages**:
- Must configure per-game
- Only works for Steam games

---

## File Manifest

### Working Files

| File | Purpose | Status |
|------|---------|--------|
| `~/.local/share/gamecontrollerdb/SDL_gamecontrollerdb.txt` | SDL2 controller mappings | ✅ Active |
| `~/.local/share/gamecontrollerdb/README.md` | Documentation | ✅ Reference |
| `~/.local/bin/diagnose-controller` | Diagnostic tool | ✅ Active |
| `/etc/nixos/modules/gaming/gaming.nix` | udev rules, env vars | ✅ Active |

### Broken/Obsolete Files

| File | Purpose | Status |
|------|---------|--------|
| `docs/gaming/DUALSENSE-DEADZONE-CONFIG.md` | Kernel-level deadzone docs | ⚠️ Outdated (linuxconsole removed) |

---

## Troubleshooting

### Issue: Still Shows Xbox Icons

**Possible causes**:
1. User GameControllerDB doesn't exist
2. Proton sees different GUID than mapped
3. Game launched without proper environment

**Fixes**:
```bash
# Verify user database exists
test -f ~/.local/share/gamecontrollerdb/SDL_gamecontrollerdb.txt || echo "NOT FOUND"

# Check what GUID Proton sees
cd ~/.steam/steam/steamapps/compatdata/955960/
tail -f pfx/dump.txt 2>/dev/null | grep -i "controller\|joystick"

# Try launching via Steam with Steam Input
```

### Issue: Camera Drift

**Possible cause**: Touchpad not disabled

**Fix**:
```bash
# Verify udev rule loaded
udevadm info --export-db | grep -i "LIBINPUT_IGNORE_DEVICE.*DualSense"

# Rebuild NixOS config
sudo nixos-rebuild switch --flake /etc/nixos#zephyr

# Reconnect controller (critical!)
```

### Issue: Deadzone Too Large/Small

**Current limitation**: Only global deadzone available (5%)

**Workarounds**:
1. **Steam Input**: Configure per-game deadzones
2. **Edit environment variable**: Change `SDL_JOYSTICK_AXIS_DEADZONE` in `gaming.nix`
3. **Wait for linuxconsole replacement**: Kernel-level per-axis deadzone currently broken

---

## References

- [SDL2 GameControllerDB Project](https://github.com/gabomdq/SDL_GameControllerDB)
- [Arch Wiki: Gamepad](https://wiki.archlinux.org/title/Gamepad)
- [Arch Wiki: Wine - PlayStation Controllers](https://wiki.archlinux.org/title/Wine#PlayStation_controllers)
- `docs/gaming/DUALSENSE-CONTROLLER-FIX.md` - Touchpad disable documentation

---

## Summary

**What works for Genshin Impact**:
1. ✅ User GameControllerDB (`~/.local/share/gamecontrollerdb/SDL_gamecontrollerdb.txt`)
2. ✅ Touchpad disable (udev rules in `gaming.nix`)
3. ⚠️ Wine/Proton registry deadzone (via `set-wine-deadzone` script)

**What doesn't work**:
1. ❌ Kernel-level per-axis deadzone (linuxconsole package removed)
2. ❌ SDL2 environment variables (Proton doesn't respect them)
3. ❌ System-wide GameControllerDB (Proton ignores it)

**Critical limitation**: There is NO global deadzone solution on Linux anymore. The kernel-level `evdev-joystick` tool (the only truly global solution) is broken because the `linuxconsole` package was removed from nixpkgs.

**Current status**: Controller is properly configured for Genshin Impact with PlayStation icons. Deadzone must be configured via Wine registry after launching the game.
