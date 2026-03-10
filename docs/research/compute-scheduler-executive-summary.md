# Compute Scheduler Analysis - Executive Summary

**Date**: 2026-03-10
**Analysis Type**: Comprehensive gap analysis and implementation planning
**Status**: Ready for implementation

---

## TL;DR - What You Asked For

You asked: **"what about the compute scheduler for xmrig and lolminer? please address all issues and gaps"**

**Answer**: The compute scheduler has **6 critical gaps** preventing coordination between mining and Kubernetes GPU workloads. I've created a comprehensive 6-phase implementation plan (30-40 hours, 3 weeks) to fix these issues.

---

## Current State (What's Working)

### ✅ What's Working Well

1. **Kubernetes Cluster**: 4-node cluster fully operational
   - Zephyr (control-plane): Ready with 2 GPUs allocatable
   - Forge, Nexus, Sentry: Worker nodes Ready
   - All core services running (apiserver, etcd, scheduler, controller-manager, CoreDNS)

2. **GPU Passthrough (Zephyr)**: Successfully achieved
   - 2 GPUs visible: `/dev/nvidia0` (RTX 3060 Ti), `/dev/nvidia1` (RTX 3090)
   - All NVIDIA device nodes accessible in containers
   - GPU resources schedulable: `nvidia.com/gpu: 2`

3. **Compute Workload Monitor**: Running and functional for CPU workloads
   - Detects: Gaming, AI processes, Builds, Mining
   - Manages GPU power/clock profiles per workload type
   - Pauses mining during builds using systemd CPUQuota

4. **Mining Services**: Operational
   - lolminer-nvidia: Running on GPU 1 (RTX 3090)
   - xmrig: Configured for CPU mining (RandomX algorithm)
   - Service hardening and resource limits configured

---

## ❌ Critical Gaps (What's Broken)

### Gap 1: No Kubernetes GPU Workload Detection

**Problem**: Mining has zero awareness of Kubernetes GPU scheduling

**Impact**:
- Kubernetes schedules GPU pods but they can't actually use GPU (mining holds it 100%)
- No preemption mechanism
- Resource conflicts guaranteed

**Example**:
```bash
# Mining running on GPU 1
$ nvidia-smi --query-gpu=index,utilization.gpu --format=csv
1, 100  # Mining at 100%

# Kubernetes schedules GPU workload to GPU 1
$ kubectl apply -f gpu-test.yaml
pod/gpu-test-phase1 created

# RESULT: Pod scheduled but cannot access GPU (mining holds it)
# No coordination, no preemption, pure collision
```

---

### Gap 2: GPU Utilization Imbalance

**Problem**: GPU 0 (3060 Ti) completely idle while GPU 1 (3090) mines

**Current State**:
```
GPU 0 (RTX 3060 Ti): 0% utilization, 154MB VRAM used - IDLE
GPU 1 (RTX 3090): 100% utilization, 8895MB VRAM used - MINING
```

**Impact**:
- Mining revenue: 0 MH/s from GPU 0 (wasted capacity)
- Kubernetes: Can't use GPU 1 (blocked by mining)
- Cluster: Only 2 of 4 physical GPUs usable (50% waste)

---

### Gap 3: No GPU Workload Preemption

**Problem**: Mining cannot be paused when Kubernetes needs GPU resources

**Current Mechanisms** (work for CPU workloads):
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

**Missing for Kubernetes**:
```bash
# NOT IMPLEMENTED:
if kubectl_has_gpu_pods "zephyr"; then
  systemctl pause lolminer-nvidia  # How? No such command
fi
```

---

### Gap 4: Control Plane Fragility

**Problem**: CRI-O restart causes cascading cluster failure

**Incident Timeline** (2026-03-10):
```
04:46:01 - CRI-O restarted for NVIDIA runtime configuration
04:46:01 - kube-apiserver: Deactivating (signal termination)
04:55:16 - kube-scheduler: "dial tcp 10.1.1.110:6443: connection refused"
04:55:26 - kube-scheduler: Leaderelection lost, exit code=1/FAILURE
04:57:19 - Manual restart required
```

**Impact**:
- **11 minutes of cluster downtime**
- No kubectl access
- No pod scheduling
- Manual intervention required

---

### Gap 5: Forge GPU Registration Failure

**Problem**: 2x RTX 4060 GPUs not registering with device plugin

**Current State**:
```
Forge Device Plugin:
  STATUS: CrashLoopBackOff
  ERROR: "No devices found"
  IMPACT: 2 GPUs unavailable cluster-wide
```

**Potential Causes**:
- Ada Lovelace architecture (RTX 40xx) driver support
- CUDA version mismatch
- CDI generation failure

---

### Gap 6: No GPU Utilization Monitoring

**Problem**: Relying on process names insufficient for GPU workloads

**Why This Fails**:
- GPU pods don't have predictable process names
- Containerized processes don't appear in host `ps` output
- GPU utilization can happen without host-visible processes

---

## 📋 Implementation Plan (6 Phases)

### Phase 1: Kubernetes GPU Workload Detection (4-6 hours)

**Objective**: Enable compute-workload-monitor to detect Kubernetes GPU pods

**What Gets Built**:
- kubectl integration into compute-workload-monitor
- Function to query GPU pods on current node
- Integration into workload priority chain

**Success**: Mining pauses when GPU pod scheduled

**Priority**: ⚠️ HIGH (blocks K8s GPU workload coordination)

---

### Phase 2: GPU Utilization Monitoring (3-4 hours)

**Objective**: Add nvidia-smi polling for actual GPU utilization detection

**What Gets Built**:
- GPU utilization polling (30-second interval)
- External workload detection (non-mining GPU usage)
- Integration into workload detection

**Success**: External GPU workloads detected accurately, no false positives

**Priority**: ⚠️ MEDIUM (improves detection accuracy)

---

### Phase 3: Preemption Mechanism (6-8 hours)

**Objective**: Implement pause/resume mechanism for Kubernetes GPU workloads

**What Gets Built**:
- Pause state tracking in `/run/compute-workload-monitor/`
- Resume logic with safety checks
- 60-second cooldown to prevent resume storms

**Success**: End-to-end test: schedule GPU pod → mining pauses → pod completes → mining resumes

**Priority**: ⚠️ HIGH (enables automatic coordination)

---

### Phase 4: GPU Utilization Balancing (1-2 hours)

**Objective**: Optimize GPU allocation between mining and Kubernetes

**Option A: Move Mining to GPU 0** (Quick Win)
- Change mining from GPU 1 to GPU 0
- GPU 1 (3090, more powerful) available for K8s
- Simple configuration change

**Option B: Time-Sharing Both GPUs** (Advanced)
- Mining at 10% when idle
- Yields 100% when K8s pod scheduled
- More complex coordination

**Recommendation**: Implement Option A first (quick win), defer Option B

**Priority**: ⚠️ MEDIUM (optimization, not blocker)

---

### Phase 5: Control Plane Robustness (8-10 hours)

**Objective**: Prevent cascading failures during CRI-O restarts

**What Gets Built**:
- Systemd dependency ordering (CRI-O → kubelet → API server)
- Health check probes (ExecStartPre scripts)
- Graceful restart script
- Documentation

**Success**: CRI-O restart doesn't cascade to cluster failure

**Priority**: ✅ **CRITICAL** (blocks all K8s work during CRI-O restarts)

---

### Phase 6: Forge GPU Registration Investigation (6-8 hours)

**Objective**: Diagnose and fix Forge RTX 4060 GPU registration failure

**What Gets Done**:
- Diagnostic report on Forge GPU failure
- Implement fix (driver update, device plugin version change, or CDI config)
- Verify 2x RTX 4060 GPUs registered
- Update cluster GPU capacity from 2 to 4 GPUs

**Success**: Forge GPUs operational, cluster has 4 GPUs

**Priority**: ⚠️ LOW (2 GPUs nice-to-have, can defer)

---

## 📊 Summary Table

| Phase | Name | Priority | Effort | Dependencies | Status |
|-------|------|----------|---------|--------------|---------|
| 1 | Kubernetes GPU Detection | ⚠️ HIGH | 4-6h | None | 🔴 Not Started |
| 2 | GPU Utilization Monitoring | ⚠️ MEDIUM | 3-4h | None | 🔴 Not Started |
| 3 | Preemption Mechanism | ⚠️ HIGH | 6-8h | Phase 1 | 🔴 Not Started |
| 4 | GPU Balancing | ⚠️ MEDIUM | 1-2h | Phase 3 | 🔴 Not Started |
| 5 | Control Plane Robustness | ✅ CRITICAL | 8-10h | None | 🔴 Not Started |
| 6 | Forge GPU Registration | ⚠️ LOW | 6-8h | None | 🔴 Not Started |

**Total Effort**: 30-40 hours across 3 weeks

---

## 🎯 Recommended Implementation Order

### Week 1 (Mar 10-16): Foundation (16 hours)

1. **Phase 5** (Control Plane Robustness) - **DO FIRST**
   - **Why**: Blocks all testing, CRI-O restarts break cluster
   - **Impact**: Prevents cascading failures
   - **Effort**: 10 hours

2. **Phase 1** (Kubernetes GPU Detection)
   - **Why**: Unlocks Phase 3 (Preemption)
   - **Impact**: Core coordination mechanism
   - **Effort**: 6 hours

### Week 2 (Mar 17-23): Coordination (10 hours)

3. **Phase 3** (Preemption Mechanism)
   - **Why**: Enables automatic coordination
   - **Impact**: Mining pauses/resumes automatically
   - **Effort**: 8 hours

4. **Phase 4 Option A** (Move Mining to GPU 0)
   - **Why**: Quick win for GPU allocation
   - **Impact**: GPU 1 available for K8s
   - **Effort**: 2 hours

### Week 3 (Mar 24-30): Optimization (16.5 hours)

5. **Phase 2** (GPU Utilization Monitoring)
   - **Why**: Improves detection accuracy
   - **Impact**: Better external workload detection
   - **Effort**: 4.5 hours

6. **Phase 6** (Forge GPU Registration)
   - **Why**: Increases cluster GPU capacity
   - **Impact**: 2 additional GPUs
   - **Effort**: 12 hours

---

## 📚 Documentation Created

1. **Comprehensive Gap Analysis** (43 pages)
   - File: `/etc/nixos/docs/research/compute-scheduler-gaps-analysis.md`
   - Content: Detailed analysis of all 6 gaps, root causes, impacts
   - Includes: Current state analysis, implementation approaches, success metrics

2. **Implementation Tracker** (28 pages)
   - File: `/etc/nixos/docs/research/compute-scheduler-implementation-tracker.md`
   - Content: Task-level breakdown for each phase
   - Includes: Time estimates, dependencies, acceptance criteria, progress tracking

3. **ROADMAP.md Update**
   - File: `/etc/nixos/ROADMAP.md`
   - Content: Phase 1 status updated to 80% complete
   - Includes: Links to gap analysis, outstanding issues, next steps

---

## ✅ Success Criteria

### Phase 1 Success
- [ ] compute-workload-monitor detects Kubernetes GPU pods
- [ ] Mining pauses when GPU pod scheduled
- [ ] Mining resumes when GPU pod completes
- [ ] No manual intervention required

### Phase 5 Success (CRITICAL)
- [ ] CRI-O restart does not cascade to control plane failure
- [ ] Health check probes prevent premature startup
- [ ] Graceful restart script tested and documented
- [ ] Zero manual intervention required for CRI-O restarts

---

## 🚀 Next Steps

### Immediate (This Week)

1. **Start Phase 5** (Control Plane Robustness)
   - Task 5.1: Add systemd dependency ordering
   - Task 5.2: Add CRI-O health check for kubelet
   - Task 5.3: Add kubelet health check for API server
   - **Estimated**: 6 hours

2. **Start Phase 1** (Kubernetes GPU Detection)
   - Task 1.1: Add kubectl to compute-workload-monitor PATH
   - Task 1.2: Implement `check_kubernetes_gpu_workload()` function
   - Task 1.3: Integrate into workload priority chain
   - **Estimated**: 3.5 hours

### Short-term (Next 2 Weeks)

3. **Complete Phase 5** (Control Plane Robustness)
4. **Complete Phase 1** (Kubernetes GPU Detection)
5. **Implement Phase 3** (Preemption Mechanism)
6. **Implement Phase 4 Option A** (Move Mining to GPU 0)

---

## 💡 Key Insights

1. **Current Setup**: Like having two cars but only driving one - cluster has 4 GPUs but only 2 usable, and even those have no coordination

2. **Root Cause**: compute-workload-monitor was designed for local workloads (gaming, builds) but has zero Kubernetes awareness

3. **Critical Path**: Phase 5 (control plane) is the biggest bang-for-buck - 10 hours prevents future 11-minute outages

4. **Quick Win**: Phase 4 Option A (move mining to GPU 0) is 2 hours for immediate improvement - frees GPU 1 for K8s

5. **Forge GPUs**: Nice-to-have but not blocker - cluster already functional with Zephyr's 2 GPUs

---

## 📞 How to Proceed

1. **Review the gap analysis**: `/etc/nixos/docs/research/compute-scheduler-gaps-analysis.md`
2. **Check the implementation tracker**: `/etc/nixos/docs/research/compute-scheduler-implementation-tracker.md`
3. **Approve the plan**: Confirm Phase 5 and Phase 1 as priorities
4. **Start implementation**: Begin with Phase 5, Task 5.1 (systemd dependency ordering)

---

**Document Version**: 1.0
**Last Updated**: 2026-03-10
**Status**: Ready for Your Review and Approval
