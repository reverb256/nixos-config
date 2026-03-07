#!/usr/bin/env bash
# Mining Profile - Maximum Efficiency
# Priority: Efficiency > hashrate > thermals
# Dynamically detects available GPUs

set -e

# Source common GPU utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_gpu-common.sh"

echo "=== Applying GPU MINING profile ==="

# Get list of available GPUs
GPUS=$(get_gpu_list)
GPU_COUNT=$(get_gpu_count)

if [ "$GPU_COUNT" -eq 0 ]; then
    echo "WARNING: No NVIDIA GPUs detected"
    exit 0
fi

echo "Detected $GPU_COUNT GPU(s) for mining profile"

# Apply settings for each detected GPU
for gpu_id in $GPUS; do
    gpu_name=$(get_gpu_name "$gpu_id")

    echo "Configuring GPU $gpu_id ($gpu_name)..."

    # Adaptive mode for power efficiency
    nvidia-settings -a [gpu:${gpu_id}]/GPUPowerMizerMode=0 2>/dev/null || true

    # Set efficient settings based on GPU model
    case "$gpu_name" in
        *"3060"*)
            # 3060 Ti: Sweet spot for efficiency
            set_power_limit "$gpu_id" 100
            nvidia-settings -a [gpu:${gpu_id}]/GPUGraphicsClockOffset[3]=50 2>/dev/null || true
            nvidia-settings -a [gpu:${gpu_id}]/GPUMemoryClockOffset[3]=500 2>/dev/null || true
            echo "  3060 Ti: 50 MHz GPU offset, 500 MHz mem offset, 100W limit"
            ;;
        *"3090"*)
            # 3090: Sweet spot for efficiency
            set_power_limit "$gpu_id" 250
            nvidia-settings -a [gpu:${gpu_id}]/GPUGraphicsClockOffset[3]=0 2>/dev/null || true
            nvidia-settings -a [gpu:${gpu_id}]/GPUMemoryClockOffset[3]=400 2>/dev/null || true
            echo "  3090: 0 MHz GPU offset, 400 MHz mem offset, 250W limit"
            ;;
        *)
            # Default: 75% power for efficiency
            set_power_limit "$gpu_id" 200
            echo "  $gpu_name: Using default 200W limit for efficiency"
            ;;
    esac
done

echo ""
echo "MINING profile applied to all GPUs"
echo "  Mode: Adaptive (power efficiency)"
echo ""
echo "NOTE: Monitor temps and hashrate. Adjust mem clock for optimal hashrate/power."
