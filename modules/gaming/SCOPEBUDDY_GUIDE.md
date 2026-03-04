# Enhanced ScopeBuddy Configuration Guide

## Overview

This enhanced ScopeBuddy module provides **maximum automation** for Gamescope on NixOS, with intelligent display detection, performance optimization, and per-game profiling.

## What's New & Enhanced

### ✅ Maximum Automation Features

1. **Display Auto-Detection**
   - Resolution detection via `wlr-randr`
   - HDR capability detection
   - VRR/adaptive sync detection
   - Refresh rate optimization
   - Scaling method auto-configuration (FSR/NIS)

2. **Performance Automation**
   - CPU governor switching (performance ↔ normal)
   - GameMode integration for system optimization
   - MangoHUD auto-configuration
   - GPU performance level adjustment (AMD)

3. **Per-Game Profiles**
   - Custom gamescope arguments per game
   - Environment variable overrides
   - MangoHUD preset selection
   - Automatic profile loading by game ID

4. **Helper Scripts**
   - `scopebuddy-detect`: Auto-detect display capabilities
   - `scopebuddy-launch`: Smart launcher with CPU governor management
   - Automatic configuration generation

## Configuration Examples

### Basic Maximum Automation

```nix
# hosts/zephyr/configuration.nix
programs.scopebuddy = {
  enable = true;

  # Enable all auto-detection features
  autoDetect = {
    resolution = true;
    hdr = true;
    vrr = true;
    refreshRate = true;
    scaling = true;
  };

  # Performance optimization
  performance = {
    enableGameMode = true;
    mangoHud = true;
    cpuGovernor = "performance";  # Sets CPU to performance mode while gaming
  };
};
```

### With Per-Game Profiles

```nix
programs.scopebuddy = {
  enable = true;

  autoDetect = {
    resolution = true;
    hdr = true;
    vrr = true;
  };

  performance = {
    enableGameMode = true;
    mangoHud = true;
    cpuGovernor = "performance";
  };

  # Define game-specific optimizations
  profiles = {
    cyberpunk2077 = {
      enable = true;
      gamescopeArgs = [
        "-f"              # Force window resolution
        "--rt"            # Enable ray tracing hints
        "--force-grab-cursor"  # Better mouse input
      ];
      envVars = {
        VKD3D_CONFIG = "dx12";  # Use DX12 for Vulkan
      };
      mangoHudPreset = "fps";
    };

    eldenring = {
      enable = true;
      gamescopeArgs = [
        "-f"
        "--expose-wayland"  # Better Wayland support
      ];
      envVars = {
        PROTON_USE_WINED3D = "1";  # Use D3D9 via Wine
      };
    };

    # Experimental games need different settings
    experimental-game = {
      enable = true;
      gamescopeArgs = [
        "-W 1920" "-H 1080"  # Force specific resolution
        "--filter fsr"       # Use FSR upscaling
        "--sharpness 5"      # Maximum sharpness
      ];
    };
  };
};
```

### Minimal Configuration (Essentials Only)

```nix
programs.scopebuddy = {
  enable = true;

  autoDetect = {
    resolution = true;  # Detect resolution automatically
    hdr = false;        # Disable HDR detection
    vrr = true;         # Enable VRR detection
  };

  performance = {
    enableGameMode = true;
    mangoHud = true;
    cpuGovernor = null;  # Don't change CPU governor
  };
};
```

## Usage

### 1. Initial Setup (Auto-Detection)

Run the detection script to generate optimal configuration:

```bash
scopebuddy-detect
```

This will:
- Detect your display resolution
- Check HDR capability
- Check VRR/adaptive sync support
- Detect refresh rate
- Generate `~/.config/scopebuddy/scb.conf`

### 2. Launch Games

**Basic launch:**
```bash
scb %command
```

**With performance mode (auto CPU governor):**
```bash
scb-launch %command
```

**Steam launch options:**
```
scopebuddy-launch %command
```

### 3. Per-Game Profiles

Place profile files in `~/.config/scopebuddy/profiles/`:

```ini
# ~/.config/scopebuddy/profiles/cyberpunk2077.conf
[Gamescope]
Args=-f --rt --force-grab-cursor

[Environment]
VKD3D_CONFIG=dx12
PROTON_NO_ESYNC=1

[MangoHUD]
Preset=fps
```

Profiles are automatically loaded based on the game's AppID.

## Advanced Features

### CPU Governor Automation

The enhanced module automatically switches CPU governors:

```bash
# Before gaming: performance mode
$ cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
performance

# After gaming: restored to original mode
$ cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
schedutil
```

**Configuration:**
```nix
performance.cpuGovernor = "performance";  # or "schedutil" or null
```

### GameMode Integration

Automatically enables GameMode optimizations:

```nix
performance.enableGameMode = true;
```

This applies GameMode's optimizations:
- CPU scheduler tweaks
- GPU performance boosts
- I/O priority adjustments
- Kernel parameter optimization

### MangoHUD Auto-Configuration

MangoHUD is automatically configured to show relevant gaming stats:

```nix
performance.mangoHud = true;
```

**Default stats shown:**
- CPU/GPU temperature
- VRAM/RAM usage
- FPS and frame timing
- CPU/GPU utilization

### Display Auto-Detection

The detection script (`scopebuddy-detect`) gathers:

1. **Resolution**: Via `wlr-randr --json`
2. **HDR**: Checks if HDR is enabled on output
3. **VRR**: Checks adaptive_sync support
4. **Refresh Rate**: Detects current mode's refresh rate
5. **Scaling**: Configures FSR with optimal sharpness

## Environment Variables

ScopeBuddy respects these environment variables:

| Variable | Purpose | Default |
|----------|---------|---------|
| `SCB_CONFIG_PATH` | Config file location | `~/.config/scopebuddy/scb.conf` |
| `SCB_PROFILES_PATH` | Profiles directory | `~/.config/scopebuddy/profiles` |
| `SCB_AUTO_RES` | Auto-detect resolution | `1` (enabled) |
| `SCB_AUTO_HDR` | Auto-detect HDR | `1` (enabled) |
| `SCB_AUTO_VRR` | Auto-detect VRR | `1` (enabled) |
| `SCB_AUTO_HZ` | Auto-detect refresh rate | `1` (enabled) |
| `SCB_AUTO_SCALE` | Auto-detect scaling | `1` (enabled) |
| `SCB_GAMEMODE` | Enable GameMode | `1` (if enabled in config) |
| `SCB_MANGOHUD` | Enable MangoHUD | `1` (if enabled in config) |

## File Structure

```
~/.config/scopebuddy/
├── scb.conf              # Main configuration (auto-generated)
├── appid/                # AppID-specific configs
│   ├── 123456.conf
│   └── 789012.conf
└── profiles/             # Per-game profiles
    ├── cyberpunk2077.conf
    ├── eldenring.conf
    └── experimental-game.conf
```

## Troubleshooting

### Detection Script Shows Wrong Resolution

**Problem**: `wlr-randr` not detecting correct resolution

**Solution**:
```bash
# Check wlr-randr output
wlr-randr --json | jq '.[0].modes[] | select(.current == true)'

# Manual override in scb.conf
[Display]
Resolution=3840x2160  # Force specific resolution
```

### HDR Not Enabling

**Problem**: HDR capable but not enabling

**Solution**:
```bash
# Check if HDR is enabled in Wayland compositor
wlr-randr --json | jq '.[0].hdr_enabled'

# Enable HDR manually in scb.conf
[HDR]
Enabled=true
```

### CPU Governor Not Changing

**Problem**: Need sudo permissions for CPU governor

**Solution**:
```bash
# Add user to video group for governor access
sudo usermod -aG video j_kro

# Or use systemd-tmpfiles to set permissions
echo "/sys/devices/system/cpu/cpu*/cpufreq/scaling_governor 0664 - video - -" | \
  sudo tee /etc/tmpfiles.d/cpu-governor.conf
```

### GameMode Not Working

**Problem**: GameMode optimizations not applying

**Solution**:
```bash
# Verify GameMode is running
gamemoded -t

# Check GameMode status
gamemctl -s

# Test with a game
scopebuddy-launch glxgears
```

## Performance Tips

### 1. **Use FSR for Older Games**

```nix
profiles.older-game = {
  gamescopeArgs = [
    "-W 1920" "-H 1080"  # Render at 1080p
    "--filter fsr"       # Upscale with FSR
    "--sharpness 5"      # Maximum sharpness
  ];
};
```

### 2. **Enable Frame Pacing for Competitive Games**

```nix
profiles.competitive = {
  gamescopeArgs = [
    "-f"                   # Force resolution
    "--expose-wayland"     # Better input latency
  ];
  envVars = {
    GDK_SCALE = "1";       # Disable fractional scaling
  };
};
```

### 3. **RTX/VDK3D Optimization for Windows Games**

```nix
profiles.windows-game = {
  envVars = {
    PROTON_USE_WINED3D = "1";      # Use WineD3D for D3D9
    VKD3D_SHADER_MODEL = "61";     # DX12 SM 6.1
  };
};
```

## Integration with Other Modules

### With Gaming Module

```nix
services.gaming = {
  enable = true;
  hdr.enable = true;  # Automatically integrated with ScopeBuddy
};

programs.scopebuddy = {
  enable = true;
  autoDetect.hdr = true;  # Reads from gaming.hdr.enable
};
```

### With Anime Game Launchers

```nix
programs.anime-game-launcher.enable = true;

programs.scopebuddy = {
  enable = true;
  profiles = {
    "genshin-impact" = {
      gamescopeArgs = ["-f" "--expose-wayland"];
      envVars = {
        WINEPREFIX = "\${HOME}/Games/anime-game-launcher";
      };
    };
  };
};
```

## Comparison: Original vs Enhanced

| Feature | Original | Enhanced |
|---------|----------|----------|
| Resolution Detection | ✅ | ✅ |
| HDR Detection | ✅ | ✅ |
| VRR Detection | ✅ | ✅ |
| Refresh Rate Detection | ❌ | ✅ |
| Scaling Detection | ❌ | ✅ |
| Per-Game Profiles | ❌ | ✅ |
| CPU Governor Automation | ❌ | ✅ |
| GameMode Integration | ❌ | ✅ |
| MangoHUD Integration | ❌ | ✅ |
| Helper Scripts | ❌ | ✅ |
| Auto-Config Generation | ❌ | ✅ |

## Sources & References

- [ScopeBuddy mentioned in PC Gamer](https://www.pcgamer.com/linux-gaming-guide/) - Tool for simplifying Gamescope parameters
- [Gamescope Documentation](https://github.com/ValveSoftware/gamescope) - Official gamescope repository
- [SteamTinkerLaunch Wiki](https://github.com/sonic2kk/steamtinkerlaunch/wiki) - Linux gaming optimization techniques
- [Gamescope Session Plus](https://github.com/ChimeraOS/gamescope-session) - Advanced Gamescope framework

## Next Steps

1. **Rebuild and test**:
   ```bash
   sudo nixos-rebuild switch
   scopebuddy-detect
   ```

2. **Verify detection**:
   ```bash
   cat ~/.config/scopebuddy/scb.conf
   ```

3. **Test with a game**:
   ```bash
   scb-launch steam -applaunch 123456
   ```

4. **Create per-game profiles** as needed

5. **Adjust performance settings** based on your hardware

---

**Status**: ✅ Enhanced configuration ready for maximum automation!
