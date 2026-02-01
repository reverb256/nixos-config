# KDE Plasma Configuration Guide

## Current Configuration (January 2026)

This guide documents the working KDE Plasma 6 + Wayland configuration for zephyr (RTX 3090).

## ✅ Working Configuration

### Display Manager (SDDM)
```nix
# Pure Wayland - no X11 required
services.displayManager = {
  sddm = {
    enable = true;              # REQUIRED: Enables SDDM service
    wayland.enable = true;      # SDDM runs in Wayland mode
  };
  defaultSession = "plasma";
};

services.desktopManager.plasma6.enable = true;
```

**Note**: `services.xserver.enable = true` is NOT required for pure Wayland setups.

### XDG Desktop Portal (Critical for Window Management)
```nix
xdg.portal = {
  enable = true;
  extraPortals = with pkgs; [
    kdePackages.xdg-desktop-portal-kde  # Primary
    xdg-desktop-portal-gtk               # GTK fallback
    xdg-desktop-portal-hyprland          # Future Hyprland support
  ];
  config = {
    common = {
      default = ["kde" "gtk"];
      "org.freedesktop.impl.portal.WindowManagement" = ["kde"];
      "org.freedesktop.impl.portal.Settings" = ["kde" "gtk"];
      "org.freedesktop.impl.portal.Notification" = ["kde"];
    };
  };
};
```

### NVIDIA Configuration (RTX 3090)
```nix
# Stable driver (beta causes KWin crashes)
hardware.nvidia.package = config.boot.kernelPackages.nvidiaPackages.stable;

# Wayland support
hardware.nvidia.wayland = {
  enable = true;
  openModules = true;
  sddmWayland = true;
};

# Required for GPU detection
hardware.graphics = {
  enable = true;
  enable32Bit = true;
};
```

### Dynamic Linker (nix-ld) for CUDA/Steam/Flatpak
```nix
programs.nix-ld = {
  enable = true;
  libraries = with pkgs; [
    # CUDA libraries for AI/ML
    cudaPackages.cuda_cudart
    cudaPackages.cudnn
    cudaPackages.libcublas
    cudaPackages.libcufft
    
    # Graphics libraries
    libGL
    vulkan-loader
    libdrm
    
    # Browser/MCP support
    libxcb
    libX11
    gtk3
    # ... (see modules/nix-ld.nix for full list)
  ];
};
```

## 🔧 Fixes Applied

### 1. SDDM Service Fix
**Problem**: SDDM service had no ExecStart, causing direct boot to Plasma
**Solution**: Use `services.displayManager.sddm.enable = true` (not just `wayland.enable`)

### 2. Portal Registration Fix
**Problem**: "Could not register app ID: Connection already associated with an application ID"
**Solution**: Use `config.common` instead of `config.kde` for portal configuration

### 3. Task Manager Window Tracking
**Problem**: Icons-only-task-manager not showing open windows
**Solution**: Explicitly assign `WindowManagement` to `kde` in portal config

### 4. Dead Code Removal
**Removed modules**:
- `nix-ld-simple.nix` (duplicate of nix-ld.nix)
- `nvidia-sandbox.nix` (no-op module)
- `steam-sockets.nix` (Steam manages these automatically)

## 🎮 Gaming Configuration

### Steam with Wayland Support
```nix
services.steamWayland = {
  enable = true;
  protonVersion = "GE-Proton9-25";
};

programs.steam = {
  enable = true;
  extraCompatPackages = with pkgs; [ proton-ge-bin ];
  gamescopeSession.enable = true;
};
```

### Available Tools
- `gamescope` - Micro-compositor for problematic games
- `mangohud` - Performance overlay
- `goverlay` - Mangohud configuration GUI
- `protonup-ng` - Easy Proton-GE management

## 🧠 AI/ML (LM Studio, Ollama)

### CUDA Binary Cache (Updated Nov 2025)
```nix
nix.settings = {
  substituters = [
    "https://cache.nixos.org"
    "https://cache.nixos-cuda.org"  # Updated from cuda-maintainers.cachix.org
  ];
  trusted-public-keys = [
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
  ];
};

nixpkgs.config.cudaSupport = true;
```

### DLSS & Tensor Core Access
Applications have access to NVIDIA features through:
1. **nix-ld** - Provides CUDA libraries to dynamically linked binaries
2. **Flatpak** - NVIDIA drivers are mounted in sandbox
3. **Wine/Steam** - Proton handles NVIDIA DLLs

**Note**: DLSS requires game-specific support. The NGX SDK libraries are proprietary and bundled with games or the driver.

## 📦 Flatpak Integration

### Flathub Remotes (Declarative)
```nix
system.activationScripts.flatpak-remotes = ''
  ${pkgs.flatpak}/bin/flatpak remote-add --if-not-exists --system flathub https://flathub.org/repo/flathub.flatpakrepo
  ${pkgs.flatpak}/bin/flatpak remote-add --if-not-exists --system flathub-beta https://flathub.org/beta-repo/flathub-beta.flatpakrepo
'';
```

### Global Overrides
```nix
services.flatpak.overrides = {
  global = {
    Context.sockets = ["wayland" "x11" "pulseaudio"];
    Context.filesystems = [
      "xdg-download"
      "xdg-documents"
      "xdg-pictures"
    ];
    Environment = {
      GTK_THEME = "Breeze";
      QT_QPA_PLATFORMTHEME = "kde";
    };
  };
};
```

## 🚀 Quick Commands

### Restart Portal Services
```bash
systemctl restart --user xdg-desktop-portal plasma-xdg-desktop-portal-kde
```

### Check Portal Status
```bash
systemctl status --user plasma-xdg-desktop-portal-kde
```

### Verify Wayland Session
```bash
echo $XDG_SESSION_TYPE  # Should output: wayland
echo $XDG_CURRENT_DESKTOP  # Should output: KDE
```

### Rebuild System
```bash
sudo nixos-rebuild switch --flake .#zephyr
```

## 📋 Verification Checklist

- [ ] SDDM greeter appears on boot
- [ ] Lock screen works (Meta+L)
- [ ] Task manager shows open windows
- [ ] Portal services running without errors
- [ ] Steam launches games
- [ ] Flatpak apps have proper theming
- [ ] CUDA apps (LM Studio) detect GPU
- [ ] NVENC/NVDEC hardware acceleration works

## 📚 References

- [NixOS KDE Wiki](https://wiki.nixos.org/wiki/KDE)
- [NixOS CUDA Wiki](https://wiki.nixos.org/wiki/CUDA)
- [KDE Plasma Wayland](https://community.kde.org/Plasma/Wayland)
- [NVIDIA Wayland](https://download.nvidia.com/Xfree86/Linux-nvidia/README/wayland.html)

---

**Last Updated**: January 31, 2026  
**Branch**: feature/moltbot-integration  
**Status**: ✅ Production Ready
