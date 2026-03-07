#!/usr/bin/env bash
# AI Inference Profile - Balanced Performance
# Priority: Consistency > latency > throughput
# Dynamically detects available GPUs

set -e

# Source common GPU utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_gpu-common.sh"

echo "=== Applying GPU AI INFERENCE profile ==="

# Get list of available GPUs
GPUS=$(get_gpu_list)
GPU_COUNT=$(get_gpu_count)

if [ "$GPU_COUNT" -eq 0 ]; then
    echo "WARNING: No NVIDIA GPUs detected"
    exit 0
fi

echo "Detected $GPU_COUNT GPU(s):"
for gpu_id in $GPUS; do
    gpu_name=$(get_gpu_name "$gpu_id")
    echo "  GPU $gpu_id: $gpu_name"
done
echo ""

# Apply settings for each detected GPU
for gpu_id in $GPUS; do
    gpu_name=$(get_gpu_name "$gpu_id")

    echo "Configuring GPU $gpu_id ($gpu_name)..."

    # Set adaptive mode for consistent performance
    nvidia-settings -a [gpu:${gpu_id}]/GPUPowerMizerMode=0 2>/dev/null || true

    # Set power limit and clocks based on GPU model
    case "$gpu_name" in
        *"3060"*)
            # 3060 Ti: 110W limit (55% of 200W)
            set_power_limit "$gpu_id" 110
            nvidia-settings -a [gpu:${gpu_id}]/GPUGraphicsClockOffset[3]=100 2>/dev/null || true
            nvidia-settings -a [gpu:${gpu_id}]/GPUMemoryClockOffset[3]=400 2>/dev/null || true
            echo "  3060 Ti: 100 MHz GPU offset, 400 MHz mem offset, 110W limit"
            ;;
        *"3090"*)
            # 3090: 280W limit (80% of 350W)
            set_power_limit "$gpu_id" 280
            nvidia-settings -a [gpu:${gpu_id}]/GPUGraphicsClockOffset[3]=80 2>/dev/null || true
            nvidia-settings -a [gpu:${gpu_id}]/GPUMemoryClockOffset[3]=500 2>/dev/null || true
            echo "  3090: 80 MHz GPU offset, 500 MHz mem offset, 280W limit"
            ;;
        *)
            # Default: 75% of typical power limit
            set_power_limit "$gpu_id" 200
            echo "  $gpu_name: Using default 200W limit, adaptive clocks"
            ;;
    esac
done

echo ""
echo "AI INFERENCE profile applied to all GPUs"
echo "  Mode: Adaptive (consistent performance)"
echo ""
echo "This profile optimizes for:"
echo "  - Consistent inference latency"
echo "  - Power efficiency"
echo "  - Thermal headroom for sustained workloads"
