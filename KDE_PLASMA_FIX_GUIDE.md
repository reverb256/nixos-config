# KDE Plasma Window Management Fix Guide

## 🔍 Problem Diagnosis

Your KDE Plasma windows disappearing or "dropping off" the interface is caused by **missing critical components** for window tracking and management.

### Root Causes Identified:

1. **Missing xdg-desktop-portal-kde** - The primary culprit for window tracking issues
2. **Missing environment variables** - KDE needs specific variables to manage windows properly
3. **Incomplete NVIDIA configuration** - Missing modesetting causes rendering issues
4. **SDDM not configured for Wayland** - Causes session ambiguity

## ✅ Fixes Applied

### Fix 1: Added Essential KDE Packages
```nix
# In modules/system-packages.nix
environment.systemPackages = with pkgs; [
  kdePackages.xdg-desktop-portal-kde  # ← CRITICAL for window management
  kdePackages.libdbusmenu-qt5         # Application menu support
  kdePackages.kdeconnect              # Device integration
  kdePackages.plasma-systemmonitor    # System widgets
];
```

### Fix 2: Added KDE Environment Variables
```nix
# In configuration.nix
environment.sessionVariables = {
  QT_QPA_PLATFORM = "wayland";       # Qt Wayland support
  GDK_BACKEND = "wayland";           # GTK Wayland support
  SDL_VIDEODRIVER = "wayland";       # SDL Wayland support
  XDG_CURRENT_DESKTOP = "KDE";       # Desktop environment identification
  XDG_SESSION_TYPE = "wayland";      # Session type specification
};
```

### Fix 3: Added NVIDIA Modesetting
```nix
# In configuration.nix
hardware.nvidia = {
  modesetting.enable = true;         # Kernel mode setting
  powerManagement.enable = true;    # Power optimization
  nvidiaSettings = true;             # NVIDIA settings utility
  open = false;                      # Proprietary drivers
};
```

### Fix 4: Enabled SDDM Wayland
```nix
# In configuration.nix
services.displayManager.sddm.wayland.enable = true;
```

### Fix 5: Added Plasma Configuration
```nix
# In configuration.nix
services.xserver.desktopManager.plasma6 = {
  enableQtScale = true;  # Better HiDPI support
  krunner.enabled = true; # Application launcher
};
```

## 🚀 Immediate Steps

### Step 1: Apply Configuration Changes
```bash
# Rebuild and switch to new configuration
sudo nixos-rebuild switch --flake /etc/nixos
```

### Step 2: Restart Display Manager
```bash
# Restart SDDM to apply Wayland changes
sudo systemctl restart sddm.service
```

### Step 3: Log Out and Log Back In
```bash
# Log out of Plasma session and log back in
# All changes will take effect on next login
```

### Step 4: Run Fix Script (Optional)
```bash
# Run the automated fix script
/etc/nixos/fix-plasma.sh
```

## 🔧 Manual Troubleshooting Steps

If windows still disappear after applying fixes:

### Check 1: Verify Services are Running
```bash
# Check xdg-desktop-portal status
systemctl status xdg-desktop-portal-kde

# Check if running (should show "active (running)")
# If not running, start it:
sudo systemctl start xdg-desktop-portal-kde
```

### Check 2: Verify Environment Variables
```bash
# Check if variables are set correctly
echo $QT_QPA_PLATFORM
echo $XDG_CURRENT_DESKTOP
echo $XDG_SESSION_TYPE

# Should output:
# wayland
# KDE
# wayland
```

### Check 3: Reset Plasma Settings
```bash
# Backup current settings
cp -r ~/.config/plasma ~/.config/plasma.backup
cp ~/.config/kwinrc ~/.config/kwinrc.backup

# Reset Plasma to defaults
rm -rf ~/.cache/plasma*
kwriteconfig5 --file plasmashellrc --group "PlasmaShell" --key "compactMode" ""
kwriteconfig5 --file kwinrc --group "Windows" --key "Placement" "Smart"
kwriteconfig5 --file kwinrc --group "Desktops" --key "NumberOfDesktops" "1"

# Restart Plasma
kquitapp5 plasmashell && plasmashell &
```

### Check 4: Check for Conflicting Applications
```bash
# Look for processes that might interfere
ps aux | grep -E "compton|picom|xfwm4|openbox"

# These can conflict with Plasma's window manager
# Remove or disable if running
```

### Check 5: Verify NVIDIA Driver
```bash
# Check NVIDIA driver status
nvidia-smi

# Check if modesetting is enabled
cat /sys/module/nvidia_drm/parameters/modeset

# Should show "Y" for modesetting enabled
```

### Check 6: Check Wayland vs X11
```bash
# Check current session type
loginctl

# Or in Plasma, run:
kquitapp5 krunner && krunner &

# Check if running Wayland or X11
echo $WAYLAND_DISPLAY

# If empty, you might be on X11
# To force Wayland, ensure SDDM Wayland is enabled
```

## 🎯 Advanced Troubleshooting

### Reset Virtual Desktops
```bash
# Reset virtual desktop configuration
kwriteconfig5 --file kwinrc --group "Desktops" --key "NumberOfDesktops" "2"
kwriteconfig5 --file kwinrc --group "Desktops" --key "DesktopName_1" "Desktop 1"
kwriteconfig5 --file kwinrc --group "Desktops" --key "DesktopName_2" "Desktop 2"

# Restart KWin
kquitapp5 kwin_x11 && kwin_x11 &
# OR for Wayland:
kquitapp5 kwin_wayland && kwin_wayland &
```

### Clear KDE Cache
```bash
# Clear all KDE caches
rm -rf ~/.cache/plasma*
rm -rf ~/.cache/kio*
rm -rf ~/.cache/ksycoca*

# Rebuild cache
kbuildsycoca6 &
```

### Reset Window Management Rules
```bash
# Remove window management rules that might be hiding windows
rm ~/.config/kwinrulesrc

# Restart KWin
kquitapp5 kwin_x11 && kwin_x11 &
```

### Check Monitor Configuration
```bash
# Check if monitors are detected correctly
kquitapp5 kscreen_backend && kscreen_backend &

# Or use xrandr
xrandr -q

# Ensure all monitors are configured correctly
# Duplicate or extended desktop settings can cause window tracking issues
```

## 📋 Best Practices for KDE Plasma Stability

### Do:
- ✅ Use Wayland session for NVIDIA GPUs with modesetting enabled
- ✅ Keep xdg-desktop-portal-kde installed and running
- ✅ Use SDDM with Wayland enabled
- ✅ Set XDG_CURRENT_DESKTOP = "KDE"
- ✅ Restart Plasma after major configuration changes

### Don't:
- ❌ Mix X11 and Wayland applications inconsistently
- ❌ Disable xdg-desktop-portal services
- ❌ Use multiple window managers simultaneously
- ❌ Run Compton/Picom with KDE (KWin handles compositing)
- ❌ Modify Plasma settings while applications are open

## 🔍 Monitoring Window Management

### Check if windows are being tracked:
```bash
# Look for window events
dbus-monitor --session interface=org.freedesktop.portal.Desktop

# In another terminal, open a window and watch for events
```

### Monitor KWin activity:
```bash
# Check KWin logs
journalctl -u plasma-kwin_wayland.service -f

# Look for window placement or visibility events
```

### Check xdg-desktop-portal:
```bash
# Check portal status
xdg-desktop-portal --version

# Check if portals are available
ls /usr/share/xdg-desktop-portal/

# Specifically check for KDE portal
ls /usr/share/xdg-desktop-portal/portals/
```

## 📞 If Issues Persist

If windows continue to disappear after trying all fixes:

1. **Collect system information**:
   ```bash
   # Save system info to file
   neofetch > ~/system-info.txt
   nix-instantiate --eval -E 'builtins.nixVersion' >> ~/system-info.txt
   ```

2. **Check for hardware issues**:
   ```bash
   # Check GPU memory
   nvidia-smi
   
   # Check for GPU errors
   dmesg | grep -i nvidia | tail -20
   ```

3. **Try fresh Plasma profile**:
   ```bash
   # Create backup
   cp -r ~/.config ~/.config.backup
   
   # Create minimal Plasma configuration
   mkdir -p ~/.config/plasma-workspace/env
   echo 'export QT_QPA_PLATFORM=wayland' > ~/.config/plasma-workspace/env/wayland.sh
   ```

4. **Check for conflicting NixOS modules**:
   Review your imports in `configuration.nix` and ensure no modules are disabling or conflicting with Plasma services.

## 📚 References

- [KDE Plasma Wayland Documentation](https://community.kde.org/Plasma/Wayland)
- [NixOS KDE Plasma Module](https://nixos.org/manual/nixos/stable/#sec-kde)
- [xdg-desktop-portal-kde](https://github.com/KDE/xdg-desktop-portal-kde)
- [NVIDIA Wayland Support](https://download.nvidia.com/Xfree86/Linux-nvidia/README/wayland.html)

## ✅ Verification Checklist

After applying fixes, verify:

- [ ] `systemctl status xdg-desktop-portal-kde` shows "active (running)"
- [ ] `echo $QT_QPA_PLATFORM` outputs "wayland"
- [ ] `echo $XDG_CURRENT_DESKTOP` outputs "KDE"
- [ ] `nvidia-smi` shows drivers working correctly
- [ ] Windows remain visible and trackable across virtual desktops
- [ ] Application menus work properly (right-click menus)
- [ ] File dialogs open correctly
- [ ] Screenshot functionality works

---

**Fix applied**: January 17, 2026  
**Configuration version**: zephyr  
**Status**: ✅ Ready for testing