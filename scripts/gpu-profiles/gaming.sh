#!/usr/bin/env bash
# Gaming Profile - Maximum Performance
# Priority: FPS > efficiency > thermals

set -e

echo "=== Applying GPU GAMING profile ==="

# Switch to max performance mode
nvidia-settings -a [gpu:0]/GPUPowerMizerMode=1
nvidia-settings -a [gpu:1]/GPUPowerMizerMode=1

# Max power limits
nvidia-smi -i 0 -pl 200  # 3060 Ti
nvidia-smi -i 1 -pl 350  # 3090

# Aggressive clock offsets (tune based on your GPU stability)
# 3060 Ti: +180 MHz graphics, +700 MHz memory
nvidia-settings -a [gpu:0]/GPUGraphicsClockOffset[3]=180
nvidia-settings -a [gpu:0]/GPUMemoryClockOffset[3]=700

# 3090: +150 MHz graphics, +600 MHz memory
nvidia-settings -a [gpu:1]/GPUGraphicsClockOffset[3]=150
nvidia-settings -a [gpu:1]/GPUMemoryClockOffset[3]=600

echo "GAMING profile applied:"
echo "  GPU 0 (3060 Ti):  180 MHz GPU offset, 700 MHz mem offset, 200W limit"
echo "  GPU 1 (3090):     150 MHz GPU offset, 600 MHz mem offset, 350W limit"
echo "  Mode: Prefer Maximum Performance"
