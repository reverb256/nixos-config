# TV Monitor Daemon - Automatic TV Power Management

## What It Does

The TV monitor daemon automatically manages your 4K TV (HDMI-A-2) display and audio when you turn the TV on or off:

- **TV turns OFF**: Automatically disables the TV display and switches audio away from HDMI
- **TV turns ON**: Re-enables the TV display with full HDR configuration
- **No flashing**: Other monitors remain stable throughout the process
- **Smart detection**: Distinguishes between "physically connected" and "actually powered on"

## How It Works

### State Detection

The daemon runs every 5 seconds and checks:

1. **Is TV connected?** - Physical HDMI connection detected
2. **Is TV enabled?** - Display is actively accepting signals (not in standby)
3. **TV is ON** = connected + enabled
4. **TV is OFF** = not connected OR not enabled (standby mode)

This prevents the issue where a TV in standby mode still appears as an active display.

### State Machine

```
┌─────────────┐     TV ON     ┌─────────────┐
│   OFF       │ ─────────────→ │    ON       │
│ (disabled)  │               │  (enabled)  │
└─────────────┘               └─────────────┘
      ▲                             │
      │     TV OFF                  │
      └─────────────────────────────┘
```

**Initial state**: Detected on startup, logged but no action taken

**ON → OFF**: Disables TV output + switches audio from HDMI to fallback
**OFF → ON**: Enables TV output + configures HDR, scaling, position

### Audio Switching

When TV turns OFF:
- Checks if default audio sink is HDMI
- Finds first non-HDMI audio sink (excludes DualSense controller)
- Switches default audio to fallback sink
- Prevents audio from playing to a disabled display

When TV turns ON:
- Re-enables TV display with full configuration
- **Does NOT force audio to HDMI** - lets you choose
- Ensures audio isn't stuck on a disconnected sink

## Features

### Display Configuration

When TV turns ON, the daemon applies:
```bash
kscreen-doctor \
  output.HDMI-A-2.enable \
  output.HDMI-A-2.mode.1 \              # Preferred mode
  output.HDMI-A-2.position.3520,1080 \  # Layout position
  output.HDMI-A-2.scale.1.5 \           # 150% scaling
  output.HDMI-A-2.priority.4 \          # Priority 4
  output.HDMI-A-2.hdr.enable \          # HDR enabled
  output.HDMI-A-2.sdr-brightness.900    # SDR brightness
```

All settings applied atomically in a single command to prevent flashing.

### Logging

**Log file**: `/tmp/tv-monitor-daemon.log`
- Timestamps all state changes
- Records audio switching actions
- Tracks configuration success/failures

**State file**: `/tmp/tv-state`
- Persists current TV state across daemon restarts
- Values: "enabled", "disabled", or empty (unknown)

### Notifications

Desktop notifications for state changes:
- "TV turned off - Disabling display and audio"
- "TV turned on - Enabling display with HDR"

## Service Details

**Service name**: `tv-monitor-daemon.service`
**Type**: User systemd service
**Autostart**: Enabled (starts with graphical session)
**Restart**: Always (restarts if crashes, 5s delay)

### Management Commands

```bash
# Check status
systemctl --user status tv-monitor-daemon

# View logs (real-time)
journalctl --user -u tv-monitor-daemon -f

# View log file
cat /tmp/tv-monitor-daemon.log

# Restart daemon
systemctl --user restart tv-monitor-daemon

# Stop daemon
systemctl --user stop tv-monitor-daemon

# Disable autostart
systemctl --user disable tv-monitor-daemon
```

## Testing

### Test 1: TV Power Cycle

1. **Turn TV OFF using remote**
   - Wait 5-10 seconds
   - Check log: `cat /tmp/tv-monitor-daemon.log`
   - Expected: "TV DISABLING: Disabling HDMI-A-2 and switching audio"
   - Notification should appear

2. **Verify TV is disabled**
   ```bash
   kscreen-doctor -o | grep -A 3 "HDMI-A-2"
   # Should show "disabled" or not appear at all
   ```

3. **Verify audio switched**
   ```bash
   wpctl status | grep "Default Sink"
   # Should show non-HDMI sink
   ```

4. **Turn TV ON using remote**
   - Wait 5-10 seconds
   - Check log: `cat /tmp/tv-monitor-daemon.log`
   - Expected: "TV ENABLING: Enabling and configuring HDMI-A-2"
   - Notification should appear

5. **Verify TV is enabled with HDR**
   ```bash
   kscreen-doctor -o | grep -A 5 "HDMI-A-2"
   # Should show "enabled", "connected", "priority 4"
   ```

### Test 2: Monitor Stability

While turning TV on/off:
- Watch other monitors (DP-5, DP-4, DP-6)
- They should **NOT flash or reposition**
- Windows should stay in place
- No panel flickering

### Test 3: Audio Switching

1. Play music with TV ON
2. Turn TV OFF
3. Audio should switch to another device automatically
4. Turn TV ON
5. TV display returns but audio stays on chosen device

## Troubleshooting

### Daemon not running?

```bash
# Check if service is enabled
systemctl --user is-enabled tv-monitor-daemon

# Check if service is active
systemctl --user is-active tv-monitor-daemon

# View recent logs
journalctl --user -u tv-monitor-daemon -n 50
```

### TV not being detected?

```bash
# Check if HDMI-A-2 is connected
kscreen-doctor -o | grep "HDMI-A-2"

# Check if HDMI-A-2 is enabled
kscreen-doctor -o | grep -A 3 "HDMI-A-2" | grep enabled

# Manual daemon output
journalctl --user -u tv-monitor-daemon -f
```

### Audio not switching?

```bash
# Check available audio sinks
wpctl status short

# Check default sink
wpctl status | grep "Default Sink"

# Test manual audio switch
wpctl set-default <sink-id>
```

### Other monitors flashing?

This should not happen with the atomic kscreen-doctor commands. If it does:

1. Check KScreen is disabled:
   ```bash
   cat /etc/xdg/kscreenlockerrc
   # Should show: AutoConfig=false
   ```

2. Check KScreen backend is masked:
   ```bash
   systemctl --user is-enabled kscreen_backend_launcher
   # Should show: masked or disabled
   ```

3. Check logs for what's changing:
   ```bash
   journalctl -f | grep -i monitor
   ```

## Technical Details

### Dependencies

- `kdePackages.kscreen` - Display configuration
- `libnotify` - Desktop notifications
- `wireplumber` - Audio control (wpctl)

### Timing

- **Check interval**: 5 seconds
- **Restart delay**: 5 seconds (if crashes)
- **Start limit**: 3 restarts per 60 seconds

### File Locations

- **Daemon binary**: `/nix/store/*-tv-monitor-daemon/bin/tv-monitor-daemon`
- **Service file**: `/etc/systemd/user/tv-monitor-daemon.service`
- **Autostart entry**: `/etc/xdg/autostart/tv-monitor-daemon.desktop`
- **Log file**: `/tmp/tv-monitor-daemon.log`
- **State file**: `/tmp/tv-state`

## Architecture

The daemon is designed with **defense in depth**:

1. **Boot-time configuration** (boot-monitor-setup.service)
   - Runs before display manager
   - Ensures correct initial state

2. **Session-time configuration** (plasma-monitor-setup.service)
   - Runs after Plasma starts
   - Re-applies configuration

3. **Continuous monitoring** (tv-monitor-daemon.service)
   - Monitors TV power state
   - Automatically enables/disables
   - Handles audio switching

This ensures your TV is always properly managed, no matter when you turn it on or off.

## Summary

✅ **Automatic TV management** - No manual configuration needed
✅ **Smart detection** - Distinguishes connected vs powered on
✅ **No flashing** - Atomic operations, other monitors stable
✅ **Audio switching** - Automatically moves audio from HDMI
✅ **HDR support** - Full 4K HDR configuration maintained
✅ **Persistent** - State remembered across daemon restarts
✅ **Visible feedback** - Desktop notifications for all changes

Your 4K TV is now fully integrated into your desktop setup! 🎉
