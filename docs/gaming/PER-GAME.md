# Per-Game Configuration Guide

## Overview

This guide provides optimal settings for popular games, including Proton version, launch options, and GameMode configuration.

## How to Configure Per-Game Settings

### 1. Steam Launch Options

Right-click game → Properties → General → Launch options:
```
gamemoderun %command%
```

### 2. Proton Selection

Right-click game → Properties → Compatibility:
- Tick "Force the use of a specific Steam Play compatibility tool"
- Select Proton version

### 3. GameMode Per-Game Config

Edit `~/.config/gamemode.ini`:
```ini
[game/GAME_NAME]
governor=performance
gpu_optimisations=1
renice=15
```

## VRChat

**Proton:** Proton-GE 9-x

**Launch Options:**
```
gamemoderun %command%
```

**GameMode Config:**
```ini
[game/VRChat]
governor=performance
gpu_optimisations=1
renice=15
```

**Settings:**
- Graphics: Medium-High (VRChat is CPU-bound)
- Avatar Impostors: 8-12
- Shadow Distance: Medium
- Enable GameMode overlay: No (use in-game FPS)

**VR Settings (WiVRn):**
- Refresh Rate: 90Hz
- Resolution: 2160x2160
- Bitrate: 250-300 Mbps

**Notes:**
- MangoHud causes issues with VRChat overlay
- Use in-game FPS counter instead
- Proton-GE required for EAC compatibility

## Half-Life: Alyx

**Proton:** Proton-Experimental or Proton-GE

**Launch Options:**
```
gamemoderun gamescope -- %command%
```

**GameMode Config:**
```ini
[game/hl_alyx.exe]
governor=performance
gpu_optimisations=1
```

**Settings:**
- Graphics: High/Ultra
- VR: 90Hz
- Supersampling: 100-120%

**Notes:**
- Runs great with WiVRn
- Consider Gamescope for upscaling if needed

## Cyberpunk 2077

**Proton:** Proton-GE 9-x

**Launch Options:**
```
gamemoderun gamescope -W 1920 -H 1080 -r 60 -- %command%
```

**GameMode Config:**
```ini
[game/Cyberpunk2077]
governor=performance
gpu_optimisations=1
```

**Settings:**
- Resolution: Let Gamescope handle (1920x1080 upscaled)
- Ray Tracing: Medium (RTX 3090 can handle it)
- DLSS: Quality mode
- FPS Limit: 60 (with Gamescope frame gen)

**Notes:**
- Gamescope frame generation works well
- Start with RT off, enable if performance allows

## Elden Ring

**Proton:** Proton-Experimental

**Launch Options:**
```
gamemoderun %command%
```

**GameMode Config:**
```ini
[game/eldenring.exe]
governor=performance
gpu_optimisations=0  # Disable if unstable
```

**Settings:**
- Graphics: Max
- Ray Tracing: Off (performance killer)
- FPS: Unlock (60+ is smooth)

**Notes:**
- EAC may require Proton-GE
- If crashes, disable GPU overclock

## Starfield

**Proton:** Proton-Experimental or Proton-GE

**Launch Options:**
```
gamemoderun gamescope -- %command%
```

**GameMode Config:**
```ini
[game/Starfield.exe]
governor=performance
gpu_optimisations=1
```

**Settings:**
- Graphics: High
- Upscaling: FSR2 (Quality mode)
- VSync: Off (let Gamescope handle)

**Notes:**
- Poorly optimized, Gamescope helps
- Consider texture streaming fix mods

## Red Dead Redemption 2

**Proton:** Proton-Experimental

**Launch Options:**
```
gamemoderun %command% -vulkan
```

**GameMode Config:**
```ini
[game/RDR2.exe]
governor=performance
gpu_optimisations=1
```

**Settings:**
- API: Vulkan (better than DX12 on Proton)
- Graphics: High/Ultra
- VSync: Off

**Notes:**
- Vulkan runs better than DX12
- Ultra settings achievable on RTX 3090

## Counter-Strike 2

**Proton:** Native (no Proton needed)

**Launch Options:**
```
gamemoderun %command% -nojoy -novid -nosound -freq 165 -refresh 165 -fullscreen -tickrate 128
```

**GameMode Config:**
```ini
[game/cs2]
governor=performance
gpu_optimisations=1
```

**Settings:**
- Resolution: Native
- Max FPS: 0 (unlimited)
- VSync: Off
- NVIDIA Reflex: On+Boost

**Notes:**
- Native Linux support, no Proton needed
- Extremely competitive, GameMode helps

## Dota 2

**Proton:** Native

**Launch Options:**
```
gamemoderun %command% -gl -console -novid
```

**Settings:**
- Graphics: Max
- VSync: Off
- Display Mode: Fullscreen

**Notes:**
- Native support, excellent performance
- Consider Vulkan renderer (-vulkan)

## Baldur's Gate 3

**Proton:** Native

**Launch Options:**
```
gamemoderun %command%
```

**GameMode Config:**
```ini
[game/Baldurs Gate 3]
governor=performance
gpu_optimisations=1
```

**Settings:**
- Graphics: Ultra
- Ray Tracing: Off/On depending on scene
- DLSS: Quality

**Notes:**
- Native Linux support
- DX11 mode recommended

## Emulation (Retro games)

### Yuzu (Switch Emulator)

**No GameMode needed** - emulator handles CPU governor.

**Settings:**
- Accuracy: Normal
- GPU: High
- Async GPU: On

### RPCS3 (PS3 Emulator)

**Launch Options:**
```
gamemoderun rpcs3
```

**Settings:**
- PPU Decoder: LLVM
- SPU Decoder: ASMJIT
- GPU: Vulkan

## Wine/Proton Games (Non-Steam)

### Lutris

**Launch:**
```bash
gamemoderun lutris game://12345
```

### Heroic Games Launcher (Epic Games)

**Launch:**
```bash
gamemoderun heroic
```

### Wine Direct

**Launch:**
```bash
gamemoderun wine game.exe
```

## Troubleshooting Per-Game Issues

### Game Crashes on Launch

**Try:**
1. Disable GPU overclock in GameMode config
2. Try different Proton version
3. Add launch option: `WINEDLLOVERRIDES="mfplat=n" %command%`
4. Check logs: `journalctl --user -f` (while launching)

### Poor Performance

**Check:**
1. GameMode is active: `gamemodelist -i`
2. GPU usage: `nvidia-smi`
3. CPU throttling: `watch -n 0.1 cat /proc/cpuinfo | grep MHz`

**Try:**
1. Reduce graphics settings
2. Enable Gamescope upscaling
3. Close background apps

### Graphics Glitches

**Try:**
1. Different Proton version
2. Enable/Disable Proton's Vulkan (PROTON_USE_WINED3D=1)
3. Update GPU drivers
4. Check MangoHud overlay isn't interfering

### VR Issues (VRChat, etc.)

**Check:**
1. WiVRn connected: `wivrn-cli show`
2. SteamVR running
3. OpenXR runtime: `echo $PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES`

**Try:**
1. Restart SteamVR
2. Reconnect WiVRn
3. Lower bitrate in WiVRn

## GameMode Advanced Configuration

### GPU Overclock Settings

Global (`~/.config/gamemode.ini`):
```ini
[gpu]
apply_gpu_optimisations=accept-responsibility
nv_powermizer_mode=1
nv_core_clock_mhz_offset=100
nv_mem_clock_mhz_offset=400
```

Per-game override (safer):
```ini
[game/Cyberpunk2077]
gpu_optimisations=1

[game/VRChat]
gpu_optimisations=0  # Disable for stability
```

### CPU Governor

**Performance** (best FPS):
```ini
[general]
desiredgov=performance
```

**Schedutil** (balanced):
```ini
[game/CasualGame]
governor=schedutil
```

### Renice (Process Priority)

Higher = more CPU time:
```ini
[general]
renice=15  # Default

[game/CPU_Heavy_Game]
renice=5   # Higher priority
```

## MangoHud Per-Game Config

**Environment Variable:**
```bash
MANGOHUD_CONFIG=fps,frametime,cpu_temp,gpu_temp
```

**Config File:**
Create `~/.config/MangoHud/GAME_NAME.conf`:
```
fps,frametime=1,cpu_stats,gpu_stats,vram,ram
position=top-right
toggle_hud=Shift_F2
```

## Testing Performance

### Benchmarking

**With MangoHud:**
```bash
mangohud game_executable
```

**With GameMode:**
```bash
gamemoderun game_executable
```

**Both:**
```bash
gamemoderun mangohud game_executable
```

### Check Logs

**GameMode:**
```bash
journalctl --user -u gamemoded -f
```

**Steam:**
```bash
journalctl --user -u steam -f
```

## Recommended Reading

- [ProtonDB](https://www.protondb.com/) - Check game compatibility
- [MangoHud Config](https://github.com/flightlessmango/MangoHud/blob/master/data/MangoHud.conf)
- [GameMode Config](https://github.com/FeralInteractive/gamemode-linux/blob/master/README.md)
- [Steam Play](https://github.com/ValveSoftware/Proton/wiki)
