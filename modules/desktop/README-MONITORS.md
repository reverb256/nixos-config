# Monitor Configuration

This directory contains the persistent monitor configuration for your KDE Plasma 6 setup.

## What This Does

- **Automatically applies your 4-monitor layout at boot** (before login screen!)
- Gracefully handles TV (HDMI-A-2) being on or off
- Maintains screen priorities (DP-5 is primary)
- Works on login screen (SDDM) and desktop session
- **Prevents monitor flashing** when TV turns on/off

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

### Three-Layer Automatic Configuration
The setup runs at three different levels for maximum reliability:

1. **Boot-level service** (`boot-monitor-setup.service`)
   - Runs **before display manager** starts
   - Configures monitors as soon as they're detected
   - Ensures login screen has correct layout
   - Command: `systemctl status boot-monitor-setup`

2. **User-level service** (`plasma-monitor-setup.service`)
   - Runs **after Plasma session** starts
   - Re-applies configuration to ensure it sticks
   - Runs as user service in your session
   - Command: `systemctl --user status plasma-monitor-setup`

3. **Plasma autostart** (desktop entry)
   - Fallback method via KDE's autostart system
   - Runs when Plasma fully initializes
   - Located: `/etc/xdg/autostart/plasma-monitor-setup.desktop`

### Anti-Flashing Measures

The configuration includes several features to **prevent monitor flashing**:

1. **Atomic kscreen-doctor commands**
   - All display changes applied in a single command
   - No intermediate states that cause refreshes
   - Prevents the "flicker" effect

2. **KScreen auto-configuration disabled**
   - Prevents KDE from auto-reconfiguring on hotplug
   - Stops the "disconnected/reconnected" flash cycle
   - Configuration in: `/etc/xdg/kscreenlockerrc`

3. **KWin compositing optimizations**
   - Smooth transitions on display changes
   - Prevents full screen redraws
   - Configuration in: `/etc/xdg/kwinrc`

4. **Udev hotplug handling**
   - Graceful handling of display connect/disconnect
   - Logs events for debugging
   - Rules in: systemd udev extraRules

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
4. Check boot service: `systemctl status boot-monitor-setup`
5. Check user service: `systemctl --user status plasma-monitor-setup`

### TV not appearing when connected?
1. Check if HDMI-A-2 is connected: `kscreen-doctor -o | grep HDMI-A-2`
2. The script should automatically detect and configure it
3. If not, manually trigger: `plasma-monitor-setup`

### Monitors flash when TV turns on/off?
This should be prevented, but if it still happens:
1. Check KScreen auto-config is disabled: `cat /etc/xdg/kscreenlockerrc`
2. Verify KWin settings: `cat /etc/xdg/kwinrc`
3. Check for conflicting rules in `/etc/udev/rules.d/`
4. As a last resort, add kernel parameter (see below)

### TV causes desk monitors to reconfigure?
The atomic command application should prevent this. If issues persist:
1. The script only configures connected displays
2. Desk monitors should remain stable
3. Check logs to see what's changing: `journalctl -f | grep monitor`

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

### Disabling TV at boot (kernel parameter)

If you want to completely ignore the TV at boot (prevent any hotplug detection):

1. Edit your NixOS configuration:
```nix
boot.kernelParams = [ "video=HDMI-A-1:D" ];  # Disable HDMI-A-1 at boot
```

2. Or temporarily test by adding to GRUB:
```bash
# Edit GRUB entry and add: video=HDMI-A-1:D
# Press 'e' in GRUB menu, add parameter, press F10
```

Note: This completely disables the port until you remove the parameter and reboot.

## KScreen Doctor Reference

The configuration uses `kscreen-doctor` commands:
- `output.NAME.enable` - Enable the output
- `output.NAME.mode.NUMBER` - Set resolution/refresh rate
- `output.NAME.geometry.XxY/WIDTHxHEIGHT` - Position and size
- `output.NAME.scale.VALUE` - Set scaling factor (1.0 = none, 1.5 = 150%)
- `output.NAME.priority.NUMBER` - Set priority (1 = highest/primary)

Find available modes: `kscreen-doctor -o | grep -A 5 "Output: YOUR-OUTPUT-NAME"`
