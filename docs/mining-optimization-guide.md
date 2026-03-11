# GPU Mining Optimization Guide

## Current Performance Baseline

### Zephyr GPUs
- **RTX 3060 Ti**: 4.97 g/s @ 98W (50.7 g/s per kW) ✅ Efficient
- **RTX 3090**: 6.30 g/s @ 198W (31.8 g/s per kW) ⚠️ Severely limited

### Forge GPUs
- **2x RTX 4060**: 8.53 g/s @ 90W each
- **2x RX 5700 XT**: 9.60 g/s

## Optimization Strategies

### 1. Power Limit Optimization (Immediate Wins)

#### RTX 3090 - Highest Impact
**Problem**: Core clock stuck at 705 MHz (should be 1400-1500 MHz)

**Solution**:
```bash
# Apply compute profile
sudo /etc/nixos/scripts/gpu-profiles/compute.sh
```

**Expected Results**:
- Power: 200W → 350W
- Core Clock: 705 MHz → 1400-1500 MHz
- Hashrate: 6.30 g/s → 8.5-10 g/s (+35-60%)
- Temperature: 48°C → 65-70°C (still safe)

#### RTX 3060 Ti
**Current**: Already efficient, room for improvement

**Solution**: Increase to 220W limit
```bash
sudo nvidia-smi -i 0 -pl 220
```

**Expected Results**:
- Hashrate: 4.97 g/s → 6-6.5 g/s (+20-30%)

### 2. Memory Clock Optimization

Cuckaroo29 is **memory-bound**, not core-bound.

**RTX 3090** (9.7 GB/s memory bandwidth):
- Already excellent at 9751 MHz
- Focus on core clock unlock

**RTX 4060** (224 GB/s memory bandwidth):
- Excellent memory bandwidth (8.4 GB/s effective)
- Power limit is main constraint

### 3. Thermal Optimization

**Current temperatures are excellent** (48-62°C), leaving headroom:

**Zephyr**:
- RTX 3060 Ti: 62°C @ 98W → Can go to 220W safely
- RTX 3090: 48°C @ 198W → Can go to 350W easily

**Forge**:
- RTX 4060: 60-62°C @ 90W → Can increase to 130-150W

### 4. Proxy Architecture Benefits

**Why xmrig-proxy improves hashrate**:

1. **Connection Stability**
   - Single TLS connection to pool
   - No per-miner TLS handshake overhead
   - Automatic pool failover reduces downtime

2. **Worker Optimization**
   - Centralized worker management
   - Easy load balancing
   - Share aggregation improves luck

3. **Network Efficiency**
   - Reduced connection overhead
   - Better packet routing
   - Local DNS resolution cached

## Implementation Priority

### Phase 1: Quick Wins (Today)
```bash
# Apply compute profile to Zephyr
ssh zephyr 'sudo /etc/nixos/scripts/gpu-profiles/compute.sh'

# Restart mining to apply new power limits
ssh zephyr 'sudo systemctl restart lolminer-nvidia'

# Wait 5 minutes for stabilization
sleep 300

# Check new hashrate
curl -s http://zephyr:4068 | jq '.Algorithms[0].Worker_Performance'
```

**Expected gain**: +4-5 g/s total (+35-45% on Zephyr)

### Phase 2: Permanent Configuration
Update NixOS config to use compute profile defaults:

```nix
# hosts/zephyr/configuration.nix
mining.lolminer.nvidia = {
  enable = true;
  autostart = true;
  devices = "0,1";
  powerLimit = 350;  # Increased for RTX 3090
  apiPort = 4068;
};
```

### Phase 3: Forge Optimization
```nix
# hosts/forge/configuration.nix
mining.lolminer.nvidia = {
  powerLimit = 130;  # Increased from 90W
  ...
};

mining.lolminer.amd = {
  powerLimit = 160;  # Increased from 140W
  ...
};
```

## Expected Final Performance

### Zephyr (After Optimization)
- **RTX 3060 Ti**: 6.0-6.5 g/s @ 220W
- **RTX 3090**: 8.5-10 g/s @ 350W
- **Total**: 14.5-16.5 g/s (+30-50% from current 11.3 g/s)

### Forge (After Optimization)
- **2x RTX 4060**: 10-11 g/s @ 130W each
- **2x RX 5700 XT**: 10-11 g/s @ 160W each
- **Total**: 20-22 g/s (+20-30% from current 18.1 g/s)

### Cluster Total
- **Current**: ~29.4 g/s
- **Optimized**: 34.5-38.5 g/s
- **Improvement**: +17-31% ⭐

## Safety Limits

### Maximum Safe Power Limits
- **RTX 3060 Ti**: 220W (TDP: 200W)
- **RTX 3090**: 350W (TDP: 350W)
- **RTX 4060**: 130W (TDP: 115W)
- **RX 5700 XT**: 160W (TDP: 225W)

### Temperature Targets
- **Optimal**: 60-70°C under load
- **Maximum**: 83°C (NVIDIA thermal throttle)
- **Warning**: Above 75°C reduce power limit

## Monitoring

### Real-time Stats
```bash
# Zephyr GPU stats
watch -n 5 'nvidia-smi --query-gpu=name,power.draw,clocks.gr,clocks.mem,temperature.gpu --format=csv'

# Mining hashrate
watch -n 10 'curl -s http://localhost:4068 | jq ".Algorithms[0].Total_Performance"'

# Proxy stats
watch -n 10 'journalctl -u xmrig-proxy -n 1 | grep "miners:"'
```

### Efficiency Metrics
```bash
# Calculate g/s per kW
# Formula: (hashrate / power_draw) * 1000

# RTX 3060 Ti: (4.97 / 98) * 1000 = 50.7 g/s per kW ✅
# RTX 3090: (6.30 / 198) * 1000 = 31.8 g/s per kW ⚠️ (Will improve with power increase)
```

## Troubleshooting

### Low Hashrate Symptoms
1. **Core clock too low** → Increase power limit
2. **High temperature** → Reduce power limit, improve cooling
3. **Shares rejected** → Check pool connection, stratum protocol version
4. **Connection drops** → Check xmrig-proxy logs, network stability

### Proxy Issues
```bash
# Check proxy status
sudo systemctl status xmrig-proxy

# View proxy logs
sudo journalctl -u xmrig-proxy -f

# Test pool connection
telnet xtm-c29-us.kryptex.network 8040
```

## Advanced Optimizations (Future)

### 1. Overclocking
```bash
# RTX 3090 memory overclock
sudo nvidia-smi -i 1 -pl 350  # Power limit first
nvidia-settings -a [gpu:1]/GPUMemoryTransferRateOffset[3]=500  # +500 MHz
```

### 2. Custom lolMiner Tuning
```nix
# Add to mining.nix
extraArgs = [
  "--density" "8"  # Cuckaroo29 tuning
  "--mt" "1"       # Multi-threading
];
```

### 3. Pool Selection
Test different pools for better luck/performance:
- Kryptex US (current)
- Kryptex EU (failover)
- f2pool (backup)

## Conclusion

**Key takeaways**:
1. Power limits are the #1 constraint on your hashrate
2. RTX 3090 is severely underutilized (705 MHz vs 1500 MHz capability)
3. Proxy architecture is working perfectly - focus on GPU optimization
4. Conservative thermal headroom allows safe power increases
5. Expected gains: +17-31% cluster-wide with just power limit changes

**Next steps**:
1. Apply compute profile to Zephyr ✅
2. Monitor temperatures and hashrate
3. Update NixOS config for permanent settings
4. Consider overclocking for additional gains
