# Compute Scheduler Gap Analysis & Implementation Plan

**Date**: 2026-03-10
**Author**: Claude Code Analysis
**Purpose**: Comprehensive analysis of compute scheduling gaps between mining (lolminer/xmrig) and Kubernetes GPU workloads

---

## Executive Summary

### Critical Findings

1. **🚨 Kubernetes Control Plane Fragility**: API server shutdown during CRI-O restart cascades to full cluster unavailability
2. **⚠️ No GPU Workload Coordination**: Mining operates independently with zero awareness of Kubernetes GPU scheduling
3. **⚠️ GPU Utilization Imbalance**: GPU 0 (3060 Ti) idle while GPU 1 (3090) mines
4. **⚠️ Forge GPU Registration Failure**: RTX 4060 GPUs not registering with device plugin

### Impact Assessment

| Issue | Severity | Impact | Affected Components |
|-------|----------|---------|---------------------|
| Control plane fragility | **CRITICAL** | Cluster unavailable during CRI-O restarts | kube-apiserver, kube-scheduler |
| No GPU workload coordination | **HIGH** | Resource conflicts, mining disrupts K8s workloads | lolminer, Kubernetes pods |
| GPU utilization imbalance | **MEDIUM** | Wasted compute capacity | GPU 0 (3060 Ti) |
| Forge GPU registration | **MEDIUM** | 2 GPUs unavailable cluster-wide | Forge node |

---

## Current State Analysis

### 1. Compute Workload Monitor Capabilities

**Location**: `/nix/store/.../compute-workload-monitor`

**Current Detection Capabilities**:
```bash
✅ Gaming processes: steam, lutris, heroic, wine, proton
✅ AI processes: lmstudio, ollama, python.*llm, ai-inference-gateway
✅ Build processes: nixos-rebuild, colmena, nix-build, gcc, clang, cargo build, make, cmake, ninja
✅ Distributed build detection: SSH connections + nix-daemon CPU > 30%
✅ Mining services: lolminer-nvidia, lolminer-amd, xmrig
❌ Kubernetes GPU workloads: NOT DETECTED
```

**Current Resource Management**:
```bash
✅ GPU power/clock profiling: per-GPU tuning (3060 Ti, 3090, etc.)
✅ CPU quota management: systemd runtime CPUQuota for mining
✅ CPU affinity control: taskset for xmrig thread reduction
✅ Service pause/resume: systemctl stop/start for mining
❌ Kubernetes GPU workload detection: NOT IMPLEMENTED
❌ GPU utilization monitoring: NOT IMPLEMENTED
❌ Preemption mechanism: NOT IMPLEMENTED
```

### 2. Current GPU Allocation

**Zephyr (control-plane, 2x NVIDIA GPUs)**:
```
GPU 0 (RTX 3060 Ti):
  - Status: IDLE
  - Utilization: 0%
  - VRAM Used: 154MB / 8192MB (1.9%)
  - Kubernetes: Allocatable ✅
  - Mining: Not running
  - Issue: Completely underutilized

GPU 1 (RTX 3090):
  - Status: MINING (lolminer-nvidia.service)
  - Utilization: 100%
  - VRAM Used: 8895MB / 24576MB (36%)
  - Kubernetes: Allocatable (but blocked by mining)
  - Mining: Active (CR29 algorithm, Kryptex pool)
  - Issue: No coordination with K8s scheduling
```

**Forge (worker, 2x NVIDIA RTX 4060)**:
```
GPU 0 & 1 (RTX 4060):
  - Status: FAILED REGISTRATION
  - Device Plugin: CrashLoopBackOff
  - Error: "No devices found"
  - Issue: Ada Lovelace architecture support gap
```

**Nexus (worker, AMD GPU)**:
```
GPU 0 (AMD Radeon):
  - Mining: lolminer-amd (configured, autostart=false)
  - Kubernetes: No device plugin for AMD
```

**Sentry (worker, no GPU)**:
```
Status: CPU-only node
```

### 3. Kubernetes Cluster State

**Control Plane (Zephyr)**:
```
✅ kube-apiserver: Running (after restart)
✅ kube-scheduler: Running (after restart)
✅ kube-controller-manager: Running
✅ etcd: Running
✅ CoreDNS: Running
✅ Flannel CNI: Running
✅ NVIDIA Device Plugin: Running (Zephyr), Failing (Forge)
```

**Worker Nodes**:
```
✅ Forge: Ready (GPU plugin failing)
✅ Nexus: Ready
✅ Sentry: Ready
```

**GPU Resource Capacity**:
```
Zephyr: nvidia.com/gpu: 2 allocatable
Forge:  nvidia.com/gpu: 0 allocatable (registration failed)
Total:  2 GPUs cluster-wide (out of 4 physical GPUs)
```

---

## Critical Gaps Identified

### Gap 1: No Kubernetes GPU Workload Detection

**Problem**: compute-workload-monitor has zero visibility into Kubernetes GPU scheduling

**Current Behavior**:
```bash
# Mining runs continuously on GPU 1
$ systemctl status lolminer-nvidia
● lolminer-nvidia.service - lolMiner NVIDIA Mining Service
   Active: active (running)
   GPU: 100% utilization, 8895MB VRAM used

# Kubernetes schedules GPU workload to GPU 1
$ kubectl apply -f gpu-test.yaml
pod/gpu-test-phase1 created

# RESULT: Resource conflict!
# Mining holds GPU 100%, Kubernetes pod cannot actually use GPU
# No preemption, no coordination, pure collision
```

**Missing Detection Mechanisms**:
1. No `kubectl` integration to query GPU pod scheduling
2. No Kubernetes API client for pod resource allocation monitoring
3. No GPU utilization threshold monitoring (nvidia-smi polling)
4. No pod lifecycle event detection (create/delete/evict)

**Impact**:
- Kubernetes GPU pods scheduled but cannot actually use GPU
- Mining continues unabated, causing resource starvation
- No priority system (Kubernetes vs. mining)
- No preemption mechanism

---

### Gap 2: No GPU Workload Preemption

**Problem**: Mining cannot be paused when Kubernetes needs GPU resources

**Current Pause Mechanisms** (working for CPU workloads):
```bash
# Gaming detection
if check_process_running "steam"; then
  systemctl set-property lolminer-nvidia.service CPUQuota="0%" --runtime
fi

# Build detection
if check_process_running "nixos-rebuild"; then
  systemctl set-property lolminer-nvidia.service CPUQuota="10%" --runtime
fi
```

**Missing Preemption for Kubernetes**:
```bash
# NOT IMPLEMENTED:
if kubectl_has_gpu_pods "zephyr"; then
  systemctl pause lolminer-nvidia  # How? No such command
  # OR
  systemctl set-property lolminer-nvidia.service CPUQuota="0%" --runtime
  # BUT: When to resume? How to detect pod completion?
fi
```

**Challenges**:
1. **Detection Latency**: By the time we detect a GPU pod, it's already scheduled
2. **Resume Condition**: When is it safe to resume mining?
   - Pod deleted?
   - Pod succeeded?
   - No GPU pods for X minutes?
3. **Priority System**: What takes precedence?
   - Interactive (gaming) > AI > Builds > **Kubernetes GPU** > Mining
   - OR: Kubernetes GPU > Mining > Builds?

---

### Gap 3: No GPU Utilization Monitoring

**Problem**: Relying solely on process names is insufficient for GPU workloads

**Current Detection**: Process name matching
```bash
AI_PROCESSES=("lmstudio" "ollama" "python.*llm" "ai-inference-gateway")
for proc in "${AI_PROCESSES[@]}"; do
  if check_process_running "$proc"; then
    echo "ai"
    return
  fi
done
```

**Why This Fails for Kubernetes**:
- GPU pods don't have predictable process names
- Containerized processes don't appear in host `ps` output
- GPU utilization can happen without host-visible processes

**Missing GPU Utilization Monitoring**:
```bash
# NOT IMPLEMENTED:
gpu_utilization=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits)
if [ "$gpu_utilization" -gt 80 ]; then
  # Something is using GPU (mining, AI, K8s pod)
  # But what? How to decide?
fi
```

**Challenges**:
1. **Ambiguity**: High GPU utilization could be mining, K8s pod, or both
2. **Latency**: nvidia-smi polling has overhead (should minimize frequency)
3. **False Positives**: Mining uses 100% GPU by design, how to detect K8s pod added load?

---

### Gap 4: GPU Utilization Imbalance

**Problem**: GPU 0 (3060 Ti) completely idle while GPU 1 (3090) mines

**Current State**:
```bash
$ nvidia-smi --query-gpu=index,name,utilization.gpu,memory.used,memory.total --format=csv
0, NVIDIA GeForce RTX 3060 Ti, 0, 154, 8192
1, NVIDIA GeForce RTX 3090, 100, 8895, 24576
```

**Wasted Capacity**:
- GPU 0: 0% utilization = **0 MH/s mining revenue**
- GPU 0: Available for Kubernetes but no workloads scheduled
- GPU 1: 100% mining = **~95 MH/s on CR29**
- GPU 1: Kubernetes allocatable but blocked by mining

**Root Cause**:
1. Mining configured to use GPU 1 only (`devices = "1"`)
2. No mechanism to move mining to GPU 0 when K8s needs GPU 1
3. No time-sharing between K8s and mining on either GPU

**Potential Solutions**:
- **Option A**: Move mining to GPU 0, leave GPU 1 (more powerful) for K8s
- **Option B**: Time-share both GPUs (mine when idle, K8s preempts)
- **Option C**: GPU partitioning (MIG - Multi-Instance GPU) - **NOT SUPPORTED** on 30xx

---

### Gap 5: Kubernetes Control Plane Fragility

**Problem**: CRI-O restart causes API server shutdown, cascading to cluster unavailability

**Incident Timeline**:
```bash
04:46:01 - CRI-O restarted for NVIDIA runtime configuration
04:46:01 - kube-apiserver: Deactivating (signal termination)
04:55:16 - kube-scheduler: "dial tcp 10.1.1.110:6443: connection refused"
04:55:26 - kube-scheduler: Leaderelection lost, exit code=1/FAILURE
04:55:31 - kube-scheduler: Scheduled restart (restart counter=1)
04:56:16 - kube-scheduler: Restart attempt (still failing to connect)
04:57:19 - Manual restart: All control plane services back online
```

**Root Cause**:
1. **CRI-O restart terminates container runtime socket**
2. **kubelet loses connection to CRI-O**
3. **API server loses connection to kubelet**
4. **Scheduler loses connection to API server**
5. **Cascading failure**: All control plane components enter restart loops

**Impact**:
- **11 minutes of cluster downtime** (04:46 to 04:57)
- No kubectl access
- No pod scheduling
- No GPU workload management possible
- Manual intervention required to restart services

**Missing Robustness**:
1. No automatic recovery from CRI-O restart
2. No health check probes for CRI-O readiness
3. No dependency ordering (CRI-O must be fully ready before kubelet)
4. No graceful restart sequence

---

### Gap 6: Forge GPU Registration Failure

**Problem**: 2x RTX 4060 GPUs not registering with NVIDIA device plugin

**Symptoms**:
```bash
$ kubectl get pods -n kube-system -l name=nvidia-device-plugin-ds
NAME                                   READY   STATUS             RESTARTS   AGE
nvidia-device-plugin-daemonset-6g4v8   1/1     Running            7          17m
nvidia-device-plugin-daemonset-z4spp   0/1     CrashLoopBackOff   7          2m
```

**Forge Device Plugin Logs** (hypothesis - needs verification):
```
ERROR: No devices found
ERROR: Failed to initialize NVML: ERROR_LIB_RM_VERSION_MISMATCH
OR
ERROR: Incompatible strategy detected auto
```

**Potential Causes**:
1. **Ada Lovelace Architecture**: RTX 40xx may have driver-specific requirements
2. **CUDA Version Mismatch**: Device plugin built for CUDA 12.x, driver supports CUDA 13.2
3. **CDI Generation Failure**: nvidia-ctk cdi generate may not support 4060
4. **Driver State**: nvidia-smi on Forge may show different driver version

**Impact**:
- 2 GPUs unavailable cluster-wide
- Forge cannot run GPU workloads
- 50% of total GPU capacity wasted

---

## Implementation Plan

### Phase 1: Kubernetes GPU Workload Detection (Week 1)

**Objective**: Enable compute-workload-monitor to detect Kubernetes GPU pods

**Implementation Approach**:

```bash
# Add Kubernetes detection to compute-workload-monitor
check_kubernetes_gpu_workload() {
  local node_name=$(get_hostname)

  # Check for GPU pods on this node
  local gpu_pods=$(kubectl get pods -A --field-selector=spec.nodeName=${node_name} \
    -o json | jq '.items[] | select(.spec.containers[]?.resources?.limits["nvidia.com/gpu"] != null) | .metadata.name')

  if [ -n "$gpu_pods" ]; then
    log "Detected Kubernetes GPU pods: $gpu_pods"
    return 0
  fi

  return 1
}

# Integrate into get_workload_type()
get_workload_type() {
  # Priority: Gaming > AI > Kubernetes GPU > Builds > Mining > Idle

  # ... existing gaming/AI/builds detection ...

  # NEW: Check for Kubernetes GPU workloads
  if check_kubernetes_gpu_workload; then
    echo "kubernetes-gpu"
    return
  fi

  # ... existing mining/idle detection ...
}
```

**Deliverables**:
1. Add `kubectl` to compute-workload-monitor PATH
2. Implement `check_kubernetes_gpu_workload()` function
3. Create `apply_kubernetes_gpu_profile()` to pause mining
4. Test with gpu-test-phase1 pod
5. Verify mining resumes when pod completes

**Estimated Effort**: 4-6 hours

---

### Phase 2: GPU Utilization Monitoring (Week 1)

**Objective**: Add nvidia-smi polling for actual GPU utilization detection

**Implementation Approach**:

```bash
# Add GPU utilization checking
check_gpu_utilization() {
  local gpu_id="$1"
  local utilization=$(nvidia-smi -i "$gpu_id" --query-gpu=utilization.gpu \
    --format=csv,noheader,nounits 2>/dev/null || echo "0")

  echo "$utilization"
}

# Detect if non-mining GPU workload is present
check_external_gpu_workload() {
  local gpus=$(get_gpu_list)

  for gpu_id in $gpus; do
    local util=$(check_gpu_utilization "$gpu_id")

    # If GPU 0 (not mining) has > 50% utilization, something else is using it
    if [ "$gpu_id" = "0" ] && [ "$util" -gt 50 ]; then
      log "Detected external workload on GPU 0: ${util}% utilization"
      return 0
    fi

    # If GPU 1 (mining) has > 110% utilization, additional workload present
    if [ "$gpu_id" = "1" ] && [ "$util" -gt 110 ]; then
      log "Detected additional workload on GPU 1: ${util}% utilization (mining + external)"
      return 0
    fi
  done

  return 1
}
```

**Optimization**:
- Cache nvidia-smi output (don't poll every 10 seconds)
- Use `--query-gpu=utilization.gpu,memory.used` for single call
- Consider using NVIDIA DCGM (Data Center GPU Manager) for more efficient monitoring

**Deliverables**:
1. Add GPU utilization polling (30-second interval)
2. Implement external workload detection
3. Add to workload priority detection
4. Test with AI workloads (ollama, lmstudio)
5. Verify no false positives from mining-only workload

**Estimated Effort**: 3-4 hours

---

### Phase 3: Preemption Mechanism (Week 2)

**Objective**: Implement pause/resume mechanism for Kubernetes GPU workloads

**Implementation Approach**:

```bash
apply_kubernetes_gpu_profile() {
  echo "=== Applying KUBERNETES GPU WORKLOAD profile ==="

  # Pause GPU mining completely
  if systemctl is-active --quiet lolminer-nvidia; then
    log "Pausing lolminer-nvidia for Kubernetes GPU workload"
    systemctl set-property lolminer-nvidia.service CPUQuota="0%" --runtime

    # Track that we paused mining for this workload
    echo "$(date +%s)" > /run/compute-workload-monitor/mining-paused-for-k8s
  fi

  # Optional: Reduce CPU mining to 10%
  if systemctl is-active --quiet xmrig; then
    log "Reducing xmrig to 10% CPU for Kubernetes GPU workload"
    systemctl set-property xmrig.service CPUQuota="10%" --runtime
  fi

  echo "KUBERNETES GPU WORKLOAD profile applied: Mining paused"
}

# Add resume logic to workload type change
resume_mining_if_safe() {
  # Only resume if we paused mining for K8s and no K8s GPU pods remain
  if [ -f /run/compute-workload-monitor/mining-paused-for-k8s ]; then
    if ! check_kubernetes_gpu_workload; then
      log "No more Kubernetes GPU pods, resuming mining"
      rm /run/compute-workload-monitor/mining-paused-for-k8s
      systemctl set-property lolminer-nvidia.service CPUQuota="100%" --runtime
    fi
  fi
}
```

**Resume Conditions**:
1. No GPU pods allocated to this node
2. No GPU utilization above baseline mining level
3. 60-second cooldown after last GPU pod deletion

**Deliverables**:
1. Implement `apply_kubernetes_gpu_profile()`
2. Add pause state tracking in `/run/compute-workload-monitor/`
3. Implement resume logic with safety checks
4. Test pause/resume cycle with gpu-test-phase1
5. Verify no resume storms (multiple pods completing rapidly)

**Estimated Effort**: 6-8 hours

---

### Phase 4: GPU Utilization Balancing (Week 2)

**Objective**: Optimize GPU allocation between mining and Kubernetes

**Option A: Move Mining to GPU 0**

```nix
# modules/mining/mining.nix
lolminer.nvidia.devices = mkOption {
  type = types.str;
  default = "0";  # Changed from "1" to "0"
  description = "NVIDIA GPU device IDs for mining (comma-separated)";
};
```

**Pros**:
- GPU 1 (3090, more powerful) available for K8s workloads
- Simple configuration change
- No runtime coordination needed

**Cons**:
- Mining less efficient on 3060 Ti vs 3090
- No time-sharing (still binary allocation)

**Option B: Time-Sharing Both GPUs**

```bash
# New profile: "kubernetes-standby"
apply_kubernetes_standby_profile() {
  # Reduce mining to 10% on both GPUs
  for gpu_id in 0 1; do
    nvidia-smi -i "$gpu_id" -pl 50
  done

  systemctl set-property lolminer-nvidia.service CPUQuota="10%" --runtime

  # Monitor for K8s GPU pods, pause completely if scheduled
  if check_kubernetes_gpu_workload; then
    apply_kubernetes_gpu_profile
  fi
}
```

**Pros**:
- Both GPUs available for K8s workloads
- Mining continues at reduced rate when idle
- Better GPU utilization overall

**Cons**:
- More complex coordination logic
- Mining efficiency reduced by 90%
- Potential for K8s pod starvation if mining doesn't yield

**Recommended Approach**: Implement Option A first (quick win), then Phase 5 for time-sharing

**Deliverables**:
1. Change mining to GPU 0
2. Verify GPU 1 available for K8s workloads
3. Update documentation
4. Consider time-sharing for Phase 5

**Estimated Effort**: 1-2 hours

---

### Phase 5: Control Plane Robustness (Week 2-3)

**Objective**: Prevent cascading failures during CRI-O restarts

**Implementation Approach**:

```nix
# modules/services/kubernetes.nix
systemd.services = {
  crio = {
    after = ["network.target"];
    before = ["kubelet.service"];
    restartTriggers = ["/etc/crio/crio.conf.d/99-nvidia.toml"];
  };

  kubelet = {
    after = ["crio.service"];
    requires = ["crio.service"];
    serviceConfig.Restart = "on-failure";
    serviceConfig.RestartSec = "10s";
  };

  kube-apiserver = {
    after = ["kubelet.service"];
    requires = ["kubelet.service"];
    serviceConfig.Restart = "on-failure";
    serviceConfig.RestartSec = "15s";
  };

  kube-scheduler = {
    after = ["kube-apiserver.service"];
    requires = ["kube-apiserver.service"];
    serviceConfig.Restart = "on-failure";
    serviceConfig.RestartSec = "20s";
  };

  kube-controller-manager = {
    after = ["kube-apiserver.service"];
    requires = ["kube-apiserver.service"];
    serviceConfig.Restart = "on-failure";
    serviceConfig.RestartSec = "20s";
  };
};
```

**Health Check Probes**:

```bash
# Add to kubelet service ExecStartPre
ExecStartPre = pkgs.writeShellScript "wait-for-crio" ''
  echo "Waiting for CRI-O to be ready..."
  timeout=60
  while [ $timeout -gt 0 ]; do
    if /run/current-system/sw/bin/crictl info >/dev/null 2>&1; then
      echo "CRI-O is ready"
      exit 0
    fi
    sleep 1
    ((timeout--))
  done
  echo "ERROR: CRI-O not ready after 60 seconds"
  exit 1
'';

# Similar for kube-apiserver waiting for kubelet
ExecStartPre = pkgs.writeShellScript "wait-for-kubelet" ''
  echo "Waiting for kubelet to be ready..."
  timeout=120
  while [ $timeout -gt 0 ]; do
    if /run/current-system/sw/bin/kubectl get nodes >/dev/null 2>&1; then
      echo "Kubelet is ready"
      exit 0
    fi
    sleep 2
    ((timeout--))
  done
  echo "ERROR: Kubelet not ready after 120 seconds"
  exit 1
'';
```

**Graceful Restart Sequence**:

```bash
#!/nix/store/.../bin/bash
# scripts/graceful-k8s-restart.sh

echo "=== Graceful Kubernetes Restart Sequence ==="

# 1. Stop control plane (reverse dependency order)
echo "Stopping control plane services..."
systemctl stop kube-controller-manager
systemctl stop kube-scheduler
systemctl stop kube-apiserver
systemctl stop kubelet

# 2. Restart CRI-O
echo "Restarting CRI-O..."
systemctl restart crio

# 3. Wait for CRI-O readiness
echo "Waiting for CRI-O..."
timeout=60
while [ $timeout -gt 0 ]; do
  if crictl info >/dev/null 2>&1; then
    break
  fi
  sleep 1
  ((timeout--))
done

if [ $timeout -eq 0 ]; then
  echo "ERROR: CRI-O failed to become ready"
  exit 1
fi

# 4. Start kubelet
echo "Starting kubelet..."
systemctl start kubelet

# 5. Wait for kubelet readiness
echo "Waiting for kubelet..."
timeout=120
while [ $timeout -gt 0 ]; do
  if kubectl get nodes >/dev/null 2>&1; then
    break
  fi
  sleep 2
  ((timeout--))
done

if [ $timeout -eq 0 ]; then
  echo "ERROR: Kubelet failed to become ready"
  exit 1
fi

# 6. Start control plane (dependency order)
echo "Starting control plane services..."
systemctl start kube-apiserver
systemctl start kube-scheduler
systemctl start kube-controller-manager

# 7. Verify cluster health
echo "Verifying cluster health..."
sleep 10
kubectl get nodes
kubectl get pods -A

echo "=== Graceful Restart Complete ==="
```

**Deliverables**:
1. Add systemd dependency ordering
2. Add health check probes (ExecStartPre scripts)
3. Create graceful restart script
4. Test CRI-O restart scenario
5. Verify no cascading failures

**Estimated Effort**: 8-10 hours

---

### Phase 6: Forge GPU Registration Investigation (Week 3)

**Objective**: Diagnose and fix Forge RTX 4060 GPU registration failure

**Diagnostic Steps**:

```bash
# 1. Check nvidia-smi on Forge
ssh forge "nvidia-smi --query-gpu=index,name,driver_version,cuda_version --format=csv"

# 2. Check CDI files on Forge
ssh forge "ls -la /var/run/nvidia-cdi/"

# 3. Check device plugin logs on Forge
ssh forge "sudo journalctl -u nvidia-device-plugin-daemonset -n 100 --no-pager"

# 4. Compare driver versions between Zephyr and Forge
ssh zephyr "nvidia-smi --query-gpu=driver_version --format=csv,noheader"
ssh forge "nvidia-smi --query-gpu=driver_version --format=csv,noheader"

# 5. Generate CDI manually on Forge
ssh forge "sudo nvidia-ctk cdi generate --output=/var/run/nvidia-cdi/"
```

**Potential Fixes**:

1. **Driver Version Mismatch**:
   ```bash
   # If Forge has different driver version, update to match Zephyr
   # Or: Use device plugin image compatible with Forge's driver
   ```

2. **Ada Lovelace Support**:
   ```bash
   # Try latest device plugin version
   image: nvcr.io/nvidia/k8s-device-plugin:v0.18.2  # Try v0.19.0 or later
   ```

3. **CDI Configuration**:
   ```bash
   # Add RTX 40xx device ID to CDI configuration
   # Or: Disable CDI and use legacy device mapping
   ```

**Deliverables**:
1. Diagnostic report on Forge GPU failure
2. Implement fix (driver update, device plugin version change, or CDI config)
3. Verify 2x RTX 4060 GPUs registered
4. Update cluster GPU capacity from 2 to 4 GPUs
5. Test GPU workload scheduling to Forge

**Estimated Effort**: 6-8 hours (highly dependent on root cause)

---

## Summary & Recommendations

### Immediate Actions (This Week)

1. **✅ CRITICAL**: Fix Kubernetes control plane robustness (Phase 5)
   - Prevents cascading failures during CRI-O restarts
   - Adds health checks and dependency ordering
   - Creates graceful restart sequence

2. **✅ HIGH**: Implement Kubernetes GPU workload detection (Phase 1)
   - Enables compute-workload-monitor to see K8s GPU pods
   - Basic pause mechanism for mining during K8s workloads
   - First step toward coordination

3. **✅ MEDIUM**: Move mining to GPU 0 (Phase 4, Option A)
   - Quick win: frees GPU 1 (3090) for K8s workloads
   - Simple configuration change
   - Immediate improvement in GPU allocation

### Short-term Goals (Next 2 Weeks)

4. **⚠️ HIGH**: Implement preemption mechanism (Phase 3)
   - Automatic pause/resume of mining for K8s workloads
   - Resume safety checks to avoid resume storms
   - Cooldown periods for stability

5. **⚠️ MEDIUM**: Add GPU utilization monitoring (Phase 2)
   - Detect non-mining GPU workloads
   - Prevent false positives from mining-only load
   - Enable time-sharing approach (Phase 4, Option B)

6. **⚠️ LOW**: Investigate Forge GPU registration (Phase 6)
   - Diagnostic report on RTX 4060 failure
   - Implement fix to enable 2 additional GPUs
   - Increase cluster GPU capacity from 2 to 4 GPUs

### Long-term Goals (Next Month)

7. **🔮 FUTURE**: Time-sharing between mining and K8s
   - Dynamic GPU allocation based on workload priority
   - Mining yields to K8s pods automatically
   - Mining resumes when GPU idle

8. **🔮 FUTURE**: GPU partitioning (MIG)
   - **NOT SUPPORTED** on GeForce RTX 30xx
   - Consider for future GPU upgrades (RTX 40xx Axx/Hopper)
   - Enables true GPU sharing between workloads

9. **🔮 FUTURE**: Advanced scheduling policies
   - Kubernetes scheduler extensions for GPU awareness
   - Custom scheduler for mining vs. K8s workloads
   - Priority classes and preemption policies

---

## Success Metrics

### Phase 1 Success Criteria
- [ ] compute-workload-monitor detects Kubernetes GPU pods
- [ ] Mining pauses when GPU pod scheduled
- [ ] Mining resumes when GPU pod completes
- [ ] No manual intervention required

### Phase 2 Success Criteria
- [ ] GPU utilization polling active (30-second interval)
- [ ] External GPU workloads detected accurately
- [ ] No false positives from mining-only workload
- [ ] CPU overhead < 1%

### Phase 3 Success Criteria
- [ ] Preemption mechanism pauses mining automatically
- [ ] Resume safety checks prevent resume storms
- [ ] 60-second cooldown prevents rapid flip-flop
- [ ] End-to-end test: schedule GPU pod → mining pauses → pod completes → mining resumes

### Phase 4 Success Criteria
- [ ] Mining moved to GPU 0 (3060 Ti)
- [ ] GPU 1 (3090) available for K8s workloads
- [ ] GPU test pod successfully runs on GPU 1
- [ ] Mining revenue impact quantified

### Phase 5 Success Criteria
- [ ] CRI-O restart does not cascade to control plane failure
- [ ] Health check probes prevent premature startup
- [ ] Graceful restart script tested and documented
- [ ] Zero manual intervention required for CRI-O restarts

### Phase 6 Success Criteria
- [ ] Forge RTX 4060 GPUs registered with device plugin
- [ ] Cluster GPU capacity increased to 4 GPUs
- [ ] GPU workload successfully scheduled to Forge
- [ ] Diagnostic report documents root cause and fix

---

## Conclusion

The current compute scheduling setup has **critical gaps** in Kubernetes GPU workload coordination:

1. **No detection** of Kubernetes GPU pods
2. **No preemption** mechanism for mining pause/resume
3. **No GPU utilization monitoring** for external workloads
4. **No balancing** of GPU allocation between mining and K8s
5. **Control plane fragility** during CRI-O restarts

The **6-phase implementation plan** addresses these gaps systematically:

- **Phase 1-3**: Kubernetes GPU workload detection and preemption
- **Phase 4**: GPU utilization balancing
- **Phase 5**: Control plane robustness
- **Phase 6**: Forge GPU registration

**Estimated Total Effort**: 30-40 hours across 3 weeks

**Priority**: Phase 5 (control plane robustness) and Phase 1 (K8s GPU detection) should be implemented **first**, as they unblock all other work.

**Next Steps**: Review and approve implementation plan, then begin with Phase 5 (control plane) followed by Phase 1 (K8s GPU detection).

---

**Document Version**: 1.0
**Last Updated**: 2026-03-10
**Status**: Ready for Review
