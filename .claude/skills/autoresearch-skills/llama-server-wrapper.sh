#!/bin/bash
# llama-server startup wrapper for autoresearch
# Uses Qwen3.5-0.8B with CUDA acceleration

set -euo pipefail

MODEL_PATH="/home/j_kro/.lmstudio/models/Jackrong/Qwen3.5-0.8B-Claude-4.6-Opus-Reasoning-Distilled-GGUF/Qwen3.5-0.8B.Q8_0.gguf"
LLAMA_SERVER="/nix/store/4c3fc2icsjqgkib4ksx36wx5f47apjfs-llama-cpp-8401/bin/llama-server"

exec "$LLAMA_SERVER" \
  --model "$MODEL_PATH" \
  --host 127.0.0.1 \
  --port 8080 \
  --ctx-size 16384 \
  --n-gpu-layers 99 \
  --threads 16 \
  --metrics \
  --log-format json
