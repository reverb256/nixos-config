# GPU Resource Marketplace

**Status:** ✅ Implemented | **Created:** 2026-03-14 | **Owner:** j_kro

## Overview

The GPU Resource Marketplace is a unified auction engine that coordinates GPU allocation between competing workloads:

| Bidder | Priority | Typical Bid | Behavior |
|--------|----------|-------------|----------|
| **Gaming** | Override | $999.99/hr | Always wins, pauses all GPU workloads |
| **Kubernetes** | High | $2.50/hr | AI/ML training jobs, inference pods |
| **Akash** | Medium | Market rate | Decentralized compute marketplace leases |
| **Mining** | Baseline | $0.10/hr | Passive income, yields to higher bids |

### Key Innovation

Instead of a fixed priority chain (gaming > AI > builds > mining), the marketplace treats GPU time as an **economic resource** where bidders compete via price signals.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│               GPU RESOURCE AUCTION ENGINE                    │
│                  (compute-market-daemon)                     │
├─────────────────────────────────────────────────────────────┤
│  Auction Loop (every 30s):                                   │
│  1. Check for gaming (override)                              │
│  2. Collect bids from all bidders                            │
│  3. Determine winner (highest bid)                           │
│  4. Apply winner profile (pause/resume mining)              │
│  5. Update Prometheus metrics                               │
└─────────────────────────────────────────────────────────────┘
         │                    │                    │
         ▼                    ▼                    ▼
┌─────────────┐      ┌─────────────┐      ┌─────────────┐
│   Mining    │      │  Kubernetes │      │   Akash     │
│   Bidder    │      │   Bidder    │      │   Bidder    │
│             │      │             │      │             │
│ $0.10/hr    │      │ $2.50/hr    │      │ Market Rate │
│ (passive)   │      │ (AI work)   │      │ (leases)    │
└─────────────┘      └─────────────┘      └─────────────┘
```

### State Management

- **State Directory:** `/run/compute-market/`
- **Key Files:**
  - `current_winner` - Current auction winner
  - `auction_count` - Total auctions run
  - `metrics.prom` - Prometheus metrics
  - `paused_services` - Mining services paused for workload

---

## Configuration

### Module Options

```nix
services.compute-market = {
  enable = true;

  # Auction timing
  auctionInterval = 30; # seconds

  # Mining bidder
  bidders.mining = {
    enable = true;
    hourlyRevenue = 0.10; # USD per GPU per hour
    services = ["lolminer-nvidia" "xmrig"];
  };

  # Kubernetes bidder
  bidders.kubernetes = {
    enable = true;
    baseBid = 2.50; # USD per hour
    urgencyMultiplier = 2.0; # For high-priority jobs
    namespace = "default";
  };

  # Akash bidder
  bidders.akash = {
    enable = true;
    profitMargin = 0.90; # 90% of market rate
    namespace = "akash-services";
  };

  # Gaming override
  bidders.gaming = {
    enable = true;
    processes = ["steam" "lutris" "heroic" "wine" "proton"];
  };

  # Prometheus metrics
  prometheus = {
    enable = true;
    port = 9200;
  };
};
```

### Per-Host Configuration

Different hosts may have different configurations:

**Zephyr (Control Plane + AI Workstation):**
```nix
services.compute-market = {
  enable = true;
  bidders.mining.hourlyRevenue = 0.10;  # RTX 3090 efficient
  bidders.kubernetes.baseBid = 2.50;     # High AI value
};
```

**Forge (Dedicated GPU Miner):**
```nix
services.compute-market = {
  enable = true;
  bidders.mining.hourlyRevenue = 0.08;  # Lower cost GPUs
  bidders.kubernetes.enable = false;     # Mining-focused
};
```

---

## Prometheus Metrics

### Available Metrics

```prometheus
# Auction winner (label: winner)
compute_market_auction_winner{winner="mining|kubernetes|akash|gaming|none"}

# Winning bid amount
compute_market_winning_bid_usd

# Current bids by bidder
compute_market_bid_current{bidder="mining|kubernetes|akash|gaming"}

# Gaming active flag
compute_market_gaming_active

# Total auctions run
compute_market_auction_total
```

### Grafana Dashboard

Import the dashboard from `modules/compute-market/grafana-dashboard.json`:

1. Go to Grafana → Dashboards → Import
2. Upload the JSON file or paste the content
3. Select your Prometheus data source
4. Save the dashboard

**Dashboard UID:** `gpu-marketplace`

---

## Bidding Algorithms

### Mining Bidder

Returns the configured hourly revenue (baseline bid):

```bash
bid_mining() {
  echo "$MINING_HOURLY"  # $0.10/hr by default
}
```

**Tuning:** Adjust based on actual mining revenue:
- High hash rate → Increase bid (mining more valuable)
- Low electricity cost → Increase bid (higher margin)
- High electricity cost → Decrease bid (lower margin)

### Kubernetes Bidder

Calculates bid based on active GPU pods:

```bash
bid_kubernetes() {
  for each running GPU pod:
    bid = baseBid
    if pod has high-priority class:
      bid *= urgencyMultiplier
    total += bid
  echo $total
}
```

**Priority Classes:**
- `high` / `urgent` / `critical` → 2x multiplier
- Default → 1x multiplier

**Tuning:**
- Increase `baseBid` if K8s workloads are more valuable
- Increase `urgencyMultiplier` to prioritize urgent jobs
- Add custom priority classes for specific job types

### Akash Bidder

Returns market rate for active leases:

```bash
bid_akash() {
  for each active lease:
    price = lease.escrowed_payment
    usd_hourly = price * AKT_price * 3600 / blocks / 1_000_000
    our_bid = usd_hourly * profitMargin
    total += our_bid
  echo $total
}
```

**Tuning:**
- Decrease `profitMargin` to be more competitive (win more bids)
- Increase `profitMargin` for higher margin per lease
- Monitor Akash earnings vs. mining revenue

### Gaming Override

Always returns highest priority (overrides auction):

```bash
check_gaming() {
  for proc in $GAMING_PROCESSES:
    if pgrep -fi "$proc":
      return true  # Gaming detected
  return false
}
```

**Process Detection:**
- Steam (main process, web helper, apps)
- Lutris, Heroic (game launchers)
- Wine, Proton (compatibility layers)

---

## Troubleshooting

### Service Not Starting

```bash
# Check service status
systemctl status compute-market

# Check logs
journalctl -u compute-market -f

# Check state directory
ls -la /run/compute-market/
```

### Mining Not Pausing for K8s

```bash
# Verify K8s detection
grep "Kubernetes GPU workload" /var/log/compute-market.log

# Check kubectl access
sudo -u compute-market kubectl get pods --all-namespaces

# Verify GPU pods exist
sudo -u compute-market kubectl get pods -A \
  -o jsonpath='{range .items[?(@.spec.containers[*].resources.limits.nvidia\.com/gpu)]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}'
```

### Akash Bids Not Working

```bash
# Check Akash provider status
kubectl get pods -n akash-services

# Check for active leases
kubectl get leases -n akash-services

# Verify Akash bidder enabled
grep "AKASH_ENABLE" /var/log/compute-market.log
```

### Gaming Not Detected

```bash
# Check running processes
pgrep -fia steam

# Verify gaming processes in config
grep "GAMING_PROCESSES" /etc/systemd/system/compute-market.service

# Test detection manually
pgrep -fi "steam|lutris|heroic"
```

### Metrics Not Showing in Prometheus

```bash
# Check metrics file
cat /run/compute-market/metrics.prom

# Verify Prometheus scrape config
grep "compute-market" /etc/prometheus/scrape_configs.yaml

# Check Prometheus targets
curl http://127.0.0.1:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job=="compute-market")'
```

---

## Testing

### Manual Auction Test

```bash
# Trigger auction manually
systemctl restart compute-market
sleep 35  # Wait for first auction
cat /run/compute-market/current_winner

# Check logs
tail -20 /var/log/compute-market.log
```

### Kubernetes GPU Pod Test

```bash
# Apply test pod
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: gpu-test
spec:
  containers:
  - name: gpu-test
    image: nvidia/cuda:12.1.0-base-ubuntu22.04
    command: ["sleep", "300"]
    resources:
      limits:
        nvidia.com/gpu: 1
EOF

# Verify auction winner changes to "kubernetes"
watch -n 5 'cat /run/compute-market/current_winner'

# Cleanup
kubectl delete pod gpu-test
```

### Gaming Detection Test

```bash
# Simulate gaming (create a process named "steam")
sleep 300 &
pgrep -f sleep | xargs rename -n '.*/sleep' 'steam' {} 2>/dev/null || \
  (mkdir -p /tmp/fake-steam && echo '#!/bin/bash' > /tmp/fake-steam/steam \
    && echo 'sleep 3600' >> /tmp/fake-steam/steam \
    && chmod +x /tmp/fake-steam/steam \
    && PATH="/tmp/fake-steam:$PATH" steam &)

# Or actually launch Steam (if installed)
steam &

# Verify auction winner changes to "gaming"
watch -n 5 'cat /run/compute-market/current_winner'
```

---

## Future Enhancements

### Phase 2: Advanced Features

1. **Time-Based Bidding**
   - Higher mining bids during low electricity rates
   - Lower K8s bids during peak hours

2. **GPU-Specific Bidding**
   - Different bids per GPU (e.g., 3090 > 3060 Ti)
   - Per-GPU auction (allocate individual GPUs)

3. **Predictive Bidding**
   - Learn patterns (gaming evenings, K8s jobs overnight)
   - Preemptive mining pause before expected workload

4. **Revenue Optimization**
   - Track actual mining revenue vs. K8s value
   - Auto-tune bid amounts based on historical data

5. **Akash Integration**
   - Direct Akash bid submission (not just monitoring)
   - Lease lifecycle management

---

## See Also

- **Implementation:** `modules/compute-market/default.nix`
- **Dashboard:** `modules/compute-market/grafana-dashboard.json`
- **Compute Monitor:** `modules/system/compute-workload-monitor.nix`
- **Akash Provider:** `modules/services/akash-provider.nix`
- **ROADMAP:** `/etc/nixos/ROADMAP.md`

---

**Document Version:** 1.0 | **Last Updated:** 2026-03-14
