#!/usr/bin/env bash
# llama-server startup wrapper for autoresearch
# Uses Qwen3.5-0.8B with CUDA acceleration

set -euo pipefail

MODEL_PATH="/home/j_kro/.lmstudio/models/Jackrong/Qwen3.5-0.8B-Claude-4.6-Opus-Reasoning-Distilled-GGUF/Qwen3.5-0.8B.Q8_0.gguf"

# Disable CUDA (GPU is full with mining)
# llama.cpp is built with CUDA but we'll run CPU-only
export CUDA_VISIBLE_DEVICES=""

exec llama-server \
  --model "$MODEL_PATH" \
  --host 0.0.0.0 \
  --port 8080 \
  --ctx-size 16384 \
  --threads 16 \
  --metrics
