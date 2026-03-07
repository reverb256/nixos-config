#!/usr/bin/env bash
# Capacity planning calculator for NixOS AI cluster
# Usage: ./calculate-capacity.sh <total_gpus> <ai_users> <model_vram_gb> <users_per_gpu>

set -euo pipefail

TOTAL_GPUS=${1:-8}
AI_USERS=${2:-10}
MODEL_SIZE_GB=${3:-16}
USERS_PER_GPU=${4:-2}

# Calculate VRAM requirements
TOTAL_VRAM_NEEDED=$((AI_USERS * MODEL_SIZE_GB))
VRAM_PER_GPU=$((MODEL_SIZE_GB * USERS_PER_GPU))

# Calculate GPUs needed for AI
AI_GPUS_NEEDED=$((TOTAL_VRAM_NEEDED / VRAM_PER_GPU))
if [ $((TOTAL_VRAM_NEEDED % VRAM_PER_GPU)) -ne 0 ]; then
    AI_GPUS_NEEDED=$((AI_GPUS_NEEDED + 1))
fi

# Calculate remaining GPUs for mining
MINING_GPUS=$((TOTAL_GPUS - AI_GPUS_NEEDED))

# Calculate percentages
AI_PCT=$(echo "scale=1; $AI_GPUS_NEEDED * 100 / $TOTAL_GPUS" | bc)
MINING_PCT=$(echo "scale=1; $MINING_GPUS * 100 / $TOTAL_GPUS" | bc)

# Estimate revenue (assuming $1/GPU/day for mining)
MINING_REVENUE=$((MINING_GPUS * 1))

cat <<EOF
╔═══════════════════════════════════════════════════════════════╗
║                    CAPACITY PLAN                              ║
╚═══════════════════════════════════════════════════════════════╝

INPUTS:
  Total GPUs:        $TOTAL_GPUS
  AI Users:          $AI_USERS
  Model VRAM:        ${MODEL_SIZE_GB}GB
  Users per GPU:     $USERS_PER_GPU

RESOURCE ALLOCATION:
  ┌─────────────────────────────────────────────────────────┐
  │ AI GPUs:         $AI_GPUS_NEEDED ($AI_PCT%)                      │
  │ Mining GPUs:     $MINING_GPUS ($MINING_PCT%)                   │
  └─────────────────────────────────────────────────────────┘

CAPACITY METRICS:
  Total VRAM Needed: ${TOTAL_VRAM_NEEDED}GB
  VRAM per AI GPU:   ${VRAM_PER_GPU}GB
  Users per GPU:     $USERS_PER_GPU

ESTIMATED DAILY MINING REVENUE: ~$$MINING_REVENUE

RECOMMENDATIONS:
EOF

if [ $MINING_GPUS -lt 0 ]; then
    echo "  ⚠️  WARNING: Not enough GPUs for current AI workload!"
    echo "     Need $AI_GPUS_NEEDED GPUs but only have $TOTAL_GPUS"
    echo "     Options: Add $((AI_GPUS_NEEDED - TOTAL_GPUS)) GPUs OR reduce AI users to $((TOTAL_GPUS * USERS_PER_GPU))"
elif [ $MINING_GPUS -eq 0 ]; then
    echo "  ℹ️  All GPUs allocated to AI - no mining capacity"
else
    echo "  ✓ Balanced configuration - both AI and mining can run"
    echo "  💡 Consider time-based separation for better utilization:"
    echo "     - AI during work hours (9am-6pm)"
    echo "     - Mining during off-hours (6pm-9am + weekends)"
fi

echo ""
echo "NEXT STEPS:"
echo "  1. Update host configuration with GPU allocation"
echo "  2. Configure systemd services for AI vs Mining"
echo "  3. Set up monitoring to validate capacity assumptions"
