# DualSense Deadzone Configuration

## Overview
**Extremely small 2% deadzone** applied to DualSense controller sticks at the system level.

- **Left stick (X/Y)**: 2% deadzone (primary movement)
- **Right stick (Rx/Ry)**: 2% deadzone (camera control)
- **Applied globally**: Affects all games and applications

## Why So Small?

**2% is considered "extremely small"** for a reason:
- Large deadzones (10%+) make controls feel sluggish
- DualSense has excellent analog precision (±0.008 resolution)
- 2% prevents "phantom touches" without impacting gameplay
- Still allows precise control for games that need it

## Deadzone Scale Reference

| Deadzone | Feel | Best For |
|-----------|------|----------|
| 0% | None, raw input | Fighting games, precision tasks |
| 2% | ✅ Minimal (our setting) | Most games, maintains sensitivity |
| 5% | Small | Action games, casual play |
| 10% | Medium | Racing games, less precise |
| 15%+ | Large | Children, accessibility |

## Configuration Locations

### 1. SDL2 GameControllerDB (Primary)
**File**: `/etc/sdl2-dualsense-db`

```nix
# GameControllerDB V2 format with deadzone hint
0300000054c0ce60000000000000000,DualSense Wireless Controller,...,Deadzone:2,
```

**How it works**:
- SDL2 reads this file at startup
- `Deadzone:2` tells SDL2 to apply 2% deadzone to all axes
- Affects: Native Linux games, SDL2-based titles, Proton/Wine games

**Environment variable**:
```bash
SDL_GAMECONTROLLERDB=/etc/sdl2-dualsense-db
```

### 2. evdev Calibration (Fallback)
**File**: `/etc/joystick/DualSense.calibration`

```
evdev ABS_X 2   # Left stick X
evdev ABS_Y 2   # Left stick Y
evdev ABS_RX 2  # Right stick X
evdev ABS_RY 2  # Right stick Y
```

**How it works**:
- Kernel-level calibration via evdev
- Affects ALL applications reading from /dev/input/js0
- Note: Not all applications respect evdev calibration

### 3. Steam Input (Per-Game)
**Location**: Steam → Settings → Controller → Desktop Configuration

**For each game**:
1. Right-click game → Properties → Controller
2. Check "Use Steam Input for generic controllers"
3. Launch game → Click controller icon
4. **Controller Settings** → **Right Stick** → **Deadzone**: Set to 2%

## Right Stick Axes

| Axis | Linux Name | Typical Use | Deadzone |
|------|------------|-------------|----------|
| **Rx** | **ABS_RX** | **Camera horizontal (left/right)** | **2%** ✅ |
| **Ry** | **ABS_RY** | **Camera vertical (up/down)** | **2%** ✅ |

## How to Adjust

### Make Deadzone Larger (e.g., 5%)
Edit `/etc/nixos/modules/gaming/gaming.nix`:

```nix
# In the SDL2 GameControllerDB entry, change:
Deadzone:5  # 5% instead of 2%

# In evdev calibration:
evdev ABS_RX 5
evdev ABS_RY 5
```

Then rebuild:
```bash
sudo nixos-rebuild switch --flake .#zephyr
```

### Make Deadzone Smaller (e.g., 1%)
```nix
Deadzone:1  # 1% - even more sensitive
```

### Per-Game Override (Steam)
1. Launch game via Steam
2. Open Steam Overlay (Shift+Tab)
3. Click **Controller Configuration**
4. Adjust deadzone for just that game

## Verification

### Test Deadzone in Terminal
```bash
# Install joystick testing tools
nix-shell -p joystick

# Real-time axis monitoring
jstest /dev/input/js0

# Move right stick - you should see:
# - Deadzone: Center area where values stay at 0
# - Active zone: Values respond once outside deadzone
```

### Test in Game
1. Launch Honkai Star Rail
2. Move right stick slightly
3. Should NOT see camera movement until stick moves ~2% from center
4. Full range of motion should still work normally

## Troubleshooting

### Deadzone Not Applying

**Problem**: Camera still drifts or feels too sensitive

**Check 1**: Verify SDL2 database is loaded
```bash
echo $SDL_GAMECONTROLLERDB
# Should output: /etc/sdl2-dualsense-db
```

**Check 2**: Verify file exists
```bash
cat /etc/sdl2-dualsense-db
# Should show DualSense entry with Deadzone:2
```

**Check 3**: Rebuild and switch
```bash
sudo nixos-rebuild switch --flake .#zephyr
# Then fully restart the game
```

### Deadzone Too Large/Large

**Problem**: Controls feel unresponsive

**Solution**: Reduce to 1%
```nix
Deadzone:1
```

### Deadzone Too Small/None

**Problem**: Camera drift returns

**Solutions**:
1. Increase to 3-5%
2. Check if touchpad is being ignored (see DUALSENSE-CONTROLLER-FIX.md)
3. Test with `jstest /dev/input/js0` - look for non-zero values at rest

## Advanced: Per-Axis Deadzones

If you want different deadzones for each axis:

**Edit** `/etc/nixos/modules/gaming/gaming.nix`:

```nix
# For advanced per-axis configuration, create multiple entries:
0300000054c0ce60000000000000000,DualSense Wireless Controller,a:b0:b1:b2:b3:b4:b5:b6:b7:b8:b9:b10:b11:b12:b13:b14:b15:b16:b17:b18:b19:b20:b21:b22:b23:b24,platform:Linux,
  hint:SDL_GAMECONTROLLER_DEADZONE_LEFT_STICK:=2,
  hint:SDL_GAMECONTROLLER_DEADZONE_RIGHT_STICK:=2,

# Or separate entirely:
0300000054c0ce60000000000000000,DualSense-Light,a:b0:b1:b2:...,platform:Linux,Deadzone:3,
0300000054c0ce60000000000000000,DualSense-Pro,a:b0:b1:b2:...,platform:Linux,Deadzone:1,
```

## Alternative: Steam Input Per-Game

If you prefer **per-game configuration** instead of global:

1. **Enable Steam Input** for the game
2. **Right-click game** → **Properties** → **Controller**
3. **Check** "Use Steam Input for generic controllers"
4. **Launch game**, then click **Controller icon**
5. **Adjust deadzones** per-axis in controller settings

**Advantages**:
- Different deadzone per game
- Easy GUI, no editing config files
- Takes effect immediately

**Disadvantages**:
- Must configure for each game separately
- Only works for Steam games (not Lutris, Heroic, etc.)

## Technical Details

### DualSense Precision
- **Resolution**: 16-bit (0-65535)
- **Physical precision**: Excellent (high-quality potentiometers)
- **2% deadzone**: ±1310 raw values (out of 65535)
- **At rest**: Should read 32767 (center)

### Deadzone Calculation
```
Deadzone% = (ignored_range / total_range) × 100

For 2% deadzone:
- Center ±2% = ignored
- Values 0-1310 and 64224-65535 ignored
- Active range: 1310-64224 (96% of total)
```

### Why Right Stick Specifically?

The right stick is almost universally used for:
- **Camera control** in 3D games
- **Menu navigation** in 2D games
- **Precision aiming** in shooters

Camera drift is **more noticeable and annoying** than movement drift from the left stick, so the right stick gets more attention in calibration.

## Comparison with Other Controllers

| Controller | Default Deadzone | DualSense Ours |
|------------|-----------------|---------------|
| Xbox Series X|S | ~5% | 2% ✅ (more precise) |
| PS5 DualSense | Varies | 2% ✅ |
| Switch Pro | ~5% | 2% ✅ |
| Generic Linux | 0-15% | 2% ✅ (consistent) |

## Related Documentation

- **DUALSENSE-CONTROLLER-FIX.md** - Fix for touchpad causing camera drift
- **SCOPEBUDDY_GUIDE.md** - ScopeBuddy controller integration
- **Steam Input** - https://help.steampowered.com/en/steamdeck/steaminput/

## Status

- [x] 2% deadzone configured (extremely small)
- [x] Applied system-wide via SDL2 GameControllerDB
- [x] Environment variable set: `SDL_GAMECONTROLLERDB=/etc/sdl2-dualsense-db`
- [x] NixOS configuration ready to build
- [ ] **Next: Rebuild and test in-game**

After running `sudo nixos-rebuild switch --flake .#zephyr`, the deadzone will be active for all SDL2-based games.
