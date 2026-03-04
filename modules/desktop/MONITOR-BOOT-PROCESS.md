# Monitor Configuration: Boot Process

This document explains exactly how and when your monitor configuration is applied.

## Boot Timeline

```
┌─────────────────────────────────────────────────────────────────┐
│ BOOT PROCESS                                                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. System Boot                                                │
│     ├─ Kernel loads                                            │
│     ├─ DRM devices initialize (/dev/dri/card0)                 │
│     └─ Display hardware ready                                  │
│                                                                 │
│  2. boot-monitor-setup.service  ← RUNS HERE (Before DM!)       │
│     ├─ Displays are detected                                   │
│     ├─ kscreen-doctor applies config                           │
│     ├─ All 4 monitors positioned (if TV connected)             │
│     └─ Configuration complete before login screen              │
│                                                                 │
│  3. Display Manager (SDDM) starts                              │
│     ├─ Uses already-configured displays                        │
│     ├─ Shows login screen on correct monitors                  │
│     └─ Auto-login triggers                                     │
│                                                                 │
│  4. Plasma Session starts                                      │
│     ├─ KWin (window manager) loads                             │
│     ├─ Plasma shell initializes                                │
│     └─ User session ready                                      │
│                                                                 │
│  5. plasma-monitor-setup.service  ← RUNS HERE (After Plasma)   │
│     ├─ Re-applies configuration (ensures it sticks)            │
│     ├─ Handles any late-detecting displays                     │
│     └─ Final configuration confirmed                           │
│                                                                 │
│  6. Plasma Autostart (Fallback)                                │
│     ├─ Desktop entry executes                                  │
│     └─ Last-resort configuration application                   │
│                                                                 │
│  7. System Ready                                               │
│     └─ Monitors fully configured and stable                    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Service Details

### 1. boot-monitor-setup.service (System Level)

**File Location**: `/etc/systemd/system/boot-monitor-setup.service`

**When it runs**: Before display manager starts
- Target: `display-manager.service`
- Timing: `Before=display-manager.service`
- User: root (system level)

**Purpose**: Configure monitors at the earliest possible moment

**Status check**:
```bash
systemctl status boot-monitor-setup
```

**Logs**:
```bash
journalctl -u boot-monitor-setup -f
```

**Manual trigger** (rarely needed):
```bash
sudo systemctl start boot-monitor-setup
```

### 2. plasma-monitor-setup.service (User Level)

**File Location**: `~/.config/systemd/user/plasma-monitor-setup.service`

**When it runs**: After Plasma session starts
- Target: `graphical-session.target`
- Timing: `After=plasma-plasmashell.service`
- User: j_kro (user level)

**Purpose**: Re-apply configuration after Plasma fully loads

**Status check**:
```bash
systemctl --user status plasma-monitor-setup
```

**Logs**:
```bash
journalctl --user -u plasma-monitor-setup -f
```

**Manual trigger**:
```bash
systemctl --user start plasma-monitor-setup
```

### 3. Plasma Autostart Entry

**File Location**: `/etc/xdg/autostart/plasma-monitor-setup.desktop`

**When it runs**: During Plasma initialization
- Phase: 2 (after basic services)
- Triggered by: KDE's autostart system

**Purpose**: Fallback method if systemd services fail

**Not directly manageable** - it's a KDE desktop file

## What Happens on TV Hotplug

### Scenario 1: TV is ON at boot

```
Boot → Display detection → TV detected → Configured with other monitors
```

**Result**: All 4 monitors configured at boot, login screen sees all displays

### Scenario 2: TV is OFF at boot

```
Boot → Display detection → TV not detected → Only 3 desk monitors configured
```

**Result**: Only 3 desk monitors configured at boot, login screen uses 3 displays

### Scenario 3: TV turned ON after boot

```
Boot → 3 monitors configured → TV hotplug detected → User script triggered
```

**What happens**:
1. KDE detects hotplug event via udev
2. Script checks for connected displays
3. TV (HDMI-A-2) found, added to configuration
4. All displays reconfigured atomically (no flashing)
5. TV appears at its configured position

**Anti-flashing measures**:
- KScreen auto-config disabled (prevents auto-reconfigure)
- Atomic kscreen-doctor commands (single operation)
- KWin compositing optimized (smooth transitions)

### Scenario 4: TV turned OFF after boot

```
Boot → 4 monitors configured → TV disconnect detected → User script triggered
```

**What happens**:
1. KDE detects disconnect via udev
2. Script checks for connected displays
3. TV (HDMI-A-2) not found, skipped
4. Only 3 desk monitors configured
5. Desktop layout adjusts (windows may move)

**Anti-flashing measures**:
- Only connected displays are configured
- Atomic operations prevent intermediate states
- KWin prevents unnecessary redraws

## Comparing Before vs After

### Before This Configuration

```
Boot → Display Manager → Login Screen → Plasma → Wait... → KScreen auto-config
                                                         ↓
                                                    Monitors finally configured
                                                    (after visible flashing)
```

**Issues**:
- Configuration happened late in the process
- Login screen had wrong layout
- Visible flashing and repositioning
- TV hotplug caused full reconfigure

### After This Configuration

```
Boot → boot-monitor-setup → Display Manager → Login → Plasma → plasma-monitor-setup
       ↑                                                      ↑
    Monitors configured                                Confirmed stable
    (before DM starts)                                 (no flashing)
```

**Benefits**:
- Configuration happens before display manager
- Login screen has correct layout from the start
- No visible flashing (atomic operations)
- TV hotplug handled gracefully
- Multiple layers ensure reliability

## Why Multiple Layers?

You might wonder: "Why three different methods?"

**Defense in depth** - Each layer has a specific purpose:

1. **Boot service** (primary)
   - Runs earliest
   - Configures before login screen
   - Most important for correct initial state

2. **User service** (secondary)
   - Re-applies after Plasma loads
   - Catches any displays that initialized late
   - Ensures configuration "sticks"

3. **Autostart** (tertiary/fallback)
   - Last resort if systemd fails
   - Managed by KDE itself
   - Provides redundancy

This ensures your monitor configuration is **always correct**, no matter what.

## Manual Testing

You can test each layer independently:

```bash
# Test boot-level script manually
sudo /run/current-system/sw/bin/boot-monitor-setup

# Test user-level script manually
plasma-monitor-setup

# Test autostart entry
grep Exec /etc/xdg/autostart/plasma-monitor-setup.desktop
# Then run the Exec= line
```

## Debugging Boot Issues

If monitors aren't configured at boot:

```bash
# 1. Check if boot service ran
systemctl status boot-monitor-setup

# 2. Check boot logs
journalctl -b0 -u boot-monitor-setup

# 3. Check for display detection issues
dmesg | grep -i drm
dmesg | grep -i display

# 4. Check if kscreen-doctor worked
cat /tmp/plasma-monitor-setup.log

# 5. Verify display manager started after
systemctl status display-manager
```

## Summary

- ✅ **Configuration applies from boot** (before login screen)
- ✅ **No flashing on TV hotplug** (atomic operations + KScreen disabled)
- ✅ **Graceful TV handling** (only configures if connected)
- ✅ **Three-layer reliability** (boot, user, autostart)
- ✅ **Comprehensive logging** (journal + /tmp/)

Your monitor setup is now bulletproof! 🎯
