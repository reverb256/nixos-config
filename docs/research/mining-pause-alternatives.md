# Mining Pause During Builds: Alternative Approaches & Implementations

Research findings from online sources for improving compute-workload-monitor's distributed build detection and mining pause functionality.

**Date**: 2026-03-09
**Current Implementation**: Process-based detection (pgrep) + systemctl pause/resume

---

## Summary of Findings

### 1. **Systemd cgroups v2 Resource Control** (Most Promising)

**Key Insight**: Systemd has built-in resource control that could replace or supplement our current approach.

**Features Discovered**:
```nix
# CPU Scheduling (CPUWeight = CPUShares in cgroups v1)
systemd.services.my-service.serviceConfig.CPUWeight = 200;  # Default 1024

# CPU Quota (percentage limit)
systemd.services.my-service.serviceConfig.CPUQuota = "50%";  # Limit to 50% CPU

# Memory Limits
systemd.services.my-service.serviceConfig.MemoryMax = "4G";  # Hard limit
systemd.services.my-service.serviceConfig.MemoryHigh = "3G"; # Throttle at 3G

# CPU Affinity (pin to specific cores)
systemd.services.my-service.serviceConfig.CPUAffinity = "0-3"; # Use cores 0-3 only

# Process Niceness (scheduling priority)
systemd.services.my-service.serviceConfig.Nice = 10; # Lower priority
```

**Dynamic Runtime Changes**:
```bash
# Set properties at runtime without config changes
systemctl set-property xmrig.service CPUWeight=50 --runtime  # Reduce CPU weight
systemctl set-property xmrig.service CPUQuota="25%" --runtime # Limit to 25% CPU
systemctl set-property lolminer-nvidia.service CPUWeight=50 --runtime
```

**Advantages Over Current Approach**:
- ✅ No process restarts needed
- ✅ Fine-grained control (percentage-based, not just pause/resume)
- ✅ Built-in to systemd (no external dependencies)
- ✅ Works for any process, including nix-daemon children
- ✅ Can set per-workload profiles dynamically

**Implementation Idea**:
```bash
# Instead of stopping mining during builds, reduce resources
apply_builds_profile() {
    # Reduce mining to 10% CPU instead of pausing
    systemctl set-property xmrig.service CPUQuota="10%" --runtime
    systemctl set-property lolminer-nvidia.service CPUQuota="10%" --runtime
}

apply_gaming_profile() {
    # Reduce mining to 25% CPU during gaming
    systemctl set-property xmrig.service CPUQuota="25%" --runtime
    systemctl set-property lolminer-nvidia.service CPUQuota="50%" --runtime  # GPU still needs some CPU
}
```

**Sources**:
- [NixOS Manual - Control Groups](https://nixos.org/manual/nixos/unstable/index.html#sec-control-groups)
- [systemd.resource-control(5)](https://www.freedesktop.org/software/systemd/man/systemd.resource-control.html)

---

### 2. **Prometheus-Based Monitoring Approach**

**Key Insight**: Use metrics-based detection instead of process-based detection.

**Features Discovered**:
```promql
# CPU usage percentage
100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Memory usage ratio
(node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes

# High CPU detection (>80% sustained)
instance:node_cpu:usage > 80
```

**How This Could Work**:
1. Run Prometheus node_exporter on all hosts
2. Query CPU usage metrics from compute-workload-monitor
3. Detect high CPU usage from **unknown processes** (catches distributed builds)
4. Trigger mining pause based on metrics, not process names

**Advantages**:
- ✅ Catches distributed build workers (nix-daemon children show as high CPU)
- ✅ Language-agnostic (works for any compiler)
- ✅ Can detect other high-CPU workloads (rendering, encoding, etc.)
- ✅ Already in use for monitoring (you have Prometheus)

**Disadvantages**:
- ❌ Adds dependency (node_exporter + Prometheus)
- ❌ More complex (need to query metrics, not just pgrep)
- ❌ Delay in detection (metrics scraped every 15s by default)
- ❌ False positives (any high CPU process triggers pause)

**Hybrid Approach**:
```bash
# Use process detection for known workloads + metrics for unknown
get_workload_type() {
    # Check known processes first (fast)
    for proc in "${GAMING_PROCESSES[@]}" "${AI_PROCESSES[@]}" "${BUILD_PROCESSES[@]}"; do
        if check_process_running "$proc"; then
            echo "$proc"
            return
        fi
    done

    # Fall back to metrics-based detection for unknown workloads
    CPU_USAGE=$(curl -s http://localhost:9100/metrics | \
        grep 'node_cpu_seconds_total{mode="idle"}' | \
        awk '{sum+=$2; count++} END {print 100 - (sum/count)}')

    if (( $(echo "$CPU_USAGE > 80" | bc -l) )); then
        echo "high-cpu-unknown"
    fi
}
```

**Sources**:
- [Prometheus Documentation](https://context7.com/prometheus/docs/llms.txt)
- [Node Exporter Setup](https://github.com/prometheus/node_exporter)

---

### 3. **NixOS Distributed Builds Architecture**

**Key Discovery**: How distributed builds actually work.

**Architecture**:
```
Coordinator (Zephyr)          Worker (Nexus)
    |                               |
    |-- nix-build .                |
    |                               |
    |-- ssh ---> nix-daemon -------->|-- nix-daemon child (gcc)
    |                               |
    |--[build job]------------------>|-- [build job]
```

**Critical Insight**:
- The **coordinator** runs `nix-build` process → We can detect this ✅
- The **worker** runs `nix-daemon` → spawns build children → We can't detect this ❌

**Why Worker Detection Fails**:
```bash
# On coordinator (Zephyr):
$ pgrep -f nix-build
12345  # ← We can detect this

# On worker (Nexus):
$ pgrep -f nix-build
# (no results)  # ← nix-daemon receives build via SSH, doesn't run nix-build

# What actually runs on worker:
$ pgrep -f nix-daemon
23456  # ← Always running, not a good signal

$ pgrep -f gcc
# Might appear, but too late (after detection needed)
```

**Alternative Detection Methods**:

1. **Detect SSH connections from coordinator**:
```bash
# Monitor for SSH connections from known build coordinators
check_incoming_build() {
    if ss -tnp | grep -q "ESTAB .*:.* zephyr.*:22-.*ssh"; then
        # Build job incoming from zephyr
        return 0
    fi
    return 1
}
```

2. **Detect nix-daemon CPU usage**:
```bash
# nix-daemon usually idle, high CPU = build active
check_nix_daemon_build() {
    NIX_CPU=$(ps -p $(pgrep nix-daemon | head -1) -o %cpu | tail -1)
    if (( $(echo "$NIX_CPU > 50" | bc -l) )); then
        return 0  # Build likely active
    fi
    return 1
}
```

3. **Use systemd resource profiles for nix-daemon**:
```nix
# Give nix-daemon high CPUWeight when builds active
systemd.services.nix-daemon.serviceConfig.CPUWeight = 2048;  # High priority
systemd.services.xmrig.serviceConfig.CPUWeight = 50;      # Low priority
# Let systemd scheduler handle it
```

**Sources**:
- [NixOS Manual - Distributed Builds](https://nixos.org/manual/nix/stable/advanced-topics/distributed-builds.html)

---

### 4. **Mining Management Tools**

**Tools Discovered**:

#### A. **Prometheus Mining Exporter**
```bash
# Exposes mining metrics for Prometheus monitoring
- Hashrate per GPU
- Power consumption
- Temperature
- Shares (accepted/rejected)
- HTTP API polling

# Similar to your existing mining-exporter.nix
```

#### B. **MinerWrangler**
```bash
# Headless mining management
- Bash scripts for mining control
- Driver management (NVIDIA)
- Overclocking support
- No advanced pause/resume features
```

**Key Finding**: No existing tools implement automatic build detection and mining pause. This is a novel approach.

---

## Recommended Improvements

### Priority 1: Use Systemd Resource Control (CPUQuota)

**Why**: Solves the worker detection problem by letting systemd handle it.

**Implementation**:
```bash
apply_builds_profile() {
    echo "=== Applying BUILDS profile (cgroups resource control) ==="

    # Reduce mining to minimal CPU (10% instead of 0%)
    systemctl set-property xmrig.service CPUQuota="10%" --runtime
    systemctl set-property lolminer-nvidia.service CPUQuota="10%" --runtime
    systemctl set-property lolminer-amd.service CPUQuota="10%" --runtime

    # Ensure nix-daemon gets priority
    systemctl set-property nix-daemon.service CPUWeight=2048 --runtime

    echo "Mining reduced to 10% CPU, builds get priority"
}

apply_gaming_profile() {
    echo "=== Applying GAMING profile (cgroups resource control) ==="

    # Moderate reduction for gaming
    systemctl set-property xmrig.service CPUQuota="25%" --runtime  # More CPU for game
    systemctl set-property lolminer-nvidia.service CPUQuota="0%" --runtime  # Pause GPU
    systemctl set-property lolminer-amd.service CPUQuota="0%" --runtime
}
```

**Advantages**:
- ✅ No process restarts (taskset/xmrig restart)
- ✅ Works for distributed build workers (systemd handles it)
- ✅ Still allows some mining revenue during builds
- ✅ Dynamic, per-workload tuning

---

### Priority 2: Add nix-daemon Detection

**Why**: Catches distributed builds on workers.

**Implementation**:
```bash
BUILD_PROCESSES=("nixos-rebuild" "colmena" "nix-build" "gcc" "clang" "cargo build" "make" "cmake" "ninja")

check_incoming_build_job() {
    # Detect SSH connections from known coordinators
    local coordinators=("zephyr" "nexus")
    for coord in "${coordinators[@]}"; do
        if ss -tnp 2>/dev/null | grep -q "ESTAB .*${coord}.*ssh"; then
            # Check if nix-daemon is using significant CPU
            local nix_pid=$(pgrep -o nix-daemon | head -1)
            if [ -n "$nix_pid" ]; then
                local nix_cpu=$(ps -p "$nix_pid" -o %cpu | tail -1)
                if (( $(echo "$nix_cpu > 30" | bc -l) 2>/dev/null)); then
                    log "Detected incoming build from $coord (nix-daemon CPU: ${nix_cpu}%)"
                    return 0
                fi
            fi
        fi
    done
    return 1
}

get_workload_type() {
    # Existing process detection
    for proc in "${GAMING_PROCESSES[@]}"; do
        if check_process_running "$proc"; then
            echo "gaming"
            return
        fi
    done

    # NEW: Check for incoming distributed build jobs
    if check_incoming_build_job; then
        echo "builds"
        return
    fi

    # ... rest of existing logic
}
```

---

### Priority 3: Hybrid Approach (Process + Metrics)

**Why**: Best of both worlds - fast process detection + fallback metrics.

**Implementation**:
```bash
# Fast path: Process detection (0.1s)
if check_process_running "nixos-rebuild"; then
    echo "builds"
    return
fi

# Slow path: Metrics detection (1s, for unknown workloads)
if check_metrics_build_detection; then
    echo "builds"
    return
fi
```

---

## Comparison: Current vs. Recommended Approaches

| Approach | Worker Detection | Process Restarts | Granularity | Complexity |
|----------|-----------------|------------------|-------------|------------|
| **Current** (pgrep + systemctl) | ❌ No | ✅ Yes (stop/start) | Binary (on/off) | Low |
| **Systemd CPUQuota** | ✅ Yes (indirect) | ❌ No | Percentage (0-100%) | Low |
| **Metrics-based** | ✅ Yes | ❌ No | Percentage | Medium |
| **Hybrid** | ✅ Yes | ❌ No | Percentage + Binary | Medium |

---

## Implementation Roadmap

### Phase 1: Quick Win (1-2 hours)
1. Replace `systemctl stop` with `systemctl set-property ... CPUQuota="10%"`
2. Test on single host first
3. Verify mining pauses during builds
4. Check if worker detection works (nix-daemon CPU quota)

### Phase 2: Worker Detection (2-3 hours)
1. Add `check_incoming_build_job()` function
2. Monitor SSH connections + nix-daemon CPU
3. Test distributed builds (zephyr → nexus)
4. Verify worker mining pause

### Phase 3: Metrics Fallback (Optional, 3-4 hours)
1. Install node_exporter if not present
2. Add metrics-based detection
3. Test with unknown high-CPU processes
4. Tune thresholds

---

## Sources

- [NixOS Manual - Distributed Builds](https://nixos.org/manual/nix/stable/advanced-topics/distributed-builds.html)
- [NixOS Manual - Control Groups](https://nixos.org/manual/nixos/unstable/index.html#sec-control-groups)
- [systemd.resource-control(5)](https://www.freedesktop.org/software/systemd/man/systemd.resource-control.html)
- [Systemd CPUWeight/CPUQuota Docs](https://context7.com/systemd/systemd/llms.txt)
- [Prometheus Monitoring](https://context7.com/prometheus/docs/llms.txt)
- [Node Exporter](https://github.com/prometheus/node_exporter)
- [Prometheus Mining Exporter](https://github.com/nouveau-nvc0/prometheus-mining)
- [MinerWrangler](https://github.com/nekrutnikolai/minerwrangler)

---

**Conclusion**: Systemd resource control (CPUQuota/CPUWeight) is the most promising approach - it's simpler, more reliable, and solves the worker detection problem by letting the kernel scheduler handle it.
