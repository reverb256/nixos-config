#!/usr/bin/env bash
set -euo pipefail

MODEL="/home/j_kro/.lmstudio/models/unsloth/Qwen3.6-35B-A3B-GGUF/Qwen3.6-35B-A3B-UD-IQ3_S.gguf"
PORT=1237
EXPECTED_GPU="NVIDIA GeForce RTX 3090"
EXPECTED_VRAM_MB=24000

device_id="${1:-CUDA0}"

resolve_device_index() {
    llama-server --list-devices 2>&1 | grep -oP "^  $device_id: \K.*" > /dev/null
    llama-server --list-devices 2>&1 | awk -v dev="$device_id" '$0 ~ "^  "dev": " {print $0}'
}

device_line=$(resolve_device_index)
if [[ -z "$device_line" ]]; then
    echo "ABORT: device $device_id not found in llama-server --list-devices" >&2
    exit 1
fi

gpu_name=$(echo "$device_line" | grep -oP '(?<=:\s).+?(?=,)' | xargs)
gpu_vram=$(echo "$device_line" | grep -oP '[0-9]+ (?=MiB)' | head -1)

if [[ "$gpu_name" != "$EXPECTED_GPU" ]]; then
    echo "ABORT: $device_id is '$gpu_name', expected '$EXPECTED_GPU'" >&2
    echo "Full line: $device_line" >&2
    exit 1
fi

if [[ -n "$gpu_vram" && "$gpu_vram" -lt "$EXPECTED_VRAM_MB" ]]; then
    echo "ABORT: $device_id VRAM is ${gpu_vram}MiB, expected >= ${EXPECTED_VRAM_MB}MiB" >&2
    exit 1
fi

echo "VERIFIED: $device_id = $gpu_name (${gpu_vram}MiB)"
echo "Starting llama-server on port $PORT..."

exec llama-server \
    -dev "$device_id" \
    --model "$MODEL" \
    --host 0.0.0.0 \
    --port "$PORT" \
    -ngl 99 \
    --ctx-size 32768 \
    --cache-type-k q4_0 \
    --cache-type-v q4_0 \
    --parallel 1 \
    --cont-batching \
    --alias qwen3.6-35b-a3b
