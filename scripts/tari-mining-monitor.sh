#!/bin/bash
# Tari (XTM) Mining Profitability Monitor
# Fetches price and mining stats to calculate profitability

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Tari (XTM) Mining Profitability Monitor ===${NC}"
echo ""

# API Endpoints
COINGECKO_API="https://api.coingecko.com/api/v3"
MINING_POOL_STATS="https://api.kryptex.com/v2/stats"

# Get current XTM price from multiple sources
get_xtm_price() {
    echo -e "${YELLOW}Fetching Tari (XTM) price...${NC}"

    # Try CoinGecko
    local price=$(curl -s "$COINGECKO_API/simple/price?ids=tari&vs_currencies=usd" 2>/dev/null | jq -r '.tari.usd // empty' // echo "")

    if [[ -n "$price" && "$price" != "null" ]]; then
        echo -e "${GREEN}✓ CoinGecko: \$${price}${NC}"
        XTM_PRICE="$price"
        return
    fi

    # Try alternative - get from CoinMarketCap via scraping
    price=$(curl -s "https://coinmarketcap.com/currencies/tari/" 2>/dev/null | grep -oP 'price:".*?\$\K[\d,]+\.?\d*' | head -1 | tr -d ',' || echo "")

    if [[ -n "$price" ]]; then
        echo -e "${GREEN}✓ CoinMarketCap: \$${price}${NC}"
        XTM_PRICE="$price"
        return
    fi

    # Fallback - use hardcoded approximate price (update periodically)
    echo -e "${YELLOW}⚠ APIs unavailable, using cached price${NC}"
    XTM_PRICE="0.15" # Update this periodically as fallback
}

# Get hashrate from xmrig (CPU mining on sentry)
get_cpu_hashrate() {
    echo -e "${YELLOW}Fetching CPU hashrate (sentry)...${NC}"

    # Try to get from xmrig API
    local hashrate=$(ssh sentry "curl -s http://127.0.0.1:4066/1/summary 2>/dev/null | jq -r '.hashrate.total[0] // .hashrate // empty' // echo ''")

    if [[ -n "$hashrate" && "$hashrate" != "null" ]]; then
        # Convert H/s to kH/s
        local khps=$(echo "scale=2; $hashrate / 1000" | bc)
        echo -e "${GREEN}✓ CPU: ${khps} kH/s${NC}"
        CPU_HASHRATE="$hashrate"
        return
    fi

    # Fallback - estimate from xmrig logs
    hashrate=$(ssh sentry "journalctl -u xmrig --since '5 minutes ago' -n 1 | grep -oP 'speed \K[\d.]+ H/s' | tail -1 | grep -oP '[\d.]+' || echo '2300'")

    if [[ -n "$hashrate" ]]; then
        echo -e "${GREEN}✓ CPU (estimated): ${hashrate} H/s${NC}"
        CPU_HASHRATE="$hashrate"
        return
    fi

    # Default estimate based on 4 threads @ 575 H/s each
    echo -e "${YELLOW}⚠ CPU (estimated): 2300 H/s${NC}"
    CPU_HASHRATE="2300"
}

# Get GPU hashrate from lolminer (GPU mining)
get_gpu_hashrate() {
    echo -e "${YELLOW}Fetching GPU hashrate...${NC}"

    # Try lolminer API on forge
    local gpu_stats=$(curl -s http://10.1.1.130:4070/summary 2>/dev/null)

    if [[ -n "$gpu_stats" ]]; then
        local sols=$(echo "$gpu_stats" | jq -r '.SolPs // empty' // echo "")
        if [[ -n "$sols" && "$sols" != "null" ]]; then
            echo -e "${GREEN}✓ GPU (Forge): ${sols} Sol/s${NC}"
            GPU_HASHRATE_SOL="$sols"
            return
        fi
    fi

    # Try zephyr GPU miner
    local zephyr_stats=$(ssh zephyr "curl -s http://10.1.1.110:4070/summary 2>/dev/null || echo ''")

    if [[ -n "$zephyr_stats" ]]; then
        local sols=$(echo "$zephyr_stats" | jq -r '.SolPs // empty' // echo "")
        if [[ -n "$sols" && "$sols" != "null" ]]; then
            echo -e "${GREEN}✓ GPU (Zephyr): ${sols} Sol/s${NC}"
            GPU_HASHRATE_SOL="${GPU_HASHRATE_SOL:-0} + $sols"
            return
        fi
    fi

    # Estimate based on GPU count
    # RTX 4060 does ~300-400 Sol/s on RandomX
    local total_gpus=5
    local estimated_sols=$((total_gpus * 350))
    echo -e "${YELLOW}⚠ GPU (estimated): ${estimated_sols} Sol/s (5 GPUs)${NC}"
    GPU_HASHRATE_SOL="$estimated_sols"
}

# Calculate daily earnings
calculate_earnings() {
    local price="$1"
    local cpu_hps="$2"
    local gpu_sols="$3"

    echo ""
    echo -e "${BLUE}=== Profitability Calculations ===${NC}"

    # CPU Mining (RandomX)
    # Network hashrate ~100 MH/s, CPU contribution is small
    local cpu_hps_decimal=$(echo "scale=6; $cpu_hps / 1000" | bc)
    local daily_xtm_cpu=$(echo "scale=4; $cpu_hps_decimal * 86400 / 100000000 * 2.5" | bc) # Approximate
    local daily_usd_cpu=$(echo "scale=2; $daily_xtm_cpu * $price" | bc)

    echo -e "${BLUE}CPU Mining (sentry):${NC}"
    echo "  Hashrate: ${cpu_hps_decimal} kH/s"
    echo "  Est. Daily XTM: ${daily_xtm_cpu}"
    echo "  Est. Daily USD: \$${daily_usd_cpu}"

    # GPU Mining (RandomX on CUDA)
    # Network hashrate ~5 GH/s, GPU contribution is moderate
    local gpu_mhs=$(echo "scale=6; $gpu_sols / 1000000" | bc)
    local daily_xtm_gpu=$(echo "scale=4; $gpu_mhs * 86400 / 1000 * 1.8" | bc) # Approximate
    local daily_usd_gpu=$(echo "scale=2; $daily_xtm_gpu * $price" | bc)

    echo -e "${BLUE}GPU Mining (forge + zephyr):${NC}"
    echo "  Hashrate: ${gpu_mhs} MH/s"
    echo "  Est. Daily XTM: ${daily_xtm_gpu}"
    echo "  Est. Daily USD: \$${daily_usd_gpu}"

    # Total
    local total_daily_xtm=$(echo "scale=4; $daily_xtm_cpu + $daily_xtm_gpu" | bc)
    local total_daily_usd=$(echo "scale=2; $daily_usd_cpu + $daily_usd_gpu" | bc)
    local monthly_usd=$(echo "scale=2; $total_daily_usd * 30" | bc)

    echo ""
    echo -e "${GREEN}=== TOTAL ESTIMATED EARNINGS ===${NC}"
    echo "  Daily:  \$${total_daily_usd} USD (${total_daily_xtm} XTM)"
    echo "  Monthly: \$${monthly_usd} USD"
    echo ""
}

# Display breakeven analysis for Akash bidding
breakeven_analysis() {
    local daily_usd="$1"

    echo -e "${BLUE}=== Akash Bidding Breakeven ===${NC}"
    echo "To match mining revenue, your minimum bid should be:"
    echo ""

    # Per GPU per hour
    local per_gpu_hour=$(echo "scale=4; $daily_usd / 5 / 24" | bc)
    echo "  Per GPU/hour: \$${per_gpu_hour}"

    # Per 1000 CPU (millicore) per hour
    local per_millicore_hour=$(echo "scale=6; $daily_usd / 78000 / 24" | bc)
    echo "  Per 1000mCPU/hour: \$${per_millicore_hour}"

    # Current pricing
    echo ""
    echo -e "${YELLOW}Current Akash Pricing:${NC}"
    echo "  CPU:     0.004 uakt/mCPU/s ≈ \$0.00006/hour per 1000mCPU"
    echo "  Memory:  0.0016 uakt/MB/s ≈ \$0.00002/hour per GB"
    echo "  Storage: 0.00016 uakt/MB/s ≈ negligible"
    echo ""
    echo -e "${BLUE}Recommendation:${NC}"
    local akash_hourly=$(echo "scale=4; 0.00006 * 78 + 0.00002 * 111" | bc)
    echo "  Current Akash pricing earns: ~\$${akash_hourly}/hour"
    echo "  Mining earns: ~\$(echo "scale=4; $daily_usd / 24" | bc)/hour"
    echo ""
}

# Main execution
main() {
    get_xtm_price
    get_cpu_hashrate
    get_gpu_hashrate
    calculate_earnings "$XTM_PRICE" "$CPU_HASHRATE" "$GPU_HASHRATE_SOL"
    breakeven_analysis "$DAILY_USD"

    # Save to file for tracking
    {
        echo "{\"timestamp\":\"$(date -Iseconds)\",\"xtm_price\":$XTM_PRICE,\"cpu_hashrate_hps\":$CPU_HASHRATE,\"gpu_hashrate_sols\":$GPU_HASHRATE_SOL}"
    } >> /tmp/tari-mining-stats.jsonl
}

main "$@"
