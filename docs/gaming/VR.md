# VR Configuration Guide

## Overview

This system supports wireless VR streaming to Quest Pro via WiVRn, with SteamVR and OpenXR runtime support.

## Hardware

- **Headset:** Meta Quest Pro
- **GPU:** NVIDIA RTX 3090
- **Display:** 4K HDR TV

## Software Stack

- **WiVRn:** Wireless VR streaming server
- **SteamVR:** VR runtime
- **OpenXR:** Modern VR API
- **xrizer:** OpenVR→OpenXR translation layer
- **Avahi:** Automatic device discovery

## Setup

### 1. Quest Pro - Install WiVRn Client

**Option A: Side-load with Developer Hub**
1. Install Meta Quest Developer Hub on PC
2. Enable Developer Mode on Quest Pro
3. Connect Quest Pro via USB
4. Side-latest WiVRn APK from: https://github.com/WiVRn/WiVRn/releases

**Option B: Use QuestAppToolbox**
1. Install QuestAppToolbox on Quest Pro
2. Search for WiVRn
3. Install

### 2. PC - WiVRn Server

WiVRn server is installed and enabled via NixOS:
```bash
systemctl status wivrn
```

### 3. Network Setup

Both devices must be on the same network. Wi-Fi 6E/7 recommended (5GHz/6GHz).

**Check connection:**
```bash
# On PC - check IP
ip addr show

# On Quest Pro - check Wi-Fi
Settings → Wi-Fi → Network info
```

### 4. Pairing

**Automatic (Avahi):**
1. Enable WiVRn on Quest Pro
2. Should auto-discover PC on local network
3. Click to connect

**Manual (if Avahi fails):**
1. Find PC IP address
2. Enter in WiVRn app: `192.168.x.x:9757`
3. Connect

### 5. SteamVR Setup

1. Launch SteamVR on PC
2. WiVRn should auto-connect
3. Run room setup if prompted
4. Test tracking and controllers

## Configuration

### WiVRn Settings

Located in: `~/.config/wivrn/session.json`

Recommended for Quest Pro:
```json
{
  "refreshRate": 90,
  "resolution": "2160x2160",
  "encoder": "nvenc",
  "bitrate": 300
}
```

### System Config

NixOS configuration (`/etc/nixos/modules/gaming/gaming.nix`):
```nix
services.gaming.vr = {
  enable = true;
  encoder = "nvenc";  // NVENC for RTX 3090
  refreshRate = 90;    // 90Hz for Quest Pro
  resolution = "2160x2160";  // Per-eye
};
```

### OpenXR Environment

Set automatically by NixOS:
```bash
OPENVR_API_PATH=/nix-store-...-xrizer/lib/xrizer
PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES=1
```

## Performance Tuning

### Encoder Settings (NVENC)

**Bitrate:**
- 150 Mbps: Minimum
- 200-250 Mbps: Good quality
- 300 Mbps: High quality (recommended)
- 400+ Mbps: Diminishing returns

**Adjust bitrate:**
Edit `~/.config/wivrn/session.json` or system config.

### Refresh Rate

Quest Pro supports:
- 72 Hz: Battery saving
- 90 Hz: Default (recommended)
- 120 Hz: Experimental

Set in WiVRn app or config file.

### Decoder

PC uses NVENC hardware decoder (RTX 3090).

Quest Pro decoder: Auto-detected.

## Troubleshooting

### WiVRn Won't Connect

**Check Avahi:**
```bash
systemctl status avahi-daemon
```

**Check firewall:**
```bash
# Ports should be open
sudo firewall-cmd --list-ports
# Should include: 9757, 5353, 9947
```

**Manual connection:**
Enter PC IP in WiVRn app: Settings → Add server manually

### Stuttering/Lag

**Causes:**
1. Wi-Fi interference (2.4GHz vs 5GHz)
2. High bitrate on weak signal
3. Background processes on PC

**Solutions:**
1. Use 5GHz or 6GHz Wi-Fi
2. Reduce bitrate to 200-250 Mbps
3. Close background apps
4. Check CPU usage with `htop`

### Poor Image Quality

**Causes:**
1. Low bitrate
2. High network latency
3. Encoder settings

**Solutions:**
1. Increase bitrate (try 300 Mbps)
2. Use wired Ethernet if possible
3. Check Wi-Fi signal strength

### Controllers Not Tracking

**Check SteamVR:**
1. Launch SteamVR status window
2. Check controller status
3. Re-pair if needed

**Check USB:**
```bash
# Should see controllers
ls /dev/input/
```

### SteamVR Games Won't Launch

**Check Proton:**
- Use Proton-GE for best compatibility
- Add to Steam compatibility tools

**Check xrizer:**
```bash
# OpenVR→OpenXR translation
echo $OPENVR_API_PATH
# Should show: /nix/store/...-xrizer/lib/xrizer
```

## Firewall Ports

Required ports (automatically opened):
- 9757/tcp: WiVRn control
- 9757/udp: WiVRn streaming
- 5353/udp: mDNS (Avahi discovery)
- 9947/udp: WiVRn alternative
- 27031/udp: SteamVR
- 27036/udp: SteamVR

**Verify:**
```bash
sudo firewall-cmd --list-ports
```

## Performance Monitoring

### Check WiVRn Stats

WiVRn app shows:
- Frame rate
- Encoding time
- Network latency
- Packet loss

### Check PC Performance

```bash
# GPU usage
nvidia-smi

# CPU usage
htop

# Network latency
ping <quest-pro-ip>
```

## Known Limitations

### SteamVR Async Reproduction

**Issue:** Does NOT work on NVIDIA GPUs (no fix available).

**Impact:** Some judder in SteamVR titles.

**Workaround:** WiVRn handles frame timing better than native SteamVR.

### OpenVR vs OpenXR

**xrizer** provides OpenVR→OpenXR translation:
- Most games work
- Some edge cases may have issues
- Report bugs to: https://github.com/cloudef/nixpkgs-xr

## Recommended Games

### Native OpenXR (Best)
- DCS World
- MS Flight Simulator (2024)
- IL-2 Sturmovik

### SteamVR via OpenXR (Good)
- VRChat (recommended)
- Half-Life: Alyx
- Boneworks
- Pavlov

### Troublesome
- Games with aggressive anti-cheat
- Older OpenVR-only titles

## System Files

- WiVRn config: `~/.config/wivrn/session.json`
- OpenXR runtime: `/run/opengl-driver/share/openxr/1/`
- xrizer translation: `$OPENVR_API_PATH`
- NixOS module: `/etc/nixos/modules/gaming/gaming.nix`

## Resources

- [WiVRn GitHub](https://github.com/WiVRn/WiVRn)
- [WiVRn Wiki](https://github.com/WiVRn/WiVRn/wiki)
- [OpenXR Specification](https://www.khronos.org/openxr/)
- [xrizer](https://github.com/cloudef/nixpkgs-xr)
