# Compute Scheduler Implementation Tracker

**Start Date**: 2026-03-10
**Target Completion**: 2026-03-31 (3 weeks)
**Overall Progress**: 0% (6 phases, 0 started)

---

## Phase 1: Kubernetes GPU Workload Detection

**Objective**: Enable compute-workload-monitor to detect Kubernetes GPU pods
**Estimated Effort**: 4-6 hours
**Priority**: ⚠️ HIGH (blocks K8s GPU workload coordination)
**Status**: 🔴 NOT STARTED

### Tasks

- [ ] **Task 1.1**: Add kubectl to compute-workload-monitor PATH
  - File: `modules/services/kubernetes.nix` (find compute-workload-monitor definition)
  - Action: Add `kubectl` to environment.systemPackages or service PATH
  - Acceptance: `which kubectl` succeeds from compute-workload-monitor context
  - Estimated: 30 minutes

- [ ] **Task 1.2**: Implement `check_kubernetes_gpu_workload()` function
  - File: Find compute-workload-monitor script source (likely in `modules/services/` or `scripts/`)
  - Action: Add function to query kubectl for GPU pods on current node
  - Acceptance: Function returns 0 when GPU pod present, 1 otherwise
  - Estimated: 2 hours

- [ ] **Task 1.3**: Integrate into `get_workload_type()` priority chain
  - File: Same as Task 1.2
  - Action: Add kubernetes-gpu check after AI, before builds
  - Acceptance: `get_workload_type()` returns "kubernetes-gpu" when GPU pod present
  - Estimated: 1 hour

- [ ] **Task 1.4**: Create `apply_kubernetes_gpu_profile()` function
  - File: Same as Task 1.2
  - Action: Implement GPU mining pause using `systemctl set-property CPUQuota="0%"`
  - Acceptance: Mining pauses when GPU pod scheduled
  - Estimated: 2 hours

- [ ] **Task 1.5**: Test with gpu-test-phase1 pod
  - Command: `kubectl apply -f kubernetes-manifests/gpu-test.yaml`
  - Acceptance: Mining pauses automatically, pod runs successfully
  - Estimated: 30 minutes

**Total Estimated**: 6 hours

**Dependencies**: None (can start immediately)

**Blocked By**: None

**Blocker For**: Phase 2 (GPU utilization monitoring), Phase 3 (Preemption)

---

## Phase 2: GPU Utilization Monitoring

**Objective**: Add nvidia-smi polling for actual GPU utilization detection
**Estimated Effort**: 3-4 hours
**Priority**: ⚠️ MEDIUM (improves detection accuracy)
**Status**: 🔴 NOT STARTED

### Tasks

- [ ] **Task 2.1**: Add `check_gpu_utilization()` function
  - File: compute-workload-monitor script
  - Action: Query nvidia-smi for GPU utilization percentage
  - Acceptance: Function returns GPU utilization as integer (0-100+)
  - Estimated: 1 hour

- [ ] **Task 2.2**: Implement `check_external_gpu_workload()` function
  - File: compute-workload-monitor script
  - Action: Detect non-mining GPU utilization using thresholds
  - Acceptance: Detects AI workloads even when process names don't match
  - Estimated: 2 hours

- [ ] **Task 2.3**: Add to workload priority detection
  - File: compute-workload-monitor script
  - Action: Integrate GPU utilization checks into `get_workload_type()`
  - Acceptance: External GPU workloads detected and mining paused
  - Estimated: 1 hour

- [ ] **Task 2.4**: Optimize nvidia-smi polling frequency
  - File: compute-workload-monitor script
  - Action: Cache nvidia-smi output, poll every 30 seconds (not 10)
  - Acceptance: CPU overhead < 1%, no duplicate nvidia-smi calls
  - Estimated: 30 minutes

**Total Estimated**: 4.5 hours

**Dependencies**: None (can run in parallel with Phase 1)

**Blocked By**: None

**Blocker For**: Phase 3 (Preemption - optional, can use pod detection only)

---

## Phase 3: Preemption Mechanism

**Objective**: Implement pause/resume mechanism for Kubernetes GPU workloads
**Estimated Effort**: 6-8 hours
**Priority**: ⚠️ HIGH (enables automatic coordination)
**Status**: 🔴 NOT STARTED

### Tasks

- [ ] **Task 3.1**: Implement pause state tracking
  - File: compute-workload-monitor script
  - Action: Create `/run/compute-workload-monitor/mining-paused-for-k8s` timestamp file
  - Acceptance: Can determine if mining was paused for K8s (not other workload)
  - Estimated: 1 hour

- [ ] **Task 3.2**: Implement `resume_mining_if_safe()` function
  - File: compute-workload-monitor script
  - Action: Resume mining only if safe (no GPU pods, cooldown elapsed)
  - Acceptance: Mining resumes after GPU pod completes, no resume storms
  - Estimated: 3 hours

- [ ] **Task 3.3**: Add 60-second cooldown after pod completion
  - File: compute-workload-monitor script
  - Action: Don't resume mining until 60 seconds after last GPU pod deleted
  - Acceptance: No rapid flip-flop between mining and K8s workloads
  - Estimated: 1 hour

- [ ] **Task 3.4**: Test pause/resume cycle
  - Command: Create and delete gpu-test-phase1 pod repeatedly
  - Acceptance: Mining pauses → pod completes → 60s cooldown → mining resumes
  - Estimated: 1 hour

- [ ] **Task 3.5**: Handle edge cases
  - File: compute-workload-monitor script
  - Action: Handle multiple GPU pods, rapid pod deletion, compute-workload-monitor restart
  - Acceptance: All edge cases tested and documented
  - Estimated: 2 hours

**Total Estimated**: 8 hours

**Dependencies**: Phase 1 (Kubernetes GPU detection)

**Blocked By**: Phase 1

**Blocker For**: Phase 4 (GPU balancing - needs preemption working first)

---

## Phase 4: GPU Utilization Balancing

**Objective**: Optimize GPU allocation between mining and Kubernetes
**Estimated Effort**: 1-2 hours (Option A), 8-10 hours (Option B)
**Priority**: ⚠️ MEDIUM (optimization, not blocker)
**Status**: 🔴 NOT STARTED

### Option A: Move Mining to GPU 0 (Quick Win)

- [ ] **Task 4.1.A**: Change mining device configuration
  - File: `modules/mining/mining.nix`
  - Action: Change `lolminer.nvidia.devices` from "1" to "0"
  - Acceptance: Mining runs on GPU 0 (3060 Ti)
  - Estimated: 15 minutes

- [ ] **Task 4.2.A**: Rebuild and switch configuration
  - Command: `just switch` on zephyr
  - Action: Apply new mining configuration
  - Acceptance: lolminer-nvidia.service running on GPU 0
  - Estimated: 15 minutes

- [ ] **Task 4.3.A**: Verify GPU 1 available for K8s
  - Command: `kubectl describe node zephyr | grep nvidia.com/gpu`
  - Action: Confirm GPU 1 allocatable
  - Acceptance: GPU 1 not blocked by mining
  - Estimated: 15 minutes

- [ ] **Task 4.4.A**: Test K8s workload on GPU 1
  - Command: `kubectl apply -f kubernetes-manifests/gpu-test.yaml`
  - Action: Schedule GPU pod to zephyr
  - Acceptance: Pod runs on GPU 1, mining unaffected on GPU 0
  - Estimated: 30 minutes

- [ ] **Task 4.5.A**: Update documentation
  - File: `docs/research/compute-scheduler-gaps-analysis.md`, `README.mining-pause-tests.md`
  - Action: Document new GPU allocation
  - Acceptance: Documentation reflects GPU 0 mining, GPU 1 K8s
  - Estimated: 30 minutes

**Option A Total Estimated**: 2 hours

**Option A Dependencies**: Phase 3 (Preemption - to enable K8s to preempt GPU 0 if needed)

**Option A Blocked By**: Phase 3

**Option A Blocker For**: Option B (time-sharing)

---

### Option B: Time-Sharing Both GPUs (Advanced)

- [ ] **Task 4.1.B**: Design time-sharing profile
  - File: `docs/research/compute-scheduler-time-sharing-design.md`
  - Action: Document time-sharing algorithm and state machine
  - Acceptance: Design reviewed and approved
  - Estimated: 2 hours

- [ ] **Task 4.2.B**: Implement `apply_kubernetes_standby_profile()`
  - File: compute-workload-monitor script
  - Action: Reduce mining to 10% on both GPUs when K8s idle
  - Acceptance: Mining runs at reduced rate when no K8s workloads
  - Estimated: 3 hours

- [ ] **Task 4.3.B**: Implement dynamic preemption
  - File: compute-workload-monitor script
  - Action: When K8s pod scheduled, pause mining completely
  - Acceptance: Mining yields 100% to K8s when pod scheduled
  - Estimated: 3 hours

- [ ] **Task 4.4.B**: Test time-sharing scenarios
  - File: `docs/research/compute-scheduler-time-sharing-tests.md`
  - Action: Test various workload combinations
  - Acceptance: All scenarios tested and documented
  - Estimated: 2 hours

**Option B Total Estimated**: 10 hours

**Option B Dependencies**: Option A (must have basic GPU allocation working first)

**Option B Blocked By**: Option A

**Option B Blocker For**: None (optimization)

**Recommendation**: Implement Option A first (quick win), defer Option B for future optimization

---

## Phase 5: Control Plane Robustness

**Objective**: Prevent cascading failures during CRI-O restarts
**Estimated Effort**: 8-10 hours
**Priority**: ✅ CRITICAL (blocks all K8s work during CRI-O restarts)
**Status**: 🔴 NOT STARTED

### Tasks

- [ ] **Task 5.1**: Add systemd dependency ordering
  - File: `modules/services/kubernetes.nix`
  - Action: Configure before/after/requires for CRI-O → kubelet → API server
  - Acceptance: systemd dependency graph correct
  - Estimated: 2 hours

- [ ] **Task 5.2**: Add CRI-O health check for kubelet
  - File: `modules/services/kubernetes.nix`
  - Action: Add ExecStartPre script to wait for CRI-O readiness
  - Acceptance: kubelet waits for CRI-O before starting
  - Estimated: 2 hours

- [ ] **Task 5.3**: Add kubelet health check for API server
  - File: `modules/services/kubernetes.nix`
  - Action: Add ExecStartPre script to wait for kubelet readiness
  - Acceptance: API server waits for kubelet before starting
  - Estimated: 2 hours

- [ ] **Task 5.4**: Create graceful restart script
  - File: `scripts/graceful-k8s-restart.sh`
  - Action: Implement stop CRI-O/kubelet → restart CRI-O → start kubelet/API server sequence
  - Acceptance: Script restarts cluster without cascading failures
  - Estimated: 2 hours

- [ ] **Task 5.5**: Test CRI-O restart scenario
  - Command: Run graceful restart script, verify cluster healthy
  - Action: Test CRI-O restart doesn't cause cascading failures
  - Acceptance: CRI-O restart completes successfully, all pods healthy
  - Estimated: 1 hour

- [ ] **Task 5.6**: Document restart procedure
  - File: `docs/kubernetes/graceful-restart-procedure.md`
  - Action: Document when and how to use graceful restart script
  - Acceptance: Documentation reviewed and approved
  - Estimated: 1 hour

**Total Estimated**: 10 hours

**Dependencies**: None (can start immediately)

**Blocked By**: None

**Blocker For**: All other phases (CRI-O restarts break cluster, preventing testing)

**Priority**: ✅ **HIGHEST PRIORITY** - Should be implemented FIRST before any other phase

---

## Phase 6: Forge GPU Registration Investigation

**Objective**: Diagnose and fix Forge RTX 4060 GPU registration failure
**Estimated Effort**: 6-8 hours (highly dependent on root cause)
**Priority**: ⚠️ LOW (2 GPUs unavailable, but cluster still functional)
**Status**: 🔴 NOT STARTED

### Diagnostic Tasks

- [ ] **Task 6.1**: Check nvidia-smi on Forge
  - Command: `ssh forge "nvidia-smi --query-gpu=index,name,driver_version,cuda_version --format=csv"`
  - Action: Verify GPUs detected by driver on Forge
  - Acceptance: Know driver version, CUDA version, GPU count on Forge
  - Estimated: 30 minutes

- [ ] **Task 6.2**: Check CDI files on Forge
  - Command: `ssh forge "ls -la /var/run/nvidia-cdi/"`
  - Action: Verify CDI files exist for RTX 4060 GPUs
  - Acceptance: Know if CDI generation succeeded on Forge
  - Estimated: 30 minutes

- [ ] **Task 6.3**: Check device plugin logs on Forge
  - Command: `ssh forge "sudo journalctl -u nvidia-device-plugin-daemonset -n 100 --no-pager"`
  - Action: Get exact error message from device plugin
  - Acceptance: Know root cause of "No devices found" error
  - Estimated: 30 minutes

- [ ] **Task 6.4**: Compare driver versions between nodes
  - Command: Check nvidia-smi on zephyr, forge, nexus
  - Action: Verify all nodes have same driver version
  - Acceptance: Know if driver version mismatch is issue
  - Estimated: 30 minutes

- [ ] **Task 6.5**: Generate diagnostic report
  - File: `docs/research/forge-gpu-registration-diagnostic-report.md`
  - Action: Document all findings from Tasks 6.1-6.4
  - Acceptance: Diagnostic report reviewed and root cause identified
  - Estimated: 2 hours

### Fix Implementation Tasks (dependent on root cause)

- [ ] **Task 6.6**: Implement fix (driver update, device plugin version change, or CDI config)
  - File: Dependent on root cause
  - Action: Apply fix based on diagnostic report
  - Acceptance: Fix applied and tested
  - Estimated: 2-4 hours (highly variable)

- [ ] **Task 6.7**: Verify Forge GPUs registered
  - Command: `kubectl get nodes forge -o jsonpath='{.status.allocatable.nvidia\.com/gpu}'`
  - Action: Confirm 2 GPUs allocatable on Forge
  - Acceptance: Forge shows 2 GPUs allocatable
  - Estimated: 30 minutes

- [ ] **Task 6.8**: Test GPU workload on Forge
  - Command: `kubectl apply -f kubernetes-manifests/gpu-test.yaml` with nodeSelector
  - Action: Schedule GPU pod to Forge
  - Acceptance: Pod runs successfully on Forge
  - Estimated: 1 hour

**Total Estimated**: 8 hours (diagnostic) + 2-4 hours (fix) = 10-12 hours

**Dependencies**: None (can run in parallel with other phases)

**Blocked By**: None

**Blocker For**: None (optimization, 2 GPUs nice-to-have)

**Priority**: ⚠️ LOW - Can be deferred if other phases take priority

---

## Overall Progress Tracking

### Phase Status Summary

| Phase | Name | Priority | Status | Dependencies | Blocker For | Progress |
|-------|------|----------|---------|--------------|-------------|----------|
| 1 | Kubernetes GPU Detection | ⚠️ HIGH | 🔴 NOT STARTED | None | 2, 3 | 0/5 tasks |
| 2 | GPU Utilization Monitoring | ⚠️ MEDIUM | 🔴 NOT STARTED | None | 3 (optional) | 0/4 tasks |
| 3 | Preemption Mechanism | ⚠️ HIGH | 🔴 NOT STARTED | 1 | 4 | 0/5 tasks |
| 4 | GPU Utilization Balancing | ⚠️ MEDIUM | 🔴 NOT STARTED | 3 | None | 0/10 tasks |
| 5 | Control Plane Robustness | ✅ CRITICAL | 🔴 NOT STARTED | None | ALL | 0/6 tasks |
| 6 | Forge GPU Registration | ⚠️ LOW | 🔴 NOT STARTED | None | None | 0/8 tasks |

### Recommended Implementation Order

1. **Phase 5** (Control Plane Robustness) - **DO FIRST**
   - Blocks all testing
   - CRI-O restarts break cluster
   - Highest impact, medium effort

2. **Phase 1** (Kubernetes GPU Detection)
   - Unlocks Phase 3 (Preemption)
   - Core coordination mechanism
   - High impact, low effort

3. **Phase 3** (Preemption Mechanism)
   - Enables automatic coordination
   - High impact, medium effort

4. **Phase 4 Option A** (Move Mining to GPU 0)
   - Quick win for GPU allocation
   - Medium impact, low effort

5. **Phase 2** (GPU Utilization Monitoring)
   - Improves detection accuracy
   - Optional for Phase 3
   - Medium impact, low effort

6. **Phase 6** (Forge GPU Registration)
   - Optimization, not blocker
   - Low impact (2 GPUs), high effort
   - Can defer

### Time Estimates

- **Week 1** (Mar 10-16): Phase 5 (10h) + Phase 1 (6h) = **16 hours**
- **Week 2** (Mar 17-23): Phase 3 (8h) + Phase 4A (2h) = **10 hours**
- **Week 3** (Mar 24-30): Phase 2 (4.5h) + Phase 6 (12h) + buffer = **16.5 hours**

**Total Estimated**: **42.5 hours** across 3 weeks

**Buffer Built In**: ~7.5 hours for unforeseen issues

---

## Success Criteria

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

## Notes

**2026-03-10**: Initial tracker created. All phases in NOT STARTED state. Ready to begin Phase 5 (Control Plane Robustness) as highest priority blocker.

**Next Action**: Start Phase 5, Task 5.1 (Add systemd dependency ordering)

---

**Document Version**: 1.0
**Last Updated**: 2026-03-10
**Status**: Ready for Implementation
