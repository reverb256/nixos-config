# Razer & Corsair Peripherals Troubleshooting Guide

## Current Status (2026-02-05)

### OpenRazer (Razer Devices)
- **Status**: FIXED - Now using NixOS built-in `hardware.openrazer` module
- **Previous Issue**: Custom daemon service tried to write to `/etc/openrazer` (read-only on NixOS)
- **Solution**: The official `hardware.openrazer.enable = true` module properly handles:
  - Daemon service with correct `/var/lib/openrazer` location
  - udev rules
  - openrazer group creation

### ckb-next (Corsair Devices)
- **Status**: ADDED - ckb-next-daemon systemd service now configured
- **Verification**: Service running - "Root controller ready at /dev/input/ckb0"
- **Remaining Issue**: USB device permission error (typical on first run)

## Configuration Changes Made

### 1. Switched to Official OpenRazer Module

**Before (broken)**:
```nix
hardware.peripherals = {
  razer = {
    enable = true;
    daemon = true;
  };
};
```

**After (fixed)**:
```nix
hardware.openrazer.enable = true;  # Built-in module handles everything

hardware.peripherals = {
  enable = true;
  corsair = {
    enable = true;
    ckbNext = true;
  };
};
```

### 2. Added User to openrazer Group

```nix
users.users.j_kro.extraGroups = ["plugdev" "audio" "input" "docker" "openrazer"];
```

### 3. Added ckb-next-daemon Service

Added systemd service for Corsair devices in `modules/peripherals.nix`.

## Quick Verification Commands

```bash
# Check OpenRazer service
systemctl status openrazer-daemon

# Check ckb-next service  
systemctl status ckb-next-daemon

# Check user groups
groups j_kro

# Test Razer CLI
razer-cli --list

# Check device permissions
ls -la /dev/hidraw*
```

## Post-Rebuild Steps

After running `sudo nixos-rebuild switch`:

1. **Reboot** or log out/in to refresh group memberships
2. **Reload udev rules**:
   ```bash
   sudo udevadm control --reload-rules
   sudo udevadm trigger
   ```
3. **Restart daemons**:
   ```bash
   systemctl restart openrazer-daemon
   systemctl restart ckb-next-daemon
   ```

## Common Issues

### 1. OpenRazer "Read-only file system" on /etc
- **Cause**: Custom service trying to create `/etc/openrazer`
- **Fix**: Use `hardware.openrazer.enable = true` (already applied)

### 2. ckb-next "Failed to open USB device: Operation not permitted"
- **Cause**: USB permissions not applied yet
- **Fix**: Reload udev rules, ensure user in `plugdev` group, reboot

### 3. Devices not detected after reboot
- **Cause**: udev rules need reload or daemon needs restart
- **Fix**: Run the post-rebuild steps above

### 4. Polychromatic shows "No devices found"
- **Cause**: User not in `openrazer` group or daemon not running
- **Fix**: 
  ```bash
  sudo usermod -aG openrazer j_kro
  systemctl restart openrazer-daemon
  ```

## Supported Devices

- **OpenRazer**: https://github.com/openrazer/openrazer/wiki/Supported-devices
- **ckb-next**: https://github.com/matricali/ckb-next/wiki/Supported-Hardware

## Files Modified

- `/etc/nixos/configuration.nix` - Added `hardware.openrazer.enable`
- `/etc/nixos/hosts/zephyr/configuration.nix` - Added `openrazer` to user groups
- `/etc/nixos/modules/peripherals.nix` - Simplified, removed custom OpenRazer service
- `/etc/nixos/modules/system-packages.nix` - Removed redundant `openrazer-daemon`
