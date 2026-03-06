#!/usr/bin/env bash
# Compute Mode Profile for RTX 3060 Ti
# Optimizes GPU for dedicated compute workloads (AI, mining, rendering)
# Sets EXCLUSIVE_PROCESS mode for maximum performance

set -e

echo "=== Applying GPU COMPUTE MODE profile ==="

# GPU 0 (3060 Ti) - Headless, safe for compute mode
echo "Setting GPU 0 (3060 Ti) to EXCLUSIVE_PROCESS mode..."
sudo nvidia-smi -i 0 -c 3  # EXCLUSIVE_PROCESS (3, not 1 which is deprecated)

# GPU 1 (3090) - Has display output, be careful!
echo "GPU 1 (3090) warning: Connected to display"
echo "Leaving GPU 1 in DEFAULT mode (compatible with graphics)"
# Don't change GPU 1 mode - it's driving your display

# Set compute-optimized power settings
echo "Setting power limits for compute workloads..."
sudo nvidia-smi -i 0 -pl 220  # High power for sustained compute
sudo nvidia-smi -i 1 -pl 350  # Keep 3090 at max (it drives display)

# Set to maximum performance mode (no downclocking)
nvidia-settings -a [gpu:0]/GPUPowerMizerMode=1
nvidia-settings -a [gpu:1]/GPUPowerMizerMode=1

echo ""
echo "COMPUTE MODE profile applied:"
echo "  GPU 0 (3060 Ti): EXCLUSIVE_PROCESS mode"
echo "  GPU 1 (3090): DEFAULT mode (has display)"
echo "  Power limits: 220W (3060 Ti), 350W (3090)"
echo "  Performance mode: Maximum (no downclocking)"
echo ""
echo "Benefits:"
echo "  ✅ Single process gets full GPU access"
echo "  ✅ No context switching overhead"
echo "  ✅ Maximum performance for compute workloads"
echo "  ⚠️  Only one process can use GPU at a time"
echo ""
echo "Best for: AI inference, training, mining, rendering"
echo "NOT recommended for: Gaming (use gaming profile instead)"
