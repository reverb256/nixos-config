#!/usr/bin/env bash
# Common GPU utilities for profile scripts
# Detects available GPUs and provides safe configuration functions
# All functions use nvidia-smi for headless compatibility

# Get list of available GPU indices
get_gpu_list() {
    nvidia-smi --query-gpu=index --format=csv,noheader,nounits 2>/dev/null || echo ""
}

# Get GPU name/model for a given index
get_gpu_name() {
    local gpu_id="$1"
    nvidia-smi -i "$gpu_id" --query-gpu=name --format=csv,noheader 2>/dev/null || echo "Unknown"
}

# Check if a GPU exists
gpu_exists() {
    local gpu_id="$1"
    nvidia-smi -i "$gpu_id" --query-gpu=name --format=csv,noheader >/dev/null 2>&1
}

# Apply power limit safely (only if GPU exists)
set_power_limit() {
    local gpu_id="$1"
    local limit="$2"

    if gpu_exists "$gpu_id"; then
        nvidia-smi -i "$gpu_id" -pl "$limit" 2>/dev/null || true
    fi
}

# Set GPU clock offset safely (using nvidia-smi, not nvidia-settings)
# Args: gpu_id, offset_type (graphics/memory), offset_value
set_clock_offset() {
    local gpu_id="$1"
    local offset_type="$2"
    local offset_value="$3"

    if ! gpu_exists "$gpu_id"; then
        return 1
    fi

    case "$offset_type" in
        graphics|gpu)
            nvidia-smi -i "$gpu_id" -lgc "$offset_value" 2>/dev/null || true
            ;;
        memory|mem)
            nvidia-smi -i "$gpu_id" -lmc "$offset_value" 2>/dev/null || true
            ;;
        *)
            echo "Warning: Unknown offset type '$offset_type' for GPU $gpu_id" >&2
            return 1
            ;;
    esac
}

# Reset GPU clocks to default
reset_clocks() {
    local gpu_id="$1"

    if gpu_exists "$gpu_id"; then
        nvidia-smi -i "$gpu_id" -rgc 2>/dev/null || true  # Reset graphics clock
        nvidia-smi -i "$gpu_id" -rmc 2>/dev/null || true  # Reset memory clock
    fi
}

# Safely execute nvidia-smi command (suppress errors)
nvidia_safe() {
    "$@" 2>/dev/null || true
}

# Count available GPUs
get_gpu_count() {
    get_gpu_list | wc -l
}

# Store original power limits for restoration
# Args: state_dir (default: /run/gpu-profiles)
store_original_power_limits() {
    local state_dir="${1:-/run/gpu-profiles}"

    # Create state directory if it doesn't exist
    mkdir -p "$state_dir"

    # SC2155: declare and assign separately to avoid masking return values.
    local gpus
    gpus=$(get_gpu_list)
    for gpu_id in $gpus; do
        local current_limit
        current_limit=$(nvidia-smi -i "$gpu_id" --query-gpu=power.limit --format=csv,noheader,nounits 2>/dev/null | tr -d '[:space:]')
        if [ -n "$current_limit" ]; then
            echo "$current_limit" > "$state_dir/gpu${gpu_id}_original_power"
        fi
    done
}

# Restore original power limits
# Args: state_dir (default: /run/gpu-profiles)
restore_original_power_limits() {
    local state_dir="${1:-/run/gpu-profiles}"

    # SC2155: declare and assign separately to avoid masking return values.
    local gpus
    gpus=$(get_gpu_list)
    for gpu_id in $gpus; do
        local stored_file="$state_dir/gpu${gpu_id}_original_power"
        if [ -f "$stored_file" ]; then
            local original_limit
            original_limit=$(cat "$stored_file")
            if [ -n "$original_limit" ]; then
                nvidia_safe nvidia-smi -i "$gpu_id" -pl "$original_limit"
            fi
        fi
    done
}
