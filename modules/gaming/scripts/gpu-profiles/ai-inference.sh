#!/usr/bin/env bash
# AI Inference Profile - Balanced Performance
# Priority: Consistency > latency > throughput

set -e

echo "=== Applying GPU AI INFERENCE profile ==="

# Adaptive mode for consistent performance
nvidia-settings -a [gpu:0]/GPUPowerMizerMode=0
nvidia-settings -a [gpu:1]/GPUPowerMizerMode=0

# Moderate power limits (sweet spot for perf/watt)
nvidia-smi -i 0 -pl 110  # 3060 Ti (55%)
nvidia-smi -i 1 -pl 280  # 3090 (80%)

# Moderate clocks - stable and efficient
nvidia-settings -a [gpu:0]/GPUGraphicsClockOffset[3]=100
nvidia-settings -a [gpu:0]/GPUMemoryClockOffset[3]=400

nvidia-settings -a [gpu:1]/GPUGraphicsClockOffset[3]=80
nvidia-settings -a [gpu:1]/GPUMemoryClockOffset[3]=500

echo "AI INFERENCE profile applied:"
echo "  GPU 0 (3060 Ti):  100 MHz GPU offset, 400 MHz mem offset, 110W limit"
echo "  GPU 1 (3090):     80 MHz GPU offset, 500 MHz mem offset, 280W limit"
echo "  Mode: Adaptive (consistent performance)"
echo ""
echo "This profile optimizes for:"
echo "  - Consistent inference latency"
echo "  - Power efficiency"
echo "  - Thermal headroom for sustained workloads"
