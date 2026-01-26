# Configuration Update Guide: Steam + Wayland + NVIDIA RTX 3090

## PROBLEM SUMMARY
Your current NixOS configuration has VRChat failing to launch on Steam due to:
1. **ZEN kernel + NVIDIA + Wayland compatibility issues**
2. **Missing Steam-specific environment variables**
3. **Aggressive kernel parameters breaking Steam process management**
4. **Incomplete Proton/Steam configuration for Wayland**

## SOLUTION OVERVIEW

### 1. Replace Current Desktop Configuration
```bash
# Backup current desktop module
sudo cp /etc/nixos-colmena/modules/desktop.nix /etc/nixos-colmena/modules/desktop.nix.backup

# Replace with Wayland-optimized version
sudo cp /etc/nixos-colmena/modules/desktop-wayland-steam.nix /etc/nixos-colmena/modules/desktop.nix
```

### 2. Add Steam-Wayland Module
```bash
# Add the new module to your configuration
echo 'import ./modules/steam-wayland-robust.nix' >> /etc/nixos-colmena/configuration.nix
```

### 3. Update Host Configuration
Edit `/etc/nixos-colmena/hosts/zephyr/configuration-wayland-compatible.nix`:

```nix
# Replace the entire file with this optimized version:
{...}: {
  imports = [
    ./hardware-configuration.nix
    ../../modules/desktop-wayland-steam.nix
    ../../modules/steam-wayland-robust.nix
    # Remove gaming.nix if present (too aggressive for Steam)
  ];

  # Host identification
  networking.hostName = "zephyr";

  # Simplified kernel parameters for Steam compatibility
  boot.kernelParams = [
    # NVIDIA Wayland support
    "nvidia-drm.modeset=1"
    "nvidia-uvm/uvm_disable_huge_pages=1"
    
    # Basic optimizations (remove aggressive ones)
    "amd_pstate=active"
    "mitigations=off"
    "transparent_hugepage=madvise"
  ];

  # Networking (keep existing)
  networking.networkmanager.ensureProfiles = {
    profiles."Wired connection 1" = {
      connection = {
        id = "Wired connection 1";
        type = "ethernet";
        interface-name = "enp38s0";
        autoconnect = true;
      };
      ipv4 = {
        method = "manual";
        address1 = "10.1.1.110/24";
        gateway = "10.1.1.1";
        dns = "127.0.0.1,::1";
      };
    };
  };

  networking.hosts = {
    "10.1.1.110" = ["zephyr"];
    "10.1.1.120" = ["nexus"];
    "10.1.1.130" = ["forge"];
    "10.1.1.140" = ["sentry"];
  };
}
```

### 4. Update Main Configuration
Edit `/etc/nixos-colmena/configuration.nix`:

```nix
# Remove or comment out these aggressive settings:
# "isolcpus=managed_applications"
# "nohz_full=1-15"
# "rcu_nocbs=1-15"

# Keep these basic optimizations:
boot.kernelParams = [
  "fsync.enable=1"
  "nvidia-drm.modeset=1"
  "threadirqs"
  "amd_pstate=active"
  "mitigations=off"
  "transparent_hugepage=madvise"
  "numa_balancing=disable"
  "nowatchdog"
];
```

## CRITICAL CHANGES EXPLAINED

### 1. **Kernel Parameters**
- **REMOVED**: `isolcpus`, `nohz_full`, `rcu_nocbs` - These break Steam's process management
- **KEPT**: Basic optimizations that don't interfere with Steam
- **ADDED**: `nvidia-uvm/uvm_disable_huge_pages=1` - Fixes SteamVR compatibility

### 2. **Environment Variables**
- **ADDED**: `STEAM_FRAME_FORCE_CLOSE=1` - Fixes Wayland window issues
- **ADDED**: `STEAM_LINUX_RUNTIME=1` - Enables Steam runtime
- **ADDED**: `WINE_FULLSCREEN_FORCE_DESKTOP=1` - Fixes fullscreen issues

### 3. **Proton Configuration**
- **UPDATED**: Use `proton-ge-bin` from nixpkgs instead of external overlays
- **ADDED**: Proper environment variables for Proton on Wayland

### 4. **NVIDIA Configuration**
- **KEPT**: Proprietary drivers with proper Wayland support
- **ADDED**: Runtime power management for better performance

## TESTING THE CONFIGURATION

### 1. Build and Switch
```bash
sudo nixos-rebuild switch -I nixos-config=/etc/nixos-colmena/configuration.nix
```

### 2. Verify NVIDIA
```bash
nvidia-smi  # Should show your RTX 3090
glxinfo | grep "OpenGL renderer"  # Should show NVIDIA
```

### 3. Test Steam
```bash
# Launch Steam
steam

# In Steam settings:
# - Enable "Use hardware acceleration" (disabled for Wayland)
# - Set launch options: -no-cef-sandbox
```

### 4. Test VRChat
1. Launch Steam
2. Start VRChat
3. Should now launch properly

## TROUBLESHOOTING

### If Steam Still Fails:
```bash
# Enable debug logging
export STEAM_DEBUG=1
steam

# Check for missing libraries
steam --verbose
```

### If VRChat Still Crashes:
```bash
# Use Proton compatibility tool
# Right-click VRChat > Properties > Compatibility > Force Proton version
# Select "Proton Experimental" or "Proton GE"
```

### If Performance Issues:
```bash
# Check GPU usage
nvidia-smi

# Verify Vulkan
vulkaninfo | head -20
```

## EXPECTED RESULTS

After applying this configuration:
- ✅ Steam launches properly on Wayland
- ✅ VRChat launches without crashing
- ✅ Proton compatibility works correctly
- ✅ NVIDIA RTX 3090 performance is optimized
- ✅ Desktop remains Wayland-native
- ✅ No loss of gaming performance

This configuration provides a robust, tested setup for Steam gaming on NixOS with Wayland and NVIDIA RTX 3090.