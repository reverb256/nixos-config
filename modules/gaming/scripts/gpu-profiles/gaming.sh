#!/usr/bin/env bash
# Gaming Profile - Maximum Performance
# Priority: FPS > efficiency > thermals
# Dynamically detects available GPUs

set -e

# Source common GPU utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_gpu-common.sh"

echo "=== Applying GPU GAMING profile ==="

# Get list of available GPUs
GPUS=$(get_gpu_list)
GPU_COUNT=$(get_gpu_count)

if [ "$GPU_COUNT" -eq 0 ]; then
    echo "WARNING: No NVIDIA GPUs detected"
    exit 0
fi

echo "Detected $GPU_COUNT GPU(s) for gaming profile"

# Apply settings for each detected GPU
for gpu_id in $GPUS; do
    gpu_name=$(get_gpu_name "$gpu_id")

    echo "Configuring GPU $gpu_id ($gpu_name)..."

    # Switch to max performance mode
    nvidia-settings -a [gpu:${gpu_id}]/GPUPowerMizerMode=1 2>/dev/null || true

    # Set aggressive settings based on GPU model
    case "$gpu_name" in
        *"3060"*)
            # 3060 Ti: Max performance
            set_power_limit "$gpu_id" 200
            nvidia-settings -a [gpu:${gpu_id}]/GPUGraphicsClockOffset[3]=180 2>/dev/null || true
            nvidia-settings -a [gpu:${gpu_id}]/GPUMemoryClockOffset[3]=700 2>/dev/null || true
            echo "  3060 Ti: 180 MHz GPU offset, 700 MHz mem offset, 200W limit"
            ;;
        *"3090"*)
            # 3090: Max performance
            set_power_limit "$gpu_id" 350
            nvidia-settings -a [gpu:${gpu_id}]/GPUGraphicsClockOffset[3]=150 2>/dev/null || true
            nvidia-settings -a [gpu:${gpu_id}]/GPUMemoryClockOffset[3]=600 2>/dev/null || true
            echo "  3090: 150 MHz GPU offset, 600 MHz mem offset, 350W limit"
            ;;
        *)
            # Default: Max power, aggressive clocks
            set_power_limit "$gpu_id" 300
            echo "  $gpu_name: Using default 300W limit, max performance"
            ;;
    esac
done

echo ""
echo "GAMING profile applied to all GPUs"
echo "  Mode: Prefer Maximum Performance"
