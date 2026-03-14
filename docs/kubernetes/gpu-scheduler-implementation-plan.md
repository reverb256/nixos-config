# GPU Scheduler Coordination - Implementation Plan

**Status:** Phase 1 partially implemented, needs node filtering and resume tracking
**Estimated Effort:** 20 hours for remaining work
**Priority:** HIGH (enables K8s GPU workload coordination)

---

## Current State Assessment

### Already Implemented ✅

1. **Kubernetes GPU Detection** (`check_kubernetes_gpu_workload()`)
   - kubectl integration working
   - Detects pods with nvidia.com/gpu resources
   - Filters by Running phase

2. **GPU Profile Application** (`apply_kubernetes_gpu_profile()`)
   - Sets power limits and clock speeds for K8s workloads
   - Stops lolminer-nvidia completely
   - Reduces xmrig to 50% CPU

3. **Workload Priority Chain**
   - Gaming > K8s GPU > VRAM Pressure > Builds > Mining > Idle

### Critical Gaps ❌

1. **No Node Filtering**
   - Current implementation checks pods cluster-wide
   - Will pause mining on Zephyr when GPU pod runs on Forge
   - **Impact:** False positives, unnecessary mining pauses

2. **No Resume Tracking**
   - No `/run/compute-workload-monitor/mining-paused-for-k8s` state file
   - Can't distinguish between K8s pause and other pause reasons
   - **Impact:** Resume logic doesn't know K8s was the cause

3. **No Cooldown Period**
   - Could resume mining immediately after pod deletion
   - K8s scheduler might be placing another pod
   - **Impact:** Resume storms, K8s pod startup failures

4. **No GPU Utilization Monitoring**
   - Phase 2 not implemented
   - Can't detect non-mining GPU workloads by utilization
   - **Impact:** Relies solely on K8s API for detection

---

## Implementation Roadmap

### Phase 1.5: Node Filtering (CRITICAL - 1 hour)

**Objective:** Only detect GPU pods on the local node

**File:** `modules/system/compute-workload-monitor.nix`

**Change:**
```bash
check_kubernetes_gpu_workload() {
    # ... existing kubectl availability checks ...

    # NEW: Get current hostname for node filtering
    local node_name=$(hostname)

    # MODIFIED: Add nodeName filter to jsonpath
    local gpu_pods=$(kubectl get pods --all-namespaces \
        -o jsonpath="{range .items[?(@.spec.nodeName==\"$node_name\" && @.spec.containers[*].resources.limits.nvidia\.com/gpu)]}{.metadata.namespace}/{.metadata.name}{\"\\n\"}{end}" \
        2>/dev/null || echo "")

    # ... rest of existing logic ...
}
```

**Testing:**
```bash
# On Zephyr, apply pod to Forge
kubectl apply -f gpu-test-phase1.yaml --field-selector spec.nodeName=forge
# Verify: Mining should NOT pause on Zephyr

# On Zephyr, apply pod locally
kubectl apply -f gpu-test-phase1.yaml --field-selector spec.nodeName=zephyr
# Verify: Mining SHOULD pause on Zephyr
```

**Success Criteria:**
- [ ] GPU pods on other nodes don't trigger local mining pause
- [ ] GPU pods on local node correctly trigger mining pause
- [ ] Logs show node name being used for filtering

---

### Phase 3.5: Resume Tracking (HIGH - 2 hours)

**Objective:** Track that mining was paused for K8s, implement safe resume

**File:** `modules/system/compute-workload-monitor.nix`

**Changes:**

1. **Add state tracking directory:**
```bash
# State file for tracking K8s pause reason
K8S_PAUSE_STATE_FILE="/run/compute-workload-monitor/mining-paused-for-k8s"
COOLDOWN_SECONDS=60
```

2. **Modify `apply_kubernetes_gpu_profile()`:**
```bash
apply_kubernetes_gpu_profile() {
    echo "=== Applying GPU KUBERNETES GPU WORKLOAD profile ==="

    # ... existing GPU configuration ...

    # NEW: Track that we paused mining for K8s
    echo "$(date +%s)" > "$K8S_PAUSE_STATE_FILE"
    log "Created K8s pause state file: $K8S_PAUSE_STATE_FILE"

    # ... existing mining pause logic ...
}
```

3. **Add `check_kubernetes_cooldown()`:**
```bash
check_kubernetes_cooldown() {
    if [ ! -f "$K8S_PAUSE_STATE_FILE" ]; then
        return 1  # No cooldown needed
    fi

    local pause_time=$(cat "$K8S_PAUSE_STATE_FILE")
    local current_time=$(date +%s)
    local elapsed=$((current_time - pause_time))

    if [ "$elapsed" -lt "$COOLDOWN_SECONDS" ]; then
        local remaining=$((COOLDOWN_SECONDS - elapsed))
        log "K8s cooldown active: ${remaining}s remaining"
        return 0  # Still in cooldown
    fi

    # Cooldown expired, clean up
    rm -f "$K8S_PAUSE_STATE_FILE"
    log "K8s cooldown expired, safe to resume"
    return 1  # Cooldown over
}
```

4. **Add `resume_mining_if_safe()`:**
```bash
resume_mining_if_safe() {
    # Only resume if we paused for K8s
    if [ ! -f "$K8S_PAUSE_STATE_FILE" ]; then
        return 0  # Not paused for K8s, nothing to do
    fi

    # Check if still in cooldown
    if check_kubernetes_cooldown; then
        return 0  # Still cooling down
    fi

    # Check for new GPU pods
    if check_kubernetes_gpu_workload; then
        log "New K8s GPU pods detected, keeping mining paused"
        echo "$(date +%s)" > "$K8S_PAUSE_STATE_FILE"  # Reset timer
        return 0
    fi

    # Safe to resume
    log "Resuming mining after K8s workload completion"
    rm -f "$K8S_PAUSE_STATE_FILE"

    if systemctl is-active --quiet lolminer-nvidia; then
        # Already running, just reset CPU quota
        systemctl set-property lolminer-nvidia.service CPUQuota="100%" --runtime
    else
        # Was stopped, restart it
        systemctl start lolminer-nvidia
    fi

    # Reset xmrig to 100%
    if systemctl is-active --quiet xmrig; then
        systemctl set-property xmrig.service CPUQuota="100%" --runtime
    fi
}
```

5. **Integrate into main loop:**
```bash
# In main monitoring loop
while true; do
    new_workload=$(get_workload_type)

    # NEW: Check for resume opportunity when leaving kubernetes-gpu state
    if [ "$CURRENT_WORKLOAD" = "kubernetes-gpu" ] && [ "$new_workload" != "kubernetes-gpu" ]; then
        resume_mining_if_safe
    fi

    # ... existing workload change logic ...
done
```

**Success Criteria:**
- [ ] State file created when mining paused for K8s
- [ ] 60-second cooldown enforced after pod deletion
- [ ] Mining resumes automatically after cooldown
- [ ] New GPU pods during cooldown reset timer
- [ ] Logs clearly show cooldown state transitions

---

### Phase 2: GPU Utilization Monitoring (MEDIUM - 4 hours)

**Objective:** Detect GPU workloads by utilization, not just K8s API

**File:** `modules/system/compute-workload-monitor.nix`

**Implementation:**

```bash
# Add to top of script
GPU_UTILIZATION_THRESHOLD=50  # Percent
GPU_POLL_INTERVAL=30  # Seconds (don't poll too frequently)
LAST_GPU_POLL_TIME=0
CACHED_GPU_UTILIZATION=0

check_gpu_utilization() {
    local gpu_id="$1"

    # Check cache
    local current_time=$(date +%s)
    if [ $((current_time - LAST_GPU_POLL_TIME)) -lt "$GPU_POLL_INTERVAL" ]; then
        echo "$CACHED_GPU_UTILIZATION"
        return
    fi

    # Poll nvidia-smi
    local utilization=$(nvidia-smi -i "$gpu_id" --query-gpu=utilization.gpu \
        --format=csv,noheader,nounits 2>/dev/null || echo "0")

    # Update cache
    CACHED_GPU_UTILIZATION="$utilization"
    LAST_GPU_POLL_TIME="$current_time"

    echo "$utilization"
}

check_external_gpu_workload() {
    local gpus=$(get_gpu_list)

    for gpu_id in $gpus; do
        local util=$(check_gpu_utilization "$gpu_id")

        # GPU 0 (not mining) - any utilization is external
        if [ "$gpu_id" = "0" ] && [ "$util" -gt "$GPU_UTILIZATION_THRESHOLD" ]; then
            log "External GPU workload detected on GPU 0: ${util}%"
            return 0
        fi

        # GPU 1 (mining) - >110% indicates additional workload
        if [ "$gpu_id" = "1" ] && [ "$util" -gt 110 ]; then
            log "Additional GPU workload detected on GPU 1: ${util}%"
            return 0
        fi
    done

    return 1
}
```

**Integration into priority chain:**
```bash
get_workload_type() {
    # ... existing checks ...

    # NEW: Check for external GPU utilization
    if check_external_gpu_workload; then
        echo "external-gpu"
        return
    fi

    # ... rest of checks ...
}
```

**Success Criteria:**
- [ ] GPU utilization polled every 30 seconds (not every 10)
- [ ] External workloads on GPU 0 detected correctly
- [ ] Additional workloads on GPU 1 detected correctly
- [ ] No false positives from mining-only workload
- [ ] CPU overhead < 1%

---

### Phase 4: GPU Balancing (MEDIUM - 2 hours)

**Objective:** Move mining to GPU 0, leave GPU 1 for K8s

**Option A: Quick Win (recommended)**

**File:** `modules/mining/mining.nix`

**Change:**
```nix
lolminer.nvidia.devices = mkOption {
  type = types.str;
  default = "0";  # Changed from "1" - mine on 3060 Ti
  description = "NVIDIA GPU device IDs for mining (comma-separated)";
};
```

**Benefits:**
- GPU 1 (3090, more powerful) available for K8s workloads
- Simple configuration change
- No runtime coordination needed

**Testing:**
```bash
# After rebuild
nvidia-smi  # Verify lolminer using GPU 0
kubectl apply -f gpu-test-phase1.yaml  # Should schedule to GPU 1
```

**Option B: Time-Sharing (future enhancement)**

**Approach:** Both GPUs mine at reduced rate when idle, pause when K8s needs them

**Implementation:** Requires dynamic device configuration in lolminer (may not support runtime changes)

**Recommendation:** Implement Option A first, defer Option B

---

### Phase 6: Forge GPU Registration (LOW - 6-8 hours)

**Objective:** Diagnose and fix RTX 4060 GPU registration failure

**Diagnostic Steps:**

```bash
# 1. Check nvidia-smi on Forge
ssh forge "nvidia-smi --query-gpu=index,name,driver_version,cuda_version --format=csv"

# 2. Check CDI files
ssh forge "ls -la /var/run/nvidia-cdi/"

# 3. Check device plugin logs
ssh forge "sudo journalctl -u nvidia-device-plugin-daemonset -n 100 --no-pager"

# 4. Compare driver versions
for node in zephyr forge nexus; do
    echo "$node:"
    ssh "$node" "nvidia-smi --query-gpu=driver_version --format=csv,noheader"
done

# 5. Generate diagnostic report
# Document findings in docs/forge-gpu-registration-diagnostic-report.md
```

**Potential Fixes:**
1. Update device plugin version for Ada Lovelace support
2. Match driver versions across nodes
3. Adjust CDI configuration for RTX 40xx

**Success Criteria:**
- [ ] Diagnostic report completed
- [ ] Root cause identified
- [ ] Fix implemented and tested
- [ ] Forge shows 2 GPUs allocatable
- [ ] GPU workload successfully scheduled to Forge

---

## Testing Strategy

### Unit Tests

```bash
# Test node filtering
check_kubernetes_gpu_workload() {
    # Mock kubectl output
    # Verify correct filtering by hostname
}

# Test cooldown logic
check_kubernetes_cooldown() {
    # Create old state file (> 60s)
    # Verify returns false

    # Create new state file (< 60s)
    # Verify returns true
}
```

### Integration Tests

```bash
# Test 1: Node-specific detection
# 1. On Zephyr, start mining
# 2. Schedule GPU pod to Forge
# 3. Verify: Mining continues on Zephyr

# Test 2: Pause/resume cycle
# 1. Schedule GPU pod to Zephyr
# 2. Verify: Mining pauses
# 3. Delete pod
# 4. Wait 70 seconds
# 5. Verify: Mining resumes

# Test 3: Cooldown prevents rapid cycling
# 1. Schedule GPU pod to Zephyr
# 2. Delete pod after 5 seconds
# 3. Immediately schedule new pod
# 4. Verify: Mining stays paused through cooldown

# Test 4: GPU utilization detection
# 1. Start non-K8s GPU workload (e.g., ollama)
# 2. Verify: External GPU workload detected
# 3. Verify: Mining pauses

# Test 5: GPU balancing
# 1. Configure mining on GPU 0
# 2. Schedule K8s GPU pod
# 3. Verify: Pod uses GPU 1
# 4. Verify: Mining unaffected on GPU 0
```

### End-to-End Test

```bash
# Full scenario: K8s training job with mining
# 1. Start mining on both GPUs (if applicable)
# 2. Submit K8s training job requesting GPU
# 3. Verify: Mining pauses on affected GPU
# 4. Training completes
# 5. Wait 60 seconds
# 6. Verify: Mining resumes
# 7. Check: No resume storms, no startup failures
```

---

## Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| K8s GPU pod detection accuracy | 100% | False positives = 0 |
| Mining pause latency | < 10s | Time from pod create to mining stop |
| Mining resume latency | 60-70s | Pod delete + cooldown |
| GPU utilization during K8s workload | 0% mining | No contention |
| Mining revenue impact | < 5% | Time mining vs. baseline |
| CPU overhead | < 1% | compute-workload-monitor CPU % |
| Resume storms | 0 | Count of rapid pause/resume cycles |

---

## Rollback Plan

If issues occur:

1. **Disable K8s detection:**
   ```bash
   # Comment out check_kubernetes_gpu_workload in get_workload_type()
   just switch
   ```

2. **Restore mining configuration:**
   ```bash
   # Set lolminer.nvidia.devices back to "1"
   git checkout modules/mining/mining.nix
   just switch
   ```

3. **Manually manage mining:**
   ```bash
   # Stop mining manually before K8s workloads
   sudo systemctl stop lolminer-nvidia

   # Start mining manually when done
   sudo systemctl start lolminer-nvidia
   ```

---

## Next Steps

1. ✅ **Review this plan** - Approve approach and priorities
2. ⏳ **Implement Phase 1.5** - Node filtering (1 hour)
3. ⏳ **Implement Phase 3.5** - Resume tracking (2 hours)
4. ⏳ **Test pause/resume cycle** - End-to-end verification
5. ⏳ **Implement Phase 2** - GPU utilization monitoring (4 hours)
6. ⏳ **Implement Phase 4** - GPU balancing (2 hours)
7. ⏳ **Phase 6 diagnostics** - Forge GPU registration (as needed)

**Total Estimated:** 9-11 hours for core functionality (Phases 1.5, 3.5, 2, 4)

---

**Document Version:** 1.0
**Created:** 2026-03-14
**Status:** Ready for Implementation
