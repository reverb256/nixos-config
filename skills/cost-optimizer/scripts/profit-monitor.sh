#!/usr/bin/env bash
# Mining profit monitoring script
# Returns exit code 0 if profitable, 1 if should pause mining
# Usage: ./profit-monitor.sh <electricity_rate> <min_profit_margin> <current_revenue_per_gpu>

set -euo pipefail

ELECTRICITY_RATE=${1:-0.12}
MIN_PROFIT=${2:-0.10}  # Minimum $/day profit to continue mining
REVENUE_PER_GPU=${3:-1.00}  # Current daily revenue per GPU

# Get GPU info
GPU_COUNT=$(nvidia-smi --query-gpu=count --format=csv,noheader 2>/dev/null || echo "1")
AVG_POWER_W=$(nvidia-smi --query-gpu=power.limit --format=csv,noheader 2>/dev/null | awk -F, '{sum+=$1} END {print sum/NR}' || echo "320")

POWER_KW=$(echo "scale=4; $AVG_POWER_W / 1000" | bc)
TOTAL_POWER_KW=$(echo "scale=4; $POWER_KW * $GPU_COUNT" | bc)

# Calculate costs
POWER_COST_PER_GPU=$(echo "scale=3; $POWER_KW * 24 * $ELECTRICITY_RATE" | bc)
TOTAL_POWER_COST=$(echo "scale=2; $TOTAL_POWER_KW * 24 * $ELECTRICITY_RATE" | bc)

# Calculate profit
TOTAL_REVENUE=$(echo "scale=2; $REVENUE_PER_GPU * $GPU_COUNT" | bc)
PROFIT=$(echo "scale=2; $TOTAL_REVENUE - $TOTAL_POWER_COST" | bc)
PROFIT_PER_GPU=$(echo "scale=2; $PROFIT / $GPU_COUNT" | bc)

# Log status
logger -t mining-profit "GPUs: $GPU_COUNT, Revenue: \$$TOTAL_REVENUE/day, Power: \$$TOTAL_POWER_COST/day, Profit: \$$PROFIT/day"

# Check profitability
if (( $(echo "$PROFIT_PER_GPU >= $MIN_PROFIT" | bc -l) )); then
    echo "✓ Profitable: \$$PROFIT/day (\$$PROFIT_PER_GPU per GPU)"
    exit 0
else
    echo "✗ Unprofitable: \$$PROFIT/day (\$$PROFIT_PER_GPU per GPU < \$$MIN_PROFIT minimum)"
    exit 1
fi
