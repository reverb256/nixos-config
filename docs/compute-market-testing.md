# GPU Marketplace Testing Guide

**Purpose:** Verify GPU Resource Marketplace functionality before deployment
**Created:** 2026-03-14 | **Status:** Ready for Testing

---

## Pre-Deployment Checklist

### 1. Configuration Verification

```bash
# Verify module is imported
grep "compute-market" /etc/nixos/modules/default.nix

# Verify enabled on zephyr
grep "compute-market.enable = true" /etc/nixos/hosts/zephyr/configuration.nix

# Check Prometheus scrape config includes marketplace
grep "compute-market" /etc/nixos/modules/services/monitoring/prometheus.nix
```

### 2. Build Verification

```bash
# Test configuration builds
just test

# Or manual
nixos-rebuild test --flake .#zephyr
```

---

## Deployment Steps

### Step 1: Apply Configuration

```bash
# Apply to zephyr
just switch

# Or manual
sudo nixos-rebuild switch --flake .#zephyr
```

### Step 2: Verify Service Started

```bash
# Check service is running
systemctl status compute-market

# Check logs
journalctl -u compute-market -f

# Check state directory
ls -la /run/compute-market/
```

**Expected Output:**
```
-rw-r--r-- 1 root root 4 Mar 14 22:30 auction_count
-rw-r--r-- 1 root root 5 Mar 14 22:30 current_winner
-rw-r--r-- 1 root root 0 Mar 14 22:30 metrics.prom
```

---

## Functional Tests

### Test 1: Mining Baseline Bid

**Purpose:** Verify mining bidder returns correct baseline bid

```bash
# Wait for first auction (30 seconds)
sleep 35

# Check current winner
cat /run/compute-market/current_winner
# Expected: "mining" (if no other workloads active)

# Check logs
grep "AUCTION" /var/log/compute-market.log | tail -5
```

**Expected Log Output:**
```
[2026-03-14 22:30:15] [AUCTION] Auction #1 - Mining: $0.10/hr | K8s: $0/hr | Akash: $0/hr
[2026-03-14 22:30:15] [AUCTION] WINNER SELECTED: mining ($0.10/hr)
```

### Test 2: Kubernetes GPU Pod Detection

**Purpose:** Verify K8s bidder detects GPU workloads

```bash
# Apply test GPU pod
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: gpu-auction-test
spec:
  containers:
  - name: gpu-test
    image: nvidia/cuda:12.1.0-base-ubuntu22.04
    command: ["sleep", "300"]
    resources:
      limits:
        nvidia.com/gpu: 1
EOF

# Wait for next auction cycle
sleep 35

# Check winner changed
cat /run/compute-market/current_winner
# Expected: "kubernetes"

# Check logs
grep "Kubernetes GPU workload" /var/log/compute-market.log | tail -3
```

**Expected Log Output:**
```
[2026-03-14 22:31:45] [AUCTION] Auction #3 - Mining: $0.10/hr | K8s: $2.50/hr | Akash: $0/hr
[2026-03-14 22:31:45] [AUCTION] WINNER CHANGED: mining → kubernetes ($2.50/hr)
[2026-03-14 22:31:45] [INFO] Applying KUBERNETES profile - pausing mining for K8s workloads
```

**Cleanup:**
```bash
kubectl delete pod gpu-auction-test
```

### Test 3: Gaming Override

**Purpose:** Verify gaming bidder overrides auction

```bash
# Simulate gaming (create a process named "steam")
mkdir -p /tmp/fake-steam
cat > /tmp/fake-steam/steam <<'SCRIPT'
#!/bin/bash
echo "Fake Steam process"
sleep 3600
SCRIPT
chmod +x /tmp/fake-steam/steam
/tmp/fake-steam/steam &

# Wait for auction cycle
sleep 35

# Check winner
cat /run/compute-market/current_winner
# Expected: "gaming"

# Check logs
grep "GAMING OVERRIDE" /var/log/compute-market.log | tail -3

# Cleanup
pkill -f /tmp/fake-steam/steam
rm -rf /tmp/fake-steam
```

**Expected Log Output:**
```
[2026-03-14 22:32:45] [AUCTION] GAMING OVERRIDE - Gaming detected, pausing all GPU workloads
```

### Test 4: Akash Lease Detection

**Purpose:** Verify Akash bidder monitors active leases

```bash
# Check if Akash provider is running
kubectl get pods -n akash-services

# If Akash is running, check for leases
kubectl get leases -n akash-services

# Verify Akash bid in logs (if leases exist)
grep "Akash" /var/log/compute-market.log
```

### Test 5: Metrics Export

**Purpose:** Verify Prometheus metrics are generated

```bash
# Check metrics file exists
cat /run/compute-market/metrics.prom

# Expected content:
# HELP compute_market_auction_winner The current auction winner
# TYPE compute_market_auction_winner gauge
compute_market_auction_winner{winner="mining"} 1
...
```

---

## Integration Tests

### Test 6: Full Auction Cycle

**Purpose:** Verify complete pause/resume cycle

```bash
# Start with mining baseline
echo "Initial state:"
cat /run/compute-market/current_winner

# Apply K8s GPU pod
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: gpu-auction-test
spec:
  containers:
  - name: gpu-test
    image: nvidia/cuda:12.1.0-base-ubuntu22.04
    command: ["sleep", "120"]
    resources:
      limits:
        nvidia.com/gpu: 1
EOF

# Wait for auction cycle
sleep 35

# Verify mining paused
echo "During K8s workload:"
cat /run/compute-market/current_winner
systemctl status lolminer-nvidia | grep "CPUQuota"

# Delete pod
kubectl delete pod gpu-auction-test

# Wait for auction cycle
sleep 35

# Verify mining resumed
echo "After K8s workload:"
cat /run/compute-market/current_winner
systemctl status lolminer-nvidia | grep "CPUQuota"
```

### Test 7: Grafana Dashboard Verification

```bash
# Access Grafana
# URL: http://127.0.0.1:3001
# Navigate to: Dashboards → GPU Resource Marketplace

# Verify panels show data:
# - Current Auction Winner (should show "mining" initially)
# - Winning Bid (USD/hr)
# - All Bids by Bidder
# - Gaming Status
# - Total Auctions
```

---

## Rollback Plan

If issues occur:

```bash
# Disable marketplace service
sudo systemctl stop compute-market
sudo systemctl disable compute-market

# Remove from configuration
# Edit hosts/zephyr/configuration.nix
# Set: services.compute-market.enable = false;

# Rebuild
just switch

# Verify mining resumes normally
systemctl status lolminer-nvidia
```

---

## Success Criteria

- [ ] Service starts without errors
- [ ] Auction cycle runs every 30 seconds
- [ ] Mining baseline bid registered correctly
- [ ] K8s GPU pods trigger mining pause
- [ ] Gaming detection overrides auction
- [ ] Mining resumes after workload completes
- [ ] Prometheus metrics generated
- [ ] Grafana dashboard displays correctly
- [ ] No resume storms (rapid flip-flopping)

---

## Next Steps

After successful testing:

1. **Monitor for 24 hours** - Observe auction behavior under real workloads
2. **Tune bid amounts** - Adjust based on actual revenue/value
3. **Extend to other nodes** - Enable on Forge, Nexus, Sentry
4. **Add custom bidders** - Implement domain-specific bidders if needed

---

**Document Version:** 1.0 | **Last Updated:** 2026-03-14
