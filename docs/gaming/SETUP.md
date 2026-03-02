# Gaming Setup Guide

## Overview

This NixOS configuration provides a complete gaming setup with Steam, GameMode, Gamescope, VR support (WiVRn), and performance optimizations for NVIDIA GPUs (RTX 3090).

## Features Enabled

### Core Gaming
- **Steam** with Proton-GE from nixpkgs-xr
- **GameMode** with GPU overclock (+100MHz core, +400MHz memory)
- **Gamescope** for upscaling and frame generation
- **MangoHud** for performance monitoring
- **SCX lavd scheduler** for better gaming performance
- **Low-latency PipeWire** (1.3ms audio latency)
- **DualShock/DualSense controller support** with touchpad fix

### VR Support
- **WiVRn** for wireless VR streaming (Quest Pro)
- **SteamVR** with OpenXR runtime
- **Avahi** for automatic device discovery
- **xrizer** for OpenVR→OpenXR translation

### HDR Support
- **HDR-enabled Gamescope** for 4K HDR TV

## Quick Start

### 1. Enable Gaming Features

Gaming is enabled by default. Verify:
```bash
# Check if GameMode is running
systemctl --user status gamemoded

# Check SCX scheduler
systemctl status scx-lavd

# Check WiVRn
systemctl status wivrn
```

### 2. Steam Setup

Launch Steam and let it update. Proton-GE should be available in compatibility tools.

### 3. VR Setup (Quest Pro)

1. **Install WiVRn on Quest Pro:**
   - Side load the WiVRn APK from: https://github.com/WiVRn/WiVRn/releases
   - Or use AppManager/QuestAppToolbox

2. **Connect to PC:**
   - Put Quest Pro in pairing mode
   - WiVRn should auto-discover via Avahi
   - Manual connection: Enter PC IP in WiVRn app

3. **SteamVR Setup:**
   - Launch SteamVR on PC
   - WiVRn should auto-connect
   - Run room setup if needed

### 4. HDR Setup (4K HDR TV)

HDR is enabled automatically in Gamescope. To verify:
```bash
# Check Gamescope HDR settings
gamescope --hdr-enabled
```

## Usage

### Launching Games with GameMode

Use the `gamemoderun` wrapper:
```bash
gamemoderun steam
```

Or use the `launch-game` script (runs in gaming.slice cgroup):
```bash
launch-game steam
```

### Using Gamescope for Upscaling

Steam launch options example:
```
gamescope -- %command%
```

### MangoHud Configuration

Default MangoHud config shows:
- FPS, frametime
- CPU/GPU stats, temperature, load
- VRAM, RAM usage
- Toggle: Shift+F12

Per-game config:
```bash
# Create ~/.config/MangoHud/GAME_NAME.conf
MANGOHUD_CONFIG=fps,gpu_stats,cpu_stats
```

### ScopeBuddy (Gamescope Wrapper)

For automatic resolution/HDR detection:
```bash
# Steam launch options
scb -- %command%
```

## Per-Game Configuration

### VRChat

Recommended settings:
- Proton: Proton-GE
- Launch: `gamemoderun %command%`
- MangoHud: Disable (use in-game overlay)

### Cyberpunk 2077

Recommended settings:
- Proton: Proton-GE
- Gamescope: Enable for upscaling
- GameMode: Enable

### Elden Ring

Recommended settings:
- Proton: Proton-Experimental
- EasyAntiCheat: Requires Proton-GE

## Performance Tuning

### GameMode Settings

Located in `~/.config/gamemode.ini`:
```ini
[general]
desiredgov=performance
softrealtime=auto
renice=15

[gpu]
apply_gpu_optimisations=accept-responsibility
nv_powermizer_mode=1
nv_core_clock_mhz_offset=100
nv_mem_clock_mhz_offset=400
```

Per-game overrides:
```ini
[game/VRChat]
governor=performance
gpu_optimisations=1
```

### SCX Scheduler

The SCX lavd scheduler is enabled by default for better gaming performance.

To disable:
```bash
sudo systemctl disable scx-lavd
```

### GPU Overclock

Default overclock in GameMode:
- Core: +100MHz
- Memory: +400MHz

Adjust in `~/.config/gamemode.ini` or system config in:
`/etc/nixos/modules/gaming/gaming.nix`

## Troubleshooting

### GameMode Not Activating

Check GameMode status:
```bash
systemctl --user status gamemoded
```

Verify game is supported:
```bash
gamemodelist -i
```

### WiVRn Not Connecting

1. Check Avahi (for auto-discovery):
```bash
systemctl status avahi-daemon
```

2. Check firewall ports (9757, 5353, 9947):
```bash
sudo firewall-cmd --list-ports
```

3. Check WiVRn service:
```bash
systemctl status wivrn
```

### HDR Not Working

1. Verify display supports HDR:
```bash
# Check display capabilities
wlr-randr
```

2. Check Gamescope HDR args:
```bash
ps aux | grep gamescope
```

Should include: `--hdr-enabled --hdr-itm-enabled`

### Controller Not Detected

1. Check controller is detected:
```bash
ls /dev/input/
```

2. Test with SDL:
```bash
sdl2-jstest --list
```

3. Check udev rules:
```bash
sudo udevadm info --attribute-walk --name=/dev/input/eventXX
```

## System Files

### Configuration Files

- Gaming module: `/etc/nixos/modules/gaming/gaming.nix`
- HDR module: `/etc/nixos/modules/gaming/gaming-hdr.nix`
- ScopeBuddy: `/etc/nixos/modules/gaming/scopebuddy.nix`
- Host config: `/etc/nixos/hosts/zephyr/configuration.nix`

### Systemd Services

- GameMode: User service (auto-started by games)
- SCX scheduler: `scx-lavd.service`
- WiVRn: `wivrn.service`
- Avahi: `avahi-daemon.service`

### Firewall Ports

- 9757 (TCP/UDP): WiVRn streaming
- 5353 (UDP): mDNS (Avahi)
- 9947 (UDP): WiVRn
- 27031, 27036 (UDP): SteamVR

## Further Reading

- [GameMode Documentation](https://github.com/FeralInteractive/gamemode)
- [Gamescope Documentation](https://github.com/ValveSoftware/gamescope)
- [WiVRn Documentation](https://github.com/WiVRn/WiVRn)
- [Proton-GE](https://github.com/GloriousEggroll/proton-ge-custom)
- [MangoHud](https://github.com/flightlessmango/MangoHud)
