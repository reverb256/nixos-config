# Intelligent Xmrig Autoscaling Design

**Date**: 2026-03-22
**Status**: Design Approved
**Author**: Claude (user-approved)
**Target**: Kubernetes v1.35.2 on NixOS 26.05

---

## Executive Summary

Design an intelligent autoscaling system for CPU mining workloads (xmrig) that responds to:
- CPU availability for profitability optimization
- Resource utilization for automatic tuning
- Nix build operations (scale down during builds)
- Gaming sessions (scale down when gaming detected)

**Goals**:
1. Maximize mining profitability during idle CPU time
2. Immediately preempt mining for builds and gaming
3. Prevent resource contention with user workloads
4. Automatic tuning based on CPU availability

**Chosen Approach**: Dual-deployment HPA with Prometheus metrics, unified workload watcher daemon, and multi-factor scaling signals.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         Kubernetes Cluster                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────┐      ┌──────────────────────────────────┐   │
│  │ Gaming Mode  │      │   Workload Watcher DaemonSet     │   │
│  │ Daemon       │─────▶│   (mining namespace)             │   │
│  │ (host)       │      │   - Monitors /run/gaming-state   │   │
│  └──────────────┘      │   - Monitors /nix/var/nix/locks  │   │
│         │              │   - Publishes node annotation    │   │
│         │              │   - Exposes Prometheus metrics   │   │
│         ▼              └──────────────────────────────────┘   │
│  ┌────────────────────────────────────┐                       │
│  │  Node Workload Lock ConfigMap      │                       │
│  │  - state: idle|building|gaming     │                       │
│  └────────────────────────────────────┘                       │
│                                  │                             │
│                                  ▼                             │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │              Prometheus Adapter                          │  │
│  │  (queries xmrig_scaling_allowed metric)                  │  │
│  └─────────────────────────────────────────────────────────┘  │
│                                  │                             │
│                                  ▼                             │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │  Horizontal Pod Autoscaler (HPA)                         │  │
│  │  - minReplicas: 0                                        │  │
│  │  - maxReplicas: 1                                        │  │
│  │  - metric: xmrig_scaling_allowed == 1 (scale up)         │  │
│  │  - metric: xmrig_scaling_allowed == 0 (scale down)       │  │
│  └─────────────────────────────────────────────────────────┘  │
│                                  │                             │
│                                  ▼                             │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │  Xmrig Deployments (per-node)                            │  │
│  │  - xmrig-zephyr (32 cores)                               │  │
│  │  - xmrig-nexus (24 cores)                                │  │
│  └─────────────────────────────────────────────────────────┘  │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

---

## Components

### 1. Unified Workload Watcher DaemonSet

**Purpose**: Single lightweight daemon that monitors both build and gaming activity, publishing unified state.

**Namespace**: `mining`

**Host Access Required**:
- `/run/gaming-detection/gaming_state` (GameMode daemon state)
- `/nix/var/nix/locks/*.lock` (Nix build locks)

**Outputs**:
1. **Node Annotation**: `workload.state=idle|building|gaming`
2. **Prometheus Metrics**:
   - `workload_state{node}`: 0=idle, 1=building, 2=gaming
   - `xmrig_scaling_allowed{node}`: 1=scale up, 0=scale down
   - `workload_hysteresis_count{node,state}`: Consecutive checks in current state
   - `workload_state_transitions{node,from,to}`: Total transitions

**Priority Ordering** (higher = more important):
- Gaming: 100 (immediate preemption)
- Building: 50 (fast preemption)
- Idle: 0 (mining allowed)

**Hysteresis** (prevent flapping):
- Gaming: 5 consecutive checks (10 seconds) before scaling down
- Building: 3 consecutive checks (15 seconds) before scaling down
- Idle: 10 consecutive checks (20 seconds) before scaling up

**Check Intervals**:
- Gaming: 2s (fast response)
- Building: 5s (moderate response)
- Idle: 30s (slow recovery to avoid thrashing)

### 2. Prometheus Adapter Integration

**Purpose**: Bridge Prometheus metrics to Kubernetes HPA API.

**Configuration**:
```yaml
externalRules:
- seriesQuery: 'xmrig_scaling_allowed{node!="",namespace="mining"}'
  resources:
    overrides:
      node:
        resource: node
  metricsQuery: 'sum(xmrig_scaling_allowed{<<.LabelMatchers>>}) by (<<.GroupBy>>)'
  name:
    as: xmrig_scaling_allowed
```

**Metric API**:
```
/apis/external.metrics.k8s.io/v1beta1/namespaces/mining/xmrig_scaling_allowed
```

### 3. Horizontal Pod Autoscalers (HPA)

**Per-Node Deployments**:
- `xmrig-zephyr-hpa` (zephyr node, 32 cores)
- `xmrig-nexus-hpa` (nexus node, 24 cores)

**Configuration**:
```yaml
minReplicas: 0
maxReplicas: 1
metrics:
- type: External
  external:
    metric:
      name: xmrig_scaling_allowed
      selector:
        matchLabels:
          node: zephyr  # or nexus
    target:
      type: AverageValue
      averageValue: "1"
behavior:
  scaleDown:
    stabilizationWindowSeconds: 30
    policies:
    - type: Percent
      value: 100
      periodSeconds: 15
  scaleUp:
    stabilizationWindowSeconds: 60
    policies:
    - type: Percent
      value: 100
      periodSeconds: 30
```

**Scaling Logic**:
- `xmrig_scaling_allowed == 1`: Scale to maxReplicas (1)
- `xmrig_scaling_allowed == 0`: Scale to minReplicas (0)

### 4. Existing Gaming Detection Service

**Location**: `/run/gaming-detection/gaming_state`

**Current Implementation**: `/etc/nixos/modules/system/gaming-detection.nix`

**State File Format**:
```
GAMING_ACTIVE=1  # or 0
DETECTION_METHOD=gamemode  # or gpu_fallback
HYSTERESIS_COUNT=0
PAUSE_COUNT=42
```

**Prometheus Metrics**: `/var/lib/node_exporter/textfile_collector/gaming.prom`

---

## Data Flow

### State Transition: Idle → Gaming

```
1. User launches game
   ↓
2. GameMode daemon detects game
   ↓
3. gaming-detection service updates /run/gaming-detection/gaming_state
   GAMING_ACTIVE=1
   ↓
4. workload-watcher reads state file (next 2s check)
   ↓
5. workload-watcher increments gaming_count
   GAMING_COUNT = 1
   ↓
6. Repeat checks 2-5 (hysteresis: 5 consecutive checks)
   GAMING_COUNT = 5
   ↓
7. workload-watcher transitions state: idle → gaming
   - Update node annotation: workload.state=gaming
   - Publish metrics: workload_state=2, xmrig_scaling_allowed=0
   ↓
8. Prometheus Adapter queries metric
   xmrig_scaling_allowed{node="zephyr"} = 0
   ↓
9. HPA evaluates metric: 0 < target(1)
   - Triggers scaleDown
   - Waits 15s (stabilizationWindow)
   ↓
10. HPA scales xmrig-zephyr deployment to 0 replicas
    ↓
11. Mining stops, CPU freed for gaming
```

**Total time**: ~45 seconds (10s hysteresis + 15s stabilization + 20s pod termination)

### State Transition: Gaming → Idle

```
1. User closes game
   ↓
2. GameMode daemon detects game closed
   ↓
3. gaming-detection service updates /run/gaming-detection/gaming_state
   GAMING_ACTIVE=0
   ↓
4. workload-watcher reads state file (next 2s check)
   ↓
5. workload-watcher increments gaming_count (towards idle threshold)
   GAMING_COUNT = 1 (towards 10)
   ↓
6. Repeat checks 5-9 (hysteresis: 10 consecutive checks)
   GAMING_COUNT = 10
   ↓
7. workload-watcher transitions state: gaming → idle
   - Update node annotation: workload.state=idle
   - Publish metrics: workload_state=0, xmrig_scaling_allowed=1
   ↓
8. Prometheus Adapter queries metric
   xmrig_scaling_allowed{node="zephyr"} = 1
   ↓
9. HPA evaluates metric: 1 >= target(1)
   - Triggers scaleUp
   - Waits 60s (stabilizationWindow)
   ↓
10. HPA scales xmrig-zephyr deployment to 1 replica
    ↓
11. Mining resumes
```

**Total time**: ~90 seconds (20s hysteresis + 60s stabilization + 10s pod startup)

### State Transition: Idle → Building

```
1. User runs "nixos-rebuild switch"
   ↓
2. Nix creates lock file: /nix/var/nix/locks/*.lock
   ↓
3. workload-watcher detects lock file (next 5s check)
   BUILD_LOCKS = 1
   ↓
4. workload-watcher increments building_count
   BUILDING_COUNT = 1
   ↓
5. Repeat checks 4-6 (hysteresis: 3 consecutive checks)
   BUILDING_COUNT = 3
   ↓
6. workload-watcher transitions state: idle → building
   - Update node annotation: workload.state=building
   - Publish metrics: workload_state=1, xmrig_scaling_allowed=0
   ↓
7. HPA scales deployment to 0 replicas
   ↓
8. Mining stops, CPU freed for build
```

**Total time**: ~30 seconds (15s hysteresis + 15s stabilization)

---

## Error Handling

### Failure Modes

| Failure | Detection | Response |
|---------|-----------|----------|
| Watcher pod crash | Kubernetes liveness probe | Pod restarts, metric disappears |
| Gaming state file missing | File check fails | Assume gaming=0 (no gaming detected) |
| Nix locks directory missing | Directory check fails | Assume building=0 (no build detected) |
| Prometheus Adapter down | Metric endpoint error | HPA uses last known metric value |
| Node annotation fails | kubectl command fails | Continue publishing metrics anyway |

### Liveness Probe

```yaml
livenessProbe:
  httpGet:
    path: /healthz
    port: 9101
  initialDelaySeconds: 5
  periodSeconds: 10
  failureThreshold: 3  # 30 seconds before restart
```

**Health Endpoint**: Returns 200 if state file readable, 503 otherwise

### Dead Man's Switch

Alert if watcher pod down for >5 minutes:

```yaml
- alert: WorkloadWatcherDown
  expr: up{job="workload-watcher"} == 0
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "Workload watcher on {{ $labels.node }} is down"
    description: "Mining may not respond to build/gaming activity"
```

### Fail-Safe Behavior

**Critical**: If workload-watcher crashes, mining MUST continue (fail open). HPA stabilization windows prevent rapid scale-down/scale-up loops.

**Default State**: If watcher not present, HPA keeps current replica count (doesn't scale).

---

## Testing and Validation

### Test Matrix

| Scenario | Trigger | Expected State | Expected HPA Action | Time to Scale |
|----------|---------|----------------|---------------------|---------------|
| Idle → Gaming | `GAMING_ACTIVE=1` | gaming (2) | Scale to 0 | ~45s |
| Gaming → Idle | `GAMING_ACTIVE=0` (10×) | idle (0) | Scale to 1 | ~90s |
| Idle → Building | Nix lock appears | building (1) | Scale to 0 | ~30s |
| Building → Idle | Nix locks gone (10×) | idle (0) | Scale to 1 | ~90s |
| Gaming + Building | Both detected | gaming (2) | Scale to 0 | ~45s (gaming wins) |
| Watcher crash | Kill pod | Metric disappears | Keep current replicas | N/A |

### Automated Test Script

**Location**: `/etc/nixos/scripts/test-workload-watcher.sh`

**Test Cases**:
1. Gaming detection and scale-down
2. Gaming cleared and scale-up
3. Build detection and scale-down
4. Build cleared and scale-up
5. Gaming priority over building
6. Watcher crash recovery

**Manual Testing**:
```bash
# Test gaming detection
echo "GAMING_ACTIVE=1" | sudo tee /run/gaming-detection/gaming_state
kubectl get hpa -n mining  # Should show 0/1

# Test build detection
sudo touch /nix/var/nix/locks/test.lock
kubectl get hpa -n mining  # Should show 0/1

# Verify metric API
kubectl get --raw /apis/external.metrics.k8s.io/v1beta1/namespaces/mining/xmrig_scaling_allowed | jq .
```

---

## Current Xmrig Deployments

### Zephyr (32-core node)

**File**: `/kubernetes-manifests/mining/xmrig-zephyr.yaml`

**Current Configuration**:
- Threads: 8
- CPU requests: 4 cores
- CPU limits: 8 cores
- Memory: 1Gi request, 3Gi limit
- Current utilization: ~9618m CPU (30%)

### Nexus (24-core node)

**File**: `/kubernetes-manifests/mining/xmrig-nexus.yaml`

**Current Configuration**:
- Threads: 6
- CPU requests: 3 cores
- CPU limits: 6 cores
- Memory: not specified
- Current utilization: ~8380m CPU (34%)

---

## Implementation Plan

See separate implementation plan document: `2026-03-22-xmrig-intelligent-autoscaling-implementation.md`

**High-Level Steps**:
1. Create workload-watcher DaemonSet manifest
2. Deploy Prometheus Adapter configuration
3. Create HPA resources for zephyr and nexus
4. Deploy workload-watcher pods
5. Test gaming detection and scale-down
6. Test build detection and scale-down
7. Verify hysteresis and stabilization
8. Monitor for 24 hours

---

## Rollback Plan

If issues occur:
1. Delete HPA resources: `kubectl delete hpa -n mining xmrig-*-hpa`
2. Scale deployments manually: `kubectl scale deployment -n mining xmrig-zephyr --replicas=1`
3. Delete workload-watcher DaemonSet: `kubectl delete daemonset -n mining workload-watcher`
4. Restore original xmrig deployments (remove HPA references)

**Rollback Time**: <5 minutes

---

## Success Criteria

- ✅ Gaming detected within 10 seconds, mining stops within 45 seconds
- ✅ Build detected within 15 seconds, mining stops within 30 seconds
- ✅ Mining resumes within 90 seconds after gaming/building ends
- ✅ No resource contention with user workloads
- ✅ Zero false positives (no scaling when not needed)
- ✅ Stable operation over 24 hours (no flapping)

---

## Alternatives Considered

### Alternative A: Custom Metrics Server
**Rejected**: Additional complexity, Prometheus Adapter is standard

### Alternative B: Node Autoscaler (Cluster Autoscaler)
**Rejected**: Scales nodes, not pods. Overkill for single-pod deployments.

### Alternative C: Volcano Scheduler Preemption
**Rejected**: Better for batch jobs, not immediate preemption for interactive workloads.

### Alternative D: Manual Scripts + CronJobs
**Rejected**: Not responsive enough, difficult to maintain, no hysteresis.

---

## References

- **Existing Gaming Detection**: `/etc/nixos/modules/system/gaming-detection.nix`
- **HPA Documentation**: https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/
- **Prometheus Adapter**: https://github.com/kubernetes-sigs/prometheus-adapter
- **GameMode Daemon**: https://github.com/FeralInteractive/gamemode
- **Nix Build Locks**: `/nix/var/nix/locks/` directory

---

**Document Version**: 1.0
**Last Updated**: 2026-03-22
**Status**: Approved - Ready for Implementation
