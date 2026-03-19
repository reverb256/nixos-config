# GPU Resource Marketplace - Compute Scheduler

**Author**: Reverb256 Cluster
**Last Updated**: 2026-03-19
**Version**: 2.1.0 (Gaming Detection Fix)

---

## Overview

The GPU Resource Marketplace is a sophisticated auction engine that coordinates GPU allocation between competing workloads across your cluster:

- **Mining** ($0.10/hr baseline) - Passive income when GPUs are idle
- **Kubernetes** ($0-5/hr) - AI/ML workloads, inference, training
- **Akash Network** ($0.05-0.07/hr) - Decentralized compute marketplace
- **Gaming** ($999.99/hr override) - Priority override for actual games

### Key Features

✅ **Dynamic Pricing** - Time-based (±10-20%), demand-based (±15%), workload-specific multipliers (+10-30%)
✅ **GPU Memory Tracking** - Real-time nvidia-smi monitoring for intelligent bidding
✅ **Market Intelligence** - Queries Akash API every 5 minutes for competitive pricing
✅ **Gaming Detection** - Whitelist-based approach to avoid false positives
✅ **Prometheus Metrics** - Comprehensive monitoring at `:9200/metrics`

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    GPU AUCTION ENGINE                        │
│                  (runs every 30 seconds)                     │
└─────────────────────────────────────────────────────────────┘
                              │
                ┌─────────────┼─────────────┐
                │             │             │
        ┌───────▼──────┐ ┌───▼────┐ ┌────▼─────┐
        │   Mining     │ │K8s/Akash│ │  Gaming  │
        │  Bidder      │ │ Bidders  │ │ Detector │
        └──────────────┘ └─────────┘ └──────────┘
                │             │             │
                └─────────────┼─────────────┘
                              │
                    ┌─────────▼─────────┐
                    │   Auction Logic   │
                    │  (highest bid)    │
                    └─────────┬─────────┘
                              │
                    ┌─────────▼─────────┐
                    │  GPU Profile      │
                    │  Application      │
                    └───────────────────┘
```

---

## Configuration

### Basic Setup

Enable in `/etc/nixos/hosts/<hostname>/configuration.nix`:

```nix
services.compute-market = {
  enable = true;
  prometheusPort = 9200;
  auctionInterval = 30;  # seconds
};
```

### Gaming Detection (GameMode Integration)

**IMPORTANT**: Gaming detection now uses **GameMode signals** for reliable detection.

**How it works**:
```
1. Game starts → GameMode activates
2. Compute-market queries gamemoded -s
3. Gaming override activated (mining paused)
4. Game ends → GameMode deactivates
5. Compute-market detects deactivation
6. Mining resumed
```

**Why GameMode is superior**:
- ✅ **Authoritative**: GameMode is THE source of truth for gaming state
- ✅ **No false positives**: Only activates when actual games are running
- ✅ **Already integrated**: Works with Steam, Lutris, Heroic, etc.
- ✅ **Simple**: `gamemoded -s` returns 0 if gaming, 1 if not

#### Enable GameMode

GameMode is already configured in your gaming module. Verify it's enabled:

```nix
# /etc/nixos/hosts/<hostname>/configuration.nix
{
  programs.gamemode.enable = true;

  # GameMode hooks for compute-market integration
  programs.gamemode.settings = {
    custom = {
      start = "${pkgs.writeShellScript "gamemode-start" ''
        # GameMode activated - compute-market will automatically detect this
        ${pkgs.libnotify}/bin/notify-send 'GameMode activated' 'Compute market will pause mining'
      ''}";
      end = "${pkgs.writeShellScript "gamemode-end" ''
        # GameMode deactivated - compute-market will automatically resume mining
        ${pkgs.libnotify}/bin/notify-send 'GameMode deactivated' 'Compute market will resume mining'
      ''}";
    };
  };
}
```

#### How Compute-Market Uses GameMode

The compute-market auction engine queries GameMode status:

```bash
check_gaming() {
    # Use GameMode signal if available
    if command -v gamemoded >/dev/null 2>&1; then
        if gamemoded -s >/dev/null 2>&1; then
            echo "true"  # Gaming active
            return
        fi
        echo "false"  # Not gaming
        return
    fi

    # Fallback: Use whitelist if GameMode not available
    # ... (whitelist logic)
}
```

#### Verify GameMode Integration

```bash
# Check if GameMode is running
systemctl status gamemoded

# Query GameMode status (0 = gaming, 1 = not gaming)
gamemoded -s
echo $?  # Exit code: 0 = gaming, 1 = not gaming

# Test gaming detection
curl -s http://localhost:9200/metrics | grep gaming_active
# Should show: compute_market_gaming_active 0  # (when not gaming)
```

#### Fallback: Whitelist Configuration

If GameMode is not available, compute-market falls back to whitelist detection:

**Option 1: Via NixOS Configuration**

**Option 1: Via NixOS Configuration**

```nix
# /etc/nixos/hosts/zephyr/configuration.nix
systemd.services.compute-market.environment = {
  GAMING_ENABLE = "true";
  GAMING_GAMES = "Cyberpunk2077.exe eldenring.exe Dota2.exe";
};
```

**Option 2: Via Environment Variable**

```bash
# Temporary (until reboot)
sudo systemctl edit compute-market
# Add:
[Service]
Environment="GAMING_GAMES=Game1.exe Game2.exe"

# Reload
sudo systemctl daemon-reload
sudo systemctl restart compute-market
```

**Option 3: Wildcard Patterns**

```bash
# Match all Steam games (Steam app IDs)
GAMING_GAMES="steam_app_*.exe"

# Match all games from a specific publisher
GAMING_GAMES="ParadoxInteractive.*"

# ⚠️ NOT RECOMMENDED: Match ALL executables
GAMING_GAMES=".*\\.exe"
```

#### How Gaming Detection Works

1. **Check if enabled**: `GAMING_ENABLE=true` (default: true)
2. **Check if whitelist configured**: `GAMING_GAMES` must be non-empty
3. **Check for specific processes**: Uses `pgrep -x` for exact name matching
4. **Only actual games**: Launchers, helpers, and wrappers are ignored

**Example Process Flow**:

```
❌ steam-web-helper      → NOT matched (not in whitelist)
❌ steam-overlay         → NOT matched (not in whitelist)
✅ Cyberpunk2077.exe     → MATCHED (in whitelist)
→ Gaming override activated
→ Mining paused
→ Akash bidding paused
→ GPU profile applied
```

### Mining Configuration

```nix
systemd.services.compute-market.environment = {
  MINING_ENABLE = "true";           # Enable/disable mining bidder
  MINING_HOURLY = "0.10";           # $0.10/hr baseline bid
  MINING_DEVICE = "cuda:0";         # GPU device for mining
};
```

### Kubernetes Configuration

```nix
systemd.services.compute-market.environment = {
  K8S_ENABLE = "true";              # Enable Kubernetes bidder
  K8S_HOURLY_MAX = "5.00";          # Maximum bid: $5/hr
  K8S_NAMESPACE = "llm-workloads";  # Monitor GPU usage in namespace
};
```

### Akash Network Configuration

```nix
systemd.services.compute-market.environment = {
  AKASH_ENABLE = "true";            # Enable Akash bidder
  AKASH_MARGIN = "0.90";            # Bid at 90% of market rate (10% discount)
  AKASH_NAMESPACE = "akash-services"; # Monitor active leases
};
```

---

## Dynamic Pricing Strategy

The compute scheduler uses **multi-factor dynamic pricing** to maximize revenue:

### 1. Time-Based Multiplier (±10-20%)

```bash
get_time_multiplier() {
    hour=$(date +%H)

    if [ $hour -ge 0 ] && [ $hour -lt 6 ]; then
        multiplier=0.9  # Night: 10% discount (low demand)
    elif [ $hour -ge 6 ] && [ $hour -lt 12 ]; then
        multiplier=1.0  # Morning: standard rate
    elif [ $hour -ge 12 ] && [ $hour -lt 18 ]; then
        multiplier=1.2  # Afternoon: 20% premium (high demand)
    else
        multiplier=1.1  # Evening: 10% premium
    fi

    echo $multiplier
}
```

**Impact**:
- Night (12am-6am): Bids 10% lower to attract off-peak workloads
- Afternoon (12pm-6pm): Bids 20% higher during peak demand
- Evening (6pm-12am): Moderate 10% premium

### 2. Demand-Based Multiplier (±15%)

```bash
get_demand_multiplier() {
    gpu_util=$1  # Current GPU utilization (0.0-1.0)

    if [ $(echo "$gpu_util > 0.8" | bc) -eq 1 ]; then
        multiplier=1.15  # >80% utilized: 15% premium (scarcity)
    elif [ $(echo "$gpu_util < 0.3" | bc) -eq 1 ]; then
        multiplier=0.85  # <30% utilized: 15% discount (excess capacity)
    else
        multiplier=1.0   # Normal utilization
    fi

    echo $multiplier
}
```

**Impact**:
- GPUs mostly idle (<30%): Discount 15% to attract workloads
- GPUs fully utilized (>80%): Premium 15% to maximize revenue
- Balanced utilization: Standard rates

### 3. Workload-Specific Multiplier (+10-30%)

```bash
get_workload_multiplier() {
    workload=$1

    case "$workload" in
        "ai/inference")     multiplier=1.3 ;;  # LLM inference: 30% premium
        "video/transcoding") multiplier=1.25 ;; # Video processing: 25% premium
        "rendering/gpu")     multiplier=1.2 ;;  # 3D rendering: 20% premium
        *)                   multiplier=1.0 ;;  # Default: no multiplier
    esac

    echo $multiplier
}
```

**Impact**:
- AI/LLM inference: +30% (high demand, specialized)
- Video transcoding: +25% (resource-intensive)
- GPU rendering: +20% (compute-heavy)
- Default workloads: Standard rate

### Combined Pricing Formula

```
final_bid = base_bid × time_mult × demand_mult × workload_mult × profit_margin

Example: Akash bid at 3pm on 90% utilized GPU for LLM inference
final_bid = 0.05 × 1.2 × 1.15 × 1.3 × 0.90 = $0.096/hr
```

---

## GPU Memory Tracking

The scheduler tracks **GPU memory utilization** for intelligent bidding:

```bash
gpu_memory_available() {
    if command -v nvidia-smi >/dev/null 2>&1; then
        nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits | \
            awk '{s+=$1} END {print s}'
    else
        echo "24000"  # Fallback: 24GB total
    fi
}

gpu_utilization() {
    mem_free=$(gpu_memory_available)
    mem_total=$(gpu_memory_total)

    if [ "$mem_total" -gt 0 ]; then
        echo "scale=4; ($mem_total - $mem_free) / $mem_total" | bc
    else
        echo "0.5"  # Fallback: 50% utilization
    fi
}
```

**Usage**:
- Bids more aggressively when GPU memory is free
- Reduces bids when GPU memory is constrained
- Provides `compute_market_gpu_memory_free` metric

---

## Market Intelligence Module

The **market intelligence service** queries the Akash Network API every 5 minutes for competitive pricing:

```bash
analyze_market() {
    # Fetch active leases from Akash API
    api_url="https://api.akash.network/api/v1/leases"
    market_data=$(curl -s --max-time 10 "$api_url")

    # Extract GPU lease prices and calculate percentiles
    prices=$(echo "$market_data" | \
        jq -r '.[] | select(.resources.gpu > 0) | .price')

    # Calculate P25, P50, P75 percentiles
    count=$(echo "$prices" | wc -l)
    p25=$(echo "$prices" | sort -n | awk "NR==$count/4")
    p50=$(echo "$prices" | sort -n | awk "NR==$count/2")
    p75=$(echo "$prices" | sort -n | awk "NR==3*$count/4")

    # Store for bidding decisions
    echo "$p50" > "$STATE_DIR/market_p50"

    # Convert to USD (1 AKT = $0.50, 600 blocks/hr)
    p50_usd=$(echo "scale=4; $p50 * 0.50 * 600 / 1000000" | bc)

    echo "$p50_usd"
}
```

**Usage**:
- Stores P50 market rate in `/run/compute-market/market_p50`
- Scheduler uses this to calculate competitive Akash bids
- Logs market analysis every 5 minutes

---

## Prometheus Metrics

Monitor at `http://localhost:9200/metrics`:

### Auction Metrics

```
compute_market_auction_count                    # Total auctions run
compute_market_auction_winner{winner="..."}     # Current auction winner
compute_market_last_auction_timestamp           # Unix timestamp of last auction
```

### Bidder Metrics

```
compute_market_bid_mining{status="..."}         # Mining bid (USD/hr)
compute_market_bid_kubernetes{status="..."}     # Kubernetes bid (USD/hr)
compute_market_bid_akash{status="..."}          # Akash bid (USD/hr)
compute_market_bid_gaming{status="..."}         # Gaming bid (always 999.99)
```

### Gaming Detection

```
compute_market_gaming_active                    # Is gaming detected? (0/1)
compute_market_gaming_override_count            # Total gaming overrides
```

### GPU Metrics

```
compute_market_gpu_utilization                  # Current GPU utilization (0.0-1.0)
compute_market_gpu_memory_free                  # Free GPU memory (MB)
compute_market_gpu_memory_used                  # Used GPU memory (MB)
```

### Market Intelligence

```
compute_market_akash_market_p50                 # P50 market rate (USD/hr)
compute_market_akash_market_p75                 # P75 market rate (USD/hr)
compute_market_akash_market_updated             # Last market update timestamp
```

---

## Troubleshooting

### Gaming Detection False Positives (FIXED with GameMode)

**Problem**: Gaming override activates when no games are running

**Old Root Cause**: Broad pattern matching matched non-game processes
```bash
# Old (PROBLEMATIC)
GAMING_PROCESSES="steam lutris heroic wine proton"
# ❌ Matched: steam-web-helper, wine-preloader, anime-game-launcher, etc.
```

**Solution**: Use GameMode signals (authoritative gaming state)
```bash
# New (RELIABLE)
gamemoded -s >/dev/null 2>&1
# ✅ Only returns true when actual games are running
```

**Why GameMode is better**:
- No false positives from launcher processes
- Works with ALL game launchers (Steam, Lutris, Heroic, native)
- Simple query: `gamemoded -s` returns 0 if gaming
- Already integrated with your gaming setup

**Verification**:
```bash
# Check GameMode status
gamemoted -s
echo $?  # 0 = gaming, 1 = not gaming

# Check compute-market gaming detection
curl -s http://localhost:9200/metrics | grep gaming_active
# Output: compute_market_gaming_active 0  # Good! (when not gaming)

# Check current auction winner
curl -s http://localhost:9200/metrics | grep auction_winner
# Output: compute_market_auction_winner{winner="mining"} 1  # Good!
```

### Mining Not Starting

**Check 1**: Verify mining is enabled
```bash
systemctl status compute-market
# Look for: MINING_ENABLE=true
```

**Check 2**: Verify mining device
```bash
nvidia-smi -L
# Ensure GPU device matches MINING_DEVICE
```

**Check 3**: Check logs
```bash
journalctl -u compute-market -f
# Look for: "Mining bidder: $0.10/hr"
```

### Akash Bids Too Low/High

**Check market intelligence**:
```bash
cat /run/compute-market/market_p50
# Output: Current P50 market rate
```

**Adjust profit margin**:
```nix
systemd.services.compute-market.environment = {
  AKASH_MARGIN = "0.90";  # Bid at 90% of market (10% discount)
  # Increase to 1.0 for full market rate
  # Decrease to 0.80 for more competitive (20% discount)
};
```

### GPU Utilization Incorrect

**Check nvidia-smi**:
```bash
nvidia-smi --query-gpu=memory.free,memory.total --format=csv,noheader,nounits
# Should see: free memory, total memory
```

**Check metrics**:
```bash
curl -s http://localhost:9200/metrics | grep gpu_utilization
# Output: compute_market_gpu_utilization 0.15  # 15% utilized
```

---

## Performance Tuning

### Auction Frequency

**Default**: 30 seconds
**Faster** (10s): More responsive, higher CPU usage
**Slower** (60s): Less CPU, slower response to workload changes

```nix
services.compute-market.auctionInterval = 10;  # Faster
```

### Prometheus Port

**Default**: 9200
**Change if conflicting**:

```nix
services.compute-market.prometheusPort = 9100;  # Different port
```

---

## Security Considerations

### Gaming Whitelist

**⚠️ IMPORTANT**: Only add games you actually play.

```bash
# ❌ BAD: Match all executables
GAMING_GAMES=".*\\.exe"

# ✅ GOOD: Specific games
GAMING_GAMES="Cyberpunk2077.exe eldenring.exe"
```

**Why?**: Gaming override pauses ALL GPU workloads (mining, Akash, Kubernetes). False positives = lost revenue.

### Mining Credentials

**⚠️ CRITICAL**: Never commit mining wallet keys to git.

Use agenix for secrets:
```bash
agenix -e mining-secrets.nix
# Add: MINING_WALLET_ADDRESS="0x..."
```

---

## Future Enhancements

### Planned Features

- [ ] ML-based demand prediction (LSTM forecasting)
- [ ] Job queue with priority classes
- [ ] Custom Kubernetes scheduler for GPU workloads
- [ ] Advanced revenue tracking dashboard
- [ ] Integration with cluster-wide load balancer

### Contributing

To add new bidders (e.g., Folding@home, BOINC):

1. Implement `bid_<workload>()` function
2. Add to auction engine in `run_auction()`
3. Add Prometheus metrics
4. Update documentation

---

## Appendix: Configuration Reference

### Full Configuration Example

```nix
# /etc/nixos/hosts/zephyr/configuration.nix
{
  services.compute-market = {
    enable = true;
    prometheusPort = 9200;
    auctionInterval = 30;
    stateDirectory = "/run/compute-market";
    logFile = "/var/log/compute-market.log";
  };

  systemd.services.compute-market.environment = {
    # Gaming detection (whitelist approach)
    GAMING_ENABLE = "true";
    GAMING_GAMES = "Cyberpunk2077.exe eldenring.exe";

    # Mining configuration
    MINING_ENABLE = "true";
    MINING_HOURLY = "0.10";
    MINING_DEVICE = "cuda:0";

    # Kubernetes configuration
    K8S_ENABLE = "true";
    K8S_HOURLY_MAX = "5.00";
    K8S_NAMESPACE = "llm-workloads";

    # Akash Network configuration
    AKASH_ENABLE = "true";
    AKASH_MARGIN = "0.90";
    AKASH_NAMESPACE = "akash-services";
  };
}
```

---

**Version History**:
- v2.1.0 (2026-03-19): Fixed gaming detection with whitelist approach
- v2.0.0 (2026-03-18): Added dynamic pricing, GPU memory tracking, market intelligence
- v1.0.0 (2026-03-17): Initial release with basic auction engine
