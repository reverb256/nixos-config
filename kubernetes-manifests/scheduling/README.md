# Kubernetes GPU Scheduler Migration
## YuniKorn + Volcano Deployment Guide

**Status**: Ready to deploy
**Timeline**: 4 weeks
**Risk Level**: Medium (with rollback procedures)

---

## Quick Start

### Option A: YuniKorn Only (Recommended - Quick Wins)

```bash
cd /etc/nixos/kubernetes-manifests/scheduling

# Install YuniKorn
./scripts/install-yunikorn.sh

# Access web UI
kubectl port-forward svc/yunikorn-service 9889:9889 -n yunikorn
# Open http://localhost:9889
```

**Time to deploy**: 30 minutes
**Features**: Priority-based scheduling, preemption, fair sharing, web UI

### Option B: YuniKorn + Volcano (Full Features)

```bash
cd /etc/nixos/kubernetes-manifests/scheduling

# Install YuniKorn first
./scripts/install-yunikorn.sh

# Then install Volcano
./scripts/install-volcano.sh

# Deploy example workloads
kubectl apply -f deployments/ai-inference-example.yaml
kubectl apply -f deployments/mining-example.yaml
```

**Time to deploy**: 1 hour
**Features**: Everything in Option A + gang scheduling, vGPU support, NUMA awareness

---

## What This Replaces

| Current (Custom Python) | Target (YuniKorn + Volcano) |
|------------------------|----------------------------|
| File-based IPC (`/run/gpu-scheduler/ai-state`) | ConfigMap-based state |
| 5-second polling interval | Event-driven watch API |
| Binary scaling (0 or 1 replicas) | Priority-based preemption |
| No metrics or observability | Prometheus + web UI |
| Manual coordination | Automatic gang scheduling |
| No GPU sharing | vGPU fractional allocation |
| Single scheduler choice | Multiple specialized schedulers |

---

## Architecture

### Before: Custom Scheduler

```
Bare Metal → File → Python Controller → K8s API → Scale Deployments
     ↓ (poll every 5s)
```

### After: Production Schedulers

```
Bare Metal → ConfigMap → YuniKorn/Volcano → Intelligent Scheduling
     ↓ (event-driven)
```

---

## Directory Structure

```
scheduling/
├── README.md (this file)
├── SCHEDULER-MIGRATION-PLAN.md (detailed 4-week plan)
├── yunikorn/
│   ├── 00-namespace.yaml
│   ├── 02-priority-classes.yaml (AI vs mining priorities)
│   ├── 03-configmap-rbac.yaml (state management)
│   └── values.yaml (Helm configuration)
├── volcano/
│   ├── 00-namespace.yaml
│   ├── 02-podgroups.yaml (gang scheduling)
│   └── 03-queues.yaml (resource quotas)
├── deployments/
│   ├── ai-inference-example.yaml
│   └── mining-example.yaml
└── scripts/
    ├── install-yunikorn.sh
    ├── install-volcano.sh
    └── rollback.sh
```

---

## Priority Classes

| Priority Class | Value | Use Case | Preemptible? |
|----------------|-------|----------|-------------|
| ai-inference-critical | 1000 | Distributed training (gang scheduling) | No |
| ai-inference-high | 900 | Interactive AI inference | No |
| ai-inference-medium | 800 | Batch AI inference | Yes (by critical) |
| mining-low | 100 | GPU mining | Yes (by AI) |
| mining-background | 50 | Opportunistic mining | Yes (by everyone) |

**Example**: AI inference (900) will automatically preempt mining (100) when GPU resources are constrained.

---

## Installation Steps

### Phase 1: YuniKorn (Week 1)

```bash
# 1. Install YuniKorn
cd /etc/nixos/kubernetes-manifests/scheduling
./scripts/install-yunikorn.sh

# 2. Verify installation
kubectl get pods -n yunikorn
kubectl get priorityclasses | grep -E "ai-inference|mining"

# 3. Test with example deployment
kubectl apply -f deployments/ai-inference-example.yaml
kubectl apply -f deployments/mining-example.yaml

# 4. Watch preemption in action
kubectl get pods -A -w
# When AI workload starts, mining should be preempted automatically

# 5. Access web UI
kubectl port-forward svc/yunikorn-service 9889:9889 -n yunikorn
# Open http://localhost:9889
```

### Phase 2: Volcano (Week 2-3)

```bash
# 1. Install Volcano
./scripts/install-volcano.sh

# 2. Verify installation
kubectl get pods -n volcano-system
kubectl get crd | grep volcano

# 3. Test gang scheduling
kubectl apply -f deployments/ai-inference-example.yaml

# 4. Verify gang scheduling behavior
kubectl describe podgroup ai-distributed-training -n ai-inference
# Should show "Waiting for 2 GPUs" until both available

# 5. Test preemption
# Start mining on all GPUs
kubectl scale deployment gpu-miner-zephyr-yunikorn -n mining --replicas=1

# Deploy high-priority AI workload
kubectl apply -f deployments/ai-inference-example.yaml

# Watch mining get preempted
kubectl get pods -n mining -w
```

---

## Rollback Procedures

### Rollback YuniKorn Only

```bash
cd /etc/nixos/kubernetes-manifests/scheduling
./scripts/rollback.sh --yunikorn
```

### Rollback Volcano Only

```bash
./scripts/rollback.sh --volcano
```

### Complete Rollback (Everything)

```bash
./scripts/rollback.sh --all

# Then re-enable custom scheduler
kubectl scale deployment k8s-gpu-scheduler -n kube-system --replicas=1

# And revert bare metal state management
git checkout modules/services/ai-inference/ai_inference_gateway/gpu_scheduler.py
just switch
```

---

## Testing

### Test 1: Priority-Based Preemption (YuniKorn)

```bash
# Deploy low-priority mining
kubectl apply -f deployments/mining-example.yaml
kubectl get pods -n mining

# Deploy high-priority AI workload
kubectl apply -f deployments/ai-inference-example.yaml

# Expected: Mining pods preempted, AI pods scheduled
kubectl get pods -A -w
```

### Test 2: Gang Scheduling (Volcano)

```bash
# Deploy 2-GPU distributed training job
kubectl apply -f deployments/ai-inference-example.yaml

# Check PodGroup status
kubectl describe podgroup ai-distributed-training -n ai-inference

# Expected: "Waiting for 2 GPUs" until both available
# Once both GPUs available, both pods start simultaneously
```

### Test 3: State Management

```bash
# Update ConfigMap state (simulating bare metal signal)
kubectl patch configmap gpu-scheduler-state -n kube-system \
  --type=merge --patch='{"data":{"ai-state":"AI_START"}}'

# Watch YuniKorn respond
kubectl logs -n yunikorn deployment/yunikorn-scheduler -f

# Reset state
kubectl patch configmap gpu-scheduler-state -n kube-system \
  --type=merge --patch='{"data":{"ai-state":"IDLE"}}'
```

---

## Monitoring

### YuniKorn Web UI

```bash
kubectl port-forward svc/yunikorn-service 9889:9889 -n yunikorn
# Open http://localhost:9889
```

**What to check**:
- Cluster utilization (CPU, memory, GPU)
- Queue status (root.default queue)
- Application scheduling decisions
- Resource allocation heatmap

### Command-Line Monitoring

```bash
# YuniKorn queues
kubectl get queues -n yunikorn
kubectl describe queue root.default -n yunikorn

# Volcano PodGroups
kubectl get podgroup -A
kubectl describe podgroup ai-inference-single-gpu -n ai-inference

# Scheduler logs
kubectl logs -n yunikorn deployment/yunikorn-scheduler -f
kubectl logs -n volcano-system deployment/volcano-scheduler -f

# Scheduling events
kubectl get events -A --field-selector involvedObject.kind=Pod
```

---

## Troubleshooting

### Pods Not Scheduling

```bash
# Check why pod isn't scheduled
kubectl describe pod <pod-name> | grep -A 20 "Events"

# Check resource availability
kubectl describe node | grep -A 10 "Allocated resources"

# Check scheduler decisions
kubectl logs -n yunikorn deployment/yunikorn-scheduler | grep "scheduling"
```

### Preemption Not Working

```bash
# Check priority classes
kubectl get priorityclasses

# Verify pod has priority class
kubectl get pod <pod-name> -o jsonpath='{.spec.priorityClassName}'

# Check YuniKorn preemption configuration
kubectl get configmap yunikorn-config -n yunikorn -o yaml
```

### Gang Scheduling Deadlocks

```bash
# Check PodGroup status
kubectl describe podgroup <podgroup-name> -n <namespace>

# Check if minMember is achievable
kubectl get nodes -o jsonpath='{.items[*].status.allocatable.nvidia\.com/gpu}'

# Adjust minTaskTimeout if needed
kubectl patch podgroup <podgroup-name> -n <namespace> \
  --type=merge --patch='{"spec":{"minTaskTimeout":"5m"}}'
```

---

## Performance Expectations

| Metric | Custom Scheduler | YuniKorn | Volcano |
|--------|-----------------|----------|---------|
| Scheduling latency | 5s (polling) | <1s (event) | <1s (event) |
| Preemption time | 5-10s | <5s | <5s |
| GPU utilization | 70-80% | 90-95% | 95%+ |
| Scheduler throughput | ~1 pod/s | ~100 pods/s | ~100 pods/s |
| Observability | None | Web UI + metrics | Metrics + logs |

---

## Migration Checklist

### Pre-Migration
- [ ] Review SCHEDULER-MIGRATION-PLAN.md
- [ ] Backup current scheduler deployment
- [ ] Document current scheduler behavior
- [ ] Set up monitoring baseline
- [ ] Test rollback procedures

### Phase 1: YuniKorn
- [ ] Install YuniKorn
- [ ] Create priority classes
- [ ] Deploy ConfigMap state management
- [ ] Update bare metal state signaling
- [ ] Test parallel operation (custom + YuniKorn)
- [ ] Migrate deployments to YuniKorn
- [ ] Disable custom scheduler
- [ ] Monitor for 1 week

### Phase 2: Volcano
- [ ] Install Volcano
- [ ] Create PodGroups
- [ ] Create queues
- [ ] Test gang scheduling
- [ ] Test multi-GPU scenarios
- [ ] Enable advanced features (vGPU, NUMA)
- [ ] Monitor for 1 week

### Post-Migration
- [ ] Remove custom scheduler deployment
- [ ] Remove custom scheduler code
- [ ] Update documentation
- [ ] Train team on new schedulers
- [ ] Update runbooks

---

## Support and Documentation

**Official Documentation**:
- [YuniKorn Docs](https://yunikorn.apache.org/docs/)
- [Volcano Docs](https://volcano.sh/docs/)

**Community**:
- [YuniKorn Slack](https://yunikorn.apache.org/community/)
- [Volcano Slack](https://volcano-sh.slack.com/)

**Issues**:
- [YuniKorn GitHub](https://github.com/apache/yunikorn-core/issues)
- [Volcano GitHub](https://github.com/volcano-sh/volcano/issues)

---

**Version**: 1.0
**Last Updated**: 2026-03-19
**Maintained By**: Infrastructure Team
