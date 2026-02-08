# RGB Control Guide - Unified Management with Intelligent Signaling

## Overview

This cluster uses **unified RGB control** combining multiple tools for comprehensive hardware management AND intelligent system monitoring:

- **OpenRGB** - Motherboards, GPUs, RAM
- **liquidctl** - AIO coolers, Corsair Vengeance RAM (with temperature monitoring)
- **ckb-next** - Corsair keyboards/mice
- **OpenRazer + Polychromatic** - Razer peripherals

## Intelligent RGB Use Cases

### Temperature Monitoring
**liquidctl** provides real-time temperature monitoring for Corsair Vengeance RAM modules:
- **Zephyr**: Corsair Vengeance RGB DIMMs monitored via liquidctl
- **Alert thresholds**: Configure warning temperatures in `hardware.unified-rgb.liquidctl`
- **Integration**: Works with OpenRGB for unified control

### Status Indicators & Signaling
RGB profiles can indicate system state:
- **Gaming mode** (`rgb-profile gaming`): Breathing red/blue effect = **Active/Gaming**
- **Movie mode** (`rgb-profile movie`): Static blue (minimal distraction) = **Calm/Focus**
- **Off mode** (`rgb-profile off`): All RGB off = **Alert/Maintenance mode**

### Temperature-Based Alerts
Use RGB to indicate system health:
- **Cool (≤40°C)**: Green or blue (normal operation)
- **Warm (40-55°C)**: Yellow or orange (elevated temperatures)
- **Hot (55-70°C)**: Red or breathing (warning - consider pausing workloads)
- **Critical (>70°C)**: Rapid red flashing (immediate action needed)

### Mining Awareness
RGB automatically adjusts during mining:
- **Mining active**: RGB set to "off" or static green (minimal distraction)
- **Gaming/VR active**: RGB set to gaming profile (breathing effects)
- **Automatic detection**: mining module hooks into RGB control

## Tools and Their Purpose

| Tool | Hardware Type | NixOS Package | Status |
|-------|---------------|----------------|--------|
| **OpenRGB** | Motherboards, GPUs, RAM | `pkgs.openrgb` | ✅ Enabled on zephyr, nexus, forge, sentry |
| **liquidctl** | AIO coolers, Corsair RAM | `pkgs.liquidctl` | ✅ Enabled on zephyr, nexus |
| **ckb-next** | Corsair keyboards/mice | `pkgs.ckb-next` | ✅ Enabled on zephyr |
| **OpenRazer** | Razer daemon/driver | `hardware.openrazer` | ✅ Built-in NixOS module |
| **Polychromatic** | Razer GUI frontend | `pkgs.polychromatic` | ✅ Installed system-wide |

## Cluster RGB Hardware Inventory

### Zephyr (10.1.1.110)
- **Motherboard**: MSI X570 Tomahawk (supports RGB via OpenRGB)
- **RAM**: G.Skill Trident Z RGB (ASUS Aura controller via OpenRGB)
- **GPU**: RTX 3090 (OpenRGB support)
- **AIO Cooler**: Corsair H115i Platinum (liquidctl)
- **Keyboard**: Corsair K70 RGB (ckb-next)
- **Mouse**: Razer Naga Pro (OpenRazer + Polychromatic)
- **Status**: ✅ **Full RGB configuration enabled**

### Nexus (10.1.1.120)
- **Motherboard**: Gigabyte AORUS X470 Gaming (supports RGB via OpenRGB)
- **GPUs**: 2x RTX 3060 Ti (EVGA - OpenRGB support)
- **Status**: ✅ **OpenRGB enabled for RGB control**

### Forge (10.1.1.130)
- **GPUs**: 2x RTX 4060 + 2x RX 5700 XT (OpenRGB support)
- **Status**: ✅ **OpenRGB enabled** (potential for Corsair mouse)

### Sentry (10.1.1.140)
- **GPU**: RX 5600 XT (no RGB)
- **Status**: ✅ **OpenRGB enabled** (potential for Corsair mouse)

## Usage Commands

### Unified RGB Control

```bash
# Check all detected devices
openrgb --list-devices

# Check specific device status (liquidctl)
liquidctl list
liquidctl status --match h115i  # Corsair H115i on zephyr

# Change RGB profiles
rgb-profile gaming   # Breathing red/blue effect
rgb-profile movie    # Static blue (minimal distraction)
rgb-profile off      # All RGB off
```

### Device-Specific Control

```bash
# OpenRGB only
openrgb --device 0 --color ff0000 --mode static
openrgb --device 1 --color 0000ff --mode breathing

# liquidctl (AIO coolers)
liquidctl set --match kraken pump speed 70
liquidctl set --match kraken set led color fixed 0080ff
liquidctl --match vengeance set color breathing ff0000

# ckb-next (Corsair peripherals)
ckb-next -d rgb -c red  # Keyboard color
ckb-next -d rgb -b 255 255 0  # Brightness level 0-3

# Polychromatic (Razer GUI)
polychromatic
```

## OpenRGB Hardware Support

OpenRGB supports **647+ devices** including:

### Motherboards (351 devices)
- ✅ **ASUS**: Aura Core, Aura GPU (SMBus)
- ✅ **Gigabyte**: RGB Fusion 2.0 (SMBus)
- ✅ **MSI**: Mystic Light (120+ variants)
- ✅ **ASRock**: Polychrome USB/SMBus
- ✅ **AMD**: Wraith Prism (CPU cooler)

### GPUs (647 devices)
- ⚠️ **Limitation**: Only single-zone GPUs supported
- ✅ **NVIDIA**: ASUS ROG STRIX/TUF series, MSI Gaming, EVGA
- ✅ **AMD**: ASUS ROG/AREZ Radeon series

### RAM (175 devices)
- ✅ **All major brands**: G.Skill, Corsair Vengeance, Kingston Fury
- ⚠️ **Note**: Many RAM brands use ASUS Aura controller chip (shown as "ASUS Aura DRAM")

## Configuration Module

The `modules/unified-rgb.nix` module provides:

### Options
```nix
{
  hardware.unified-rgb = {
    enable = true;                    # Enable unified RGB control
    openrgb = {
      enable = true;              # Enable OpenRGB daemon
      server = {
        enable = true;           # Enable OpenRGB server on port 6742
        port = 6742;             # Server port
        autoStart = true;         # Auto-start on boot
      };
      motherboard = "msi|asus|gigabyte|asrock|amd";  # Controller type
    };
    liquidctl.enable = true;          # Enable liquidctl support
    sync = {
      enable = true;               # Enable sync service
      color = "ff00ff";           # Sync color (RRGGBB)
    };
    profiles = {                    # Predefined profiles
      gaming = "color=ff00ff mode=breathing";
      movie = "color=0000ff mode=static";
      off = "color=000000";
    };
  };
}
```

### Features
- **Profile switching**: `rgb-profile [gaming|movie|off]`
- **Device synchronization**: Sync all devices to a single color
- **Server mode**: Optional OpenRGB server for remote control
- **Comprehensive udev rules**: All major RGB controller brands

## Intelligent RGB Signaling

### Temperature-Based Alerts (liquidctl)
**Monitor Corsair Vengeance RAM temperatures:**
```bash
# Check current temperature
liquidctl status --match vengeance

# Example output:
# Corsair Vengeance RGB DIMM1
#   Temperature: 38.5°C
#   Pump speed: 0%
```

**Integrate with RGB color based on temperature:**
```bash
# Add to rgb-profile script or create custom automation
if [ "$(liquidctl status --match vengeance | grep Temperature | awk '{print $2}')" -gt 55 ]; then
    # Hot (>55°C) - Flashing red
    openrgb --device 1 --mode rainbow --speed fastest
else
    # Normal (≤55°C) - Static blue
    openrgb --device 1 --color 0000ff --mode static
fi
```

### System State Indicators

**Gaming Mode** (`rgb-profile gaming`)
- RGB: Breathing red/blue
- Meaning: Active gaming session, performance mode enabled
- Use: During gameplay for visual feedback

**Movie Mode** (`rgb-profile movie`)
- RGB: Static blue
- Meaning: Passive media consumption, minimal distraction
- Use: Watching movies/YouTube, reading documents

**Off Mode** (`rgb-profile off`)
- RGB: All off or static red flashing
- Meaning: Maintenance, sleep, or critical alert
- Use: System maintenance, CPU-intensive workloads paused

### Mining-Mode Integration

RGB automatically adjusts when mining starts/stops:
```bash
# Mining module hooks into RGB control
# When mining starts: RGB off or static green
# When gaming detected: RGB gaming profile
```

**Configuration** in `modules/unified-rgb.nix`:
```nix
{
  hardware.unified-rgb = {
    enable = true;
    profiles = {
      mining = "color=00ff00 mode=static";  # Green when mining
      off = "color=ff0000 mode=flash";       # Red alert when off
    };
  };
}
```

## Troubleshooting

### RAM Not Detected by OpenRGB

If G.Skill or other RGB RAM isn't showing:
1. Remove all RAM sticks
2. Reinstall in different slots
3. Reseat RAM to reset SMBus controller
4. Check motherboard has enabled RGB in BIOS

### GPU Multi-Zone Not Supported

GPUs with multiple RGB zones (e.g., ASUS ROG STRIX with 3 zones) are NOT fully supported by OpenRGB.

### MSI Motherboard Warning

MSI Mystic Light code has been disabled in OpenRGB due to risk of "bricking" RGB on some boards. Use with caution.

## Deployment Status

### Enabled Hosts
- ✅ zephyr: OpenRGB + liquidctl + ckb-next + OpenRazer + Polychromatic
- ✅ nexus: OpenRGB (for Gigabyte AORUS X470 RGB)
- ✅ forge: OpenRGB (potential for Corsair mouse)
- ✅ sentry: OpenRGB (potential for Corsair mouse)

### Hosts Without RGB Hardware
- ❌ No hosts without RGB hardware (all hosts have some RGB support)

## Security

- **All services bind to localhost**: OpenRGB, liquidctl
- **udev rules for device access**: Proper permissions without root
- **User groups**: `plugdev`, `input`, `openrazer` for access control

## References

- [OpenRGB Supported Devices](https://openrgb.org/devices.html)
- [OpenRGB Wiki](https://openrgb-wiki.readthedocs.io/)
- [liquidctl GitHub](https://github.com/liquidctl/liquidctl)
- [ckb-next GitHub](https://github.com/ckb-next/ckb-next)
- [OpenRazer GitHub](https://github.com/openrazer/openrazer)
- [Polychromatic Website](https://polychromatic.app/)
