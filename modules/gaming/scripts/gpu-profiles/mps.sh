#!/usr/bin/env bash
# MPS (Multi-Process Service) Profile for Ampere GPUs
# Enables GPU sharing for multiple small tasks (AI inference, etc.)

set -e

echo "=== Applying GPU MPS (Multi-Process Service) profile ==="

# Kill existing MPS servers if running
pkill -f nvidia-cuda-mps-control 2>/dev/null || true
sleep 1

# Start MPS for GPU 0 (3060 Ti)
echo "Starting MPS for GPU 0 (3060 Ti)..."
export CUDA_VISIBLE_DEVICES=0
export CUDA_MPS_PIPE_DIRECTORY=/tmp/nvidia-mps-gpu0
export CUDA_MPS_LOG_DIRECTORY=/tmp/nvidia-log-gpu0
mkdir -p "$CUDA_MPS_PIPE_DIRECTORY" "$CUDA_MPS_LOG_DIRECTORY"

nvidia-smi -i 0 -c EXCLUSIVE_PROCESS
nvidia-cuda-mps-control -d

# Configure client limits (4 clients, 10GB each)
echo "set per_client_memory_limit 10737418240" | nvidia-cuda-mps-control
echo "set per_client_thread_limit 25" | nvidia-cuda-mps-control

echo "MPS started for GPU 0"
echo "  Clients: 4 (25% threads each)"
echo "  Memory limit: 10GB per client"
echo ""

# Start MPS for GPU 1 (3090) - different config
echo "Starting MPS for GPU 1 (3090)..."
export CUDA_VISIBLE_DEVICES=1
export CUDA_MPS_PIPE_DIRECTORY=/tmp/nvidia-mps-gpu1
export CUDA_MPS_LOG_DIRECTORY=/tmp/nvidia-log-gpu1
mkdir -p "$CUDA_MPS_PIPE_DIRECTORY" "$CUDA_MPS_LOG_DIRECTORY"

nvidia-smi -i 1 -c EXCLUSIVE_PROCESS
nvidia-cuda-mps-control -d

# Configure client limits (2 clients, 12GB each)
echo "set per_client_memory_limit 12884901888" | nvidia-cuda-mps-control
echo "set per_client_thread_limit 50" | nvidia-cuda-mps-control

echo "MPS started for GPU 1"
echo "  Clients: 2 (50% threads each)"
echo "  Memory limit: 12GB per client"
echo ""

echo "=== MPS Profile Applied ==="
echo ""
echo "To use MPS, clients must set:"
echo "  export CUDA_MPS_PIPE_DIRECTORY=/tmp/nvidia-mps-gpu0  # for GPU 0"
echo "  export CUDA_MPS_PIPE_DIRECTORY=/tmp/nvidia-mps-gpu1  # for GPU 1"
echo ""
echo "Or update switch-profile to include MPS option"
