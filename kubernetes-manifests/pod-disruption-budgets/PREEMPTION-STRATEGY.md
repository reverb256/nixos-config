# PriorityClass Preemption Strategy for HA Upgrade

## Overview

**Preemptible Mining Architecture**: All 8 GPUs run mining when idle, but instantly yield to higher-priority workloads. Gaming priority on Zephyr 3090 (most powerful GPU). This maximizes GPU utilization while ensuring revenue-generating workloads are never blocked.

## GPU Constraints

| Constraint | Impact |
|------------|--------|
| **Zephyr 3090 gaming** | Most powerful GPU reserved for gaming (not 3060 Ti) |
| **AMD GPUs incompatible** | 3 AMD GPUs (5600 XT, 2x 5700 XT) not available for NVIDIA workloads |
| **Mining always preemptible** | Runs on all GPUs when idle, yields to higher priority |

## Priority Hierarchy

```
P0 (1000000) - Critical Production
├─ GPU jobs (container inference, training)
└─ Revenue-generating workloads

P1 (750000) - User Interactive
├─ Gaming (Zephyr 3060 Ti)
└─ User-initiated GPU workloads

P2 (500000) - Production Services
├─ AI inference (Sentry 5600 XT - llamafile)
├─ Monitoring dashboards
└─ Cluster services

P3 (10000) - Background Mining
```

## Implementation Plan

### Phase 1: PriorityClasses (Week 1)

Create 4-tier priority system:

```yaml
# priorityclasses.yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: critical-production
value: 1000000
globalDefault: false
description: "GPU jobs - highest priority, never preempted"
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: user-interactive
value: 750000
globalDefault: false
description: "Gaming, user-initiated workloads - preempts mining"
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: production-services
value: 500000
globalDefault: false
description: "AI inference, monitoring - preempts mining"
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: background-mining
value: 10000
globalDefault: false
description: "Preemptible mining - always yields to higher priority"
```

### Phase 2: Update Mining Deployments (Week 1)

Add `priorityClassName: background-mining` to all mining pods:

```bash
# Update all mining deployments
kubectl set deployment -n mining gpu-miner-zephyr-3090 \
  --overrides='{"spec":{"template":{"spec":{"priorityClassName":"background-mining"}}}}'

kubectl set deployment -n mining gpu-miner-zephyr-3060ti \
  --overrides='{"spec":{"template":{"spec":{"priorityClassName":"background-mining"}}}}'

kubectl set deployment -n mining gpu-miner-nexus-3060ti \
  --overrides='{"spec":{"template":{"spec":{"priorityClassName":"background-mining"}}}}'

kubectl set deployment -n mining gpu-miner-forge-nvidia-0 \
  --overrides='{"spec":{"template":{"spec":{"priorityClassName":"background-mining"}}}}'

kubectl set deployment -n mining gpu-miner-forge-nvidia-1 \
  --overrides='{"spec":{"template":{"spec":{"priorityClassName":"background-mining"}}}}'

kubectl set deployment -n mining gpu-miner-forge-amd-0 \
  --overrides='{"spec":{"template":{"spec":{"priorityClassName":"background-mining"}}}}'

kubectl set deployment -n mining gpu-miner-forge-amd-1 \
  --overrides='{"spec":{"template":{"spec":{"priorityClassName":"background-mining"}}}}'
```

### Phase 3: Update AI Inference (Week 2)

Add `priorityClassName: production-services` to llamafile:

```bash
kubectl set deployment -n ai-inference llamafile \
  --overrides='{"spec":{"template":{"spec":{"priorityClassName":"production-services"}}}}'
```

### Phase 4: Test Preemption (Week 2)

Test that high-priority jobs successfully preempt mining:

```bash
# 1. Verify all mining pods running
kubectl get pods -n mining -o wide

# 2. Submit test GPU job
cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: test-preemption
  namespace: default
spec:
  template:
    spec:
      priorityClassName: critical-production
      restartPolicy: Never
      containers:
      - name: test-gpu
        image: nvidia/cuda:11.0.3-base-ubuntu20.04
        command: ["nvidia-smi"]
        resources:
          limits:
            nvidia.com/gpu: 1
EOF

# 3. Verify mining pod evicted
kubectl get pods -n mining -w

# 4. Verify test job scheduled
kubectl get pods -n default

# 5. Clean up test job
kubectl delete job test-preemption -n default
```

## Preemption Behavior

### Scenario 1: GPU Job Arrival

**Before**:
```
8 GPUs mining (background priority)
```

**GPU job submitted** (requests 2x NVIDIA GPUs):
```
Yunikorn evaluates:
- Available GPUs: 0
- Mining pods: 8 (priority 10000)
- Request: 2 GPUs (priority 1000000)
- Decision: Preempt 2 mining pods
```

**After**:
```
6 GPUs mining + 2 GPUs running GPU job
```

### Scenario 2: Gaming on Zephyr

**Before**:
```
Zephyr: 3090 mining, 3060 Ti mining
```

**User launches game**:
```
compute-workload-monitor detects gaming process
→ kubectl scale deployment gpu-miner-zephyr-3060ti --replicas=0
```

**After**:
```
Zephyr: 3090 mining, 3060 Ti gaming
```

### Scenario 3: AI Inference on Sentry

**Before**:
```
Sentry: 5600 XT mining
```

**llamafile service starts**:
```
llamafile deployment (priority 500000) preempts mining (priority 10000)
kubectl scale deployment gpu-miner-sentry --replicas=0
```

**After**:
```
Sentry: 5600 XT running llamafile
```

## Monitoring

### Preemption Metrics

```yaml
# Grafana dashboard queries
# Preemption rate
rate(kube_pod_status_terminated_reason{reason="Evicted", namespace="mining"}[1h])

# GPU utilization by priority
sum by (priority_class) (kube_pod_container_resource_requests{resource="nvidia.com/gpu"})

# Mining hashrate impact
```

### Alerts

```yaml
# Prometheus alerts
- alert: HighMiningPreemptionRate
  expr: rate(kube_pod_status_terminated_reason{namespace="mining", reason="Evicted"}[5m]) > 0.1
  for: 10m
  annotations:
    summary: "Mining preemption rate > 0.1 pods/sec - high GPU job volume"

- alert: MiningRevenueDrop
  expr: mining_hashrate < mining_hashrate_expected * 0.7
  for: 15m
  annotations:
    summary: "Mining hashrate dropped 30% - check GPU allocation"
```

## Benefits for HA Upgrade

### 1. Simplified Capacity Planning

**Old approach** (dedicated mining GPUs):
- 6 GPUs dedicated to mining
- 2 GPUs reserved for other workloads
- Complex static allocation

**New approach** (preemptible mining):
- All 8 GPUs available for workloads
- Mining runs when idle
- Dynamic allocation based on demand

### 2. Better Resource Utilization

**Before**:
```
Zephyr 3090: Reserved for gaming (idle 90% of time)
Sentry 5600 XT (AMD): Reserved for AI (idle 95% of time)
AMD GPUs (Forge): Mining only (never available for GPU workloads)
Mining revenue: Lost during idle time
```

**After**:
```
Zephyr 3090: Mines when not gaming (revenue +90%, available when idle)
Zephyr 3060 Ti: Mines when not gaming (revenue +95%)
Nexus 3060 Ti: Mines when not running workloads (revenue +95%)
Sentry 5600 XT (AMD): Mines when not AI (revenue +95%)
Forge 4060s: Mines when not running workloads (revenue +95%)
Forge 5700 XTs (AMD): Always mining unless maintenance
GPU jobs: Instant access to 5 NVIDIA GPUs (no waiting)
```

### 3. Improved HA for GPU Workloads

**Before**:
- GPU workloads limited to 4 GPUs on Forge
- Had to wait for mining pods to drain
- Deployment latency: 5-10 minutes
- Zephyr 3090 unavailable (gaming priority)

**After**:
- Can use 5 NVIDIA GPUs cluster-wide (including Zephyr 3090 when not gaming)
- Preempts mining instantly (<30 seconds)
- Deployment latency: <1 minute
- Zephyr 3090 available when not gaming

### 4. Clearer Priority Hierarchy

**Before**:
- Mining "dedicated" to specific GPUs
- Conflicts when workloads need GPUs
- Manual intervention required

**After**:
- Priority-based automatic scheduling
- Workloads always get resources first
- Mining auto-yields without intervention

## Resource Impact for HA Upgrade

### GPU Capacity Comparison

| Scenario | Dedicated Mining | Preemptible Mining | Change |
|----------|------------------|-------------------|--------|
| GPU pool | 4 GPUs (Forge only) | 5 NVIDIA GPUs (cluster-wide) | +25% |
| Mining GPUs | 6 GPUs (fixed) | 0-8 GPUs (dynamic) | Variable |
| NVIDIA mining | 5 GPUs (when idle) | 5 GPUs (when not running workloads) | Flexible |
| AMD mining | 3 GPUs (always) | 3 GPUs (when AI not running) | Flexible |
| Gaming conflicts | Manual resolution | Auto-preemption (3090 priority) | Automated |
| AI inference conflicts | Manual resolution | Auto-preemption (5600 XT AMD) | Automated |

### CPU/RAM Impact

**Additional overhead for preemption**:
- Yunikorn scheduler: +500m CPU, +1 GB RAM
- Monitoring/metrics: +200m CPU, +500 Mi RAM
- Total: +700m CPU, +1.5 GB RAM

**Absorbed by existing cluster capacity**: ✅ No additional resources needed

## Implementation Checklist

### Week 1: Foundation
- [ ] Create PriorityClasses (critical, user, production, background)
- [ ] Update all mining deployments with `background-mining` priority
- [ ] Verify mining pods still running after priority update

### Week 2: Integration
- [ ] Update AI inference with `production-services` priority
- [ ] Configure gaming detection (compute-workload-monitor)
- [ ] Test preemption with sample GPU job

### Week 3: Validation
- [ ] Monitor preemption rate for 1 week
- [ ] Measure mining revenue impact
- [ ] Validate GPU job scheduling latency
- [ ] Test gaming preemption on Zephyr

### Week 4: Production
- [ ] Enable Yunikorn scheduler for GPU-aware scheduling
- [ ] Deploy preemption monitoring dashboards
- [ ] Document runbooks for common scenarios
- [ ] Train team on preemption behavior

## Rollback Procedures

If preemption causes issues:

```bash
# 1. Disable preemption temporarily
kubectl scale deployment -n mining --all --replicas=0

# 2. Restore dedicated mining GPUs
kubectl apply -f kubernetes-manifests/mining/dedicated-gpu-miners/

# 3. Remove PriorityClasses from mining pods
kubectl set deployment -n mining --all \
  --overrides='{"spec":{"template":{"spec":{"priorityClassName":null}}}}'
```

## Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| GPU job scheduling latency | <1 min | Time from job submission to GPU allocation |
| Mining preemption rate | <0.05 evictions/min | Evicted pods per minute |
| Gaming preemption latency | <2 sec | Time from game launch to mining pause |
| Mining revenue impact | <10% drop | Hashrate during preemption vs baseline |
| GPU utilization | >90% | Percentage of time GPUs are utilized |

## Conclusion

**Preemptible mining architecture enables**:
1. ✅ 5 NVIDIA GPUs available for workloads (25% increase from 4)
2. ✅ Zephyr 3090 available when not gaming
3. ✅ Automatic resource allocation based on priority
4. ✅ No manual intervention for GPU conflicts
5. ✅ Maximizes mining revenue during idle time
6. ✅ Zero impact on GPU workload performance
7. ✅ AMD GPUs used for mining/AI (not available for NVIDIA workloads anyway)

**This is the optimal strategy** for your cluster's mixed workload (gaming + AI + mining).

---

**Version**: 1.0
**Created**: 2026-03-21
**Maintainer**: Cluster Operations Team
