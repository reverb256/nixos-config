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

    # Set efficient settings based on GPU model (using nvidia-smi only)
    case "$gpu_name" in
        *"3060"*)
            # 3060 Ti: Sweet spot for efficiency
            set_power_limit "$gpu_id" 100
            set_clock_offset "$gpu_id" graphics 50
            set_clock_offset "$gpu_id" memory 500
            echo "  3060 Ti: 50 MHz GPU offset, 500 MHz mem offset, 100W limit"
            ;;
        *"3090"*)
            # 3090: Sweet spot for efficiency
            set_power_limit "$gpu_id" 250
            set_clock_offset "$gpu_id" graphics 0
            set_clock_offset "$gpu_id" memory 400
            echo "  3090: 0 MHz GPU offset, 400 MHz mem offset, 250W limit"
            ;;
        *"4060"*)
            # 4060 (Ada): 80W limit (70% of 115W TDP)
            # Ada architecture efficiency sweet spot
            set_power_limit "$gpu_id" 80
            set_clock_offset "$gpu_id" graphics 0
            set_clock_offset "$gpu_id" memory 300
            echo "  4060 (Ada): 0 MHz GPU offset, 300 MHz mem offset, 80W limit"
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
