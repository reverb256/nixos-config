#!/usr/bin/env bash
# Common GPU utilities for profile scripts
# Detects available GPUs and provides safe configuration functions

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

# Apply nvidia-setting safely (only if GPU exists)
set_nvidia_setting() {
    local setting="$1"

    # Extract GPU ID from setting like [gpu:0] or [gpu:1]
    local gpu_id=$(echo "$setting" | grep -oP '\[gpu:\K[0-9]+')

    if [ -n "$gpu_id" ] && gpu_exists "$gpu_id"; then
        nvidia-settings -a "$setting" 2>/dev/null || true
    fi
}

# Count available GPUs
get_gpu_count() {
    get_gpu_list | wc -l
}
