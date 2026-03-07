#!/usr/bin/env bash
# Calculate break-even mining revenue for your GPU setup
# Usage: ./calculate-break-even.sh <gpu_count> <power_per_gpu_watts> <electricity_rate>

set -euo pipefail

GPU_COUNT=${1:-1}
POWER_W=${2:-320}  # Default RTX 3090
RATE=${3:-0.12}   # Default $/kWh

POWER_KW=$(echo "scale=4; $POWER_W / 1000" | bc)
TOTAL_POWER_KW=$(echo "scale=4; $POWER_KW * $GPU_COUNT" | bc)

DAILY_COST=$(echo "scale=2; $TOTAL_POWER_KW * 24 * $RATE" | bc)
HOURLY_COST=$(echo "scale=4; $TOTAL_POWER_KW * $RATE" | bc)

cat <<EOF
=== Mining Break-Even Analysis ===
GPUs: $GPU_COUNT × ${POWER_W}W = ${TOTAL_POWER_KW}kW total
Electricity Rate: \$$RATE/kWh

Power Costs:
  Hourly:  \$$HOURLY_COST
  Daily:   \$$DAILY_COST
  Monthly: $(echo "scale=2; $DAILY_COST * 30" | bc)

Break-Even Revenue Needed:
  Per GPU: $(echo "scale=2; $DAILY_COST / $GPU_COUNT" | bc)/day
  Total:   \$$DAILY_COST/day

Recommendation: Only mine if daily revenue exceeds \$$DAILY_COST
EOF
