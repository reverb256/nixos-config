# ============================================================================
# MINING OPTIMIZER SKILL FOR CLAWDBOT
# ============================================================================
# Skill for intelligent mining operations and gaming VR detection
---
name: mining-optimizer
description: Intelligent mining control, gaming detection, and resource optimization
metadata: {"clawdbot":{"requires":{"bins":["nvidia-smi","procps"],"os":["linux"],"emoji":"⛏️"}}
---

## Capabilities

This skill provides comprehensive mining and gaming optimization:

### Mining Control
- `mining-start` - Start all mining services (GPU + CPU)
- `mining-stop` - Stop all mining services
- `mining-status` - Check mining hashrates and temperatures
- `mining-restart` - Restart mining with updated configuration
- `mining-auto` - Toggle auto-mining mode

### Gaming Detection
- `gaming-detect` - Detect active gaming sessions
- `vr-detect` - Detect VR sessions (SteamVR/WiVRn)
- `gaming-pause` - Auto-pause mining during gaming
- `vr-pause` - Specialized VR mining pause

### Performance Monitoring
- `gpu-monitor` - Monitor GPU temperature, power, hashrate
- `cpu-monitor` - Monitor CPU usage and thermal throttling
- `power-usage` - Track power consumption and costs
- `profitability` - Calculate mining profitability

### Advanced Optimization
- `overclock-gpu` - Safe GPU overclocking (+150MHz NVIDIA)
- `optimize-schedule` - Schedule mining for off-peak hours
- `thermal-throttle` - Automatic thermal protection
- `power-limit` - Set power consumption limits

## Usage Examples

### Smart Mining Control
```
> Start mining with gaming detection
> Auto-pause when VR/gaming detected
> Resume mining when gaming stops
```

### Performance Analysis
```
> Check GPU temperatures and hashrates
> Monitor power consumption vs profitability
> Optimize settings for maximum efficiency
```

### Gaming Integration
```
> Detect SteamVR session starting
> Automatically pause mining
> Resume with optimized settings after gaming
```

## Safety Features

- **Temperature monitoring**: Auto-shutdown at 85°C GPU temperature
- **Power limits**: Prevents system instability
- **Gaming priority**: Always pauses for VR/gaming sessions
- **Gradual optimization**: Safe incremental changes
- **Rollback capability**: Restore previous stable settings

## Integration Points

This skill integrates with:
- lolMiner NVIDIA service
- XMRig CPU mining service
- GameMode optimizations
- NVIDIA driver management
- systemd service control
- Gaming/VR detection systems

## Supported Mining Algorithms

- **GPU**: Ethash, KawPow, Octopus, Autolykos
- **CPU**: RandomX, CryptoNight, Argon2
- **Auto-switching**: Most profitable algorithm selection

## Commands Reference

```bash
# Start optimized mining
mining-start --algorithm auto --power-limit 80%

# Gaming-optimized mining
mining-auto --gaming-detection --vr-pause

# Performance monitoring
mining-status --detailed --temps --power

# Emergency stop
mining-stop --force --cooling-period 300
```

Use for intelligent mining operations that respect gaming and VR usage while maximizing efficiency and profitability.