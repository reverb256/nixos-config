# Autonomous GPU Workload Management for Ampere (RTX 30) GPUs

## Overview

This system provides **fully autonomous GPU workload management** for NVIDIA Ampere GPUs (RTX 30 series). It automatically detects workload types and switches GPU profiles accordingly, eliminating the need for manual intervention.

## Research-Based Architecture

Based on industry-standard approaches:

1. **GameMode** - Automatic game detection with start/end hooks
2. **MPS (Multi-Process Service)** - GPU sharing for multiple small tasks
3. **Process Monitoring** - Detect AI/mining/gaming processes automatically
4. **Priority-Based Scheduling** - Gaming > AI > Mining > Idle

## Key Findings from Research

### GameMode Integration

From real-world implementations:
- ✅ **Start/End Hooks**: Scripts run when games start/stop
- ✅ **Mining Pause**: Automatically stops mining when gaming detected
- ✅ **GPU Control**: Sets PowerMizer modes and clock offsets
- ✅ **Zero-Touch**: Works with Steam, Lutris, Heroic launchers

**Example Configuration** (from Manjaro forum):
```ini
[custom]
start=notify-send "GameMode started" && sudo nvidia-smi -i 0 -pl 140
end=notify-send "GameMode ended" && sudo nvidia-smi -i 0 -pl 120
```

### MPS (Multi-Process Service)

**What is MPS?**
- NVIDIA's technology for sharing GPU across multiple processes
- Reduces context switching overhead
- Increases GPU utilization for small tasks (inference, training)
- **Ampere Support**: Full support on RTX 30 series (compute capability 8.6+)

**Benefits**:
- 🚀 **Higher Throughput**: Multiple tasks execute in same context
- 💾 **Less Memory Waste**: Shared memory pool
- ⚡ **Lower Latency**: Eliminates context creation/destroy overhead
- 📊 **Better Utilization**: Efficient resource sharing

**Use Cases**:
- AI inference (multiple models, concurrent requests)
- Fine-tuning (LoRA, small models)
- Batch processing (multiple small jobs)

## Implementation

### System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│              Autonomous Workload Monitor                     │
│         (Detects workload type every 10 seconds)              │
└──────────────┬────────────────────────────────────────────────┘
               │
               ├─ Gaming Detected → GameMode + Gaming Profile
               │                  → Pause Mining
               │                  → Max Performance Mode
               │
               ├─ AI Detected → AI Profile
               │               → Pause Mining
               │               → Balanced Clocks
               │
               ├─ Mining Detected → Mining Profile
               │                  → Efficiency Mode
               │                  → Start Mining
               │
               └─ Idle → Reset Profile
                        → Adaptive Mode
```

### Components

#### 1. Workload Monitor Daemon

**Location**: `/etc/nixos/scripts/gpu-profiles/workload-monitor.sh`

**Function**: Continuously monitors processes and switches profiles

**Detection Logic**:
```bash
Priority: Gaming > AI > VRAM-PRESSURE > Builds > Mining > Idle

Gaming Processes:
  - steam, lutris, heroic, wine, proton, wine-preloader, wine64, wineserver

AI Processes:
  - lmstudio, ollama, python.*llm, ai-inference-gateway

Build Processes:
  - nixos-rebuild, colmena, nix-build, gcc, clang, cargo build, make, cmake, ninja

VRAM Pressure Detection:
  - Checks VRAM usage before starting miner
  - Threshold: 40% (zephyr), 35% (nexus), 50% (forge)
  - Prevents 30-second desktop freeze from VRAM contention

Mining Processes:
  - lolminer-nvidia, lolminer-amd, xmrig (systemd services)
```

**Check Interval**: 10 seconds (configurable)

#### 2. GameMode Integration

**Location**: Configured in `/etc/nixos/modules/gaming/gaming.nix`

**Function**: Automatic detection when games start/stop

**Hooks**:
- `start`: Runs gaming profile, pauses mining
- `end`: Runs AI inference profile

**Usage**:
```bash
# Launch game with GameMode
gamemoderun /path/to/game

# Or configure Steam launch options: gamemoderun %command%
```

#### 3. GPU Profiles

**Location**: `/etc/nixos/scripts/gpu-profiles/`

| Profile | Power Limit | Clock Offsets | Use Case |
|---------|-------------|---------------|----------|
| `gaming.sh` | 200W/350W | +180/+150 GPU, +700/+600 Mem | Gaming, VR |
| `mining.sh` | 100W/250W | +50/0 GPU, +500/+400 Mem | Crypto mining |
| `ai-inference.sh` | 110W/280W | +100/+80 GPU, +400/+500 Mem | LM Studio, AI |
| `mps.sh` | Adaptive | Shared context | Multi-task GPU |
| `reset.sh` | Default | 0 offset | Auto mode |

## MPS Configuration for Ampere GPUs

### GPU 0 (RTX 3060 Ti)

```bash
# Start MPS
export CUDA_VISIBLE_DEVICES=0
export CUDA_MPS_PIPE_DIRECTORY=/tmp/nvidia-mps-gpu0
mkdir -p $CUDA_MPS_PIPE_DIRECTORY

nvidia-smi -i 0 -c EXCLUSIVE_PROCESS
nvidia-cuda-mps-control -d

# Configure for 4 clients (25% each)
echo "set per_client_memory_limit 10737418240" | nvidia-cuda-mps-control  # 10GB
echo "set per_client_thread_limit 25" | nvidia-cuda-mps-control
```

### GPU 1 (RTX 3090)

```bash
# Start MPS
export CUDA_VISIBLE_DEVICES=1
export CUDA_MPS_PIPE_DIRECTORY=/tmp/nvidia-mps-gpu1
mkdir -p $CUDA_MPS_PIPE_DIRECTORY

nvidia-smi -i 1 -c EXCLUSIVE_PROCESS
nvidia-cuda-mps-control -d

# Configure for 2 clients (50% each)
echo "set per_client_memory_limit 12884901888" | nvidia-cuda-mps-control  # 12GB
echo "set per_client_thread_limit 50" | nvidia-cuda-mps-control
```

### Client Configuration

Clients must set the same `CUDA_MPS_PIPE_DIRECTORY`:

```python
import os
os.environ['CUDA_MPS_PIPE_DIRECTORY'] = '/tmp/nvidia-mps-gpu0'

# Run your CUDA code
import torch
# ...
```

## Usage

### Automatic Mode (Recommended)

The workload monitor daemon runs automatically at boot:

```bash
# Status check
systemctl status gpu-workload-monitor

# View logs
journalctl -u gpu-workload-monitor -f

# Logs also written to: /var/log/gpu-workload-monitor.log
```

### Manual Control

```bash
# Switch profiles manually
gpu-profile gaming      # Max performance
gpu-profile ai          # Balanced for AI
gpu-profile mining      # Efficiency mode
gpu-profile mps         # Enable GPU sharing
gpu-profile reset       # Back to auto
gpu-profile status      # Show current status
```

### GameMode Integration

Games that support GameMode will automatically trigger profile switches:

```bash
# Launch any game
gamemoderun ./my-game

# Or configure in Steam: gamemoderun %command%
```

## Performance Optimization

### Gaming Profile

**Optimized for**: FPS, low latency

- Power limits: 200W (3060 Ti), 350W (3090)
- Clocks: Aggressive overclock (+180/+150 MHz GPU)
- Memory: Maximum overclock (+700/+600 MHz)
- Mode: Maximum Performance (no downclocking)

**Expected Results**:
- 10-20% FPS improvement in GPU-bound games
- Consistent performance (no throttling)
- Higher power draw

### Mining Profile

**Optimized for**: Efficiency, hash/watt ratio

- Power limits: 100W (3060 Ti), 250W (3090)
- Clocks: Conservative (+50/0 GPU offset)
- Memory: Moderate (+500/+400 MHz)
- Mode: Adaptive

**Expected Results**:
- 70-80% of max hashrate
- 50% power reduction
- Better thermals
- Lower electricity cost

### AI Inference Profile

**Optimized for**: Consistency, latency, throughput

- Power limits: 110W (3060 Ti), 280W (3090)
- Clocks: Balanced (+100/+80 GPU offset)
- Memory: Optimized (+400/+500 MHz)
- Mode: Adaptive

**Expected Results**:
- Consistent inference latency
- 20-30% better perf/watt
- Thermal headroom for sustained workloads
- Suitable for 24/7 operation

### MPS Mode

**Optimized for**: Multiple concurrent tasks

- GPU 0: 4 clients, 10GB each, 25% threads
- GPU 1: 2 clients, 12GB each, 50% threads
- Shared context (reduced overhead)

**Expected Results**:
- 2-4x throughput for small tasks
- Lower latency per request
- Better GPU utilization
- Ideal for: batch inference, multiple models

## Scheduling Algorithm

### Priority System

```
1. GAMING (Highest)
   - Detected: Steam, Lutris, Heroic, Wine, Proton processes
   - Action: Apply gaming profile, hard stop mining
   - Priority: Interrupt all other workloads
   - Mining: systemctl stop (instant VRAM release)

2. AI INFERENCE
   - Detected: LM Studio, Ollama, AI gateway, Python ML processes
   - Action: Apply AI profile, hard stop mining
   - Priority: Interrupt mining, coexist with idle
   - Mining: systemctl stop (instant VRAM release)

3. VRAM-PRESSURE (NEW!)
   - Detected: VRAM usage > 40% (host-specific threshold)
   - Action: Block miner start, stop running miners
   - Priority: Prevent desktop freeze from VRAM contention
   - Mining: Blocked or stopped, check VRAM before starting

4. BUILDS
   - Detected: nixos-rebuild, colmena, gcc, cargo, make, cmake
   - Action: Apply builds profile, throttle mining
   - Priority: Reduce mining interference during compiles
   - Mining: CPUQuota=10% (keep alive for quick resume)

5. MINING
   - Detected: lolminer-nvidia service active
   - Action: Apply mining profile
   - Priority: Only when no other workloads detected
   - Requirement: VRAM usage < threshold

6. IDLE
   - Detected: No GPU-intensive processes
   - Action: Apply reset profile (adaptive mode)
   - Priority: Don't auto-start mining (user manual)
```

### State Machine

```
[IDLE] → Gaming Detected → [GAMING]
[IDLE] → AI Detected → [AI]
[IDLE] → VRAM > 40% → [VRAM-PRESSURE]
[IDLE] → Build Detected → [BUILDS]
[IDLE] → Mining Started → [MINING]

[GAMING] → Game Exits → [AI] (if AI running)
[GAMING] → Game Exits → [VRAM-PRESSURE] (if VRAM high)
[GAMING] → Game Exits → [IDLE] (if nothing else)

[AI] → Gaming Detected → [GAMING] (interrupt AI)
[AI] → AI Exits → [VRAM-PRESSURE] (if VRAM high)
[AI] → AI Exits → [BUILDS] (if build active)
[AI] → AI Exits → [MINING] (if mining enabled)
[AI] → AI Exits → [IDLE]

[VRAM-PRESSURE] → VRAM < 40% → [MINING] (auto-start)
[VRAM-PRESSURE] → Gaming Detected → [GAMING] (interrupt)
[VRAM-PRESSURE] → AI Detected → [AI] (interrupt)
[VRAM-PRESSURE] → Build Detected → [BUILDS] (interrupt)

[BUILDS] → Build Complete → [MINING] (if VRAM OK)
[BUILDS] → Gaming Detected → [GAMING] (interrupt)
[BUILDS] → AI Detected → [AI] (interrupt)

[MINING] → Gaming Detected → [GAMING] (stop mining)
[MINING] → AI Detected → [AI] (stop mining)
[MINING] → VRAM > 40% → [VRAM-PRESSURE] (stop mining)
[MINING] → Build Detected → [BUILDS] (throttle mining)
[MINING] → Mining Stopped → [IDLE]
```

### VRAM Pressure Protection (NEW!)

**Problem**: When AI models are loaded (8-10GB VRAM) and miner starts, GPU driver evicts AI model to system RAM → **30-second desktop freeze**

**Solution**: Proactive VRAM pressure detection before starting miner

**How It Works**:
1. Check VRAM usage on all GPUs before starting miner
2. If any GPU > threshold (40% on zephyr), block miner start
3. For AI/gaming workloads, hard stop miner (not just CPU quota)
4. Miner auto-resumes when VRAM is freed

**Thresholds** (host-specific):
- **zephyr**: 40% (workstation with AI/gaming)
- **nexus**: 35% (storage server, conservative)
- **forge**: 50% (dedicated mining rig, aggressive)
- **sentry**: 40% (monitoring node)

**Benefits**:
- ✅ Eliminates 30-second desktop freeze
- ✅ Smooth transitions between workloads
- ✅ Instant VRAM release (hard stop vs CPU quota)
- ✅ Automatic recovery when VRAM freed

**Trade-offs**:
- Cost: 2-3 second miner restart
- Benefit: 27+ seconds saved per VRAM contention event

## Advanced Configuration

### Custom Detection Rules

Edit `/etc/nixos/scripts/gpu-profiles/workload-monitor.sh`:

```bash
# Add your own processes
GAMING_PROCESSES=("steam" "lutris" "heroic" "wine" "proton" "your-game")
AI_PROCESSES=("lmstudio" "ollama" "python.*llm" "ai-inference-gateway" "your-ai-app")
MINING_SERVICE="lolminer-nvidia"  # or your mining service
```

### Adjust Check Interval

```bash
# In workload-monitor.sh
CHECK_INTERVAL=5   # Check every 5 seconds (more responsive)
CHECK_INTERVAL=30  # Check every 30 seconds (less overhead)
```

### Profile Customization

Each profile script can be tuned for your specific GPUs:

```bash
# Edit gaming.sh
nvidia-settings -a [gpu:0]/GPUGraphicsClockOffset[3]=200  # More aggressive
nvidia-settings -a [gpu:1]/GPUGraphicsClockOffset[3]=180
nvidia-smi -i 0 -pl 220  # Higher power limit
```

## Troubleshooting

### Monitor Not Detecting Workload

```bash
# Check if monitor is running
systemctl status gpu-workload-monitor

# View logs
journalctl -u gpu-workload-monitor -n 50

# Check process detection
pgrep -f "lmstudio"
pgrep -f "steam"
```

### GameMode Not Activating

```bash
# Test GameMode
gamemoderun echo "test"

# Check GameMode status
gamemoded -t

# View GameMode logs
journalctl --user -u gamemoded -f
```

### MPS Not Working

```bash
# Check if MPS is running
ps aux | grep nvidia-cuda-mps

# View MPS logs
cat /tmp/nvidia-log-gpu0/*

# Restart MPS
pkill -f nvidia-cuda-mps-control
/etc/nixos/scripts/gpu-profiles/mps.sh
```

### Profile Switching Issues

```bash
# Check current settings
nvidia-smi -q -d CLOCK
nvidia-settings -q [gpu:0]/GPUPowerMizerMode

# Reset to defaults
/etc/nixos/scripts/gpu-profiles/reset.sh

# Apply profile manually
/etc/nixos/scripts/gpu-profiles/gaming.sh
```

## Performance Monitoring

### Real-time Monitoring

```bash
# Watch GPU status
watch -n 2 /etc/nixos/scripts/gpu-profiles/switch-profile status

# Monitor workload detector
tail -f /var/log/gpu-workload-monitor.log

# GPU utilization and thermals
nvidia-smi dmon
```

### Metrics Collection

The system integrates with existing Prometheus exporters:
- `prometheus-nvidia-gpu-exporter.service` - GPU metrics
- `gpu-workload-monitor` - Logs workload changes

### Analyze Patterns

```bash
# View workload transitions
grep "Workload changed" /var/log/gpu-workload-monitor.log

# Count profile switches
grep "Applying profile" /var/log/gpu-workload-monitor.log | wc -l

# Find most common workload
grep "Applying profile" /var/log/gpu-workload-monitor.log | awk '{print $NF}' | sort | uniq -c
```

## Best Practices

### Gaming

1. Use `gamemoderun` for all games
2. Don't run AI/mining while gaming
3. Monitor temperatures (keep under 85°C)
4. Use gaming profile for competitive play

### AI Inference

1. Use AI profile for LM Studio
2. Enable MPS for batch processing
3. Monitor GPU memory usage
4. Adjust thread limits based on model size

### Mining

1. Only mine when GPU is idle
2. Use mining profile for efficiency
3. Monitor hashrate vs power
4. Don't mine during gaming/AI workloads

### General

1. Let workload monitor handle switching
2. Check logs periodically
3. Adjust profiles based on your GPUs
4. Keep GPU temps under 85°C sustained

## Integration with Existing Services

### AI Gateway

The workload monitor detects `ai-inference-gateway` process:

```bash
# When gateway is active → AI profile applied
# Mining automatically paused
# GPU clocks optimized for inference
```

### LM Studio

Detected by process name:

```bash
# LM Studio detected → AI profile + MPS enabled
# Multiple models can run concurrently
# Shared GPU context for efficiency
```

### Mining Service

Systemd service integration:

```bash
# Mining starts automatically in idle time
# Paused when gaming/AI detected
# Resumes when GPUs free
```

## Future Enhancements

Potential improvements:

1. **Machine Learning Prediction**: Predict workload patterns
2. **Temperature-Based Scaling**: Adjust profiles based on thermals
3. **Energy Cost Optimization**: Schedule mining during off-peak hours
4. **SLA Integration**: QoS for different workload types
5. **Kubernetes Integration**: Container-based workload scheduling

## References

- GameMode: https://github.com/FeralInteractive/gamemode
- NVIDIA MPS: https://docs.nvidia.com/deploy/mps/index.html
- CUDA MPS: https://developer.nvidia.com/blog/cuda-pro-tip-mps-aws/
- Ampere Architecture: https://www.nvidia.com/en-us/data-center/technologies/ampere/

## Changelog

- **2026-03-05**: Initial autonomous workload management system
  - GameMode integration
  - MPS support for Ampere GPUs
  - Automatic workload detection
  - Priority-based scheduling
  - Profile auto-switching

## Contributing

To add new workload types or modify detection logic:

1. Edit `workload-monitor.sh`
2. Add process patterns to detect
3. Create corresponding profile script
4. Update this documentation

## License

Part of the NixOS configuration for zephyr system.
