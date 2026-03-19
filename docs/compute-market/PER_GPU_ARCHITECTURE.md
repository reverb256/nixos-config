# Per-GPU Intelligent Scheduling Architecture

**Author**: Reverb256 Cluster
**Created**: 2026-03-19
**Status**: Design Document

---

## Problem Statement

**Current Architecture (Global Override)**:
```
Gaming on GPU 0 → Pause ALL GPUs (0, 1, 2, 3)
→ Lost revenue: $0.30/hr (3 GPUs × $0.10/hr)
→ Poor resource utilization
```

**Desired Architecture (Per-GPU Awareness)**:
```
Gaming on GPU 0 → Pause ONLY GPU 0
→ GPU 1, 2, 3 continue mining ($0.30/hr)
→ Akash can bid on GPU 1, 2, 3
→ Revenue preserved: 75% (3/4 GPUs still earning)
```

---

## Architecture Design

### 1. GPU State Tracking

Each GPU maintains independent state:

```bash
# Per-GPU state directory structure
/run/compute-market/
├── gpu0/
│   ├── state              # "idle" | "mining" | "akash" | "kubernetes" | "gaming"
│   ├── workload_pid       # PID of current workload process
│   ├── current_bid        # Current bid (USD/hr)
│   ├── last_auction       # Unix timestamp
│   └── metrics            # GPU-specific metrics
├── gpu1/
│   └── ...
├── gpu2/
│   └── ...
└── gpu3/
    └── ...
```

### 2. Per-GPU Gaming Detection

**Key Insight**: Use `nvidia-smi pmon` to detect which GPU has gaming processes.

```bash
detect_gaming_per_gpu() {
    local gpu_id=$1

    # Get processes running on specific GPU
    local gpu_processes=$(nvidia-smi pmon -c 1 -i $gpu_id --count 1 | \
        awk 'NR>2 && $2 != "-" {print $2}')

    # Check if any process matches gaming whitelist
    for proc in $gpu_processes; do
        for game_pattern in $GAMING_GAMES; do
            if pgrep -x "$game_pattern" | grep -q "^$proc\$"; then
                echo "true"
                return
            fi
        done
    done

    echo "false"
}
```

**Example**:
```
GPU 0: Cyberpunk2077.exe running → gaming_active=true → Pause mining on GPU 0
GPU 1: No gaming process → gaming_active=false → Continue mining on GPU 1
GPU 2: No gaming process → gaming_active=false → Continue mining on GPU 2
GPU 3: No gaming process → gaming_active=false → Continue mining on GPU 3
```

### 3. Per-GPU Auction Engine

**Instead of**: One global auction every 30 seconds
**Now**: One auction PER GPU every 30 seconds (parallel execution)

```bash
run_auction_for_gpu() {
    local gpu_id=$1

    # Increment GPU-specific auction counter
    local count=$(($(cat "$STATE_DIR/gpu$gpu_id/auction_count" 2>/dev/null || echo 0) + 1))
    echo "$count" > "$STATE_DIR/gpu$gpu_id/auction_count"

    # Check if gaming is active on THIS GPU
    local gaming_active=$(detect_gaming_per_gpu $gpu_id)

    if [ "$gaming_active" = "true" ]; then
        log_auction "GPU $gpu_id: Gaming override - pausing workloads"
        update_gpu_metrics $gpu_id "gaming" 999.99
        echo "gaming" > "$STATE_DIR/gpu$gpu_id/state"
        apply_gaming_profile_to_gpu $gpu_id
        return
    fi

    # Collect bids for THIS GPU
    local mining_bid=$(bid_mining_per_gpu $gpu_id)
    local k8s_bid=$(bid_kubernetes_per_gpu $gpu_id)
    local akash_bid=$(bid_akash_per_gpu $gpu_id)

    # Run auction for THIS GPU
    local winner=$(run_auction_logic "$mining_bid" "$k8s_bid" "$akash_bid")

    # Apply winner to THIS GPU only
    apply_winner_profile_to_gpu $gpu_id $winner
}

# Parallel auction execution for all GPUs
run_parallel_auctions() {
    for gpu_id in $(list_available_gpus); do
        run_auction_for_gpu $gpu_id &
    done
    wait  # Wait for all GPU auctions to complete
}
```

### 4. Per-GPU Workload Management

**Mining**:
```bash
bid_mining_per_gpu() {
    local gpu_id=$1

    # Check if mining is profitable on THIS GPU
    local gpu_util=$(gpu_utilization_per_gpu $gpu_id)
    local mem_used=$(gpu_memory_used_per_gpu $gpu_id)

    # Only bid if GPU is available
    if [ "$gpu_util" -lt 0.1 ] && [ "$mem_used" -lt 1000 ]; then
        echo "$MINING_HOURLY"
    else
        echo "0"  # Don't bid if GPU busy
    fi
}

apply_mining_to_gpu() {
    local gpu_id=$1

    # Start mining instance on specific GPU
    local mining_cmd="lolminer --devices $gpu_id ..."
    $mining_cmd &
    echo $! > "$STATE_DIR/gpu$gpu_id/workload_pid"
}
```

**Akash**:
```bash
bid_akash_per_gpu() {
    local gpu_id=$1

    # Check if Akash has active lease needing THIS GPU
    local gpu_needed=$(check_akash_gpu_demand)

    if [ "$gpu_needed" = "true" ]; then
        # Calculate bid for THIS GPU only
        local our_bid=$(calculate_akash_bid)
        echo "$our_bid"
    else
        echo "0"
    fi
}
```

**Kubernetes**:
```bash
bid_kubernetes_per_gpu() {
    local gpu_id=$1

    # Check if K8s has workload needing THIS GPU
    local pending_pods=$(kubectl get pods -n llm-workloads -o json | \
        jq ".items[] | select(.spec.nodeSelector['nvidia.com/gpu.count'] | tonumber > 0) | .status.phase == 'Pending'" | wc -l)

    if [ "$pending_pods" -gt 0 ]; then
        # Bid for THIS GPU
        echo "$K8S_HOURLY_MAX"
    else
        echo "0"
    fi
}
```

---

## Intelligent Features

### 1. GPU Workload Prediction

**Predict future demand** based on historical patterns:

```bash
predict_gpu_demand() {
    local gpu_id=$1
    local hour=$(date +%H)
    local day_of_week=$(date +%u)

    # Historical patterns (from logs)
    # Monday-Friday 9am-5pm: High Kubernetes demand (AI workloads)
    # Evening 6pm-12am: High gaming probability
    # Night 12am-6am: High Akash demand (off-peak compute)

    if [ "$day_of_week" -le 5 ] && [ "$hour" -ge 9 ] && [ "$hour" -lt 17 ]; then
        echo "kubernetes"  # Business hours: K8s likely
    elif [ "$hour" -ge 18 ] && [ "$hour" -lt 24 ]; then
        echo "gaming"  # Evening: Gaming likely
    else
        echo "akash"  # Night/weekend: Akash likely
    fi
}
```

### 2. Dynamic GPU Allocation

**Rebalance workloads** based on real-time conditions:

```bash
rebalance_gpu_workloads() {
    # If GPU 0 gaming ends → Start mining on GPU 0
    # If GPU 1-3 mining revenue < Akash bid → Switch to Akash on GPU 1-3
    # If K8s workload completes → Return GPUs to mining

    for gpu_id in $(list_available_gpus); do
        local current_state=$(cat "$STATE_DIR/gpu$gpu_id/state")
        local predicted_demand=$(predict_gpu_demand $gpu_id)

        # Switch if prediction is confident (>70% probability)
        if should_switch_workload $current_state $predicted_demand; then
            log_auction "GPU $gpu_id: Rebalancing $current_state → $predicted_demand"
            apply_winner_profile_to_gpu $gpu_id $predicted_demand
        fi
    done
}
```

### 3. Multi-GPU Akash Bidding

**Bid individual GPUs** to Akash (not all-or-nothing):

```bash
bid_akash_individual_gpus() {
    local available_gpus=()

    # Find all GPUs NOT in gaming
    for gpu_id in $(list_available_gpus); do
        local gaming=$(detect_gaming_per_gpu $gpu_id)
        if [ "$gaming" = "false" ]; then
            available_gpus+=($gpu_id)
        fi
    done

    # Bid each GPU independently
    for gpu_id in "${available_gpus[@]}"; do
        local bid=$(calculate_akash_bid_per_gpu $gpu_id)
        submit_akash_bid $gpu_id $bid
    done
}
```

**Example Akash manifest**:
```yaml
resources:
  gpu:
    - vendor: nvidia
      model: rtx3060ti
      memory: 8GB
      units: 1  # Bid for 1 GPU, not all 4
```

---

## Prometheus Metrics (Per-GPU)

### GPU State Metrics

```
compute_market_gpu_state{gpu="0",state="gaming"}              # Current state
compute_market_gpu_state{gpu="1",state="mining"}             # Current state
compute_market_gpu_state{gpu="2",state="akash"}              # Current state
compute_market_gpu_state{gpu="3",state="mining"}             # Current state
```

### GPU Auction Metrics

```
compute_market_gpu_auction_winner{gpu="0",winner="gaming"}    # GPU 0: Gaming won
compute_market_gpu_auction_winner{gpu="1",winner="mining"}    # GPU 1: Mining won
compute_market_gpu_auction_winner{gpu="2",winner="akash"}     # GPU 2: Akash won
compute_market_gpu_auction_winner{gpu="3",winner="mining"}    # GPU 3: Mining won
```

### GPU Revenue Metrics

```
compute_market_gpu_revenue{gpu="0",workload="gaming"}         # $0/hr (gaming = no revenue)
compute_market_gpu_revenue{gpu="1",workload="mining"}        # $0.10/hr
compute_market_gpu_revenue{gpu="2",workload="akash"}         # $0.096/hr
compute_market_gpu_revenue{gpu="3",workload="mining"}        # $0.10/hr
compute_market_cluster_revenue                                 # $0.296/hr total
```

### GPU Utilization Metrics

```
compute_market_gpu_utilization{gpu="0"}                       # 95% (gaming)
compute_market_gpu_utilization{gpu="1"}                       # 98% (mining)
compute_market_gpu_utilization{gpu="2"}                       # 85% (akash)
compute_market_gpu_utilization{gpu="3"}                       # 97% (mining)
```

---

## Implementation Plan

### Phase 1: Per-GPU State Tracking (1 hour)
- [ ] Create per-GPU state directories
- [ ] Implement `detect_gaming_per_gpu()`
- [ ] Add per-GPU Prometheus metrics
- [ ] Test gaming detection on individual GPUs

### Phase 2: Per-GPU Auction Engine (2 hours)
- [ ] Implement `run_auction_for_gpu()`
- [ ] Refactor bidding functions for per-GPU
- [ ] Add parallel auction execution
- [ ] Test with 1 GPU gaming, 3 GPUs mining

### Phase 3: Per-GPU Workload Management (2 hours)
- [ ] Implement `apply_mining_to_gpu()`
- [ ] Implement `apply_akash_to_gpu()`
- [ ] Implement `apply_kubernetes_to_gpu()`
- [ ] Test workload switching per GPU

### Phase 4: Intelligent Features (2 hours)
- [ ] Implement `predict_gpu_demand()`
- [ ] Implement `rebalance_gpu_workloads()`
- [ ] Implement multi-GPU Akash bidding
- [ ] Test rebalancing scenarios

### Phase 5: Testing & Validation (1 hour)
- [ ] Test: Gaming on GPU 0, verify GPU 1-3 continue mining
- [ ] Test: Gaming ends on GPU 0, verify mining resumes on GPU 0
- [ ] Test: Akash lease on GPU 2, verify GPU 0,1,3 continue mining
- [ ] Test: All scenarios, verify revenue metrics

**Total Estimated Time**: 8 hours

---

## Example Scenarios

### Scenario 1: Single GPU Gaming

**Initial State**:
```
GPU 0: Mining ($0.10/hr)
GPU 1: Mining ($0.10/hr)
GPU 2: Mining ($0.10/hr)
GPU 3: Mining ($0.10/hr)
Total Revenue: $0.40/hr
```

**User starts Cyberpunk2077 on GPU 0**:
```
GPU 0: Gaming ($0/hr)           ← Paused mining
GPU 1: Mining ($0.10/hr)       ← Continues
GPU 2: Mining ($0.10/hr)       ← Continues
GPU 3: Mining ($0.10/hr)       ← Continues
Total Revenue: $0.30/hr        ← 75% preserved!
```

**Old behavior would have been**: $0/hr (0% preserved)

### Scenario 2: Akash Lease on Partial GPUs

**Initial State**:
```
GPU 0: Mining ($0.10/hr)
GPU 1: Mining ($0.10/hr)
GPU 2: Mining ($0.10/hr)
GPU 3: Mining ($0.10/hr)
Total Revenue: $0.40/hr
```

**Akash wins auction for GPU 2**:
```
GPU 0: Mining ($0.10/hr)       ← Continues
GPU 1: Mining ($0.10/hr)       ← Continues
GPU 2: Akash ($0.096/hr)       ← Switched to Akash
GPU 3: Mining ($0.10/hr)       ← Continues
Total Revenue: $0.396/hr       ← 99% preserved
```

**Old behavior would have been**: Mining paused on ALL GPUs ($0/hr during lease setup)

### Scenario 3: Dynamic Rebalancing

**Pattern Recognition**:
```
Time: 9am Monday
Historical data: High Kubernetes demand (AI workloads)
Prediction: K8s will need GPUs

Action:
GPU 0: Mining → Kubernetes (pre-emptive allocation)
GPU 1: Mining → Kubernetes (pre-emptive allocation)
GPU 2: Mining (standby for Akash)
GPU 3: Mining (standby for gaming)
```

**Benefit**: Zero-delay K8s workload allocation (no waiting for auction)

---

## Configuration Examples

### Basic Per-GPU Configuration

```nix
# /etc/nixos/hosts/zephyr/configuration.nix
{
  services.compute-market = {
    enable = true;
    perGPUScheduling = true;  # NEW: Enable per-GPU awareness
    gpuList = [0 1 2 3];      # List of GPUs to manage
  };
}
```

### GPU-Specific Gaming Whitelist

```nix
systemd.services.compute-market.environment = {
  # Different games for different GPUs (if you have multiple monitors)
  GAMING_GAMES_GPU0 = "Cyberpunk2077.exe";
  GAMING_GAMES_GPU1 = "eldenring.exe";
  GAMING_GAMES_GPU2 = "";  # No gaming on GPU 2 (server room)
  GAMING_GAMES_GPU3 = "";  # No gaming on GPU 3 (server room)
};
```

### GPU-Specific Workload Preferences

```nix
systemd.services.compute-market.environment = {
  # GPU 0: Prioritize gaming (primary gaming GPU)
  GPU0_PREFERENCES = "gaming,mining,akash,kubernetes";

  # GPU 1: Prioritize Akash (high GPU memory)
  GPU1_PREFERENCES = "akash,mining,kubernetes,gaming";

  # GPU 2: Prioritize Kubernetes (ML workloads)
  GPU2_PREFERENCES = "kubernetes,akash,mining,gaming";

  # GPU 3: Prioritize mining (baseline revenue)
  GPU3_PREFERENCES = "mining,akash,kubernetes,gaming";
};
```

---

## Migration Path

### Step 1: Deploy Current Fix (5 minutes)
- Gaming whitelist approach (no false positives)
- Test gaming detection works

### Step 2: Deploy Per-GPU Architecture (8 hours)
- Implement per-GPU state tracking
- Implement per-GPU auction engine
- Test all scenarios

### Step 3: Monitor & Optimize (ongoing)
- Collect metrics on per-GPU revenue
- Tune workload prediction algorithms
- Adjust preference weights

---

## Success Metrics

### Before (Global Override)
- Gaming on 1 GPU → 0% revenue (all GPUs paused)
- Akash lease → 0% mining revenue during lease
- GPU utilization: 60% (gaming GPU + idle GPUs)

### After (Per-GPU Awareness)
- Gaming on 1 GPU → 75% revenue (3/4 GPUs continue)
- Akash lease on 1 GPU → 90% revenue (3/4 GPUs continue mining)
- GPU utilization: 95% (all GPUs earning)

**Expected Revenue Increase**: +50-75%

---

## Future Enhancements

### 1. ML-Based Demand Prediction
- Train LSTM model on historical workload patterns
- Predict demand 1 hour in advance
- Pre-allocate GPUs for predicted workloads

### 2. Automatic GPU Pooling
- Dynamically pool GPUs for large workloads
- Split GPUs for small workloads
- Optimize for revenue per GPU-hour

### 3. Cross-Cluster Coordination
- Coordinate GPU allocation across Zephyr, Nexus, Forge
- Migrate workloads between hosts
- Maximize cluster-wide revenue

---

**Status**: Design Complete - Ready for Implementation
**Priority**: HIGH (Revenue optimization)
**Dependencies**: None (can be implemented independently)
