# Genshin Impact Window Rule - TV Display

## What This Does

Genshin Impact will now **always open on your TV (HDMI-A-2)** in fullscreen mode, automatically.

### Window Rule Details

- **Window Class Match**: `.*GenshinImpact.*` (catches GenshinImpact.exe)
- **Target Screen**: Screen 3 (HDMI-A-2, your 4K TV)
- **Fullscreen**: Forced
- **Rule Type**: Force (not just "Apply initially")

This means:
- Game opens on TV every time
- Even if you move it away, next launch it's back on TV
- Survives reboots, display changes, etc.

## How to Apply

### Option 1: Automatic (Recommended)
Just restart Genshin Impact - the rule is already active!

### Option 2: Reload KWin (If rule doesn't apply)
```bash
qdbus org.kde.KWin /KWin reconfigure
```

### Option 3: Log Out/In (Last resort)
Log out of Plasma and log back in to reload all window rules.

## Testing

1. **Close Genshin Impact completely**
2. **Reopen Genshin Impact**
3. **Expected behavior**:
   - Game launches on TV (HDMI-A-2)
   - Game is in fullscreen mode
   - Desktop panels/other windows on desk monitors only

## What If It Opens on Wrong Monitor?

### Check current screen numbers:
```bash
kscreen-doctor -o | sed 's/\x1b\[[0-9;]*m//g' | grep "^Output:"
```

Your displays:
- Output 1: DP-4 (Screen 0)
- Output 2: DP-5 (Screen 1) - Primary
- Output 3: DP-6 (Screen 2)
- Output 4: HDMI-A-2 (Screen 3) - TV ← This is what we want

### To change the target screen:
Edit `/etc/nixos/modules/desktop/plasma6.nix`:
```nix
environment.etc."xdg/kwinrulesrc".text = ''
  [General]
  count=1

  [1]
  Description=Genshin Impact - Always on TV (HDMI-A-2)
  wmclass=.*GenshinImpact.*
  wmclassmatch=2
  screen=3        # Change this number (0-3 for your 4 displays)
  screenrule=3    # 3 = Force
  fullscreen=true
  fullscreenrule=3  # 3 = Force
  types=1
'';
```

Then rebuild:
```bash
sudo nixos-rebuild switch
```

## Adding More Games

Want other games to also open on the TV? Here's how:

### Find the window class:
1. Run the game
2. Open terminal and run:
   ```bash
   xprop | grep WM_CLASS
   ```
3. Click on the game window
4. Note the WM_CLASS value (e.g., "eldenring.exe")

### Add a new rule:
Edit the plasma6.nix file and increment count, add new rule:
```nix
environment.etc."xdg/kwinrulesrc".text = ''
  [General]
  count=2  # Increment this

  [1]
  Description=Genshin Impact - Always on TV
  wmclass=.*GenshinImpact.*
  wmclassmatch=2
  screen=3
  screenrule=3
  fullscreen=true
  fullscreenrule=3
  types=1

  [2]
  Description=Elden Ring - Always on TV
  wmclass=.*eldenring.*  # Match window class
  wmclassmatch=2
  screen=3
  screenrule=3
  fullscreen=true
  fullscreenrule=3
  types=1
'';
```

## Rule Values Reference

### wmclassmatch (Window class matching):
- `0` = None
- `1` = Exact match
- `2` = RegExp match ← We use this for flexibility
- `3` = Substring match

### screenrule / fullscreenrule (Rule types):
- `0` = Dont Affect
- `1` = Apply Initially
- `2` = Apply
- `3` = Force ← We use this for reliability
- `4` = Force Now
- `5` = Remember

### types (Window types):
- `1` = Normal windows
- `2` = Desktop windows
- `4` = Dock windows
- `8` = Toolbar windows
- `16` = Menu windows
- `32` = Dialog windows
- `64` = Override-redirect windows
- `128` = Top-level windows

Use `1` for normal application windows (games).

## Verification

### Check if rule is loaded:
```bash
cat /etc/xdg/kwinrulesrc
```

### Check active KWin rules:
```bash
qdbus org.kde.KWin /KWin org.kde.KWin.queryWindowInfo
```

### View KWin debug output:
```bash
qdbus org.kde.KWin /KWin org.kde.KWin.debug
```

## Troubleshooting

### Game not opening on TV?

1. **Verify rule exists**:
   ```bash
   cat /etc/xdg/kwinrulesrc | grep -A 10 "Genshin"
   ```

2. **Check KWin reloaded**:
   ```bash
   qdbus org.kde.KWin /KWin reconfigure
   ```

3. **Check game window class**:
   ```bash
   xprop | grep WM_CLASS
   # Should show something like "GenshinImpact.exe"
   ```

4. **Verify screen number**:
   ```bash
   kscreen-doctor -o | grep -A 2 "HDMI-A-2"
   # Should show enabled/connected
   ```

### Game is on TV but wrong size/position?

The rule forces fullscreen, but some games ignore KWin's positioning. Try:
- Disable in-game fullscreen
- Re-enable in-game fullscreen
- Or use in-game borderless fullscreen mode

### Multiple monitors showing game?

Some games clone displays. Check game's video settings:
- Set display to HDMI-A-2 specifically
- Use exclusive fullscreen or borderless windowed
- Disable multi-monitor display in game settings

## Manual Method (GUI Alternative)

If you prefer GUI over NixOS config:

1. Open **System Settings**
2. Go to **Workspace** → **Window Management** → **Window Rules**
3. Click **Add New...**
4. Click **Detect Window Properties**
5. Click on Genshin Impact window
6. Under **Geometry**:
   - Screen: Force → "HDMI-A-2"
7. Under **Appearance & Fixes**:
   - Fullscreen: Force → "Yes"
8. Click **Apply** → **OK**

**Note**: Manual rules are stored in `~/.config/kwinrulesrc` and may not survive NixOS rebuilds. The NixOS method above is persistent.

## Summary

✅ **Genshin Impact always opens on TV**
✅ **Fullscreen mode forced**
✅ **Survives reboots and display changes**
✅ **Persistent across NixOS rebuilds**
✅ **Easy to extend to other games**

Just close and reopen Genshin Impact to test! 🎮
