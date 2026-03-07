# GPU Manual Clock Control Guide

## Overview

This system provides manual control over GPU clocks and power limits for optimal performance across different workloads (gaming, mining, AI inference).

## Philosophy

**Why Manual Control?**
- ✅ Predictable, consistent performance
- ✅ No auto-scaling surprises
- ✅ Optimized per-workload tuning
- ⚠️ Requires manual tuning for stability
- ⚠️ Must monitor thermals

## Quick Start

```bash
# Check current status
/etc/nixos/scripts/gpu-profiles/switch-profile status

# Switch profiles
/etc/nixos/scripts/gpu-profiles/switch-profile gaming
/etc/nixos/scripts/gpu-profiles/switch-profile mining
/etc/nixos/scripts/gpu-profiles/switch-profile ai
/etc/nixos/scripts/gpu-profiles/switch-profile reset
```

## Profiles

### Gaming Profile (`gaming.sh`)
**Priority**: FPS > efficiency > thermals

- **Power Limits**: 200W (3060 Ti), 350W (3090) - MAX
- **Clock Offsets**:
  - 3060 Ti: +180 MHz GPU, +700 MHz Memory
  - 3090: +150 MHz GPU, +600 MHz Memory
- **Power Mizer**: Mode 1 (Prefer Maximum Performance)

**Use for**: Competitive gaming, AAA titles, VR

### Mining Profile (`mining.sh`)
**Priority**: Efficiency > hashrate > thermals

- **Power Limits**: 100W (3060 Ti), 250W (3090) - REDUCED
- **Clock Offsets**:
  - 3060 Ti: +50 MHz GPU, +500 MHz Memory
  - 3090: 0 MHz GPU, +400 MHz Memory
- **Power Mizer**: Mode 0 (Adaptive)

**Use for**: Cryptocurrency mining, distributed computing

### AI Inference Profile (`ai-inference.sh`)
**Priority**: Consistency > latency > throughput

- **Power Limits**: 110W (3060 Ti), 280W (3090) - BALANCED
- **Clock Offsets**:
  - 3060 Ti: +100 MHz GPU, +400 MHz Memory
  - 3090: +80 MHz GPU, +500 MHz Memory
- **Power Mizer**: Mode 0 (Adaptive)

**Use for**: LM Studio, AI inference, ML workloads

### Reset Profile (`reset.sh`)
Returns all GPUs to automatic/default mode.

## Advanced Tuning

### Understanding Clock Offsets

**GPU Graphics Clock Offset**:
- Range: 0 to +200 MHz (typical safe range)
- Higher = more FPS in GPU-bound games
- Too high = instability, crashes
- **Start conservative**: +100 MHz

**Memory Clock Offset**:
- Range: 0 to +1000 MHz (possible)
- **Safe start**: +400-600 MHz
- Higher = more bandwidth (helps high-res textures)
- Mining: Memory bandwidth is critical
- **3090 GDDR6X**: More sensitive to mem overclocks

### Stability Testing

For each workload type:

**Gaming**:
```bash
# Apply gaming profile
/etc/nixos/scripts/gpu-profiles/switch-profile gaming

# Run a demanding game for 30+ minutes
# Monitor for: artifacts, crashes, driver resets

# If unstable, reduce offsets by 25 MHz and retry
```

**Mining**:
```bash
# Apply mining profile
/etc/nixos/scripts/gpu-profiles/switch-profile mining

# Start miner, monitor for 1+ hour
# Watch for: rejected shares, hardware errors

# Check hashrate vs power consumption
# Optimize: Increase mem clock until hashrate plateaus
```

**AI Inference**:
```bash
# Apply AI profile
/etc/nixos/scripts/gpu-profiles/switch-profile ai

# Run sustained inference workload
# Monitor: temperatures, inference latency

# If throttling, reduce power limit by 10-20W
```

### Finding Sweet Spots

**Power vs Performance Curve**:

```
Power Draw
  |
  |    ___
  |   /   \__  Sweet spot: 60-80% power
  |  /
  | /
  |/___________
  0          100% Power Limit

Performance increases linearly up to ~70% power,
then plateaus. Going beyond = diminishing returns.
```

**Recommended Approach**:
1. Start with profile defaults
2. Run your workload
3. Monitor: temps, power, performance
4. Adjust in 10% increments
5. Find sweet spot (where performance/power ratio is best)

### Temperature Targets

**Safe Operating Temps**:
- **Idle**: < 45°C
- **Load**: 70-80°C (optimal)
- **Max**: 85°C (start throttling)
- **Critical**: > 90°C (danger zone)

**If temps are too high**:
1. Reduce power limit by 10-20W
2. Reduce GPU clock offset by 25-50 MHz
3. Check case airflow and GPU fans

## Manual Control Commands

### Set Power Limits
```bash
# Set specific power limits (watts)
sudo nvidia-smi -i 0 -pl 150  # 3060 Ti
sudo nvidia-smi -i 1 -pl 300  # 3090

# Reset to default
sudo nvidia-smi -i 0 -pl 200
sudo nvidia-smi -i 1 -pl 350
```

### Set Clock Offsets
```bash
# Graphics clock offset (performance state 3)
sudo nvidia-settings -a [gpu:0]/GPUGraphicsClockOffset[3]=150
sudo nvidia-settings -a [gpu:1]/GPUGraphicsClockOffset[3]=100

# Memory clock offset
sudo nvidia-settings -a [gpu:0]/GPUMemoryClockOffset[3]=600
sudo nvidia-settings -a [gpu:1]/GPUMemoryClockOffset[3]=500

# Reset to 0 (auto)
sudo nvidia-settings -a [gpu:0]/GPUGraphicsClockOffset[3]=0
sudo nvidia-settings -a [gpu:0]/GPUMemoryClockOffset[3]=0
```

### Power Mizer Mode
```bash
# Adaptive (default - auto scaling)
sudo nvidia-settings -a [gpu:0]/GPUPowerMizerMode=0
sudo nvidia-settings -a [gpu:1]/GPUPowerMizerMode=0

# Prefer maximum performance (no downclocking)
sudo nvidia-settings -a [gpu:0]/GPUPowerMizerMode=1
sudo nvidia-settings -a [gpu:1]/GPUPowerMizerMode=1
```

## Monitoring

### Real-time Monitoring
```bash
# Watch GPU stats in real-time
watch -n 1 'nvidia-smi --query-gpu=index,name,power.draw,power.limit,temperature.gpu,utilization.gpu,clocks.current.graphics,clocks.current.memory --format=csv,noheader'

# Or use the status script
watch -n 2 /etc/nixos/scripts/gpu-profiles/switch-profile status
```

### Check Current Settings
```bash
# Full query
nvidia-smi -q

# Clocks only
nvidia-smi -q -d CLOCK

# Power only
nvidia-smi -q -d POWER

# Temperature only
nvidia-smi -q -d THERMAL
```

## Troubleshooting

### "Unable to query clock offset"
**Normal**: When offset is 0 (default), query may fail. This is expected behavior.

### "Attribute 'GPUGraphicsClockOffset' is not writable"
**Cause**: Wrong performance state or GPU doesn't support it
**Fix**: Use `[3]` (highest perf state) or check GPU capability

### System crashes after applying profile
**Cause**: Clock offsets too aggressive
**Fix**:
1. Switch to reset profile: `./switch-profile reset`
2. Reduce offsets by 25-50 MHz
3. Re-test stability

### Poor performance in gaming
**Cause**: Power limit too low or clocks too conservative
**Fix**: Use gaming profile or increase limits

### High temperatures (>85°C)
**Cause**: Power limit too high or poor cooling
**Fix**:
1. Reduce power limit by 10-20W
2. Check GPU fan curves (use nvidia-settings or coolbits)
3. Improve case airflow

## Integration with NixOS

To make these profiles persistent across reboots, add to your NixOS config:

```nix
# /etc/nixos/modules/gaming/gpu-profiles.nix
{ config, pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    (pkgs.writeShellScriptBin "gpu-profile" ''
      exec ${./scripts/gpu-profiles/switch-profile} "$@"
    '')
  ];

  # Optional: Set default profile at boot
  systemd.services.gpu-default-profile = {
    description = "Set default GPU profile at boot";
    after = [ "nvidia-persistence-mode.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${./scripts/gpu-profiles/ai-inference.sh}";
    };
  };
}
```

## Safety Notes

⚠️ **WARNING**: Manual clock control can damage hardware if set incorrectly

1. **Start conservative**: Use profile defaults as starting point
2. **Monitor temperatures**: Always watch temps when adjusting
3. **Stability test**: Run extended tests before using for important work
4. **Incremental changes**: Adjust in small steps (10-20%)
5. **Know your limits**: Each GPU is different - what works for one may not work for another

## Further Reading

- NVIDIA GPU Boost: https://developer.nvidia.com/blog/boostkernels/
- GPU Overclocking Guide: [External guides]
- Thermal Throttling: https://en.wikipedia.org/wiki/Thermal_throttling

## Changelog

- **2026-03-05**: Initial setup with gaming, mining, AI profiles
- **TODO**: Add auto-switching based on detected workload
- **TODO**: Integrate with temperature monitoring for dynamic adjustment
