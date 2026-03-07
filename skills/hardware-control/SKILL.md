---
name: hardware-control
description: Manage GPU/CPU hardware for mining and AI workloads. Use when user asks to: control fans, adjust power limits, check GPU status, manage mining, toggle between mining and AI, or monitor hardware.
---

# Hardware Control

Manage multi-GPU and CPU hardware across the cluster for mining (xmrig, lolminer) and AI workloads (LM Studio).

## When to Use This Skill

Use this skill when the user:
- Asks to "check GPU status", "what's mining", "stop mining"
- Wants to "adjust power limit", "set fan speed", "overclock"
- Needs to "switch to AI mode", "pause mining for AI"
- Asks about "temperature", "power usage", "hashrate"
- Wants to "monitor hardware", "check sensors"

## Cluster Hardware Overview

| Host | CPU | GPUs | Cooling | Primary Use |
|------|-----|------|---------|-------------|
| **zephyr** | AMD Ryzen 9 5900X | RTX 3090 + RTX 3060 Ti | Corsair AIO + RGB | Workstation + Gaming + VR + Mining + AI |
| **nexus** | AMD Ryzen 9 5900X | 2x RTX 3060 Ti | Air cooling | Gaming + VR + Mining + AI |
| **forge** | Intel i7-6700K | 2x RTX 4060 + RX 5600 | Air cooling | Mining + AI (CUDA + ROCm) |
| **sentry** | AMD Ryzen 9 5900X | RX 6800 (Wayland) | Air cooling | Mining + AI (ROCm) |

## GPU Monitoring

### Check GPU Status (NVIDIA)
```bash
# Quick overview
nvidia-smi

# Detailed with continuous updates
watch -n 1 nvidia-smi

# Check specific GPU
nvidia-smi -i 0  # GPU 0
nvidia-smi -i 1  # GPU 1

# Format output
nvidia-smi --query-gpu=index,name,temperature.gpu,utilization.gpu,power.draw,fan.speed --format=csv
```

### Check GPU Status (AMD)
```bash
# Overview
rocminfo | grep -A 5 "Device Type"

# Temperature and usage
sensors | grep -A 5 amdgpu

# ROCm info
rocm-smi
```

### System Sensors
```bash
# All sensors
sensors

# CPU temperature
sensors | grep -i core

# Fan speeds
sensors | grep -i fan
```

## Mining Control

### Check Mining Status
```bash
# On zephyr (local)
systemctl status xmrig@nvidia0  # RTX 3090
systemctl status xmrig@nvidia1  # RTX 3060 Ti

# On remote hosts
ssh nexus "systemctl status lolminer-nvidia"
ssh forge "systemctl status lolminer-nvidia"
ssh sentry "systemctl status xmrig@amdgpu"
```

### Stop Mining
```bash
# Stop specific miner
sudo systemctl stop xmrig@nvidia0

# Stop all mining on host
sudo systemctl stop xmrig@*
sudo systemctl stop lolminer-*

# Stop on remote host
ssh nexus "sudo systemctl stop lolminer-*"
```

### Start Mining
```bash
# Start specific miner
sudo systemctl start xmrig@nvidia0

# Start all mining on host
sudo systemctl start xmrig@*

# Start on remote host
ssh forge "sudo systemctl start lolminer-*"
```

### Restart Mining
```bash
# Restart after configuration change
sudo systemctl restart xmrig@nvidia0

# Restart all mining
sudo systemctl restart xmrig@*
sudo systemctl restart lolminer-*
```

## Mining Configuration

Mining services are defined in NixOS modules:
```
/etc/nixos/modules/mining/
├── default.nix           # Main mining module
├── xmrig.nix             # XMRig (RandomX) CPU/GPU miner
└── lolminer.nix          # LolMiner (Etchash) GPU miner
```

### Host-Specific Mining Configuration

Each host enables mining in its `configuration.nix`:
```nix
# hosts/zephyr/configuration.nix
profiles.role.mining = true;

# Or enable specific miners
services.xmrig = {
  enable = true;
  gpus = [ "0" "1" ];  # GPU indices
};

services.lolminer = {
  enable = true;
  devices = [ "0" "1" ];
};
```

## GPU Power Control (NVIDIA)

### Set Power Limit
```bash
# Check current power limit
nvidia-smi -i 0 --query-gpu=power.limit --format=csv

# Set power limit (in watts)
sudo nvidia-smi -i 0 -pl 250  # Set 250W limit
sudo nvidia-smi -i 1 -pl 130  # Set 130W limit

# Reset to default
sudo nvidia-smi -i 0 -pl 350  # RTX 3090 default
```

### Set Fan Speed
```bash
# Set manual fan control (speed 0-100)
sudo nvidia-smi -i 0 -pm 1  # Enable manual control
sudo nvidia-smi -i 0 -风扇 70  # Set 70%

# Reset to auto
sudo nvidia-smi -i 0 -pm 0  # Enable auto control
```

### Set Clock Offset
```bash
# Set GPU clock offset (+/- MHz)
sudo nvidia-smi -i 0 -lg 100   # +100 MHz GPU clock
sudo nvidia-smi -i 0 -lc 1000  # +1000 MHz memory clock

# Reset
sudo nvidia-smi -i 0 -rg  # Reset GPU offset
sudo nvidia-smi -i 0 -rc  # Reset memory offset
```

## GPU Power Control (AMD)

### AMD GPU settings via ROCm
```bash
# Check current power limit
rocm-smi --showpower

# Set power limit (in watts)
rocm-smi --setpoweroverdrive 250

# Set fan speed
rocm-smi --setfan 70

# Set performance level
rocm-smi --setperflevel DPM_LEVEL_AUTO
```

## Workload Mode Switching

### Mining Mode (Max Performance)
```bash
# Set high power limits for mining
sudo nvidia-smi -i 0 -pl 350  # RTX 3090 max
sudo nvidia-smi -i 1 -pl 200  # RTX 3060 Ti max

# Ensure mining is running
sudo systemctl restart xmrig@*
sudo systemctl restart lolminer-*
```

### AI Mode (Balanced)
```bash
# Set moderate power limits
sudo nvidia-smi -i 0 -pl 250
sudo nvidia-smi -i 1 -pl 130

# Stop mining to free GPU
sudo systemctl stop xmrig@*
sudo systemctl stop lolminer-*

# Verify LM Studio has access
curl http://127.0.0.1:1234/v1/models
```

### Gaming Mode (Low Latency)
```bash
# Stop mining first
sudo systemctl stop xmrig@*
sudo systemctl stop lolminer-*

# Set optimal gaming power
sudo nvidia-smi -i 0 -pl 280
sudo nvidia-smi -i 1 -pl 130

# Disable persistence mode (if enabled)
sudo nvidia-smi -pm 0
```

## Temperature Monitoring

### Check Temperatures
```bash
# GPU temperatures
nvidia-smi --query-gpu=index,name,temperature.gpu --format=csv

# CPU temperatures
sensors | grep -i Core

# All temperatures
sensors
```

### Temperature Alerts
```bash
# Watch for high temperatures
watch -n 5 'nvidia-smi --query-gpu=index,temperature.gpu --format=csv,noheader | awk "\$2 > 80 {print \"GPU \" \$1 \" hot: \" \$2 \"C\"}"'
```

## Power Monitoring

### Check Power Usage
```bash
# GPU power draw
nvidia-smi --query-gpu=index,power.draw --format=csv

# Total system power (if supported)
sudo tlp-stat -s  # If TLP is installed

# UPS power (if configured)
upsc ups@localhost
```

## Persistent GPU Settings

To make GPU settings persistent across reboots, use NixOS:

### Via Udev Rules
```nix
# In hardware/ gpu configuration
services.udev.extraRules = ''
  # NVIDIA GPU power limit on boot
  ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", RUN+="/usr/bin/nvidia-smi -i 0 -pl 250"
'';
```

### Via Systemd Service
```nix
# Create systemd service to set GPU settings
systemd.services.gpu-power-limit = {
  description = "Set GPU power limits on boot";
  wantedBy = [ "multi-user.target" ];
  after = [ "multi-user.target" ];
  script = ''
    /run/current-system/sw/bin/nvidia-smi -i 0 -pl 250
    /run/current-system/sw/bin/nvidia-smi -i 1 -pl 130
  '';
};
```

## Mining Logs

### View Mining Output
```bash
# View xmrig logs
journalctl -u xmrig@nvidia0 -f

# View lolminer logs
journalctl -u lolminer-nvidia -f

# Check recent hashrate
journalctl -u xmrig@nvidia0 -n 100 | grep -i "speed\|hash"
```

## Troubleshooting

### GPU Not Detected
```bash
# Check if NVIDIA driver is loaded
lsmod | grep nvidia

# Check GPU devices
lspci | grep -i vga

# Restart NVIDIA services
sudo systemctl restart nvidia-persistenced
```

### Mining Not Starting
```bash
# Check service status
systemctl status xmrig@nvidia0

# Check logs
journalctl -u xmrig@nvidia0 -n 50

# Verify GPU is accessible
nvidia-smi
```

### High Temperatures
```bash
# Check fan speeds
nvidia-smi --query-gpu=index,fan.speed --format=csv

# Clean fans if needed (hardware maintenance)

# Reduce power limit
sudo nvidia-smi -i 0 -pl 200
```

## Quick Reference

| Task | Command |
|------|---------|
| Check GPUs | `nvidia-smi` or `rocm-smi` |
| Check mining | `systemctl status xmrig@*` |
| Stop mining | `sudo systemctl stop xmrig@* lolminer-*` |
| Start mining | `sudo systemctl start xmrig@* lolminer-*` |
| Set power limit | `sudo nvidia-smi -i 0 -pl 250` |
| Check temps | `sensors` or `nvidia-smi` |
| View logs | `journalctl -u xmrig@nvidia0 -f` |

## Related Skills
- **nix-rebuild**: For applying hardware configuration changes
- **ai-gateway-manager**: For managing AI workloads
- **nixos-deploy**: For deploying mining config to cluster
