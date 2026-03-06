#!/usr/bin/env bash
# Reset to Default/Auto Profile
# Clears all manual clock control

set -e

echo "=== Resetting GPUs to DEFAULT/AUTO profile ==="

# Reset to adaptive mode
nvidia-settings -a [gpu:0]/GPUPowerMizerMode=0
nvidia-settings -a [gpu:1]/GPUPowerMizerMode=0

# Reset clock offsets to 0
nvidia-settings -a [gpu:0]/GPUGraphicsClockOffset[3]=0
nvidia-settings -a [gpu:0]/GPUMemoryClockOffset[3]=0
nvidia-settings -a [gpu:1]/GPUGraphicsClockOffset[3]=0
nvidia-settings -a [gpu:1]/GPUMemoryClockOffset[3]=0

# Reset power limits to defaults
nvidia-smi -i 0 -pl 200  # 3060 Ti default
nvidia-smi -i 1 -pl 350  # 3090 default (actually 350W is your current limit)

echo "RESET to defaults applied:"
echo "  All clock offsets reset to 0"
echo "  Power limits reset to configured defaults"
echo "  Mode: Adaptive (auto)"
echo ""
echo "GPUs will now auto-scale based on workload."
