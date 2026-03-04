# Monitor Configuration

This directory contains the persistent monitor configuration for your KDE Plasma 6 setup.

## What This Does

- Automatically applies your 4-monitor layout on login
- Gracefully handles TV (HDMI-A-2) being on or off
- Maintains screen priorities (DP-5 is primary)
- Works on both login screen (SDDM) and desktop session

## Monitor Layout

### Desk Monitors (Always Configured)
1. **DP-5** - Primary display, 1920x1080, position (0, 349), Priority 1
2. **DP-4** - Top desk monitor, 1920x1080, position (1920, 0), Priority 2
3. **DP-6** - Bottom desk monitor, 1600x900, position (1920, 1080), Priority 3

### TV (Optional)
4. **HDMI-A-2** - 4K HDR TV, 3840x2160 scaled to 2560x1440 (1.5x), position (3520, 1080), Priority 4
   - Only configured if connected
   - Automatically skipped if TV is off

## How It Works

### Automatic Configuration
The setup runs automatically via:
1. **Systemd user service**: `plasma-monitor-setup.service` (runs at login)
2. **Plasma autostart**: Desktop entry in `/etc/xdg/autostart/`
3. **SDDM integration**: Login screen uses KScreen's automatic configuration

### Manual Application
If monitors get messed up, you can manually reapply the configuration:

```bash
# Option 1: Run the setup script directly
plasma-monitor-setup

# Option 2: Use the wrapper script (with better feedback)
/etc/nixos/modules/desktop/apply-monitors.sh
```

### Checking Logs
See what happened during setup:
```bash
cat /tmp/plasma-monitor-setup.log
```

## Applying the Configuration

After modifying this configuration, rebuild and switch:

```bash
cd /etc/nixos
sudo nixos-rebuild switch
```

Then log out and back in for changes to take effect.

## Troubleshooting

### Monitors not configured correctly?
1. Check the log: `cat /tmp/plasma-monitor-setup.log`
2. Verify monitors are connected: `kscreen-doctor -o`
3. Manually reapply: `plasma-monitor-setup`

### TV not appearing when connected?
1. Check if HDMI-A-2 is connected: `kscreen-doctor -o | grep HDMI-A-2`
2. The script should automatically detect and configure it

### Wrong monitor is primary?
The script sets DP-5 as priority 1 (primary). If another monitor is primary:
1. Open KDE System Settings → Displays
2. Set your preferred primary monitor
3. The configuration will persist

### Want to change the layout?
Edit the script in `/etc/nixos/modules/desktop/plasma6.nix`:
- Find the `monitorSetupScript` section
- Modify the geometry/scale/priority values
- Rebuild with `sudo nixos-rebuild switch`

## KScreen Doctor Reference

The configuration uses `kscreen-doctor` commands:
- `output.NAME.enable` - Enable the output
- `output.NAME.mode.NUMBER` - Set resolution/refresh rate
- `output.NAME.geometry.XxY/WIDTHxHEIGHT` - Position and size
- `output.NAME.scale.VALUE` - Set scaling factor (1.0 = none, 1.5 = 150%)
- `output.NAME.priority.NUMBER` - Set priority (1 = highest/primary)

Find available modes: `kscreen-doctor -o | grep -A 5 "Output: YOUR-OUTPUT-NAME"`
