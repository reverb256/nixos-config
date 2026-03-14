# RGB Control - Temperature-Based Lighting

**Created:** 2026-03-14
**Status:** Ready for deployment

## Overview

Temperature-reactive RGB lighting control for cluster hosts, using OpenRGB, OpenRAZER, and cm-rgb for AMD Wraith Prism coolers.

## Per-Host Configuration

### Zephyr (10.1.1.110) - **Primary RGB Host**
- **Motherboard:** MSI MAG X570 TOMAHAWK WIFI (MSI Mystic Light RGB)
- **Keyboard:** Corsair K70 RGB RAPIDFIRE (per-key RGB)
- **Mouse:** Razer Naga Pro (Chroma RGB)
- **GPUs:** RTX 3060 Ti + RTX 3090 (potential RGB)
- **AIO:** Corsair H115i (RGB pump block)
- **Control:** OpenRGB (motherboard/GPU/AIO) + OpenRAZER (mouse) + liquidctl (Corsair)
- **Sensor:** Both CPU and GPU temperatures
- **Thresholds:** 50°C (cool) → 65°C (warm) → 75°C (hot)
- **Interval:** 5 seconds

### Forge (10.1.1.130)
- **Hardware:** ASRock RX 5700 XT GPUs (potentially RGB-enabled)
- **Control:** OpenRGB for GPU RGB
- **Sensor:** GPU temperature
- **Thresholds:** 60°C (cool) → 70°C (warm) → 75°C (hot)
- **Interval:** 10 seconds

### Nexus (10.1.1.120)
- **Hardware:** Razer Naga Pro mouse, Gigabyte X470 AORUS ULTRA GAMING motherboard
- **Control:** OpenRGB (motherboard) + OpenRAZER (mouse)
- **Sensor:** CPU temperature
- **Thresholds:** 50°C (cool) → 65°C (warm) → 75°C (hot)
- **Interval:** 5 seconds

### Sentry (10.1.1.140)
- **Hardware:** AMD Wraith Prism cooler, MSI B360-F PRO motherboard
- **Control:** cm-rgb (cooler) + OpenRGB (motherboard)
- **Sensor:** CPU temperature
- **Thresholds:** 45°C (cool) → 60°C (warm) → 70°C (hot)
- **Interval:** 5 seconds

## Color Scheme

| Temperature | Color | Hex Code |
|-------------|-------|----------|
| Cool | Blue | 0000FF |
| Warm | Green | 00FF00 |
| Hot | Yellow | FFFF00 |
| Critical | Red | FF0000 |

## Usage

### Enable Temperature-Reactive RGB

The RGB control service is enabled via the host configuration:

```nix
hardware.rgb-control = {
  enable = true;
  openrgb.enable = true;
  openrazer.enable = true;  # For Razer peripherals
  wraithRgb.enable = true;   # For AMD Wraith Prism
  temperatureReactive = {
    enable = true;
    sensor = "cpu";  # or "gpu" or "both"
    thresholds = {
      cool = 50;
      warm = 65;
      hot = 75;
    };
    interval = 5;
  };
};
```

### Manual RGB Control

Use the helper script to set colors manually:

```bash
# Set to blue (cool)
/etc/rgb-control.sh 0000FF

# Set to green
/etc/rgb-control.sh 00FF00

# Set to red (hot)
/etc/rgb-control.sh FF0000
```

### OpenRGB Commands

```bash
# List detected devices
openrgb -l

# Set color for device 0 (RGB format)
openrgb -d 0 -c "255,0,0"  # Red
openrgb -d 0 -c "0,255,0"  # Green
openrgb -d 0 -c "0,0,255"  # Blue

# Set all zones
openrgb -d 0 -m "Direct" -c "255,0,0"
```

### Razer Commands (Nexus)

```bash
# List devices
razer-cli -l

# Set color
razer-cli -c "255,0,0"

# Set effect
razer-cli -e static -c "255,0,0"
razer-cli -e breath -c "0,255,0"
```

### Wraith Prism Commands (Sentry)

```bash
# Set color
cm-rgb -c FF0000  # Red
cm-rgb -c 00FF00  # Green
cm-rgb -c 0000FF  # Blue
```

### Corsair Commands (Zephyr)

```bash
# List Corsair devices
liquidctl list

# Get AIO status
liquidctl status

# Set RGB color on Corsair devices
# Note: Requires stopping OpenRGB service first if running
systemctl stop openrgb  # If using OpenRGB
liquidctl set led color fixed ff0000  # Red
liquidctl set led color fixed 00ff00  # Green
liquidctl set led color fixed 0000ff  # Blue

# Set pump speed
liquidctl set pump speed 50  # 50%
```

## Service Management

```bash
# Check service status
systemctl status rgb-temperature-control

# Start/stop service
systemctl start rgb-temperature-control
systemctl stop rgb-temperature-control

# Enable/disable at boot
systemctl enable rgb-temperature-control
systemctl disable rgb-temperature-control

# View logs
journalctl -u rgb-temperature-control -f
```

## Module Structure

- **Module:** `/etc/nixos/modules/hardware/rgb-control.nix`
- **Host configs:** Updated `forge/configuration.nix`, `nexus/configuration.nix`, `sentry/configuration.nix`

## Packages Used

| Package | Purpose | Hosts |
|---------|---------|-------|
| openrgb | General RGB control | All |
| openrgb-plugin-effects | OpenRGB effects | All |
| python3Packages.openrgb-python | Python SDK | All |
| polychromatic | Razer GUI | Nexus, Zephyr |
| razer-cli | Razer CLI | Nexus, Zephyr |
| liquidctl | Corsair AIO/device control | Zephyr |
| cm-rgb | AMD Wraith Prism | Sentry |

## Kernel Modules

The following kernel modules are loaded for RGB control:
- `i2c-dev` - I2C device access
- `i2c-piix4` - SMBus controller (AMD/older Intel)
- `i2c-i801` - SMBus controller (modern Intel)

## Troubleshooting

### No RGB devices detected

1. Check if the service is running:
   ```bash
   systemctl status rgb-temperature-control
   ```

2. Verify OpenRGB can see devices:
   ```bash
   openrgb -l
   ```

3. Check kernel modules:
   ```bash
   lsmod | grep i2c
   ```

4. Verify i2c device permissions:
   ```bash
   ls -la /dev/i2c-*
   ```

### OpenRGB shows "No devices detected"

- Motherboard RGB may require `i2c-dev` kernel module
- Some RGB controllers are not supported by OpenRGB
- Try running OpenRGB with sudo to test permissions

### Razer devices not working on Nexus

1. Verify the openrazer service is running:
   ```bash
   systemctl status openrazer-daemon
   ```

2. Check if user is in the `openrazer` group:
   ```bash
   groups j_kro
   ```

3. Restart the daemon:
   ```bash
   systemctl restart openrazer-daemon
   ```

### Wraith Prism not working on Sentry

1. Verify the CPU cooler is actually a Wraith Prism:
   ```bash
   cat /sys/class/hwmon/hwmon*/name 2>/dev/null
   ```

2. Check if cm-rgb detects the device:
   ```bash
   cm-rgb -l
   ```

## Future Enhancements

- [ ] Add Prometheus metrics export for RGB status
- [ ] Support for more RGB effects (rainbow, wave, etc.)
- [ ] Web UI for RGB control
- [ ] Integration with Grafana dashboards
- [ ] GPU mining status indicators
- [ ] Kubernetes pod status indicators
