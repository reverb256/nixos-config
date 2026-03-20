# Akash Provider - Mining Preemption Configuration

## Overview

This document describes how mining workloads are configured to allow preemption by higher-priority Akash tenant workloads.

**Priority Strategy**: Akash tenants > Gaming > Mining

## Priority Classes

| Priority Class | Value | Used By | Preemption Policy |
|----------------|-------|---------|-------------------|
| `akash-tenant` | 800 | Akash tenant deployments | PreemptLowerPriority |
| `high-priority` | 500 | Gaming workloads | PreemptLowerPriority |
| `low-priority-mining` | 100 | GPU miners (Kubernetes) | PreemptLowerPriority |
| `mining-background` | 50 | Background mining | PreemptLowerPriority |

**Key**: Higher value = higher priority. Akash tenants (800) preempt miners (100).

## GPU Miners (Kubernetes)

### Configuration
- **Scheduler**: YuniKorn
- **Priority Class**: `low-priority-mining` (100)
- **Tolerations**: `scheduler.yunikorn.io/preemptible`
- **Restart Policy**: `Always` (auto-restart after preemption)
- **Locations**:
  - `forge`: 2× NVIDIA RTX 4060
  - `zephyr`: 2× NVIDIA GPU
  - `nexus`: 1× NVIDIA GPU

### Current Mining Revenue
- **Coin**: Tari (XTM)
- **Monthly Revenue**: $60-100 USD
- **Daily Revenue**: $2-3.33 USD
- **Electricity**: Free/negligible (homelab)

### Preemption Behavior

When an Akash tenant bids on GPU resources:

1. YuniKorn evaluates task priorities
2. Akash tenant (800) > Mining (100)
3. Mining pods are gracefully evicted (30s grace period)
4. Tenant workload uses the GPU
5. When tenant completes, mining auto-restarts

**No manual intervention required** - the system automatically balances revenue streams.

## CPU Miner (xmrig on Sentry)

### Current Configuration
- **Type**: Systemd service (outside Kubernetes)
- **Location**: sentry (10.1.1.140)
- **Threads**: 4
- **Hashrate**: ~2.3 kH/s
- **Status**: `active (running)`

### Limitation
**CPU miner cannot be preempted by Kubernetes** because it runs as a systemd service, not a pod.

### Impact
- Minimal: CPU mining earns negligible revenue
- Sentry's 16 cores are mostly available for Akash workloads
- Only ~4 threads used for mining (25% of one node)

## Revenue Comparison

| Scenario | Daily | Monthly | Notes |
|----------|-------|---------|-------|
| **Mining (idle)** | $2-3 | $60-100 | Passive income |
| **Akash Tenants (full)** | $60-240 | $1,800-7,200 | Requires active workloads |
| **Hybrid (opportunistic)** | Variable | $60-7,200 | Auto-switches based on demand |

**Opportunity Cost**: By mining during high-demand periods, you forgo up to $237/day in potential Akash revenue.

**Strategy**: Keep mining as baseline income, allow Akash to preempt when profitable bids arrive.

## Test Workloads

CPU-only test deployments are available at:
```bash
kubectl apply -f /etc/nixos/kubernetes-manifests/akash/cpu-test-workload.yaml
```

This includes:
- `nginx-test`: 2 replicas (CPU only)
- `cpu-stress-test`: Validates CPU allocation
- `memory-stress-test`: Validates memory allocation
- `network-test`: Validates connectivity

## Monitoring Preemption

Check if miners are being preempted:
```bash
# Get all pods with mining priority
kubectl get pods -n mining -l priorityClassName=low-priority-mining

# Check eviction events
kubectl get events -n mining | grep Evicted

# View YuniKorn queues
kubectl get queues -n volcano-system
```

## Quick Commands

```bash
# Check current mining status
ssh zephyr "kubectl get pods -n mining"
ssh sentry "systemctl status xmrig"

# Check GPU availability
ssh zephyr "kubectl describe node forge | grep 'nvidia.com/gpu' -A 2"

# Stop/start miners manually (if needed)
ssh zephyr "kubectl scale deployment -n mining gpu-miner-forge-nvidia-0 --replicas=0"
ssh zephyr "kubectl scale deployment -n mining gpu-miner-forge-nvidia-0 --replicas=1"

# Check priority classes
ssh zephyr "kubectl get priorityclass | grep -E 'akash|mining|gaming'"
```

## Configuration Files

- **Test Workloads**: `/etc/nixos/kubernetes-manifests/akash/cpu-test-workload.yaml`
- **Mining Scripts**: `/etc/nixos/scripts/mining-profitability.sh`
- **Provider Config**: `kubectl get configmap -n akash-services akash-provider-akash-provider-fixed-main`

## Best Practices

1. **Automatic Preemption**: Already configured via YuniKorn priority classes
2. **Revenue Monitoring**: Track mining vs Akash earnings to optimize pricing
3. **Bid Pricing**: Set minimum bids that exceed mining opportunity cost
4. **Gaming Priority**: Gaming workloads (priority 500) preempt mining but yield to Akash (800)

## Preemption Flow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                     GPU Resource Pool                        │
│                    (forge: 2, nexus: 1, zephyr: 2)           │
└─────────────────────────────────────────────────────────────┘
                              │
              ┌─────────────┼─────────────┐
              ▼             ▼             ▼
        ┌─────────┐    ┌─────────┐   ┌──────────┐
        │  Mining │    │  Gaming │   │  Akash   │
        │ Priority│    │ Priority│   │ Priority │
        │   100   │    │   500   │   │   800    │
        └─────────┘    └─────────┘   └──────────┘
              │             ▼             ▼
              │          Gaming       Akash Tenant
              │          Preempts      Preempts Both
              ▼
         Mining Resumes
    (when no higher priority workloads)
```

---

**Last Updated**: 2026-03-20 10:35 UTC
**Akash Provider**: akash1c6h804ky08tdpnxrv72vum783xuey09qgzt2p6
**Cluster**: 78 cores, 5 GPUs, 111GB RAM
