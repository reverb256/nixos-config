# Memory Management Implementation - 2026-03-21

## Context

Zephyr (control-plane node) experienced critical memory exhaustion (94% usage, 1.7Gi free) causing kube-apiserver instability and cluster-wide outages.

## Root Cause

1. **Workload Accumulation**: Too many pods scheduled on control-plane node
2. **Storage Constraints**: Local-path SSD PVs have node affinity, preventing cross-node migration
3. **No Guardrails**: No ResourceQuota limits to prevent over-scheduling

## Implemented Solutions

### 1. ResourceQuota Protection

Created ResourceQuotas in key namespaces to prevent memory overcommit:

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: zephyr-memory-protection
spec:
  hard:
    requests.memory: 6Gi   # Per namespace
    limits.memory: 12Gi
    requests.cpu: "3"
    limits.cpu: "6"
```

**Namespaces Protected**:
- `default` - 8Gi requests, 16Gi limits
- `glitchtip` - 6Gi requests, 12Gi limits
- `ai-inference` - 6Gi requests, 12Gi limits
- `akash-services` - 6Gi requests, 12Gi limits
- `mining` - 6Gi requests, 12Gi limits
- `ingress-nginx` - 6Gi requests, 12Gi limits

### 2. Automated Memory Monitoring

Created CronJob that runs every 5 minutes to check Zephyr memory usage:

```bash
#!/bin/bash
THRESHOLD=75
CURRENT=$(free | grep Mem | awk '{printf("%.0f", $3/$2 * 100)}')
if [ $CURRENT -gt $THRESHOLD ]; then
  echo "WARNING: Zephyr memory usage is ${CURRENT}%"
  echo "Consider moving workloads or scaling up"
  free -h
  echo "Top memory consumers:"
  ps aux --sort=-%mem | head -10
fi
```

**Location**: `default/memory-monitor` CronJob
**Schedule**: Every 5 minutes
**Alert Threshold**: 75% memory usage

### 3. Pod Distribution Analysis

**Pods That MUST Stay on Zephyr** (storage constraints):
- `ai-inference/postgres-n8n-0` - local-path SSD
- `glitchtip/postgres-0` - local-path SSD
- `glitchtip/redis` - local-path SSD
- `default/home-assistant` - local-path SSD
- `ingress-nginx/controller` - control-plane component
- `mining/gpu-miner-zephyr` - GPU required

**Pods That Can Be Moved** (stateless, no PVC):
- Most deployments without local-path storage
- Can use nodeSelector to pin to specific nodes

### 4. Current Zephyr Workload

**Running Pods** (as of 2026-03-21 08:30 UTC):
- ai-inference/postgres-n8n-0 (4Gi request)
- akash-services/operator-inventory-hardware-discovery-zephyr
- akash-services/provider-status (deleted, not recreated)
- default/home-assistant (unknown request)
- glitchtip/postgres-0 (unknown request)
- ingress-nginx/controller (100Mi request)
- mining/gpu-miner-zephyr (4Gi request, 8Gi limit)

**Memory Status**:
- Total: 31Gi
- Used: 25Gi (81%)
- Available: 6.2Gi
- Swap: 5.9Gi used

## Next Steps

### Immediate (Today)
- [ ] Monitor memory usage trends
- [ ] Review CronJob logs for alerts
- [ ] Verify ResourceQuota enforcement

### Short-term (This Week)
- [ ] Migrate databases to NFS/RWX storage for flexibility
- [ ] Set up Prometheus/Grafana for better monitoring
- [ ] Implement pod priority classes

### Medium-term (This Month)
- [ ] Consider dedicated control-plane node
- [ ] Implement cluster autoscaling
- [ ] Evaluate distributed storage (Ceph, Rook, Longhorn)

## Lessons Learned

1. **Local-path storage creates node affinity** - PVs with local storage cannot be moved between nodes
2. **ResourceQuota is essential for multi-tenant clusters** - prevents any namespace from consuming all resources
3. **Control-plane nodes need protection** - don't treat them like worker nodes
4. **Monitoring is critical** - need visibility into resource usage before it becomes critical

## Files Created

- `/etc/nixos/docs/operations/memory-management-implementation-2026-03-21.md` (this file)
- Kubernetes resources:
  - `default/zephyr-memory-protection` ResourceQuota
  - `glitchtip/zephyr-memory-protection` ResourceQuota
  - `ai-inference/zephyr-memory-protection` ResourceQuota
  - `akash-services/zephyr-memory-protection` ResourceQuota
  - `mining/zephyr-memory-protection` ResourceQuota
  - `ingress-nginx/zephyr-memory-protection` ResourceQuota
  - `default/memory-monitor-script` ConfigMap
  - `default/memory-monitor` CronJob

## Status

**Short-term Task**: ✅ COMPLETED
- ResourceQuotas implemented and active
- Memory monitoring CronJob deployed
- Documentation created

**Cluster Health**: 🟡 STABLE
- All nodes Ready
- Control plane components active
- Memory usage at 81% (improved from 94%)
- Monitoring active

---
*Created: 2026-03-21*
*Author: Claude Code*
*Related: Incident Response - Memory Exhaustion on Zephyr*
