#!/usr/bin/env bash
# Mining Profile - Maximum Efficiency
# Priority: Efficiency > hashrate > thermals

set -e

echo "=== Applying GPU MINING profile ==="

# Adaptive mode for power efficiency
nvidia-settings -a [gpu:0]/GPUPowerMizerMode=0
nvidia-settings -a [gpu:1]/GPUPowerMizerMode=0

# Reduced power limits for efficiency (70-75% of max)
nvidia-smi -i 0 -pl 100  # 3060 Ti (50% - sweet spot)
nvidia-smi -i 1 -pl 250  # 3090 (71% - sweet spot)

# Conservative clocks (or let auto handle it)
# Mining often runs best at slightly reduced clocks
nvidia-settings -a [gpu:0]/GPUGraphicsClockOffset[3]=50
nvidia-settings -a [gpu:0]/GPUMemoryClockOffset[3]=500

nvidia-settings -a [gpu:1]/GPUGraphicsClockOffset[3]=0
nvidia-settings -a [gpu:1]/GPUMemoryClockOffset[3]=400

echo "MINING profile applied:"
echo "  GPU 0 (3060 Ti):   50 MHz GPU offset, 500 MHz mem offset, 100W limit"
echo "  GPU 1 (3090):      0 MHz GPU offset, 400 MHz mem offset, 250W limit"
echo "  Mode: Adaptive (power efficiency)"
echo ""
echo "NOTE: Monitor temps and hashrate. Adjust mem clock for optimal hashrate/power."
