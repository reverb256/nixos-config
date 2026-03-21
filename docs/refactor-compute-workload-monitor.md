# Compute Workload Monitor Refactoring Plan

## Current State Analysis

**File:** `modules/system/compute-workload-monitor.nix` (1665 lines)

### Mixed Responsibilities

1. **❌ REDUNDANT - Systemd Service Management** (~400 lines)
   - `pause_xmrig()`, `resume_xmrig()` - systemctl stop/start for xmrig-always, xmrig-flexible
   - `manage_lolminer_for_gaming()` - systemctl stop/start for lolminer-nvidia
   - All systemd mining service control (lines 1046-1089, 286-292)

2. **⚠️ PARTIALLY REDUNDANT - Manual K8s Scaling** (~90 lines)
   - `scale_gaming_placeholder()` - kubectl scale deployment
   - `scale_nvidia_miners()` - kubectl scale deployment
   - `update_k8s_gaming_state()` - kubectl patch configmap
   - **Issue:** Volcano priority preemption replaces manual scaling

3. **✅ KEEP - Workload Detection** (~600 lines)
   - `detect_gaming_gamemode()` - GameMode daemon detection
   - `detect_gpu_pattern()` - GPU utilization fallback
   - `check_psi_cpu_pressure()` - PSI-based build detection
   - `check_psi_memory_pressure()` - Memory pressure detection
   - `check_psi_io_pressure()` - I/O pressure detection
   - `check_kubernetes_gpu_workload()` - K8s GPU pod detection
   - `get_workload_type()` - Returns: ai, kubernetes-gpu, builds, mining, idle

4. **✅ KEEP - GPU Profile Management** (~500 lines)
   - `apply_gaming_profile()` - nvidia-smi clock/power limits for gaming
   - `apply_ai_profile()` - nvidia-smi for AI inference
   - `apply_kubernetes_gpu_profile()` - nvidia-smi for K8s GPU workloads
   - `apply_builds_profile()` - nvidia-smi for builds
   - `apply_mining_profile()` - nvidia-smi for mining efficiency
   - **Why:** Host-level functionality, cannot be moved to K8s

5. **✅ KEEP - Gaming State Tracking** (~150 lines)
   - `read_gaming_state()`, `write_gaming_state()` - State persistence
   - `export_gaming_metric()` - Prometheus node_exporter metrics
   - Hysteresis logic (3-check countdown before resume)

## Problem Statement

User Request: "compute-workload-monitor i think we need to completely remove because all of this scheduling logic needs to be k8s native and we are using volcano now"

### Current Issues

1. **Duplicate Scheduling Logic**
   - compute-workload-monitor: Pauses systemd services, scales K8s deployments
   - Volcano scheduler: Priority-based preemption (mining-low: 100, gaming-high: 1000)
   - Both trying to control same resources → conflicts

2. **Systemd Mining Services No Longer Used**
   - xmrig systemd services replaced by K8s deployments (xmrig-zephyr, xmrig-nexus)
   - lolminer systemd being migrated to K8s (gpu-miner-forge-*)
   - Remaining systemd control is redundant

3. **K8s Integration Outdated**
   - Manual kubectl scale commands (lines 411, 440)
   - ConfigMap patching (line 379) - YuniKorn-era (replaced by Volcano)
   - Not using Volcano's native preemption capabilities

## Refactoring Strategy

### Phase 1: Split Into Focused Modules

```
compute-workload-monitor.nix (1665 lines)
    ↓
├── gaming-detection.nix (~300 lines)
│   ├── GameMode detection (gamemoded -s)
│   ├── GPU pattern fallback (nvidia-smi)
│   ├── State tracking with hysteresis
│   └── Prometheus metric export
│
├── gpu-profile-manager.nix (~600 lines)
│   ├── apply_gaming_profile()
│   ├── apply_ai_profile()
│   ├── apply_kubernetes_gpu_profile()
│   ├── apply_builds_profile()
│   └── apply_mining_profile()
│
└── mining-coordinator.nix (~400 lines) [NEW]
    ├── Detect K8s mining pod state (kubectl get pods)
    ├── Detect gaming state (read from gaming-detection module)
    ├── Apply GPU profiles based on workload
    └── NO systemd service control (K8s-native only)
```

### Phase 2: Remove Redundant Code

**Delete Entirely:**
- All `pause_xmrig()`, `resume_xmrig()` functions (lines 1046-1071)
- All `pause_lolminer_for_gaming()` logic (lines 264-348)
- All `systemctl stop/start` calls for mining services
- All `kubectl scale` calls (replaced by Volcano preemption)
- MINING_SERVICES array (line 65)

**Keep But Refactor:**
- Workload detection functions (gaming, builds, K8s GPU)
- GPU profile application (nvidia-smi commands)
- Gaming state tracking and Prometheus export
- PSI-based build detection (kernel-level, very reliable)

### Phase 3: K8s-Native Integration

**Volcano Scheduler Handles:**
- Priority-based preemption (gaming-high vs mining-low)
- Gang scheduling for GPU pods
- Resource quota enforcement
- Pod eviction and rescheduling

**Host-Level Module Handles:**
- Workload detection (GameMode, PSI, kubectl get pods)
- GPU power/clock limits (nvidia-smi -pl, -lgc, -lmc)
- Prometheus metrics (node_exporter textfile collector)
- GPU profile selection based on detected workload

**Integration Point:**
```nix
# mining-coordinator.nix
main_loop() {
    detected_workload=$(get_workload_type)  # gaming, ai, kubernetes-gpu, builds, mining

    # Apply host-level GPU profile
    apply_profile "$detected_workload"

    # Volcano handles K8s pod preemption automatically
    # No manual kubectl scale needed
}
```

## Detailed Module Breakdown

### Module 1: gaming-detection.nix

**Purpose:** Pure gaming detection and state tracking

**Functions:**
- `detect_gaming_gamemode()` - GameMode daemon query
- `detect_gpu_pattern()` - GPU utilization fallback
- `detect_gaming()` - Unified detection (GameMode primary, GPU fallback)
- `read_gaming_state()`, `write_gaming_state()` - State persistence
- `export_gaming_metric()` - Prometheus node_exporter metric

**Outputs:**
- State file: `/run/gaming-detection/gaming_state`
- Prometheus metric: `/var/lib/node_exporter/textfile_collector/gaming.prom`
- Log file: `/var/log/gaming-detection.log`

**Size:** ~300 lines

### Module 2: gpu-profile-manager.nix

**Purpose:** Host-level GPU power/clock management

**Functions:**
- `apply_gaming_profile()` - Max performance (350W 3090, 2050 MHz)
- `apply_ai_profile()` - Balanced (300W 3090, 1900 MHz)
- `apply_kubernetes_gpu_profile()` - Balanced for containers (280W 3090, 1800 MHz)
- `apply_builds_profile()` - Reduce GPU mining heat on nexus
- `apply_mining_profile()` - Efficiency optimized (250W 3090, 1750 MHz)

**GPU-Specific Settings:**
```nix
case "$gpu_name" in
    *"3060"*)
        # 3060 Ti: Tight power budget (not primary gaming GPU)
        nvidia-smi -i "$gpu_id" -pl 130  # Mining
        nvidia-smi -i "$gpu_id" -pl 110  # AI
        ;;
    *"3090"*)
        # 3090: Liquid cooled, can push harder
        nvidia-smi -i "$gpu_id" -pl 250  # Mining
        nvidia-smi -i "$gpu_id" -pl 300  # AI
        nvidia-smi -i "$gpu_id" -pl 350  # Gaming
        ;;
esac
```

**Size:** ~600 lines

### Module 3: mining-coordinator.nix (NEW)

**Purpose:** Coordinate GPU profiles with K8s-native scheduling

**Key Insight:** Does NOT control K8s pods directly. Volcano handles preemption.

**Main Loop:**
```bash
while true; do
    # 1. Detect workload (using gaming-detection module functions)
    gaming_detected=$(detect_gaming)
    k8s_gpu_pods=$(check_kubernetes_gpu_workload)
    build_pressure=$(check_psi_cpu_pressure)

    # 2. Determine workload type
    if [[ "$gaming_detected" == "1" ]]; then
        workload="gaming"
    elif [[ "$k8s_gpu_pods" == "0" ]]; then
        workload="kubernetes-gpu"
    elif [[ "$build_pressure" == "0" ]]; then
        workload="builds"
    else
        workload="mining"
    fi

    # 3. Apply GPU profile (host-level)
    apply_profile "$workload"

    # 4. Volcano automatically preempts K8s mining pods based on priority
    # No kubectl scale needed!

    sleep 10
done
```

**Size:** ~400 lines

## Volcano Scheduler Integration

### Current Setup (Already Working)

**Priority Classes:**
```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: gaming-high
value: 1000
globalDefault: false
description: "High priority for gaming workloads"
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: mining-low
value: 100
globalDefault: false
description: "Low priority for mining workloads"
```

**PodGroups:**
```yaml
apiVersion: scheduling.volcano.sh/v1beta1
kind: PodGroup
metadata:
  name: xmrig-zephyr-group
spec:
  minMember: 1
  minResources:
    cpu: "4"
    memory: "1Gi"
  priorityClassName: mining-low
  queue: mining-queue
```

**Gaming Placeholder (Triggers Preemption):**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gaming-placeholder-volcano
spec:
  template:
    spec:
      schedulerName: volcano
      priorityClassName: gaming-high
      containers:
      - name: pause
        image: gcr.io/google-containers/pause:3.9
        resources:
          limits:
            nvidia.com/gpu: "1"  # Claims GPU to preempt mining
```

**How It Works:**
1. Gaming detected → Scale gaming-placeholder to 1 replica
2. Volcano sees gaming-high (1000) > mining-low (100)
3. Volcano preempts mining pods to free GPU
4. Gaming ends → Scale gaming-placeholder to 0
5. Volcano reschedules mining pods

**No Manual K8s Control Needed!**

## Migration Plan

### Step 1: Create New Modules (Non-Breaking)

```bash
# Create focused modules alongside existing compute-workload-monitor
modules/system/gaming-detection.nix
modules/system/gpu-profile-manager.nix
modules/system/mining-coordinator.nix
```

### Step 2: Update Host Configs (Gradual Migration)

**Zephyr (gaming node):**
```nix
# Disable old module
services.compute-workload-monitor.enable = false;

# Enable new modules
services.gaming-detection.enable = true;
services.gpu-profile-manager.enable = true;
services.mining-coordinator.enable = true;
```

**Forge (mining node):**
```nix
# Keep GPU profile manager for mining optimization
services.gpu-profile-manager.enable = true;

# Gaming detection not needed (no gaming on forge)
```

**Nexus (storage + gaming):**
```nix
# Same as zephyr
services.gaming-detection.enable = true;
services.gpu-profile-manager.enable = true;
```

**Sentry (monitoring):**
```nix
# No GPU management needed (AMD GPU for desktop only)
# Gaming detection optional (for metrics)
```

### Step 3: Validate Functionality

**Test Gaming Preemption:**
```bash
# Start gaming (GameMode activates)
gamemoded -s
# Expected: gaming-placeholder scales to 1, mining pods preempted

# Check mining pods are preempted
kubectl get pods -n mining -l app=gpu-miner-forge
# Expected: 0/Running, Status: Preempted

# Stop gaming
# Expected: gaming-placeholder scales to 0, mining pods resume
```

**Test GPU Profiles:**
```bash
# Trigger gaming detection
# Check GPU power limit
nvidia-smi
# Expected: 350W for 3090 (gaming profile)

# Stop gaming, wait for hysteresis (30 seconds)
# Expected: 250W for 3090 (mining profile)
```

### Step 4: Remove Legacy Module

```bash
# After validation on all hosts
rm modules/system/compute-workload-monitor.nix
# Update modules/default.nix to remove import
```

## Benefits of Refactoring

### 1. **Clear Separation of Concerns**
- Gaming detection: Pure workload detection
- GPU profiles: Host-level hardware management
- Mining coordinator: K8s-aware coordination (no systemd)

### 2. **K8s-Native Scheduling**
- Volcano priority preemption (no manual kubectl scale)
- Declarative PodGroups (YAML, not shell scripts)
- Cluster-wide coordination (same on all nodes)

### 3. **Reduced Complexity**
- 1665 lines → 3 modules (~1300 lines total, but focused)
- Each module has single responsibility
- Easier to test and debug

### 4. **Better Observability**
- Gaming metrics exported to Prometheus
- GPU profile changes logged
- K8s state visible via kubectl/Volcano UI

### 5. **Future Extensibility**
- Easy to add new workload types (VR, ML training)
- GPU profile manager reusable for other services
- Gaming detection usable by non-mining services

## Implementation Checklist

- [ ] Create `modules/system/gaming-detection.nix`
  - [ ] GameMode detection function
  - [ ] GPU pattern fallback
  - [ ] State tracking with hysteresis
  - [ ] Prometheus metric export
  - [ ] Systemd service definition

- [ ] Create `modules/system/gpu-profile-manager.nix`
  - [ ] Gaming profile (max performance)
  - [ ] AI profile (balanced)
  - [ ] K8s GPU profile (container-optimized)
  - [ ] Builds profile (reduce heat)
  - [ ] Mining profile (efficiency)
  - [ ] GPU-specific settings (3060 Ti vs 3090)
  - [ ] Systemd service definition

- [ ] Create `modules/system/mining-coordinator.nix`
  - [ ] Main loop with workload detection
  - [ ] K8s GPU pod detection (kubectl get pods)
  - [ ] Gaming state detection (read from gaming-detection)
  - [ ] GPU profile application (call gpu-profile-manager)
  - [ ] NO systemd service control
  - [ ] NO manual kubectl scale (Volcano handles it)
  - [ ] Systemd service definition

- [ ] Update `modules/default.nix`
  - [ ] Import new modules
  - [ ] Keep compute-workload-monitor for now (gradual migration)

- [ ] Update host configurations
  - [ ] zephyr: Enable all 3 new modules
  - [ ] nexus: Enable all 3 new modules
  - [ ] forge: Enable gpu-profile-manager only
  - [ ] sentry: No GPU management needed

- [ ] Validate on Zephyr (test gaming node)
  - [ ] Gaming detection works
  - [ ] GPU profiles apply correctly
  - [ ] Volcano preempts mining pods
  - [ ] Hysteresis prevents flicker

- [ ] Validate on Forge (test mining node)
  - [ ] GPU profiles apply for mining
  - [ ] No gaming detection (not needed)

- [ ] Validate on Nexus (test storage + gaming)
  - [ ] Same as zephyr

- [ ] Remove legacy module
  - [ ] Delete compute-workload-monitor.nix
  - [ ] Remove from modules/default.nix
  - [ ] Update all host configs

## Estimated Timeline

- **Day 1:** Create gaming-detection.nix + gpu-profile-manager.nix
- **Day 2:** Create mining-coordinator.nix + test on zephyr
- **Day 3:** Validate on forge + nexus
- **Day 4:** Remove legacy module + final validation

**Total:** 4 days (gradual migration, zero downtime)

## Open Questions

1. **GPU Profile Timing:** Should gpu-profile-manager apply profiles immediately on workload change, or wait for hysteresis?
   - **Recommendation:** Apply immediately (GPU profile changes are instant, unlike service start/stop)

2. **K8s Workload Detection:** Should mining-coordinator detect K8s GPU pods directly, or rely on gaming-detection?
   - **Recommendation:** mining-coordinator should call kubectl get pods itself (separation of concerns)

3. **Fallback for Non-K8s:** What if K8s is down but mining needs to run?
   - **Recommendation:** Keep systemd mining as emergency fallback (disabled by default, manual enable only)

4. **Prometheus Metrics:** Should we export GPU profile state to Prometheus?
   - **Recommendation:** Yes, add `gpu_profile` label to gaming metric (e.g., `gaming_active{host="zephyr",gpu_profile="gaming"} 1`)

## Next Steps

**Immediate Actions:**
1. Review this refactoring plan with user
2. Get approval for module split strategy
3. Start implementing gaming-detection.nix (lowest risk)

**Validation Criteria:**
- Gaming detection still works with GameMode
- GPU profiles apply correctly via nvidia-smi
- Volcano preempts mining pods when gaming placeholder scales up
- No systemd mining service management
- No manual kubectl scale commands

**Success Metrics:**
- Reduced code complexity (1665 lines → 3 focused modules)
- K8s-native scheduling (Volcano priority preemption)
- Zero systemd mining service control
- Improved observability (Prometheus metrics)
