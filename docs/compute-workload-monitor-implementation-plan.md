# STATUS: 🟡 ACTIVE IMPLEMENTATION PLAN - IN PROGRESS

# Compute Workload Monitor Refactoring - Implementation Plan

**Objective:** Replace 1665-line compute-workload-monitor.nix with 3 focused modules that use K8s-native Volcano scheduling instead of systemd/manual kubectl control.

**Timeline:** 4 days (gradual migration, zero downtime)

**Success Criteria:**
- ✅ No systemd mining service control
- ✅ No manual kubectl scale commands
- ✅ Volcano priority preemption handles all scheduling
- ✅ GPU profiles still apply correctly
- ✅ Gaming detection still works
- ✅ All validation tests pass

---

## Day 1: Foundation - Gaming Detection Module

**Goal:** Create `gaming-detection.nix` - pure workload detection with zero service control

### Step 1.1: Extract Gaming Detection Functions (2 hours)

**Source:** `compute-workload-monitor.nix` lines 68-198

**Create:** `modules/system/gaming-detection.nix`

```nix
# Extract these functions:
- detect_gaming_gamemode()      # Lines 71-106
- detect_gpu_pattern()          # Lines 111-160
- detect_gaming()               # Lines 165-198
```

**Dependencies:** None (standalone module)

**Validation:**
```bash
# Test GameMode detection
sudo systemctl status gaming-detection
sudo journalctl -u gaming-detection -n 50
# Should see: "GameMode: Gaming detected" or "GameMode: No gaming detected"
```

**Acceptance Criteria:**
- [ ] Module compiles without errors
- [ ] Systemd service starts successfully
- [ ] GameMode detection works (gamemoded -s)
- [ ] GPU fallback detection works (nvidia-smi utilization pattern)
- [ ] Logs show detection method ("gamemode" or "gpu_fallback")

### Step 1.2: Extract State Tracking Functions (1.5 hours)

**Source:** `compute-workload-monitor.nix` lines 203-260

**Add to:** `modules/system/gaming-detection.nix`

```nix
# Extract these functions:
- read_gaming_state()           # Lines 209-217
- write_gaming_state()          # Lines 220-233
- export_gaming_metric()        # Lines 236-260
```

**Dependencies:** Step 1.1 (needs detect_gaming to work)

**Files Created:**
- `/run/gaming-detection/gaming_state` - State file
- `/var/lib/node_exporter/textfile_collector/gaming.prom` - Prometheus metric

**Validation:**
```bash
# Check state file exists
cat /run/gaming-detection/gaming_state
# Should show: GAMING_ACTIVE=0/1, DETECTION_METHOD=...

# Check Prometheus metric
cat /var/lib/node_exporter/textfile_collector/gaming.prom
# Should show: gaming_active{host="zephyr",detection_method="gamemode"} 0
```

**Acceptance Criteria:**
- [ ] State file created in correct location
- [ ] State persists across service restarts
- [ ] Prometheus metric exported correctly
- [ ] Metric includes host and detection_method labels
- [ ] Metric value updates when gaming state changes

### Step 1.3: Add Hysteresis Logic (2 hours)

**Source:** `compute-workload-monitor.nix` lines 262-348 (EXCLUDING manage_lolminer_for_gaming)

**Add to:** `modules/system/gaming-detection.nix`

```nix
# Create simplified hysteresis function:
manage_gaming_hysteresis() {
    # From manage_lolminer_for_gaming() BUT:
    # - Remove all systemctl stop/start calls
    # - Remove all kubectl scale calls
    # - Keep only state tracking logic
    # - Keep hysteresis countdown (3 checks before resume)
}
```

**Key Changes from Original:**
```bash
# REMOVE these lines:
- systemctl stop lolminer-nvidia     # Line 286
- systemctl start lolminer-nvidia    # Line 324
- kubectl scale deployment ...       # Lines 411, 416, 440

# KEEP these lines:
- write_gaming_state()              # State tracking
- hysteresis countdown logic        # Lines 314-336
```

**Dependencies:** Step 1.2 (needs state tracking functions)

**Validation:**
```bash
# Simulate gaming start/stop
# Start gaming:
gamemoded -s  # or run actual game
# Check hysteresis countdown in logs:
sudo journalctl -u gaming-detection -f
# Should see: "Gaming STARTED", then "Gaming STOPPED - starting hysteresis countdown (3 checks)"
```

**Acceptance Criteria:**
- [ ] Hysteresis countdown works (3 checks)
- [ ] State transitions correctly: 0 → 1 (immediate), 1 → 0 (3-check delay)
- [ ] No systemctl calls in logs
- [ ] No kubectl calls in logs

### Step 1.4: Create Systemd Service Definition (1 hour)

**Add to:** `modules/system/gaming-detection.nix`

```nix
config = lib.mkIf cfg.enable {
  systemd.services.gaming-detection = {
    description = "Gaming detection with GameMode and GPU fallback";
    wantedBy = ["multi-user.target"];
    after = ["network.target"];

    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.writeShellScriptBin "gaming-detection" ''...''}/bin/gaming-detection";
      Restart = "on-failure";
      RestartSec = "10s";
    };
  };

  systemd.tmpfiles.rules = [
    "d /run/gaming-detection 0755 root root - -"
  ];
};
```

**Dependencies:** Step 1.3 (complete script before wrapping in service)

**Validation:**
```bash
# Enable and start service
sudo systemctl daemon-reload
sudo systemctl enable gaming-detection
sudo systemctl start gaming-detection

# Check status
sudo systemctl status gaming-detection
# Should be: active (running)
```

**Acceptance Criteria:**
- [ ] Service enabled successfully
- [ ] Service starts without errors
- [ ] Service runs continuously (not crashing)
- [ ] Logs show detection loop running

### Step 1.5: Module Configuration Options (30 minutes)

**Add to:** `modules/system/gaming-detection.nix`

```nix
options.services.gaming-detection = {
  enable = lib.mkEnableOption "Gaming detection with GameMode and GPU fallback";

  checkInterval = lib.mkOption {
    type = lib.types.int;
    default = 10;
    description = "Check interval in seconds";
  };

  logFile = lib.mkOption {
    type = lib.types.str;
    default = "/var/log/gaming-detection.log";
    description = "Path to log file";
  };

  hysteresisCycles = lib.mkOption {
    type = lib.types.int;
    default = 3;
    description = "Number of consecutive low readings before resume";
  };
};
```

**Dependencies:** Step 1.4 (service definition needs options)

**Validation:**
```bash
# Test in host config (hosts/zephyr/configuration.nix):
services.gaming-detection = {
  enable = true;
  checkInterval = 5;  # Faster for testing
  hysteresisCycles = 2;  # Shorter for testing
};

# Rebuild and test
sudo nixos-rebuild test
```

**Acceptance Criteria:**
- [ ] Options are configurable in host config
- [ ] Default values work without explicit config
- [ ] Custom values override defaults correctly

### Day 1 Complete Checklist

- [ ] gaming-detection.nix created (~300 lines)
- [ ] No systemd mining service control
- [ ] No kubectl commands
- [ ] GameMode detection works
- [ ] GPU fallback detection works
- [ ] State tracking with hysteresis works
- [ ] Prometheus metrics exported
- [ ] Service runs continuously
- [ ] Tested on zephyr

**Deliverable:** `modules/system/gaming-detection.nix` (fully functional, tested)

---

## Day 2: GPU Profile Manager Module

**Goal:** Create `gpu-profile-manager.nix` - host-level GPU power/clock management

### Step 2.1: Extract GPU Profile Functions (3 hours)

**Source:** `compute-workload-monitor.nix` lines 1100-1564

**Create:** `modules/system/gpu-profile-manager.nix`

```nix
# Extract these functions:
- get_gpu_list()                # Lines 964-967
- get_gpu_name()                # Lines 969-973
- nvidia_safe()                 # Lines 975-978
- apply_gaming_profile()        # Lines 1165-1223
- apply_ai_profile()            # Lines 1225-1285
- apply_kubernetes_gpu_profile() # Lines 1102-1163
- apply_builds_profile()        # Lines 1287-1344
- apply_mining_profile()        # Lines 1346-1434
- apply_idle_profile()          # Lines 1436-1476
- apply_vram_pressure_profile() # Lines 1478-1532
```

**Dependencies:** None (standalone module, but needs nvidia-smi)

**Key Refactoring:**
- Remove all systemd service control calls
- Remove all kubectl calls
- Keep only nvidia-smi commands

**Example - What to Remove:**
```bash
# From apply_kubernetes_gpu_profile() - REMOVE:
if systemctl is-active --quiet lolminer-nvidia; then
    systemctl stop lolminer-nvidia  # DELETE THIS
fi

# From apply_gaming_profile() - REMOVE:
systemctl set-property xmrig-always.service CPUQuota="25%" --runtime  # DELETE THIS
```

**Validation:**
```bash
# Test each profile manually
sudo nixos-rebuild test
sudo systemctl restart gpu-profile-manager

# Trigger gaming profile (start game)
# Check GPU settings:
nvidia-smi
# Should see: 350W for 3090, 2050 MHz GPU clock

# Trigger mining profile (stop game, wait for hysteresis)
nvidia-smi
# Should see: 250W for 3090, 1750 MHz GPU clock
```

**Acceptance Criteria:**
- [ ] All 6 profiles defined (gaming, ai, kubernetes-gpu, builds, mining, idle)
- [ ] GPU-specific settings correct (3060 Ti vs 3090)
- [ ] No systemctl calls in any profile
- [ ] No kubectl calls in any profile
- [ ] nvidia-smi commands execute successfully

### Step 2.2: Create Profile Selection Logic (2 hours)

**Add to:** `modules/system/gpu-profile-manager.nix`

```nix
# Create main entry point:
apply_profile() {
    local profile="$1"
    log "Applying profile: $profile"

    case "$profile" in
        gaming)
            apply_gaming_profile
            ;;
        ai)
            apply_ai_profile
            ;;
        kubernetes-gpu)
            apply_kubernetes_gpu_profile
            ;;
        builds)
            apply_builds_profile
            ;;
        mining)
            apply_mining_profile
            ;;
        idle)
            apply_idle_profile
            ;;
        *)
            log "Unknown profile: $profile"
            return 1
            ;;
    esac
}
```

**Dependencies:** Step 2.1 (needs all profile functions)

**Validation:**
```bash
# Test profile selection
sudo systemctl status gpu-profile-manager
# Should show: "Applying profile: mining"

# Manually trigger profile change
echo "gaming" | sudo tee /run/gpu-profile-manager/requested-profile
sudo systemctl reload gpu-profile-manager
nvidia-smi
# Should show gaming profile applied
```

**Acceptance Criteria:**
- [ ] All profiles accessible via apply_profile()
- [ ] Invalid profiles return error
- [ ] Profile changes logged
- [ ] GPU settings update immediately

### Step 2.3: Add Workload Detection Integration (2 hours)

**Add to:** `modules/system/gpu-profile-manager.nix`

```nix
# Create main loop with workload detection:
main_loop() {
    CURRENT_WORKLOAD="idle"

    while true; do
        # Detect workload type
        new_workload=$(detect_workload_type)

        # Apply profile if workload changed
        if [ "$new_workload" != "$CURRENT_WORKLOAD" ]; then
            log "Workload changed: $CURRENT_WORKLOAD -> $new_workload"
            CURRENT_WORKLOAD="$new_workload"
            apply_profile "$new_workload"
        fi

        sleep "$CHECK_INTERVAL"
    done
}
```

**Workload Detection Logic:**
```nix
detect_workload_type() {
    # Priority: Gaming > K8s GPU > Builds > Mining > Idle

    # 1. Check gaming state (from gaming-detection module)
    if [ -f "/run/gaming-detection/gaming_state" ]; then
        source "/run/gaming-detection/gaming_state"
        if [ "$GAMING_ACTIVE" = "1" ]; then
            echo "gaming"
            return
        fi
    fi

    # 2. Check for K8s GPU workloads
    if kubectl get pods --all-namespaces \
        -o jsonpath='{range .items[?(@.spec.containers[*].resources.limits.nvidia\.com/gpu)]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}' \
        2>/dev/null | grep -q "Running"; then
        echo "kubernetes-gpu"
        return
    fi

    # 3. Check for builds (PSI-based detection)
    if check_psi_cpu_pressure || check_psi_memory_pressure; then
        echo "builds"
        return
    fi

    # 4. Default to mining
    echo "mining"
}
```

**Dependencies:** Step 2.2 (needs apply_profile)

**Validation:**
```bash
# Test workload transitions
# Start gaming → should apply gaming profile
# Run K8s GPU pod → should apply kubernetes-gpu profile
# Start nixos-rebuild → should apply builds profile
# Stop all workloads → should apply mining profile

# Check logs
sudo journalctl -u gpu-profile-manager -n 100
# Should see: "Workload changed: mining -> gaming"
```

**Acceptance Criteria:**
- [ ] Detects gaming from gaming-detection state file
- [ ] Detects K8s GPU pods (kubectl get pods)
- [ ] Detects builds (PSI pressure)
- [ ] Defaults to mining when idle
- [ ] Profile transitions logged

### Step 2.4: Add PSI-Based Build Detection (2 hours)

**Add to:** `modules/system/gpu-profile-manager.nix`

**Source:** `compute-workload-monitor.nix` lines 553-850

```nix
# Extract these functions:
- load_psi_threshold()           # Lines 574-600
- check_psi_cpu_pressure()       # Lines 614-666
- check_psi_memory_pressure()    # Lines 678-748
- check_psi_io_pressure()        # Lines 750-820
- is_mining_causing_pressure()   # Lines 669-676
```

**Dependencies:** Step 2.3 (needs detect_workload_type)

**Validation:**
```bash
# Trigger build workload
nixos-rebuild test

# Check PSI detection
sudo journalctl -u gpu-profile-manager -f
# Should see: "PSI: High CPU pressure detected (avg10=5.23 > 5.0)"

# Verify profile changed to builds
nvidia-smi
# Should see: reduced GPU mining (nexus only), paused CPU mining
```

**Acceptance Criteria:**
- [ ] PSI CPU pressure detection works
- [ ] PSI memory pressure detection works
- [ ] PSI I/O pressure detection works
- [ ] Mining-caused pressure filtered out
- [ ] Hysteresis prevents profile flicker

### Step 2.5: Create Systemd Service Definition (1 hour)

**Add to:** `modules/system/gpu-profile-manager.nix`

```nix
config = lib.mkIf cfg.enable {
  systemd.services.gpu-profile-manager = {
    description = "GPU power/clock profile manager";
    wantedBy = ["multi-user.target"];
    after = ["network.target" "gaming-detection.target"];

    path = with pkgs; [
        procps           # pgrep
        kubernetes       # kubectl for GPU pod detection
        coreutils        # runuser
    ];

    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.writeShellScriptBin "gpu-profile-manager" ''...''}/bin/gpu-profile-manager";
      Restart = "on-failure";
      RestartSec = "10s";
      # Allow access to nvidia-smi
      AmbientCapabilities = ["CAP_NET_ADMIN"];
    };
  };
};
```

**Dependencies:** Step 2.4 (complete script before wrapping in service)

**Validation:**
```bash
# Enable and start service
sudo systemctl daemon-reload
sudo systemctl enable gpu-profile-manager
sudo systemctl start gpu-profile-manager

# Check status
sudo systemctl status gpu-profile-manager
# Should be: active (running)
```

**Acceptance Criteria:**
- [ ] Service starts after gaming-detection
- [ ] Service has access to nvidia-smi
- [ ] Service has access to kubectl
- [ ] Service runs continuously

### Day 2 Complete Checklist

- [ ] gpu-profile-manager.nix created (~600 lines)
- [ ] All 6 profiles implemented
- [ ] GPU-specific settings (3060 Ti vs 3090)
- [ ] No systemd mining service control
- [ ] No kubectl scale commands
- [ ] Workload detection integrated
- [ ] PSI-based build detection works
- [ ] Profile transitions work correctly
- [ ] Tested on zephyr

**Deliverable:** `modules/system/gpu-profile-manager.nix` (fully functional, tested)

---

## Day 3: Mining Coordinator Module

**Goal:** Create `mining-coordinator.nix` - K8s-aware coordination without service control

### Step 3.1: Design Mining Coordinator Architecture (1 hour)

**Create:** `modules/system/mining-coordinator.nix`

**Architecture:**
```nix
# Mining coordinator responsibilities:
# 1. Read gaming state from gaming-detection module
# 2. Detect K8s GPU workloads (kubectl get pods)
# 3. Detect build workloads (PSI pressure)
# 4. Request GPU profile changes via gpu-profile-manager
# 5. NO direct control of mining pods (Volcano handles it)
# 6. NO systemd service control
# 7. NO manual kubectl scale commands
```

**Key Design Decision:**
- Mining coordinator does NOT apply GPU profiles directly
- Instead, it sends requests to gpu-profile-manager via shared state file
- This allows gpu-profile-manager to be used independently

**Communication Mechanism:**
```bash
# Shared state file: /run/mining-coordinator/requested-profile
echo "gaming" > /run/mining-coordinator/requested-profile
# gpu-profile-manager reads this file and applies profile
```

**Dependencies:** None (new module, but depends on gaming-detection state file)

**Deliverable:** Architecture documentation in module header

### Step 3.2: Implement Gaming State Reader (1.5 hours)

**Add to:** `modules/system/mining-coordinator.nix`

```nix
read_gaming_state() {
    local state_file="/run/gaming-detection/gaming_state"

    if [ ! -f "$state_file" ]; then
        echo "0"  # Default: no gaming
        return
    fi

    source "$state_file"
    echo "$GAMING_ACTIVE"  # 0 or 1
}
```

**Dependencies:** Step 3.1 (needs architecture defined)

**Validation:**
```bash
# Test reading gaming state
cat /run/gaming-detection/gaming_state
# Should show: GAMING_ACTIVE=0 or 1

# Test reader function
sudo systemctl status mining-coordinator
# Should show: "Gaming state: 0" or "Gaming state: 1"
```

**Acceptance Criteria:**
- [ ] Reads gaming state from gaming-detection module
- [ ] Returns 0 if state file doesn't exist
- [ ] Returns correct GAMING_ACTIVE value
- [ ] Logs gaming state changes

### Step 3.3: Implement K8s GPU Workload Detector (2 hours)

**Add to:** `modules/system/mining-coordinator.nix`

**Source:** `compute-workload-monitor.nix` lines 480-516

```nix
check_kubernetes_gpu_workload() {
    # Check if kubectl is available
    if ! command -v kubectl >/dev/null 2>&1; then
        return 1
    fi

    # Check if we can connect to the cluster
    if ! kubectl get nodes >/dev/null 2>&1; then
        return 1
    fi

    # Check for GPU pods across all namespaces
    # Look for pods with nvidia.com/gpu resource requests
    local gpu_pods=$(kubectl get pods --all-namespaces \
        -o jsonpath='{range .items[?(@.spec.containers[*].resources.limits.nvidia\.com/gpu)]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}' \
        2>/dev/null || echo "")

    if [ -n "$gpu_pods" ]; then
        # Filter out non-running pods AND mining pods
        local running_gpu_pods=$(echo "$gpu_pods" | while read -r pod; do
            [ -z "$pod" ] && continue
            local namespace=$(echo "$pod" | cut -d'/' -f1)
            local name=$(echo "$pod" | cut -d'/' -f2)

            # Skip mining namespace pods (they're the ones being preempted)
            if [ "$namespace" = "mining" ]; then
                continue
            fi

            # Check if pod is running
            if kubectl get pod "$name" -n "$namespace" -o jsonpath='{.status.phase}' 2>/dev/null | grep -q "Running"; then
                echo "$pod"
            fi
        done)

        if [ -n "$running_gpu_pods" ]; then
            log "Kubernetes GPU workload detected: $running_gpu_pods"
            return 0
        fi
    fi

    return 1
}
```

**Key Changes from Original:**
- Filters out mining namespace pods (don't preempt yourself!)
- Only counts non-mining GPU pods as workloads

**Dependencies:** Step 3.2 (needs gaming reader to complete workload detection)

**Validation:**
```bash
# Test K8s GPU workload detection
# Start a GPU pod in non-mining namespace:
kubectl run test-gpu-pod --image=nginx --limits=nvidia.com/gpu=1

# Check detection
sudo journalctl -u mining-coordinator -n 20
# Should see: "Kubernetes GPU workload detected: default/test-gpu-pod"

# Clean up
kubectl delete pod test-gpu-pod
```

**Acceptance Criteria:**
- [ ] Detects GPU pods in non-mining namespaces
- [ ] Ignores mining namespace pods
- [ ] Only counts running pods
- [ ] Returns 1 if no GPU workloads
- [ ] Logs detected workloads

### Step 3.4: Implement Build Workload Detector (1.5 hours)

**Add to:** `modules/system/mining-coordinator.nix`

**Source:** `compute-workload-monitor.nix` lines 614-820

```nix
check_build_workload() {
    # Reuse PSI detection from gpu-profile-manager
    # But simplify: only need yes/no, not detailed metrics

    # Check CPU pressure
    if check_psi_cpu_pressure; then
        return 0
    fi

    # Check memory pressure
    if check_psi_memory_pressure; then
        return 0
    fi

    # Check I/O pressure
    if check_psi_io_pressure; then
        return 0
    fi

    return 1
}
```

**Dependencies:** Step 3.3 (needs K8s detector to complete workload detection)

**Validation:**
```bash
# Trigger build workload
nixos-rebuild test

# Check detection
sudo journalctl -u mining-coordinator -f
# Should see: "Build workload detected (PSI CPU pressure)"

# Verify profile request sent
cat /run/mining-coordinator/requested-profile
# Should show: "builds"
```

**Acceptance Criteria:**
- [ ] Detects PSI CPU pressure
- [ ] Detects PSI memory pressure
- [ ] Detects PSI I/O pressure
- [ ] Returns 0 if any pressure detected
- [ ] Returns 1 if no pressure

### Step 3.5: Implement Workload Type Determination (1.5 hours)

**Add to:** `modules/system/mining-coordinator.nix`

```nix
get_workload_type() {
    # Priority: Gaming > K8s GPU > Builds > Mining

    # 1. Check gaming (highest priority)
    local gaming_active=$(read_gaming_state)
    if [ "$gaming_active" = "1" ]; then
        echo "gaming"
        return
    fi

    # 2. Check K8s GPU workloads
    if check_kubernetes_gpu_workload; then
        echo "kubernetes-gpu"
        return
    fi

    # 3. Check build workloads
    if check_build_workload; then
        echo "builds"
        return
    fi

    # 4. Default to mining
    echo "mining"
}
```

**Dependencies:** Step 3.4 (needs all detectors)

**Validation:**
```bash
# Test all workload types
# Gaming: gamemoded -s
# K8s GPU: kubectl run test-gpu-pod --limits=nvidia.com/gpu=1
# Builds: nixos-rebuild test
# Mining: stop all above

# Check workload detection
sudo journalctl -u mining-coordinator -n 50
# Should see transitions between workload types
```

**Acceptance Criteria:**
- [ ] Gaming detected correctly
- [ ] K8s GPU detected correctly
- [ ] Builds detected correctly
- [ ] Defaults to mining when idle
- [ ] Priority order correct (gaming > K8s GPU > builds > mining)

### Step 3.6: Implement Profile Request System (1 hour)

**Add to:** `modules/system/mining-coordinator.nix`

```nix
request_profile() {
    local profile="$1"
    local request_file="/run/mining-coordinator/requested-profile"

    mkdir -p /run/mining-coordinator
    echo "$profile" > "$request_file"

    log "Requested profile change to: $profile"
}
```

**Dependencies:** Step 3.5 (needs workload detection)

**Validation:**
```bash
# Test profile request
echo "gaming" | sudo tee /run/mining-coordinator/requested-profile
cat /run/mining-coordinator/requested-profile
# Should show: "gaming"

# Check logs
sudo journalctl -u mining-coordinator -n 10
# Should see: "Requested profile change to: gaming"
```

**Acceptance Criteria:**
- [ ] Profile request file created
- [ ] File contains requested profile name
- [ ] Request logged
- [ ] File readable by gpu-profile-manager

### Step 3.7: Implement Main Loop (1.5 hours)

**Add to:** `modules/system/mining-coordinator.nix`

```nix
main_loop() {
    CURRENT_WORKLOAD="mining"
    CHECK_INTERVAL="${toString config.services.mining-coordinator.checkInterval}"

    log "Starting mining coordinator (check interval: ${CHECK_INTERVAL}s)"

    while true; do
        new_workload=$(get_workload_type)

        if [ "$new_workload" != "$CURRENT_WORKLOAD" ]; then
            log "Workload changed: $CURRENT_WORKLOAD -> $new_workload"
            CURRENT_WORKLOAD="$new_workload"
            request_profile "$new_workload"
        fi

        sleep "$CHECK_INTERVAL"
    done
}
```

**Dependencies:** Step 3.6 (needs profile request system)

**Validation:**
```bash
# Test main loop
sudo systemctl start mining-coordinator

# Trigger workload change
gamemoded -s  # Start gaming

# Check logs
sudo journalctl -u mining-coordinator -f
# Should see: "Workload changed: mining -> gaming"
# Then: "Requested profile change to: gaming"

# Check profile request file
cat /run/mining-coordinator/requested-profile
# Should show: "gaming"
```

**Acceptance Criteria:**
- [ ] Main loop runs continuously
- [ ] Detects workload changes
- [ ] Requests profile changes
- [ ] Logs all transitions
- [ ] No systemctl calls
- [ ] No kubectl scale calls

### Step 3.8: Create Systemd Service Definition (1 hour)

**Add to:** `modules/system/mining-coordinator.nix`

```nix
config = lib.mkIf cfg.enable {
  systemd.services.mining-coordinator = {
    description = "K8s-aware mining coordinator";
    wantedBy = ["multi-user.target"];
    after = [
        "network.target"
        "gaming-detection.target"
        "gpu-profile-manager.target"
    ];

    path = with pkgs; [
        procps       # pgrep
        kubernetes   # kubectl
        coreutils    # runuser
    ];

    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.writeShellScriptBin "mining-coordinator" ''...''}/bin/mining-coordinator";
      Restart = "on-failure";
      RestartSec = "10s";
    };
  };

  systemd.tmpfiles.rules = [
    "d /run/mining-coordinator 0755 root root - -"
  ];
};
```

**Dependencies:** Step 3.7 (complete script before wrapping in service)

**Validation:**
```bash
# Enable and start service
sudo systemctl daemon-reload
sudo systemctl enable mining-coordinator
sudo systemctl start mining-coordinator

# Check status
sudo systemctl status mining-coordinator
# Should be: active (running)

# Check dependencies
systemctl list-dependencies mining-coordinator
# Should show: gaming-detection.target, gpu-profile-manager.target
```

**Acceptance Criteria:**
- [ ] Service starts after gaming-detection and gpu-profile-manager
- [ ] Service has access to kubectl
- [ ] Service creates /run/mining-coordinator directory
- [ ] Service runs continuously

### Day 3 Complete Checklist

- [ ] mining-coordinator.nix created (~400 lines)
- [ ] Reads gaming state from gaming-detection
- [ ] Detects K8s GPU workloads (non-mining namespaces only)
- [ ] Detects build workloads (PSI-based)
- [ ] Determines workload type correctly
- [ ] Requests profile changes via shared state file
- [ ] No systemd mining service control
- [ ] No kubectl scale commands
- [ ] Main loop runs continuously
- [ ] Tested on zephyr

**Deliverable:** `modules/system/mining-coordinator.nix` (fully functional, tested)

---

## Day 4: Integration and Cleanup

**Goal:** Deploy to all hosts, remove legacy module, final validation

### Step 4.1: Update Module Registry (30 minutes)

**Edit:** `modules/default.nix`

```nix
# Add new modules to imports
[
  ./system/gaming-detection.nix
  ./system/gpu-profile-manager.nix
  ./system/mining-coordinator.nix
  # Keep compute-workload-monitor for now (gradual migration)
]
```

**Dependencies:** None (registry update)

**Validation:**
```bash
# Test module imports
nix flake check
# Should pass without errors
```

**Acceptance Criteria:**
- [ ] All three modules imported
- [ ] flake check passes
- [ ] No syntax errors

### Step 4.2: Update Zephyr Configuration (1 hour)

**Edit:** `hosts/zephyr/configuration.nix`

```nix
# Disable old module
services.compute-workload-monitor.enable = lib.mkForce false;

# Enable new modules
services.gaming-detection = {
  enable = true;
  checkInterval = 10;
  hysteresisCycles = 3;
};

services.gpu-profile-manager = {
  enable = true;
  checkInterval = 10;
};

services.mining-coordinator = {
  enable = true;
  checkInterval = 10;
};
```

**Dependencies:** Step 4.1 (modules must be imported)

**Validation:**
```bash
# Build configuration
nixos-rebuild build

# Check for errors
# Should build successfully

# Apply configuration
nixos-rebuild test

# Verify services running
systemctl status gaming-detection
systemctl status gpu-profile-manager
systemctl status mining-coordinator
# All should be: active (running)
```

**Acceptance Criteria:**
- [ ] Configuration builds without errors
- [ ] Old module disabled
- [ ] All three new modules enabled
- [ ] All three services running
- [ ] No duplicate service conflicts

### Step 4.3: Update Nexus Configuration (1 hour)

**Edit:** `hosts/nexus/configuration.nix`

```nix
# Same as zephyr (nexus is also a gaming node)
services.compute-workload-monitor.enable = lib.mkForce false;

services.gaming-detection.enable = true;
services.gpu-profile-manager.enable = true;
services.mining-coordinator.enable = true;
```

**Dependencies:** Step 4.2 (zephyr working as reference)

**Validation:**
```bash
# Build configuration
nixos-rebuild build

# Apply to nexus
colmena apply nexus --sudo

# Verify services running
# (SSH to nexus or use kubectl)
ssh nexus "systemctl status gaming-detection gpu-profile-manager mining-coordinator"
```

**Acceptance Criteria:**
- [ ] Configuration builds
- [ ] Applied to nexus successfully
- [ ] All three services running
- [ ] Gaming detection works on nexus
- [ ] GPU profiles apply correctly

### Step 4.4: Update Forge Configuration (30 minutes)

**Edit:** `hosts/forge/configuration.nix`

```nix
# Forge is mining-only (no gaming), simpler config
services.compute-workload-monitor.enable = lib.mkForce false;

# Only GPU profile manager needed
services.gpu-profile-manager = {
  enable = true;
  checkInterval = 10;
};

# Gaming detection not needed (no gaming on forge)
# Mining coordinator not needed (no gaming/AI/builds)
```

**Dependencies:** Step 4.3 (nexus working as reference)

**Validation:**
```bash
# Build configuration
nixos-rebuild build

# Apply to forge
colmena apply forge --sudo

# Verify service running
ssh forge "systemctl status gpu-profile-manager"
```

**Acceptance Criteria:**
- [ ] Configuration builds
- [ ] Applied to forge successfully
- [ ] GPU profile manager running
- [ ] Mining profile applied by default
- [ ] No gaming detection running (not needed)

### Step 4.5: Update Sentry Configuration (30 minutes)

**Edit:** `hosts/sentry/configuration.nix`

```nix
# Sentry has AMD GPU (desktop only), minimal config
services.compute-workload-monitor.enable = lib.mkForce false;

# No GPU management needed (AMD GPU not used for mining)
# Gaming detection optional (for metrics only)
services.gaming-detection.enable = true;  # For Prometheus metrics
```

**Dependencies:** Step 4.4 (forge working as reference)

**Validation:**
```bash
# Build configuration
nixos-rebuild build

# Apply to sentry
colmena apply sentry --sudo

# Verify service running
ssh sentry "systemctl status gaming-detection"
```

**Acceptance Criteria:**
- [ ] Configuration builds
- [ ] Applied to sentry successfully
- [ ] Gaming detection running (metrics only)
- [ ] No GPU profile manager (not needed)

### Step 4.6: Validate Gaming Preemption (2 hours)

**Test on Zephyr and Nexus:**

```bash
# 1. Verify mining pods running
kubectl get pods -n mining -l app=xmrig
# Should show: xmrig-zephyr, xmrig-nexus Running

# 2. Start gaming
gamemoded -s  # or run actual game

# 3. Check gaming detection
cat /run/gaming-detection/gaming_state
# Should show: GAMING_ACTIVE=1

# 4. Check mining coordinator
cat /run/mining-coordinator/requested-profile
# Should show: "gaming"

# 5. Check GPU profile
nvidia-smi
# Should show: gaming profile (350W for 3090)

# 6. Verify Volcano preemption
kubectl get pods -n mining -l app=xmrig
# Should show: Status=Preempted or 0/Running

# 7. Stop gaming
# Wait for hysteresis (30 seconds)

# 8. Verify mining pods resume
kubectl get pods -n mining -l app=xmrig
# Should show: xmrig-zephyr, xmrig-nexus Running

# 9. Verify GPU profile
nvidia-smi
# Should show: mining profile (250W for 3090)
```

**Dependencies:** Step 4.5 (all hosts configured)

**Acceptance Criteria:**
- [ ] Gaming detection works
- [ ] Mining coordinator requests gaming profile
- [ ] GPU profile changes to gaming
- [ ] Volcano preempts mining pods
- [ ] Mining pods resume after gaming ends
- [ ] GPU profile changes back to mining
- [ ] Hysteresis prevents flicker

### Step 4.7: Validate GPU Profile Transitions (2 hours)

**Test all workload types:**

```bash
# Test 1: Gaming → Mining
# (Already tested in Step 4.6)

# Test 2: K8s GPU Workload → Mining
kubectl run test-ai-pod --image=python --limits=nvidia.com/gpu=1 --command=-- python -c "import time; time.sleep(300)"

# Check mining coordinator
cat /run/mining-coordinator/requested-profile
# Should show: "kubernetes-gpu"

# Check GPU profile
nvidia-smi
# Should show: kubernetes-gpu profile (280W for 3090)

# Verify mining pods preempted
kubectl get pods -n mining -l app=xmrig
# Should show: Status=Preempted

# Clean up
kubectl delete pod test-ai-pod

# Test 3: Builds → Mining
nixos-rebuild test

# Check mining coordinator
cat /run/mining-coordinator/requested-profile
# Should show: "builds"

# Check GPU profile
nvidia-smi
# Should show: builds profile (reduced GPU mining)

# Wait for build to finish
# Verify profile returns to mining
```

**Dependencies:** Step 4.6 (gaming preemption working)

**Acceptance Criteria:**
- [ ] K8s GPU workload detected
- [ ] GPU profile changes to kubernetes-gpu
- [ ] Mining pods preempted
- [ ] Build workload detected
- [ ] GPU profile changes to builds
- [ ] Profile returns to mining when idle

### Step 4.8: Validate Prometheus Metrics (1 hour)

**Test metric export:**

```bash
# Check gaming metric
cat /var/lib/node_exporter/textfile_collector/gaming.prom
# Should show:
# # HELP gaming_active Whether a game is currently running (1=yes, 0=no)
# # TYPE gaming_active gauge
# gaming_active{host="zephyr",detection_method="gamemode"} 0

# Test metric updates
# Start gaming
gamemoded -s

# Wait for next check interval (10 seconds)
cat /var/lib/node_exporter/textfile_collector/gaming.prom
# Should show: gaming_active{...} 1

# Verify metric in Prometheus
curl http://localhost:9090/api/v1/query?query=gaming_active
# Should return metric with value 1 or 0
```

**Dependencies:** Step 4.7 (all workload types tested)

**Acceptance Criteria:**
- [ ] Gaming metric exported
- [ ] Metric includes host label
- [ ] Metric includes detection_method label
- [ ] Metric value updates correctly
- [ ] Metric queryable in Prometheus

### Step 4.9: Remove Legacy Module (1 hour)

**Edit:** `modules/default.nix`

```nix
# Remove compute-workload-monitor import
[
  # ./system/compute-workload-monitor.nix  # DELETE THIS LINE
  ./system/gaming-detection.nix
  ./system/gpu-profile-manager.nix
  ./system/mining-coordinator.nix
]
```

**Edit:** All host configurations

```nix
# Remove compute-workload-monitor config
# services.compute-workload-monitor.enable = lib.mkForce false;  # DELETE THIS LINE
```

**Delete legacy module:**
```bash
rm modules/system/compute-workload-monitor.nix
```

**Dependencies:** Step 4.8 (all validation passing)

**Validation:**
```bash
# Build all hosts
nixos-rebuild build  # On zephyr
colmena build        # All hosts

# Apply to all hosts
colmena apply

# Verify old service removed
systemctl status compute-workload-monitor
# Should show: Unit compute-workload-monitor.service could not be found.

# Verify new services running
systemctl status gaming-detection gpu-profile-manager mining-coordinator
# Should show: All active (running)
```

**Acceptance Criteria:**
- [ ] Legacy module deleted
- [ ] All host configs updated
- [ ] Old service removed from all hosts
- [ ] New services still running
- [ ] All functionality preserved

### Step 4.10: Final Integration Test (2 hours)

**Complete end-to-end test:**

```bash
# 1. Start with idle system (no workloads)
# Verify mining profile applied
nvidia-smi
# Should show: mining profile

# 2. Start gaming
# Verify gaming detection
cat /run/gaming-detection/gaming_state
# Should show: GAMING_ACTIVE=1

# Verify GPU profile
nvidia-smi
# Should show: gaming profile

# Verify mining pods preempted
kubectl get pods -n mining
# Should show: Preempted

# 3. Start K8s GPU workload while gaming
kubectl run test-ai-pod --limits=nvidia.com/gpu=1

# Verify GPU profile stays gaming (gaming > K8s GPU)
nvidia-smi
# Should still show: gaming profile

# 4. Stop gaming, keep K8s GPU workload
# Wait for hysteresis

# Verify GPU profile
nvidia-smi
# Should show: kubernetes-gpu profile

# 5. Stop K8s GPU workload
kubectl delete pod test-ai-pod

# 6. Start build
nixos-rebuild test

# Verify GPU profile
nvidia-smi
# Should show: builds profile

# 7. Stop all workloads
# Wait for hysteresis

# Verify GPU profile
nvidia-smi
# Should show: mining profile

# 8. Verify mining pods running
kubectl get pods -n mining
# Should show: All Running
```

**Dependencies:** Step 4.9 (legacy module removed)

**Acceptance Criteria:**
- [ ] All workload transitions work
- [ ] Priority order correct (gaming > K8s GPU > builds > mining)
- [ ] GPU profiles apply correctly
- [ ] Volcano preemption works
- [ ] No manual intervention needed
- [ ] Hysteresis prevents flicker

### Day 4 Complete Checklist

- [ ] All three modules imported
- [ ] Zephyr configured and tested
- [ ] Nexus configured and tested
- [ ] Forge configured and tested
- [ ] Sentry configured and tested
- [ ] Gaming preemption validated
- [ ] GPU profile transitions validated
- [ ] Prometheus metrics validated
- [ ] Legacy module removed
- [ ] Final integration test passed

**Deliverable:** Complete refactoring deployed to all hosts, legacy code removed

---

## Rollback Procedures

### If Gaming Detection Fails

**Symptom:** Gaming not detected, GPU profiles not changing

**Rollback:**
```bash
# Re-enable compute-workload-monitor
# In host config:
services.compute-workload-monitor.enable = true;

# Disable new modules
services.gaming-detection.enable = false;
services.gpu-profile-manager.enable = false;
services.mining-coordinator.enable = false;

# Rebuild
nixos-rebuild switch
```

### If GPU Profiles Fail

**Symptom:** nvidia-smi commands failing, GPU not configured

**Rollback:**
```bash
# Check nvidia-smi access
nvidia-smi
# If failing: Check NVIDIA driver

# Check service logs
journalctl -u gpu-profile-manager -n 100
# Look for errors

# Re-enable compute-workload-monitor (has fallback logic)
services.compute-workload-monitor.enable = true;
services.gpu-profile-manager.enable = false;
```

### If Volcano Preemption Fails

**Symptom:** Mining pods not preempted during gaming

**Rollback:**
```bash
# Check Volcano scheduler
kubectl get pods -n volcano-system
# Should be: Running

# Check priority classes
kubectl get priorityclasses
# Should show: gaming-high, mining-low

# Check gaming placeholder
kubectl get deployment gaming-placeholder-volcano -n mining
# Should scale to 1 when gaming

# Manual workaround: Scale mining pods to 0
kubectl scale deployment xmrig-zephyr xmrig-nexus -n mining --replicas=0
```

### If Build Detection Fails

**Symptom:** Builds not detected, mining not paused during builds

**Rollback:**
```bash
# Check PSI support
cat /proc/pressure/cpu
# Should show PSI metrics

# If PSI not available: Check kernel config
# Re-enable compute-workload-monitor (has process-based fallback)
services.compute-workload-monitor.enable = true;
services.mining-coordinator.enable = false;
```

---

## Success Metrics

### Code Quality
- [ ] Reduced complexity: 1665 lines → 3 focused modules (~1300 lines total)
- [ ] Single responsibility: Each module has one clear purpose
- [ ] No code duplication: Functions not repeated across modules
- [ ] Clear interfaces: Modules communicate via state files

### Functional Requirements
- [ ] Gaming detection: GameMode + GPU fallback works
- [ ] GPU profiles: All 6 profiles apply correctly
- [ ] Workload detection: Gaming, K8s GPU, builds, mining detected
- [ ] K8s-native scheduling: Volcano preemption works
- [ ] No systemd control: Mining managed by K8s only
- [ ] No manual kubectl: Volcano handles scaling

### Observability
- [ ] Gaming metrics: Exported to Prometheus
- [ ] GPU profile state: Logged and visible
- [ ] Workload transitions: Logged with timestamps
- [ ] Service health: All services running continuously

### Performance
- [ ] Detection latency: <10 seconds (check interval)
- [ ] Profile application: <1 second (nvidia-smi instant)
- [ ] Preemption latency: <5 seconds (Volcano gang scheduling)
- [ ] Hysteresis: 30 seconds (3 checks × 10 seconds)

---

## Documentation Updates

### Update CLAUDE.md

**Add to "Modules" section:**
```markdown
### Gaming Detection
**File:** `modules/system/gaming-detection.nix`
**Purpose:** Pure gaming detection with GameMode daemon and GPU fallback
**Usage:**
```nix
services.gaming-detection.enable = true;
```

### GPU Profile Manager
**File:** `modules/system/gpu-profile-manager.nix`
**Purpose:** Host-level GPU power/clock management via nvidia-smi
**Usage:**
```nix
services.gpu-profile-manager.enable = true;
```

### Mining Coordinator
**File:** `modules/system/mining-coordinator.nix`
**Purpose:** K8s-aware workload coordination (no service control)
**Usage:**
```nix
services.mining-coordinator.enable = true;
```
```

### Update AGENTS.md

**Add to "Module Development" section:**
```markdown
## Creating System Modules

When creating new system modules:
1. Use focused single-responsibility design
2. Communicate via state files in /run/
3. Avoid direct service control (use K8s-native scheduling)
4. Export metrics to Prometheus for observability
```

### Create Module Documentation

**Create:** `modules/system/gaming-detection/README.md`
**Create:** `modules/system/gpu-profile-manager/README.md`
**Create:** `modules/system/mining-coordinator/README.md`

**Each README should include:**
- Module purpose and scope
- Configuration options
- Integration points (state files, metrics)
- Troubleshooting guide
- Example usage

---

## Next Steps After Implementation

### Phase 2: Enhanced Features (Future Work)

1. **GPU Metrics Export**
   - Export GPU profile state to Prometheus
   - Add `gpu_profile` label to gaming metric
   - Track profile transitions over time

2. **Workload History**
   - Log workload transitions to file
   - Analyze patterns (gaming hours, build frequency)
   - Generate usage reports

3. **Dynamic Thresholds**
   - Runtime threshold configuration (PSI, hysteresis)
   - Reload without rebuild (systemctl reload)
   - Per-host tuning

4. **Multi-GPU Support**
   - Per-GPU workload detection
   - Profile per-GPU (different workloads on different GPUs)
   - Support for heterogeneous GPU clusters

### Phase 3: K8s Operator (Long-term)

1. **Custom Resource Definition**
   - `WorkloadState` CRD for cluster-wide state
   - `GPUProfile` CRD for profile management
   - Replaces state files with K8s-native objects

2. **Controller**
   - Watches for workload changes
   - Applies GPU profiles via NodeAgent
   - Integrates with Volcano for preemption

3. **Dashboard**
   - Grafana dashboard for workload visualization
   - Real-time GPU profile status
   - Historical workload patterns

---

## Implementation Summary

**Total Effort:** 4 days

**Lines of Code:**
- Legacy: 1665 lines (1 monolithic module)
- New: ~1300 lines (3 focused modules)
- Reduction: ~22% (with better organization)

**Modules Created:**
1. `gaming-detection.nix` (~300 lines)
2. `gpu-profile-manager.nix` (~600 lines)
3. `mining-coordinator.nix` (~400 lines)

**Key Improvements:**
- ✅ No systemd mining service control
- ✅ No manual kubectl scale commands
- ✅ K8s-native Volcano scheduling
- ✅ Clear separation of concerns
- ✅ Better observability
- ✅ Easier to maintain and extend

**Risk Mitigation:**
- Gradual migration (keep legacy during transition)
- Extensive testing (gaming, K8s GPU, builds)
- Rollback procedures for each failure scenario
- Validation on all hosts before removing legacy

**Ready to Implement:** Start with Day 1, Step 1.1 (Extract Gaming Detection Functions)
