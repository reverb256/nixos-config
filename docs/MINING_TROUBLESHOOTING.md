# Mining Services Troubleshooting Guide

## Overview

This guide documents common issues and solutions for the lolMiner GPU mining services on Forge (2x NVIDIA RTX 4060, 2x AMD RX 5700 XT).

**Services:**
- `lolminer-nvidia.service` - NVIDIA GPU mining (CUDA)
- `lolminer-amd.service` - AMD GPU mining (OpenCL)

## Common Issues

### Issue 1: "All devices deselected or failed compatibility check"

**Symptoms:**
- Service starts but detects 0 GPUs
- Journalctl shows "Number of OpenCL supported GPUs: 0"
- Only NVIDIA GPUs detected, AMD GPUs missing

**Root Cause:**
lolMiner has a path construction bug where it looks for `/etc/OpenCL/vendorsamdocl64.icd` instead of `/etc/OpenCL/vendors/amdocl64.icd` (missing slash before filename).

**Evidence from strace:**
```bash
strace -e trace=openat lolMiner --list-devices
# openat(AT_FDCWD, "/etc/OpenCL/vendorsamdocl64.icd", O_RDONLY) = -1 ENOENT
```

**Solution:**
Add tmpfiles workaround in host configuration:

```nix
# /etc/nixos/hosts/forge/configuration.nix
systemd.tmpfiles.rules = [
  # ... other rules ...
  # lolMiner workaround for OpenCL ICD path bug
  "L /etc/OpenCL/vendorsamdocl64.icd - - - - /etc/OpenCL/vendors/amdocl64.icd"
];
```

### Issue 2: AMD service detecting only NVIDIA GPUs

**Symptoms:**
- `lolMiner --list-devices` shows only 2 NVIDIA GPUs
- OpenCL driver detected but 0 AMD GPUs
- Service runs but on wrong devices

**Root Cause:**
Missing `OCL_ICD_VENDORS` environment variable. lolMiner searches wrong directory by default.

**Evidence from strace:**
```bash
strace -e trace=openat sudo -u mining lolMiner --list-devices
# Searches /run/opengl-driver/etc/OpenCL/vendors/ (wrong)
# Should search /etc/OpenCL/vendors/ (correct)
```

**Solution:**
Add environment variable to both lolMiner services:

```nix
# /etc/nixos/modules/mining/mining.nix
systemd.services.lolminer-nvidia.serviceConfig.Environment = [
  "GPU_MAX_HEAP_SIZE=100"
  "GPU_MAX_ALLOC_PERCENT=100"
  "OCL_ICD_VENDORS=/etc/OpenCL/vendors"  # Add this
];

systemd.services.lolminer-amd.serviceConfig.Environment = [
  "OCL_ICD_VENDORS=/etc/OpenCL/vendors"  # Add this
];
```

### Issue 3: "error in creating Cuda context"

**Symptoms:**
- NVIDIA service fails to start
- Error: "error in creating Cuda context"
- nvidia-smi shows GPUs at 100% utilization

**Root Cause:**
Zombie processes from earlier testing holding GPU resources.

**Solution:**
Kill zombie processes:
```bash
# Check for processes
nvidia-smi

# Kill zombie lolMiner processes
sudo kill -9 <PID>

# Restart service
sudo systemctl restart lolminer-nvidia
```

### Issue 4: Wrong device enumeration

**Symptoms:**
- Service starts but doesn't use expected GPUs
- Device indices changed after fixes

**Root Cause:**
lolMiner enumerates GPUs in combined mode (AMD OpenCL devices first, then NVIDIA CUDA devices).

**Correct device indices for Forge:**
- AMD GPUs (RX 5700 XT): devices 0,1
- NVIDIA GPUs (RTX 4060): devices 2,3

**Configuration:**
```nix
services.mining.lolminer.nvidia = {
  devices = "2,3";  # NVIDIA GPUs in combined enumeration
};

services.mining.lolminer.amd = {
  devices = "0,1";  # AMD GPUs in combined enumeration
};
```

## Diagnostic Commands

### Check service status:
```bash
sudo systemctl status lolminer-nvidia
sudo systemctl status lolminer-amd
```

### View service logs:
```bash
sudo journalctl -u lolminer-nvidia -f
sudo journalctl -u lolminer-amd -f
```

### List available devices:
```bash
sudo -u mining lolMiner --list-devices
```

### Check GPU status:
```bash
# NVIDIA GPUs
nvidia-smi

# AMD GPUs (via ROCm SMI)
/opt/rocm/bin/rocm-smi
```

### Trace system calls (advanced):
```bash
# Trace file access
strace -e trace=openat lolMiner --list-devices

# Run as mining user
strace -e trace=openat sudo -u mining lolMiner --list-devices
```

## Expected Performance

**Forge (2x RTX 4060 + 2x RX 5700 XT):**
- NVIDIA service: ~7.3 g/s (2x RTX 4060)
- AMD service: ~9.6 g/s (2x RX 5700 XT)
- Combined: ~17 g/s
- Power: ~280W (AMD) + ~180W (NVIDIA) = ~460W total

## Module Configuration

**Enable mining services:**
```nix
services.mining = {
  enable = true;
  user = "mining";
  
  lolminer.nvidia = {
    enable = true;
    autostart = true;
    devices = "2,3";
    powerLimit = 90;
    apiPort = 4068;
  };
  
  lolminer.amd = {
    enable = true;
    autostart = true;
    devices = "0,1";
    powerLimit = 140;
    apiPort = 4069;
  };
};
```

## Systemd Integration

**Slice-based resource management:**
Both services run under `mining.slice` for coordinated resource management.

**Control services imperatively:**
```bash
# Start service manually
sudo systemctl start lolminer-nvidia

# Stop service
sudo systemctl stop lolminer-amd

# Restart service
sudo systemctl restart lolminer-nvidia

# Enable/disable autostart
sudo systemctl enable lolminer-nvidia
sudo systemctl disable lolminer-amd
```

## Hardware Configuration

**NVIDIA RTX 4060:**
- Power limit: 90W per GPU
- Default hashrate: ~3.6 g/s per GPU
- Memory: 6880MiB per GPU

**AMD RX 5700 XT:**
- Power limit: 140W per GPU
- Default hashrate: ~4.8 g/s per GPU
- Temperature: 65-67°C under load

## Security Hardening

Both services use systemd security hardening:
- `NoNewPrivileges`: True
- `PrivateTmp`: True
- `ProtectSystem`: Strict
- `ProtectHome`: True
- `CapabilityBoundingSet`: CAP_SYS_NICE (GPU scheduling)

**Exception for XMRig:**
- `NoNewPrivileges`: False (required for MSR access)
- `ProtectKernelTunables`: False (required for /dev/cpu/*/msr access)
- `CapabilityBoundingSet`: CAP_SYS_RAWIO (MSR register access)

## Related Files

- **Module:** `/etc/nixos/modules/mining/mining.nix`
- **Host config:** `/etc/nixos/hosts/forge/configuration.nix`
- **Service files:** Generated by NixOS module

## History

**2026-03-09: Initial Debugging Session**
- Identified lolMiner OpenCL path bug
- Added OCL_ICD_VENDORS environment variable
- Created tmpfiles symlink workaround
- Both services operational at 17 g/s combined

---

**Last Updated:** 2026-03-09
**Maintainer:** j-kro
