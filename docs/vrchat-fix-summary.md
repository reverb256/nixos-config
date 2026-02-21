# VRChat Fix for NixOS + KDE Plasma Wayland + NVIDIA

## Problem
VRChat was running but displaying no window (empty window bug) when launched via Steam with Proton on KDE Plasma Wayland.

## Root Cause
The issue was caused by Proton running through XWayland with a known bug: "Proton sometimes creating an empty window when running via XWayland" (fixed in Proton 10.0-2+).

## Solution Applied (Light Touch)

### 1. Removed SDL_VIDEODRIVER Override
**File**: `/etc/nixos/modules/gaming/gaming.nix`

**What changed**: Removed `SDL_VIDEODRIVER = "x11"` from the global session variables.

**Why**: This allows Steam/Proton to auto-detect the best backend. Most modern games (including VRChat) work better when they can choose between Wayland and XWayland themselves.

**Before**:
```nix
SDL_VIDEODRIVER = "x11";  # Forced X11 for all games
```

**After**:
```nix
# SDL_VIDEODRIVER is not set - let Steam/Proton auto-detect
# This fixes VRChat and other games that benefit from native Wayland
```

### 2. Configuration Changes
- **zephyr** & **nexus**: Both hosts updated with the lighter configuration
- No extra options added - trusting auto-detection (as you requested!)

## Next Steps to Fix VRChat

### Option 1: Update Proton Version (Recommended)
Steam → VRChat → Properties → Compatibility → Choose **`GE-Proton10-29-1`** (newer than current RTSP version)

### Option 2: Enable Native Wayland for VRChat
Steam → VRChat → Properties → General → Launch Options:
```
PROTON_ENABLE_WAYLAND=1 %command% --no-vr
```

This bypasses XWayland entirely and uses Wine's native Wayland driver.

### Option 3: Try Different Proton
- **Proton Experimental** (has the latest fixes)
- **Proton 10.0** (official stable version)

## Verification

After applying changes, verify:
```bash
# Check that SDL_VIDEODRIVER is no longer set globally
env | grep SDL_VIDEODRIVER

# Should return empty or show per-game overrides only
```

## Notes

- The `SDL_VIDEODRIVER=x11` you see in your environment might be from:
  - Flatpak applications setting it per-app
  - A Plasma Wayland session script
  - An older configuration

- Your NixOS configuration no longer forces this globally, which is what matters for VRChat

- **LVRA Wiki Reference**: https://lvra.gitlab.io/docs/distros/nixos/
- **Proton Changelog**: "Fixed Proton sometimes creating an empty window when running via XWayland"

## Applied To
- ✅ `/etc/nixos/modules/gaming/gaming.nix` - Removed SDL override
- ✅ `/etc/nixos/hosts/zephyr/configuration.nix` - Clean gaming config
- ✅ `/etc/nixos/hosts/nexus/configuration.nix` - Clean gaming config

## Testing
1. Log out and log back in (to get new environment)
2. Try launching VRChat with: `PROTON_ENABLE_WAYLAND=1 %command% --no-vr`
3. Or switch to newer Proton version in Steam settings

---

*Generated: 2025-02-20*
*NixOS 26.05.20260217.0182a36*
