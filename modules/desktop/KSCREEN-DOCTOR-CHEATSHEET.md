# kscreen-doctor Command Reference

Complete guide to controlling KDE Plasma displays from the command line.

## Basic Syntax

```bash
kscreen-doctor [output.<name>.<setting> ...]
```

**Important**: Pass ALL settings in a single command for atomic application (prevents screen flashing).

## Viewing Current Configuration

```bash
# Show all outputs with current configuration
kscreen-doctor -o

# Show in JSON format
kscreen-doctor -j

# Show runtime information
kscreen-doctor -i
```

## Essential Commands

### Enable/Disable Outputs

```bash
# Enable an output
kscreen-doctor output.HDMI-1.enable

# Disable an output
kscreen-doctor output.HDMI-1.disable

# Multiple outputs in one command (atomic)
kscreen-doctor output.DP-1.enable output.HDMI-1.disable
```

### Set Resolution (Mode)

```bash
# Set mode by index number (from kscreen-doctor -o)
kscreen-doctor output.HDMI-1.mode.1

# Set mode by resolution and refresh rate
kscreen-doctor output.HDMI-1.mode.1920x1080@60

# Set mode with scaling
kscreen-doctor output.HDMI-1.mode.1 output.HDMI-1.scale.1.5
```

### Position Outputs

```bash
# Set position (relative to primary display)
kscreen-doctor output.HDMI-1.position.1920,0

# Set geometry (position + size combined)
kscreen-doctor output.HDMI-1.geometry.1920x0/1920x1080

# Position multiple displays at once
kscreen-doctor \
  output.DP-1.position.0,0 \
  output.DP-2.position.1920,0 \
  output.HDMI-1.position.3840,0
```

### Set Scale Factor

```bash
# No scaling (100%)
kscreen-doctor output.HDMI-1.scale.1

# 150% scaling (1.5x) - Wayland only
kscreen-doctor output.HDMI-1.scale.1.5

# 200% scaling (2x)
kscreen-doctor output.HDMI-1.scale.2
```

### Set Rotation

```bash
# Normal (no rotation)
kscreen-doctor output.HDMI-1.rotation.none

# Rotate left (90° counter-clockwise)
kscreen-doctor output.HDMI-1.rotation.left

# Rotate right (90° clockwise)
kscreen-doctor output.HDMI-1.rotation.right

# Inverted (180°)
kscreen-doctor output.HDMI-1.rotation.inverted

# With flipping
kscreen-doctor output.HDMI-1.rotation.flipped
kscreen-doctor output.HDMI-1.rotation.flipped90
```

### Set Priority (Primary Display)

```bash
# Set as primary display (priority 1 = highest)
kscreen-doctor output.DP-1.priority.1
kscreen-doctor output.DP-2.priority.2
kscreen-doctor output.HDMI-1.priority.3
```

### HDR and Color Settings

```bash
# Enable HDR
kscreen-doctor output.HDMI-1.hdr.enable

# Disable HDR
kscreen-doctor output.HDMI-1.hdr.disable

# Set SDR brightness (100-1000 nits)
kscreen-doctor output.HDMI-1.sdr-brightness.900

# Enable wide color gamut
kscreen-doctor output.HDMI-1.wcg.enable

# Disable wide color gamut
kscreen-doctor output.HDMI-1.wcg.disable

# Set ICC profile
kscreen-doctor output.HDMI-1.iccprofile."/path/to/profile.icc"
```

### Brightness (Non-HDR Displays)

```bash
# Set brightness (0-100)
kscreen-doctor output.HDMI-1.brightness.50
```

### Display Power Management (DPMS)

```bash
# Show DPMS status
kscreen-doctor --dpms show

# Turn off display
kscreen-doctor --dpms off

# Turn on display
kscreen-doctor --dpms on

# Turn off specific display (exclude others)
kscreen-doctor --dpms off --dpms-excluded HDMI-1
```

### Custom Modes

```bash
# Add custom mode (width, height, refresh rate in mHz, blanking)
# Example: 1920x1080 at 75Hz (75000 mHz)
kscreen-doctor output.HDMI-1.addCustomMode.1920.1080.75000.full

# Remove custom mode (by index)
kscreen-doctor output.HDMI-1.removeCustomMode.0
```

## Complete Examples

### Setup 3-Monitor Workspace

```bash
kscreen-doctor \
  output.DP-1.enable \
  output.DP-1.mode.1920x1080@60 \
  output.DP-1.geometry.0x0/1920x1080 \
  output.DP-1.scale.1 \
  output.DP-1.priority.1 \
  output.DP-2.enable \
  output.DP-2.mode.1920x1080@60 \
  output.DP-2.geometry.1920x0/1920x1080 \
  output.DP-2.scale.1 \
  output.DP-2.priority.2 \
  output.DP-3.enable \
  output.DP-3.mode.1920x1080@60 \
  output.DP-3.geometry.1920x1080/1920x1080 \
  output.DP-3.scale.1 \
  output.DP-3.priority.3
```

### Setup 4K TV with HDR

```bash
kscreen-doctor \
  output.HDMI-1.enable \
  output.HDMI-1.mode.3840x2160@60 \
  output.HDMI-1.geometry.3840x0/2560x1440 \
  output.HDMI-1.scale.1.5 \
  output.HDMI-1.priority.4 \
  output.HDMI-1.hdr.enable \
  output.HDMI-1.sdr-brightness.900 \
  output.HDMI-1.wcg.enable
```

### Portrait Mode Monitor

```bash
kscreen-doctor \
  output.DP-1.enable \
  output.DP-1.mode.1920x1080@60 \
  output.DP-1.rotation.left \
  output.DP-1.geometry.0x0/1080x1920
```

### Mirror Displays

```bash
# Set both to same position and geometry
kscreen-doctor \
  output.DP-1.enable \
  output.DP-1.geometry.0x0/1920x1080 \
  output.HDMI-1.enable \
  output.HDMI-1.geometry.0x0/1920x1080
```

## Finding Mode Numbers

```bash
# List all outputs with mode numbers
kscreen-doctor -o

# Example output:
# Output: 1 HDMI-1 enabled connected
#   Modes: 1:1920x1080@60.00*  2:1920x1080@59.94  3:1920x1080@50.00
#            ^mode 1 is active   ^mode 2             ^mode 3
```

## Best Practices

1. **Atomic Operations**: Always pass all settings in one command
   ```bash
   # Good - one command, no flashing
   kscreen-doctor output.DP-1.enable output.DP-1.mode.1

   # Bad - two commands, causes flashing
   kscreen-doctor output.DP-1.enable
   kscreen-doctor output.DP-1.mode.1
   ```

2. **Use Mode Numbers**: More reliable than resolution strings
   ```bash
   # More reliable
   kscreen-doctor output.HDMI-1.mode.1

   # Less reliable (may fail on refresh rate mismatch)
   kscreen-doctor output.HDMI-1.mode.1920x1080@60
   ```

3. **Set Geometry Last**: After mode, scale, and rotation
   ```bash
   kscreen-doctor \
     output.DP-1.mode.1 \
     output.DP-1.scale.1.5 \
     output.DP-1.rotation.none \
     output.DP-1.geometry.0x0/1920x1080
   ```

4. **Test Before Scripting**: Always test commands interactively first

5. **Log Your Commands**: Keep a record of working configurations

## Troubleshooting

### Command Fails Silently
- Check output is connected: `kscreen-doctor -o | grep your-output`
- Verify mode number exists
- Check for syntax errors

### Screen Goes Black
- Wrong mode number for display
- Incompatible resolution/refresh rate
- Wait 10 seconds - KDE should auto-revert

### Settings Don't Persist
- KScreen may auto-reconfigure
- See plasma-monitor-setup.service for persistent solution

### Need to Undo Changes
- Use KDE System Settings → Displays
- Or reboot to reset to KScreen defaults
- Or use kscreen-doctor with known good values

## Integration with Scripts

```bash
#!/bin/bash
# Get current configuration
CONNECTED=$(kscreen-doctor -o)

# Check if display is connected
if echo "$CONNECTED" | grep -q "HDMI-1.*connected"; then
    # Apply configuration
    kscreen-doctor output.HDMI-1.enable output.HDMI-1.mode.1
fi
```

## See Also

- Main README: `README-MONITORS.md`
- KDE KScreen documentation: https://docs.kde.org/stable5/en/plasma-desktop/kscreenkcm/
- Wayland fractional scaling: https://docs.kde.org/stable5/en/plasma-desktop/kcontrol/kwinscreenedges/index.html
