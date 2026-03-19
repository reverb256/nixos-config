# Kubernetes GPU Scheduler Migration Plan
## YuniKorn + Volcano Deployment Strategy

**Version**: 1.0
**Created**: 2026-03-19
**Status**: Planning
**Target Completion**: 4 weeks

---

## Executive Summary

**Objective**: Replace custom Python-based GPU scheduler (`scripts/k8s-gpu-scheduler.py`) with production-grade schedulers (YuniKorn + Volcano) for improved reliability, observability, and feature set.

**Current State**:
- Custom Python controller with file-based IPC
- 5-second polling interval
- Binary scaling (0 or 1 replicas)
- No metrics, logging, or observability
- Manual coordination between bare metal and K8s

**Target State**:
- YuniKorn for priority-based scheduling (AI vs mining)
- Volcano for gang scheduling and vGPU support
- Event-driven architecture (no polling)
- Prometheus metrics + web UI
- Kubernetes-native state management

**Business Value**:
- **Reliability**: Production-tested schedulers at scale
- **Performance**: Sub-second latency vs 5-second polling
- **Observability**: Built-in metrics and dashboards
- **Features**: Gang scheduling, vGPU, preemption, NUMA awareness
- **Maintainability**: No custom code to maintain

---

## Architecture Overview

### Current Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    BARE METAL                                │
│  compute-workload-monitor.nix                               │
│         ↓                                                    │
│  AI workload detection                                       │
│         ↓                                                    │
│  Write state to /run/gpu-scheduler/ai-state                  │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│                    KUBERNETES                                │
│  k8s-gpu-scheduler.py (custom Python controller)             │
│         ↓ (poll every 5s)                                    │
│  Read state file from hostPath                               │
│         ↓                                                    │
│  Scale mining deployments (0 or 1 replicas)                  │
└─────────────────────────────────────────────────────────────┘
```

### Target Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    BARE METAL                                │
│  compute-workload-monitor.nix                               │
│         ↓                                                    │
│  AI workload detection                                       │
│         ↓                                                    │
│  Update ConfigMap: gpu-scheduler-state                       │
│  (kubectl patch configmap -n kube-system)                    │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│                    KUBERNETES                                │
│                                                              │
│  ┌──────────────────┐        ┌──────────────────┐           │
│  │   YuniKorn       │        │    Volcano       │           │
│  │  (Primary)       │        │   (Advanced)     │           │
│  │                  │        │                  │           │
│  │ • Priority       │        │ • Gang sched     │           │
│  │ • Preemption     │        │ • vGPU support   │           │
│  │ • Fair share     │        │ • NUMA aware     │           │
│  └──────────────────┘        └──────────────────┘           │
│           ↓                           ↓                       │
│    Watch ConfigMap              Advanced features            │
│           ↓                           ↓                       │
│  Scale mining deployments          Fractional GPUs           │
│  based on priority classes      Distributed training         │
└─────────────────────────────────────────────────────────────┘
```

---

## Migration Phases

### Phase 0: Preparation (Week 0)
**Duration**: 2-3 days
**Risk**: Low
**Goal**: Prepare infrastructure and documentation

**Tasks**:
1. ✅ Create scheduler migration plan (this document)
2. Create Kubernetes manifests directory structure
3. Document current scheduler behavior and edge cases
4. Identify all deployments that will use schedulers
5. Create rollback procedures documentation
6. Set up monitoring baseline (current scheduler metrics)

**Deliverables**:
- [x] Migration plan document
- [ ] `kubernetes-manifests/scheduling/` directory structure
- [ ] Current behavior documentation
- [ ] Rollback playbooks
- [ ] Baseline metrics dashboard

**Success Criteria**:
- All stakeholders reviewed and approved plan
- Test environment ready for scheduler deployment
- Rollback procedures documented and tested

---

### Phase 1: YuniKorn Deployment (Week 1)
**Duration**: 5-7 days
**Risk**: Medium
**Goal**: Deploy YuniKorn alongside existing scheduler (parallel operation)

#### Week 1, Day 1-2: YuniKorn Installation

**Manifests to Create**:
```yaml
# kubernetes-manifests/scheduling/yunikorn/
├── 00-namespace.yaml
├── 01-helm-release.yaml
├── 02-priority-classes.yaml
└── 03-configmap-rbac.yaml
```

**Step 1: Create namespace and RBAC**
```bash
kubectl create namespace yunikorn
kubectl apply -f kubernetes-manifests/scheduling/yunikorn/03-configmap-rbac.yaml
```

**Step 2: Deploy YuniKorn via Helm**
```bash
helm repo add yunikorn https://apache.github.io/yunikorn-release
helm repo update
helm install yunikorn yunikorn/yunikorn \
  --namespace yunikorn \
  --set admissionsController.enable=true \
  --set image.tag=v1.4.0 \
  --values kubernetes-manifests/scheduling/yunikorn/values.yaml
```

**Step 3: Verify deployment**
```bash
kubectl get pods -n yunikorn
kubectl port-forward svc/yunikorn-service 9889:9889 -n yunikorn
# Open http://localhost:9889
```

**Step 4: Create priority classes**
```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: ai-inference-critical
value: 1000
globalDefault: false
description: "Critical priority for AI inference workloads"
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: ai-inference-high
value: 900
globalDefault: false
description: "High priority for AI inference workloads"
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: mining-low
value: 100
globalDefault: false
description: "Low priority for mining workloads"
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: mining-background
value: 50
globalDefault: false
description: "Background priority for mining workloads"
```

#### Week 1, Day 3-4: State Management Migration

**Replace file-based IPC with ConfigMap-based state**

**Current**: Bare metal writes to `/run/gpu-scheduler/ai-state`
**Target**: Bare metal updates ConfigMap via kubectl

**Update to `modules/services/ai-inference/ai_inference_gateway/gpu_scheduler.py`**:
```python
def notify_ai_starting() -> bool:
    """Signal GPU scheduler that AI workload is starting."""
    try:
        subprocess.run([
            "kubectl", "patch", "configmap", "gpu-scheduler-state",
            "-n", "kube-system",
            "--type=merge",
            "--patch={\"data\":{\"ai-state\":\"AI_START\"}}"
        ], check=True, capture_output=True)
        return True
    except subprocess.CalledProcessError as e:
        logger.error(f"Failed to update scheduler state: {e}")
        return False

def notify_ai_stopping() -> bool:
    """Signal GPU scheduler that AI workload is stopping."""
    try:
        subprocess.run([
            "kubectl", "patch", "configmap", "gpu-scheduler-state",
            "-n", "kube-system",
            "--type=merge",
            "--patch={\"data\":{\"ai-state\":\"AI_STOP\"}}"
        ], check=True, capture_output=True)
        return True
    except subprocess.CalledProcessError as e:
        logger.error(f"Failed to update scheduler state: {e}")
        return False
```

**Create ConfigMap**:
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: gpu-scheduler-state
  namespace: kube-system
data:
  ai-state: "IDLE"
  last-updated: "2026-03-19T00:00:00Z"
```

**Create RBAC for bare metal host**:
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: gpu-scheduler-state-updater
  namespace: kube-system
rules:
  - apiGroups: [""]
    resources: ["configmaps"]
    resourceNames: ["gpu-scheduler-state"]
    verbs: ["get", "patch", "update"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: gpu-scheduler-state-updater
  namespace: kube-system
subjects:
  - kind: User
    name: "system:node:zephyr"  # Bare metal hostname
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: gpu-scheduler-state-updater
  apiGroup: rbac.authorization.k8s.io
```

#### Week 1, Day 5-7: Test Parallel Operation

**Test custom scheduler + YuniKorn running simultaneously**

**Test Matrix**:
| Scenario | Custom Scheduler | YuniKorn | Expected Behavior |
|----------|-----------------|----------|-------------------|
| AI idle | Mining scaled to 1 | Mining at low priority | Mining runs |
| AI starting | Mining scaled to 0 | Mining preempted | Mining stops |
| AI running | Mining scaled to 0 | Mining preempted | Mining stopped |
| AI stopping | Mining scaled to 1 | Mining resumes | Mining starts |

**Validation Commands**:
```bash
# Watch mining deployment replicas
kubectl get deployment -n mining -w

# Check scheduler decisions
kubectl describe pod <mining-pod> -n mining | grep -A 10 "Events"

# View YuniKorn scheduling decisions
kubectl logs -n yunikorn deployment/yunikorn-scheduler | grep "scheduling"

# Access YuniKorn UI
kubectl port-forward svc/yunikorn-service 9889:9889 -n yunikorn
```

**Success Criteria**:
- ✅ YuniKorn deployed and accessible via web UI
- ✅ Priority classes created and applied to test deployments
- ✅ ConfigMap state management working
- ✅ Both schedulers operating without conflicts
- ✅ Preemption working (AI pauses mining)

**Rollback Plan**:
```bash
# If YuniKorn causes issues
helm uninstall yunikorn -n yunikorn
kubectl delete priorityclass ai-inference-critical ai-inference-high mining-low mining-background
kubectl delete configmap gpu-scheduler-state -n kube-system

# Revert bare metal to file-based state
git checkout modules/services/ai-inference/ai_inference_gateway/gpu_scheduler.py
just switch
```

---

### Phase 2: Migration to YuniKorn (Week 2)
**Duration**: 5-7 days
**Risk**: Medium
**Goal**: Migrate all workloads to YuniKorn, disable custom scheduler

#### Week 2, Day 1-2: Update Deployments

**Update AI Inference Deployments**:
```yaml
# kubernetes-manifests/scheduling/deployments/
# ai-inference-deployment.yaml

apiVersion: apps/v1
kind: Deployment
metadata:
  name: ai-inference
  namespace: ai-inference
spec:
  template:
    spec:
      schedulerName: yunikorn  # Use YuniKorn scheduler
      priorityClassName: ai-inference-high
      containers:
      - name: ai-inference
        resources:
          requests:
            nvidia.com/gpu: "1"
          limits:
            nvidia.com/gpu: "1"
```

**Update Mining Deployments**:
```yaml
# gpu-miner-deployment.yaml

apiVersion: apps/v1
kind: Deployment
metadata:
  name: gpu-miner-zephyr
  namespace: mining
spec:
  template:
    spec:
      schedulerName: yunikorn  # Use YuniKorn scheduler
      priorityClassName: mining-low
      containers:
      - name: lolminer
        resources:
          requests:
            nvidia.com/gpu: "1"
          limits:
            nvidia.com/gpu: "1"
```

#### Week 2, Day 3-4: Deploy YuniKorn Admission Controller

**Update YuniKorn Helm values**:
```yaml
# kubernetes-manifests/scheduling/yunikorn/values.yaml

admissionsController:
  enable: true
  replicas: 2
  image:
    tag: v1.4.0

scheduler:
  image:
    tag: v1.4.0
  replicas: 2

web:
  image:
    tag: v1.4.0
  replicas: 1
```

**Upgrade YuniKorn**:
```bash
helm upgrade yunikorn yunikorn/yunikorn \
  --namespace yunikorn \
  --values kubernetes-manifests/scheduling/yunikorn/values.yaml
```

#### Week 2, Day 5-7: Monitor and Validate

**Monitoring Checklist**:
- [ ] AI inference workloads scheduled at high priority
- [ ] Mining workloads scheduled at low priority
- [ ] Preemption working (AI pauses mining automatically)
- [ ] YuniKorn UI showing correct resource allocation
- [ ] No custom scheduler scheduler logs in k8s-gpu-scheduler.py
- [ ] Mining replicas scaling based on priority (not custom controller)

**Disable Custom Scheduler**:
```bash
# Scale down custom scheduler deployment to 0
kubectl scale deployment k8s-gpu-scheduler -n kube-system --replicas=0

# Verify mining still works with YuniKorn only
kubectl get deployment -n mining
kubectl logs -n yunikorn deployment/yunikorn-scheduler | tail -100
```

**Success Criteria**:
- ✅ All deployments using YuniKorn scheduler
- ✅ Custom scheduler disabled (replicas=0)
- ✅ AI inference preempts mining automatically
- ✅ No resource conflicts or scheduling failures
- ✅ YuniKorn UI showing accurate cluster state

**Rollback Plan**:
```bash
# Re-enable custom scheduler
kubectl scale deployment k8s-gpu-scheduler -n kube-system --replicas=1

# Remove schedulerName from deployments (use default scheduler)
kubectl patch deployment ai-inference -n ai-inference --type=json \
  -p='[{"op": "remove", "path": "/spec/template/spec/schedulerName"}]'

kubectl patch deployment gpu-miner-zephyr -n mining --type=json \
  -p='[{"op": "remove", "path": "/spec/template/spec/schedulerName"}]'

# Verify custom scheduler resumes control
kubectl logs -n kube-system deployment/k8s-gpu-scheduler | tail -50
```

---

### Phase 3: Volcano Deployment (Week 3)
**Duration**: 5-7 days
**Risk**: Medium-High
**Goal**: Deploy Volcano for advanced features (gang scheduling, vGPU)

#### Week 3, Day 1-2: Volcano Installation

**Manifests to Create**:
```yaml
# kubernetes-manifests/scheduling/volcano/
├── 00-namespace.yaml
├── 01-install.sh
├── 02-podgroups.yaml
└── 03-queues.yaml
```

**Install Volcano**:
```bash
kubectl apply -f https://raw.githubusercontent.com/volcano-sh/volcano/v1.9.0/installer/volcano-development.yaml

# Or use Helm (preferred)
helm repo add volcano https://volcano-sh.github.io/charts
helm repo update
helm install volcano volcano/volcano --namespace volcano-system --create-namespace
```

**Verify installation**:
```bash
kubectl get pods -n volcano-system
kubectl get crd | grep volcano
```

#### Week 3, Day 3-4: Configure Gang Scheduling

**Create PodGroups for AI workloads**:
```yaml
apiVersion: scheduling.volcano.sh/v1beta1
kind: PodGroup
metadata:
  name: ai-inference-group
  namespace: ai-inference
spec:
  minMember: 1
  minResources:
    nvidia.com/gpu: "1"
    memory: "8Gi"
    cpu: "4"
  priorityClassName: ai-inference-high
  queue: ai-queue
---
apiVersion: scheduling.volcano.sh/v1beta1
kind: PodGroup
metadata:
  name: distributed-training-group
  namespace: ai-inference
spec:
  minMember: 2  # Gang scheduling: all or nothing
  minResources:
    nvidia.com/gpu: "2"  # Requires 2 GPUs simultaneously
    memory: "16Gi"
    cpu: "8"
  priorityClassName: ai-inference-critical
  queue: ai-queue
```

**Update AI deployment to use PodGroup**:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ai-inference
  namespace: ai-inference
spec:
  template:
    spec:
      schedulerName: volcano
      priorityClassName: ai-inference-high
      # Add PodGroup label
      metadata:
        labels:
          scheduling.volcano.sh/pod-group: ai-inference-group
```

#### Week 3, Day 5-7: Test Gang Scheduling

**Test Scenarios**:

**Scenario 1: Single GPU AI workload**
```bash
# Deploy single-GPU AI workload
kubectl apply -f kubernetes-manifests/scheduling/volcano/test-single-gpu.yaml

# Expected: Scheduled immediately if 1 GPU available
kubectl describe podgroup ai-inference-group -n ai-inference
kubectl get pods -n ai-inference
```

**Scenario 2: Multi-GPU distributed training (Gang scheduling)**
```bash
# Deploy 2-GPU training job
kubectl apply -f kubernetes-manifests/scheduling/volcano/test-distributed-training.yaml

# Expected: Waits until 2 GPUs available simultaneously
kubectl describe podgroup distributed-training-group -n ai-inference

# While gang waiting, mining should continue on available GPUs
kubectl get pods -n mining
```

**Scenario 3: Preemption**
```bash
# Start mining on all GPUs
kubectl scale deployment gpu-miner-zephyr -n mining --replicas=1

# Deploy high-priority AI workload
kubectl apply -f kubernetes-manifests/scheduling/volcano/test-ai-workload.yaml

# Expected: Mining preempted, AI scheduled immediately
kubectl get pods -n mining -w
kubectl get pods -n ai-inference -w
```

**Success Criteria**:
- ✅ Volcano deployed and operational
- ✅ PodGroups created and associated with deployments
- ✅ Gang scheduling working (multi-GPU jobs wait for all resources)
- ✅ Preemption working (high-priority AI pauses mining)
- ✅ No resource fragmentation or deadlocks

**Rollback Plan**:
```bash
# Uninstall Volcano
helm uninstall volcano -n volcano-system
kubectl delete -f https://raw.githubusercontent.com/volcano-sh/volcano/v1.9.0/installer/volcano-development.yaml

# Migrate deployments back to YuniKorn
kubectl patch deployment ai-inference -n ai-inference --type=json \
  -p='[{"op": "replace", "path": "/spec/template/spec/schedulerName", "value": "yunikorn"}]'

# Remove PodGroup labels
kubectl label deployment ai-inference -n ai-inference scheduling.volcano.sh/pod-group-
```

---

### Phase 4: Advanced Features (Week 4)
**Duration**: 5-7 days
**Risk**: Low
**Goal**: Enable vGPU support, NUMA awareness, observability

#### Week 4, Day 1-2: vGPU Support

**Install HAMI for vGPU**:
```bash
helm repo add hami-charts https://projecthami.github.io/charts
helm repo update
kubectl create namespace vgpu
helm install hami hami-charts/vgpu --namespace vgpu
```

**Create vGPU profiles**:
```yaml
apiVersion: scheduling.volcano.sh/v1beta1
kind: PodGroup
metadata:
  name: ai-inference-vgpu
  namespace: ai-inference
spec:
  minMember: 1
  minResources:
    volcano.sh/vgpu-number: "1"        # 1 vGPU
    volcano.sh/vgpu-memory: "8Gi"     # 8GB VRAM
  priorityClassName: ai-inference-high
---
apiVersion: v1
kind: Pod
metadata:
  name: ai-inference-vgpu
  namespace: ai-inference
spec:
  schedulerName: volcano
  containers:
  - name: ai-inference
    image: ai-inference:latest
    resources:
      limits:
        volcano.sh/vgpu-number: "1"
        volcano.sh/vgpu-memory: "8Gi"
```

#### Week 4, Day 3-4: NUMA-Aware Scheduling

**Enable NUMA plugin in Volcano**:
```yaml
# Update Volcano scheduler config
apiVersion: config.volcano.sh/v1beta1
kind: SchedulerConfiguration
metadata:
  name: volcano-scheduler-config
spec:
  actions: "enqueue,allocate,backfill"
  tiers:
  - plugins:
    - name: priority
    - name: gang
    - name: conformance
  - plugins:
    - name: overcommit
    - name: drf
    - name: predicates
    - name: nodeorder
    - name: numa-aware  # Enable NUMA awareness
```

**Test NUMA placement**:
```bash
# Deploy NUMA-aware workload
kubectl apply -f kubernetes-manifests/scheduling/volcano/test-numa.yaml

# Verify NUMA node placement
kubectl describe pod <numa-test-pod> | grep -A 10 "Allocated resources"
```

#### Week 4, Day 5-7: Observability and Monitoring

**Deploy Prometheus + Grafana**:
```bash
# Install Prometheus Operator
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install prometheus prometheus-community/kube-prometheus-stack -n monitoring

# Import YuniKorn dashboard
# https://yunikorn.apache.org/docs/user_guide/observability/prometheus
```

**Create custom metrics**:
```yaml
# kubernetes-manifests/scheduling/monitoring/servicemonitor.yaml

apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: yunikorn-scheduler
  namespace: yunikorn
spec:
  selector:
    matchLabels:
      app: yunikorn-scheduler
  endpoints:
  - port: metrics
    interval: 30s
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: volcano-scheduler
  namespace: volcano-system
spec:
  selector:
    matchLabels:
    app: volcano-scheduler
  endpoints:
  - port: metrics
    interval: 30s
```

**Grafana Dashboards**:
- YuniKorn cluster utilization
- Volcano scheduling decisions
- GPU allocation heatmap
- Preemption events timeline
- Gang scheduling state

**Success Criteria**:
- ✅ vGPU working (fractional GPU allocation)
- ✅ NUMA-aware placement optimizing performance
- ✅ Prometheus scraping scheduler metrics
- ✅ Grafana dashboards displaying cluster state
- ✅ Alerts configured for scheduling failures

**Rollback Plan**:
```bash
# Disable advanced features (keep basic schedulers)
kubectl label nodes --all volcano.sh/numa-

# Remove vGPU device sharing
helm uninstall hami -n vgpu

# Keep YuniKorn + Volcano running (they're stable)
```

---

## Testing Strategy

### Unit Tests
- [ ] ConfigMap state updates from bare metal
- [ ] Priority class assignment
- [ ] PodGroup creation and association
- [ ] vGPU resource allocation

### Integration Tests
- [ ] AI workload preempts mining (YuniKorn)
- [ ] Multi-GPU gang scheduling (Volcano)
- [ ] vGPU fractional allocation
- [ ] NUMA-aware placement
- [ ] State propagation (bare metal → K8s)

### End-to-End Tests
- [ ] AI inference lifecycle (start → run → stop)
- [ ] Mining preemption and resumption
- [ ] Distributed training with gang scheduling
- [ ] Resource exhaustion scenarios
- [ ] Scheduler failover (YuniKorn → Volcano fallback)

### Performance Tests
- [ ] Scheduling latency (target: <1s)
- [ ] Preemption time (target: <5s)
- [ ] GPU utilization (target: >90%)
- [ ] Scheduler throughput (pods/second)

---

## Rollback Procedures

### Phase Rollback

**Phase 1 Rollback (YuniKorn deployment)**:
```bash
# Stop YuniKorn
helm uninstall yunikorn -n yunikorn

# Remove priority classes
kubectl delete priorityclass ai-inference-critical ai-inference-high mining-low mining-background

# Remove ConfigMap state
kubectl delete configmap gpu-scheduler-state -n kube-system

# Verify custom scheduler still running
kubectl logs -n kube-system deployment/k8s-gpu-scheduler | tail -50
```

**Phase 2 Rollback (Migration to YuniKorn)**:
```bash
# Re-enable custom scheduler
kubectl scale deployment k8s-gpu-scheduler -n kube-system --replicas=1

# Remove schedulerName from deployments
kubectl patch deployment ai-inference -n ai-inference --type=json \
  -p='[{"op": "remove", "path": "/spec/template/spec/schedulerName"}]'

kubectl patch deployment gpu-miner-zephyr -n mining --type=json \
  -p='[{"op": "remove", "path": "/spec/template/spec/schedulerName"}]'

# Verify custom scheduler resumes control
kubectl logs -n kube-system deployment/k8s-gpu-scheduler | tail -50
```

**Phase 3 Rollback (Volcano deployment)**:
```bash
# Uninstall Volcano
helm uninstall volcano -n volcano-system

# Migrate deployments back to YuniKorn
kubectl patch deployment ai-inference -n ai-inference --type=json \
  -p='[{"op": "replace", "path": "/spec/template/spec/schedulerName", "value": "yunikorn"}]'

# Remove PodGroups
kubectl delete podgroup --all -n ai-inference

# Verify YuniKorn resumes control
kubectl logs -n yunikorn deployment/yunikorn-scheduler | tail -50
```

**Phase 4 Rollback (Advanced features)**:
```bash
# Disable vGPU
helm uninstall hami -n vgpu

# Remove NUMA labels
kubectl label nodes --all volcano.sh/numa-

# Keep YuniKorn + Volcano (they're stable)
```

### Complete Rollback (All Phases)

**Emergency rollback to custom scheduler**:
```bash
# Uninstall all schedulers
helm uninstall yunikorn -n yunikorn
helm uninstall volcano -n volcano-system
helm uninstall hami -n vgpu

# Remove all custom resources
kubectl delete priorityclass --all
kubectl delete podgroup --all -A
kubectl delete configmap gpu-scheduler-state -n kube-system

# Re-enable custom scheduler
kubectl scale deployment k8s-gpu-scheduler -n kube-system --replicas=1

# Restore bare metal file-based state
git checkout modules/services/ai-inference/ai_inference_gateway/gpu_scheduler.py
just switch

# Verify custom scheduler working
kubectl logs -n kube-system deployment/k8s-gpu-scheduler -f
```

---

## Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| YuniKorn deployment fails | Low | Medium | Test in dev environment first |
| Priority class conflicts | Medium | Low | Use unique priority values |
| Preemption not working | Medium | High | Thorough testing in Phase 2 |
| Volcano gang scheduling deadlocks | Low | High | Test gang scenarios in Phase 3 |
| vGPU performance degradation | Medium | Medium | Benchmark before/after |
| Bare metal state sync issues | Medium | High | Implement state validation |
| Rollback failures | Low | Critical | Test rollback procedures |
| Scheduler conflicts | Low | High | Run in parallel during migration |

---

## Success Criteria

### Phase 0 (Preparation)
- [ ] Migration plan approved
- [ ] Test environment ready
- [ ] Rollback procedures documented
- [ ] Baseline metrics captured

### Phase 1 (YuniKorn Deployment)
- [ ] YuniKorn deployed and accessible
- [ ] Priority classes created
- [ ] ConfigMap state management working
- [ ] Parallel operation validated
- [ ] Preemption working

### Phase 2 (Migration to YuniKorn)
- [ ] All deployments using YuniKorn
- [ ] Custom scheduler disabled
- [ ] No resource conflicts
- [ ] AI preempts mining automatically
- [ ] YuniKorn UI accurate

### Phase 3 (Volcano Deployment)
- [ ] Volcano deployed and operational
- [ ] PodGroups configured
- [ ] Gang scheduling working
- [ ] Multi-GPU scenarios validated
- [ ] No deadlocks or fragmentation

### Phase 4 (Advanced Features)
- [ ] vGPU support enabled
- [ ] NUMA-aware scheduling working
- [ ] Prometheus metrics scraping
- [ ] Grafana dashboards deployed
- [ ] Alerts configured

---

## Post-Migration Tasks

### Week 5: Cleanup
- [ ] Remove custom scheduler deployment
- [ ] Remove custom scheduler code (`scripts/k8s-gpu-scheduler.py`)
- [ ] Remove hostPath mounts for state file
- [ ] Update documentation
- [ ] Train team on new schedulers

### Week 6: Optimization
- [ ] Tune scheduler parameters based on metrics
- [ ] Optimize priority class values
- [ ] Adjust gang scheduling timeouts
- [ ] Fine-tune vGPU profiles
- [ ] Update capacity planning models

### Week 7: Documentation
- [ ] Update runbooks for scheduler operations
- [ ] Document troubleshooting procedures
- [ ] Create scheduler decision flowcharts
- [ ] Write architecture decision records (ADRs)
- [ ] Update on-call documentation

---

## Appendix

### A. Directory Structure

```
kubernetes-manifests/scheduling/
├── README.md
├── MIGRATION_PLAN.md (this file)
├── yunikorn/
│   ├── 00-namespace.yaml
│   ├── 01-helm-release.yaml
│   ├── 02-priority-classes.yaml
│   ├── 03-configmap-rbac.yaml
│   └── values.yaml
├── volcano/
│   ├── 00-namespace.yaml
│   ├── 01-install.sh
│   ├── 02-podgroups.yaml
│   ├── 03-queues.yaml
│   └── tests/
│       ├── test-single-gpu.yaml
│       ├── test-distributed-training.yaml
│       ├── test-preemption.yaml
│       └── test-numa.yaml
├── deployments/
│   ├── ai-inference-deployment.yaml
│   ├── gpu-miner-deployment.yaml
│   └── distributed-training-deployment.yaml
├── monitoring/
│   ├── servicemonitor.yaml
│   ├── prometheus-rules.yaml
│   └── grafana-dashboards/
│       ├── yunikorn-cluster.json
│       ├── volcano-scheduling.json
│       └── gpu-allocation.json
└── scripts/
    ├── install-yunikorn.sh
    ├── install-volcano.sh
    ├── test-scheduling.sh
    └── rollback.sh
```

### B. Commands Reference

**YuniKorn Operations**:
```bash
# View YuniKorn UI
kubectl port-forward svc/yunikorn-service 9889:9889 -n yunikorn

# View YuniKorn logs
kubectl logs -n yunikorn deployment/yunikorn-scheduler -f

# Check YuniKorn scheduling decisions
kubectl get queues -n yunikorn
kubectl describe queue root.default -n yunikorn
```

**Volcano Operations**:
```bash
# View PodGroups
kubectl get podgroup -A

# Describe PodGroup
kubectl describe podgroup ai-inference-group -n ai-inference

# View Volcano scheduler logs
kubectl logs -n volcano-system deployment/volcano-scheduler -f

# Check scheduling status
kubectl get vcjob -A
```

**Debugging**:
```bash
# Check why pod isn't scheduled
kubectl describe pod <pod-name> | grep -A 20 "Events"

# View scheduler events
kubectl get events -A --field-selector involvedObject.kind=Pod

# Check resource allocation
kubectl describe node | grep -A 10 "Allocated resources"

# View priority classes
kubectl get priorityclasses
```

### C. Monitoring Queries

**PromQL Queries**:
```promql
# YuniKorn cluster utilization
yunikorn_cluster_allocated_cpu{cluster="yunikorn"} / yunikorn_cluster_total_cpu{cluster="yunikorn"} * 100

# Volcano gang scheduling success rate
rate(volcano_gang_scheduling_success_total[5m]) / rate(volcano_gang_scheduling_attempts_total[5m]) * 100

# GPU allocation by namespace
sum(kube_pod_container_resource_requests{resource="nvidia_com/gpu"}) by (namespace)

# Preemption events
increase(kube_pod_status_reason{reason="Preempting"}[1h])
```

### D. Contacts and Resources

**Documentation**:
- YuniKorn: https://yunikorn.apache.org/docs/
- Volcano: https://volcano.sh/docs/
- HAMI vGPU: https://github.com/Project-HAMi/HAMI

**Community**:
- YuniKorn Slack: https://yunikorn.apache.org/community/
- Volcano Slack: https://volcano-sh.slack.com/

**Support**:
- YuniKorn GitHub: https://github.com/apache/yunikorn-core/issues
- Volcano GitHub: https://github.com/volcano-sh/volcano/issues

---

**Document Status**: ✅ Ready for Review
**Next Steps**: Stakeholder approval, begin Phase 0
**Owner**: Infrastructure Team
**Reviewers**: Platform Engineering, SRE, Data Science

**Change Log**:
- 2026-03-19: Initial plan created (v1.0)
- Future updates will be tracked here
