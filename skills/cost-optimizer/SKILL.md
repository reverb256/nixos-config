---
name: cost-optimizer
description: Mining profitability optimization for NixOS clusters. Track mining revenue vs. power costs, calculate break-even thresholds, and recommend auto-shutdown settings. Use this skill whenever the user mentions mining profitability, power costs, electricity rates, mining shutdown, ROI, or wants to optimize mining operations on their NixOS cluster.
---

# Mining Cost Optimizer

This skill helps you optimize mining operations on your NixOS cluster by tracking profitability against power costs and recommending when to pause mining.

## When to Use This Skill

Use this skill when:
- User asks about mining profitability or ROI
- User wants to set up automatic mining shutdown based on profitability
- User mentions electricity costs, power rates, or energy pricing
- User asks about break-even analysis for mining
- User wants to monitor mining revenue vs. costs
- User mentions "unprofitable mining" or "when to stop mining"

## Key Concepts

### Profitability Formula
```
Profit per day = (Mining Revenue per day) - (Power Cost per day)
Power Cost per day = (GPU Power in kW × Hours × Electricity Rate)
Break-even Revenue = Power Cost per day
```

### Typical Power Consumption (per GPU)
| GPU | Power (W) | kW |
|-----|-----------|-----|
| RTX 3090 | 320W | 0.32 kW |
| RTX 4090 | 420W | 0.42 kW |
| A6000 | 300W | 0.30 kW |
| H100 PCIe | 700W | 0.70 kW |

### Typical Mining Revenue (varies by market)
- Ethereum Classic (ETC): ~$0.50-$2.00 per GPU per day
- Ravencoin (RVV): ~$0.30-$1.00 per GPU per day
- Alephium (ALPH): ~$0.50-$1.50 per GPU per day

## Workflow

### Step 1: Gather Cluster Information

First, understand the user's setup:

```bash
# Check active mining services
systemctl list-units | grep -E "(xmrig|lolminer|miner)"

# Check GPU configuration
nvidia-smi --query-gpu=name,power.limit --format=csv,noheader

# Check current host
hostname
```

Ask the user for:
1. **Electricity rate** in $/kWh (typical: $0.10-$0.30 residential, $0.05-$0.15 commercial)
2. **Number of GPUs** and their models
3. **Mining coin(s)** being mined
4. **Current daily revenue** per GPU (if known, or help estimate)

### Step 2: Calculate Break-Even

For each host/GPU configuration:

```python
# Example calculation
gpu_power_kw = 0.32  # RTX 3090
hours_per_day = 24
electricity_rate = 0.12  # $/kWh
power_cost_per_day = gpu_power_kw * hours_per_day * electricity_rate
# = 0.32 * 24 * 0.12 = $0.92 per day

# So mining revenue needs to exceed $0.92/day to be profitable
```

### Step 3: Create Monitoring Script

Create a profit checker script at `/etc/nixos/scripts/check-mining-profit.sh`:

```bash
#!/usr/bin/env bash
# Mining profitability checker
# Returns 0 if profitable, 1 if unprofitable

ELECTRICITY_RATE=${1:-0.12}  # $/kWh
MIN_PROFIT_MARGIN=${2:-0.10}  # $/day minimum profit

# Get GPU count and power
GPU_COUNT=$(nvidia-smi --query-gpu=count --format=csv,noheader)
AVG_POWER_W=$(nvidia-smi --query-gpu=power.limit --format=csv,noheader | awk -F, '{sum+=$1} END {print sum/NR}')
POWER_KW=$(echo "scale=3; $AVG_POWER_W / 1000" | bc)

# Calculate daily power cost
POWER_COST=$(echo "scale=2; $POWER_KW * 24 * $ELECTRICITY_RATE" | bc)

# Get current mining revenue (this would be fetched from mining pool API)
# For now, use a conservative estimate or user-provided value
MINING_REVENUE=${3:-1.00}  # $/day

# Calculate profit
PROFIT=$(echo "scale=2; $MINING_REVENUE - $POWER_COST" | bc)

# Check if profitable
if (( $(echo "$PROFIT >= $MIN_PROFIT_MARGIN" | bc -l) )); then
    echo "Profitable: $PROFIT/day (revenue: $MINING_REVENUE, power: $POWER_COST)"
    exit 0
else
    echo "Unprofitable: $PROFIT/day (revenue: $MINING_REVENUE, power: $POWER_COST)"
    exit 1
fi
```

### Step 4: Configure Auto-Shutdown

Create a systemd timer or service that checks profitability and pauses mining:

**Option A: Using systemd timer**

```nix
# In host configuration.nix or a module
systemd.timers."mining-profit-check" = {
  description = "Check mining profitability hourly";
  wantedBy = [ "timers.target" ];
  timerConfig = {
    OnCalendar = "hourly";
    Unit = "mining-profit-check.service";
  };
};

systemd.services."mining-profit-check" = {
  description = "Check mining profitability and pause if unprofitable";
  serviceConfig = {
    Type = "oneshot";
    ExecStart = "/etc/nixos/scripts/check-mining-profit.sh 0.12 0.10";
    # If script returns 1 (unprofitable), stop mining
  };
};
```

**Option B: Using existing nixos-rebuild-safe pattern**

Leverage the existing `nixos-rebuild-safe.sh` pattern - pause mining before expensive operations:

```bash
# In your profitability script, if unprofitable:
if ! /etc/nixos/scripts/check-mining-profit.sh; then
    systemctl stop xmrig@*
    systemctl stop lolminer-*
    echo "Mining paused due to unprofitability" | logger -t mining-profit
fi
```

### Step 5: Set Up Alerting

Create a simple alert mechanism:

```bash
# Add to profit checker
if (( $(echo "$PROFIT < 0" | bc -l) )); then
    # Send alert (could use webhook, email, etc.)
    echo "WARNING: Mining is losing money! Daily loss: $$PROFIT" | \
        logger -t mining-profit -p err
fi
```

## Host-Specific Configuration

For your cluster:

| Host | GPUs | Typical Power | Notes |
|------|------|---------------|-------|
| zephyr | Multi-GPU | ~1.5 kW total | Primary workstation |
| nexus | Multi-GPU | ~1.5 kW total | Gaming + mining |
| forge | Multi-GPU | ~2.0 kW total | Mining-focused |
| sentry | AMD GPU | ~0.3 kW | Smaller setup |

## Quick Reference Commands

```bash
# Check current mining status
systemctl status xmrig@* lolminer-*

# Check power consumption
nvidia-smi --query-gpu=name,power.draw,power.limit --format=csv

# Calculate power cost for your rate
echo "0.32 * 24 * 0.12" | bc  # RTX 3090 at $0.12/kWh

# View mining logs
journalctl -u xmrig@* -u lolminer-* --since "1 hour ago"
```

## Common Questions

**Q: What's a good electricity rate assumption?**
A: Residential: $0.12-$0.25/kWh. Commercial/industrial: $0.05-$0.15/kWh. Check your bill!

**Q: Should I include cooling costs?**
A: Yes, typically add 20-30% for cooling in warm climates or dense setups.

**Q: What profit margin should I target?**
A: At minimum $0.10-$0.25/GPU/day to account for wear and variability.

**Q: How often should I check?**
A: Hourly is sufficient - mining rewards don't change that fast.

## Creating Custom Scripts

The `scripts/` directory contains helper scripts:
- `calculate-break-even.sh` - Calculate break-even revenue for your setup
- `setup-profit-monitor.sh` - Set up monitoring systemd service
- `mining-dashboard.sh` - Show current profitability status
