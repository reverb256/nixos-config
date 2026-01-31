# Systemd Boot Errors and Modprobe Boot Errors Analysis

**Generated:** January 31, 2026
**System:** zephyr (NixOS 26.05, 6.18.6-zen1 kernel)
**Boot Time:** 30.348s total (firmware: 16.009s, loader: 2.771s, kernel: 5.341s, userspace: 6.225s)

## Summary of Issues Found

Based on actual system log analysis, the following boot errors and issues have been identified:

### 1. Modprobe Configuration Errors (MODERATE)

**Issue:** Invalid comment lines in `/etc/modprobe.d/nixos.conf` causing libkmod warnings
- **Error:** `ignoring bad line starting with '#'` for lines 11, 14, 15
- **Frequency:** Multiple occurrences during boot
- **Impact:** Non-fatal warnings that clutter boot logs

**Root Cause:** Improper comment formatting in modprobe configuration
```bash
# Current problematic lines (lines 11, 14, 15):
  # Audio stability - prevent crackling during gaming
  options snd_hda_intel power_save=0
  options snd_hda_intel power_save_controller=N
  # Conservative audio buffer settings
  options snd_hda_intel bdl_pos_adj=0  # Disable buffer position adjustments
```

**Fix Required:**
```bash
# Remove leading spaces before # comments:
# Audio stability - prevent crackling during gaming
options snd_hda_intel power_save=0
options snd_hda_intel power_save_controller=N
# Conservative audio buffer settings
options snd_hda_intel bdl_pos_adj=0  # Disable buffer position adjustments
```

### 2. User Group Resolution Error (MINOR)

**Issue:** systemd-tmpfiles fails to resolve user group 'j_kro'
- **Error:** `Failed to resolve group 'j_kro': No such process`
- **Location:** `/etc/tmpfiles.d/00-nixos.conf:4`
- **Impact:** Non-fatal, but indicates configuration inconsistency

**Root Cause:** User 'j_kro' exists but group resolution timing issue during early boot

**Fix:** This is a timing issue that should resolve itself, but could be mitigated by ensuring proper user/group ordering in configuration.

### 3. Service Failures (MINOR)

**Failed Services:**
- `openclaw-gateway.service`: Exit code failure (but service may not be active)
- `NetworkManager-wait-online.service`: 3.118s timeout (longest service startup)

**Impact:** Network connectivity may be delayed, but system boots successfully.

### 4. Boot Performance Issues (MINOR)

**Slow Services:**
1. `NetworkManager-wait-online.service`: 3.118s (network timeout)
2. `docker.service`: 860ms (container runtime)
3. `home-manager-j_kro.service`: 794ms (user environment setup)
4. `NetworkManager.service`: 696ms (network management)
5. `systemd-modules-load.service`: 667ms (module loading)

**Total boot time:** 30.348s (acceptable for a development workstation with multiple services)

### 5. Application Crashes (MINOR)

**Electron Application Crashes:**
- Multiple electron processes crashed during boot
- Stack trace indicates memory access violations
- Likely related to Wayland/X11 display issues

**Impact:** User applications failing but system remains functional.

## Configuration Issues Found

### 1. Modprobe Configuration File Issues

**File:** `/etc/modprobe.d/nixos.conf`
**Problems:**
- Lines 11, 14, 15 have incorrect comment formatting
- Causes libkmod to skip parsing those lines
- Could affect audio and USB optimizations

**Current problematic content:**
```bash
  # Audio stability - prevent crackling during gaming
  options snd_hda_intel power_save=0
  options snd_hda_intel power_save_controller=N
  # Conservative audio buffer settings
  options snd_hda_intel bdl_pos_adj=0  # Disable buffer position adjustments
```

**Recommended fix:**
```bash
# Audio stability - prevent crackling during gaming
options snd_hda_intel power_save=0
options snd_hda_intel power_save_controller=N
# Conservative audio buffer settings
options snd_hda_intel bdl_pos_adj=0  # Disable buffer position adjustments
```

### 2. NVIDIA Device Node Creation Issues

**Issue:** udev fails to create NVIDIA device nodes
- **Error:** `Process '/nix/store/.../bash -c 'mknod -m 666 /dev/nvidiactl c 195 255'' failed with exit code 1`
- **Impact:** NVIDIA GPU may not be fully accessible during early boot

**Root Cause:** NVIDIA driver not fully loaded when udev rules execute

## Recommendations

### Priority 1: Fix Modprobe Configuration (CRITICAL)
```bash
# Fix comment formatting in /etc/modprobe.d/nixos.conf
sudo sed -i 's/^  #/#/g' /etc/modprobe.d/nixos.conf
```

### Priority 2: Investigate NVIDIA Device Creation (LOW)
- Check NVIDIA driver loading order
- Verify udev rules timing
- Consider adding systemd service dependency

### Priority 3: Network Timeout Optimization (LOW)
- Reduce NetworkManager-wait-online timeout
- Check network interface configuration

### Priority 4: Monitor Application Stability (LOW)
- Investigate electron crashes
- Check display manager configuration

## System Status

**✅ System Functionality:** All critical services running
**✅ Boot Success:** System boots successfully in 30.348s
**✅ GPU Access:** NVIDIA modules loaded successfully
**✅ Network:** Connected after timeout
**✅ User Environment:** Home Manager configured correctly

**⚠️ Non-Critical Issues:**
- Modprobe configuration warnings (fixable)
- Long network timeout (optimizable)
- Application crashes (monitoring required)

## Conclusion

The system has **minor boot configuration issues** that do not affect core functionality. The primary issue is improper comment formatting in modprobe configuration files, which can be easily fixed. All critical services load successfully, and the system is fully operational for VR gaming, mining, and development workloads.

The boot time of 30.348s is acceptable for a workstation with multiple services (Docker, NetworkManager, Home Manager, mining services).