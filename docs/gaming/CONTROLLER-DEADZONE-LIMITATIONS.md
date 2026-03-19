# Linux Controller Deadzone - Critical Limitation

**Date**: 2026-03-19
**Status**: ⚠️ **NO WORKING GLOBAL SOLUTION**
**Impact**: ALL games on Linux

---

## The Problem

You requested a **global** deadzone configuration for your DualSense controller that works for **ALL games**, not just Steam or SDL2 games.

**The reality**: There is currently NO working global deadzone solution for Linux controllers.

---

## What Happened

### The Only Global Solution (Broken)

The **kernel-level evdev deadzone** via `evdev-joystick` tool was the ONLY truly global deadzone solution for Linux. It worked by:

1. Setting deadzone at the kernel level using `EVIOCSABS` ioctl
2. Affecting ALL games and applications uniformly
3. Working regardless of game engine or framework

**Why it broke**: The `linuxconsole` package providing `evdev-joystick` was **removed from nixpkgs**. No replacement exists.

### Why This Matters

```
┌─────────────────────────────────────────────────────────────┐
│                    INPUT STACK LAYERS                       │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│   Hardware → Kernel evdev → Userspace (SDL2/Wine/X11)      │
│                             ↑                               │
│                             │                               │
│                    DEADZONE SHOULD GO HERE                  │
│                  (kernel-level = global)                    │
│                                                             │
│   CURRENT WORKAROUNDS (framework-specific):                │
│   • SDL2 env vars → Native SDL2 games ONLY                 │
│   • Wine registry → Proton/Wine games ONLY                 │
│   • Steam Input → Steam games ONLY                         │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Available Workarounds

### For Genshin Impact (Proton/Wine)

**Script**: `~/.local/bin/set-wine-deadzone`

```bash
# Launch Genshin Impact at least once (creates Proton prefix)
# Then run:
set-wine-deadzone 5000  # ~7.5% deadzone (recommended)
```

**How it works**:
- Sets Wine registry key: `HKEY_CURRENT_USER\Software\Wine\DirectInput\DefaultDeadZone`
- Affects ALL Wine/Proton games (not just Genshin)
- Value range: 0 (no deadzone) to 10000 (~15% deadzone)

**Limitations**:
- ⚠️ Only works for Wine/Proton games
- ⚠️ Same deadzone for all axes (not per-axis)
- ⚠️ Requires game to be launched first

### For Native SDL2 Games

**Current config**: `SDL_JOYSTICK_AXIS_DEADZONE=5` in `modules/gaming/gaming.nix`

**Limitations**:
- ⚠️ Only works for native SDL2 games
- ⚠️ Proton/Wine games ignore this
- ⚠️ Global setting for all joysticks (not per-axis)

### For Steam Games

**Use Steam Input**:
- Per-game controller configuration
- Custom deadzones per axis
- Only works for Steam games

---

## What You Need to Do

### For Genshin Impact RIGHT NOW:

1. **Launch Genshin Impact** (creates Proton prefix at `~/.steam/steam/steamapps/compatdata/955960/`)
2. **Run the script**: `set-wine-deadzone 5000`
3. **Restart Genshin Impact**
4. **Test deadzone** in game

### For Other Games:

- **Native Linux games**: SDL2 env var already set (5% deadzone)
- **Proton games**: Use `set-wine-deadzone` script
- **Steam games**: Configure via Steam Input

---

## Future Solutions

### What Needs to Happen

1. **Fix linuxconsole package**: Someone needs to fix and re-add `evdev-joystick` to nixpkgs
2. **Alternative tool**: Create a new tool that uses `EVIOCSABS` ioctl directly
3. **Systemd integration**: Add kernel-level deadzone configuration to systemd

### How to Help

- File issue with nixpkgs: https://github.com/NixOS/nixpkgs/issues
- Ask for `evdev-joystick` replacement
- Upstream: The `linuxconsole` tools project is unmaintained

---

## Summary

| Solution Type | Status | Scope |
|---------------|--------|-------|
| **Kernel-level evdev** | ❌ **BROKEN** | Would be global |
| **Wine registry** | ✅ **WORKS** | Wine/Proton only |
| **SDL2 env vars** | ✅ **WORKS** | Native SDL2 only |
| **Steam Input** | ✅ **WORKS** | Steam games only |

**The unfortunate reality**: Linux no longer has a working global controller deadzone solution. You must configure deadzone separately for each game framework.

---

## References

- Arch Wiki: [Gamepad - Deadzones](https://wiki.archlinux.org/title/Gamepad)
- Wine Documentation: [DirectInput Registry Keys](https://wiki.winehq.org/Useful_Registry_Keys)
- SDL2 Documentation: [Environment Variables](https://wiki.libsdl.org/SDL2/EnvironmentVariables)
- NixOS Issue: linuxconsole package removal

---

**Document Version**: 1.0 | **Last Updated**: 2026-03-19
