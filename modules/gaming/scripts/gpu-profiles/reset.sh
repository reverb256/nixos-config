#!/usr/bin/env bash
# Reset to Default/Auto Profile
# Clears all manual clock control
# Dynamically detects available GPUs

set -e

# Source common GPU utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_gpu-common.sh"

echo "=== Resetting GPUs to DEFAULT/AUTO profile ==="

# Get list of available GPUs
GPUS=$(get_gpu_list)
GPU_COUNT=$(get_gpu_count)

if [ "$GPU_COUNT" -eq 0 ]; then
    echo "WARNING: No NVIDIA GPUs detected"
    exit 0
fi

echo "Detected $GPU_COUNT GPU(s), resetting to defaults"

# Apply reset for each detected GPU
for gpu_id in $GPUS; do
    gpu_name=$(get_gpu_name "$gpu_id")

    echo "Resetting GPU $gpu_id ($gpu_name)..."

    # Reset to adaptive mode
    nvidia-settings -a [gpu:${gpu_id}]/GPUPowerMizerMode=0 2>/dev/null || true

    # Reset clock offsets to 0
    nvidia-settings -a [gpu:${gpu_id}]/GPUGraphicsClockOffset[3]=0 2>/dev/null || true
    nvidia-settings -a [gpu:${gpu_id}]/GPUMemoryClockOffset[3]=0 2>/dev/null || true

    # Reset power limit based on GPU model defaults
    case "$gpu_name" in
        *"3060"*)
            set_power_limit "$gpu_id" 200
            ;;
        *"3090"*)
            set_power_limit "$gpu_id" 350
            ;;
        *)
            # Try to get max power limit and use that
            max_power=$(nvidia-smi -i "$gpu_id" --query-gpu=power.max_limit --format=csv,noheader,nounits 2>/dev/null | tr -d '.' || echo "300")
            set_power_limit "$gpu_id" "${max_power%.*}"
            ;;
    esac

    echo "  GPU $gpu_id: Reset to defaults (offsets=0, adaptive mode)"
done

echo ""
echo "RESET to defaults applied:"
echo "  All clock offsets reset to 0"
echo "  Power limits reset to configured defaults"
echo "  Mode: Adaptive (auto)"
echo ""
echo "GPUs will now auto-scale based on workload."
