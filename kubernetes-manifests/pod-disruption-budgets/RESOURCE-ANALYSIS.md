# Resource Analysis - HA Upgrade Feasibility Study

## Executive Summary

**Current Capacity**: 78 cores, 123GB RAM, 7 GPUs across 4 nodes
**Current Usage**: 60 pods, 36 deployments, 5 statefulsets, 4 daemonsets
**Architecture Decision**: 3-master control plane (Zephyr, Nexus, Sentry) + 1 worker (Forge)

**Key Finding**: Cluster has **sufficient capacity** for 9/10 HA upgrade with tiered replication strategy, **IF** swap is disabled and resource optimization implemented.

---

## 1. Current Cluster Capacity

### Node Hardware Specifications

| Host | CPU | Cores | Threads | RAM | Swap | GPUs | Role |
|------|-----|-------|---------|-----|------|------|------|
| **Zephyr** | Ryzen 9 5950X | 16 | 32 | 32 GB | 32 GB | 3x NVIDIA (3090, 2x 3080) | Control plane + Gaming |
| **Nexus** | Ryzen 9 3900X | 12 | 24 | 48 GB | 16 GB | 2x AMD (6900XT, 6800) | Control plane + Storage |
| **Sentry** | Ryzen 7 1700 | 8 | 16 | 32 GB | 8 GB | 1x AMD (5600 XT) | Control plane + Monitoring |
| **Forge** | Core i5-9500 | 6 | 6 | 16 GB | 16 GB | 4x GPUs (2x NVIDIA 4060, 2x AMD 5700 XT) | Dedicated GPU Worker |

**Total Resources**:
- CPU: 78 logical cores
- RAM: 128 GB (123 GB usable)
- Swap: 72 GB (PROBLEM: should be disabled)
- GPUs: 10 (6 NVIDIA + 4 AMD)

### Control Plane Architecture (User Decision)

**Masters (3 nodes)**: Zephyr, Nexus, Sentry
- Total CPU: 72 cores (92% of cluster)
- Total RAM: 112 GB (91% of cluster)
- Quorum: Can tolerate 1 master failure
- etcd: 3-member cluster for HA

**Worker (1 node)**: Forge
- CPU: 6 cores (8% of cluster)
- RAM: 16 GB (13% of cluster)
- GPUs: 1x NVIDIA 3080

**★ Insight ─────────────────────────────────────**
**Asymmetric Architecture**: This 3-master design is unconventional but smart for your homelab:
1. **Control plane stability**: Powerful masters ensure API server never bottlenecks
2. **Resource isolation**: Forge dedicated to GPU workloads (no control plane overhead)
3. **Tradeoff**: Worker becomes single point of failure - need PDBs + quick recovery
`─────────────────────────────────────────────────`

---

## 2. Current Resource Usage

### Node-Level Allocation (from kubectl describe nodes)

| Node | CPU Requests | CPU Limits | RAM Requests | RAM Limits | CPU % | RAM % |
|------|--------------|------------|--------------|------------|-------|-------|
| **Zephyr** | 4150m | 8100m | 8306 Mi | 16512 Mi | 69% | 62% |
| **Nexus** | 8650m | 22500m | 11698 Mi | 27136 Mi | 36% | 25% |
| **Sentry** | 2150m | 5100m | 3916 Mi | 6528 Mi | 13% | 13% |
| **Forge** | 7350m | 16300m | 6586 Mi | 15744 Mi | 22% | 22% |

**Key Observations**:
1. **Zephyr is most loaded**: 69% CPU, 62% RAM (control plane + gaming + AI inference)
2. **Nexus has headroom**: Only 36% CPU, 25% RAM used (storage node, underutilized)
3. **Sentry is underutilized**: Only 13% CPU, 13% RAM (monitoring only)
4. **Forge has capacity**: 22% CPU, 22% RAM (but only 6 cores total)

### Namespace-Level Workload Distribution

| Namespace | Deployments | Replicas | Primary Workload | Priority |
|-----------|-------------|----------|------------------|----------|
| **mining** | 8 | 6 | GPU/CPU mining | Critical |
| **ai-inference** | 6 | 3 | n8n, databases | High |
| **akash-services** | 3 | 3 | Akash provider | High |
| **monitoring** | 2 | 2 | Prometheus, Grafana | High |
| **kube-system** | 2 | 2 | DNS, ingress | Critical |
| **ai-coding** | 2 | 2 | Claude Code, OpenCode | Medium |
| **search** | 2 | 2 | Qdrant vector DB | Medium |
| **yunikorn** | 2 | 1 | Scheduler | Critical |
| **glitchtip** | 2 | 0 | Error tracking | Low |
| **istio-system** | 1 | 1 | Service mesh | Low |
| **volcano-system** | 3 | 3 | Batch scheduler | Medium |

**Total**: 60 pods across 14 namespaces

### Current Resource Requests by Namespace

| Namespace | Estimated CPU Requests | Estimated RAM Requests | Notes |
|-----------|------------------------|-------------------------|-------|
| kube-system | ~2000m | ~2000 Mi | DNS, ingress, metrics |
| monitoring | ~1000m | ~2000 Mi | Prometheus, Grafana |
| ai-inference | ~3000m | ~6000 Mi | n8n, Redis, Postgres, Qdrant |
| mining | ~12000m | ~8000 Mi | 6 GPU miners + CPU miners |
| akash-services | ~2000m | ~4000 Mi | Provider, operators |
| ai-coding | ~2000m | ~4000 Mi | Claude Code, OpenCode |
| yunikorn | ~500m | ~1000 Mi | Scheduler + admission |
| volcano-system | ~1500m | ~2000 Mi | Batch scheduler |
| search | ~1000m | ~2000 Mi | Qdrant |
| istio-system | ~500m | ~1000 Mi | Istio pilot |
| glitchtip | ~0m | ~0 Mi | Scaled to 0 |

**Estimated Total**: ~25,500m CPU (32.7 cores), ~33,000 Mi RAM (32 GB)

---

## 3. Multi-Replica Requirements for HA Upgrade

### Tiered Replication Strategy (from BRAINSTORM-HA-UPGRADE.md)

| Service Tier | Replicas | Count | Services | CPU Requirement | RAM Requirement |
|--------------|----------|-------|----------|-----------------|-----------------|
| **Critical** | 3 | 6 | Mining (6), CoreDNS, Ingress, Yunikorn | +12,000m | +6,000 Mi |
| **High** | 2 | 12 | AI inference (6), Akash (3), Monitoring (2), AI coding (2) | +4,000m | +4,000 Mi |
| **Medium** | 2 | 6 | StatefulSets (3), Search (2), Volcano (3) | +2,000m | +2,000 Mi |
| **Low** | 1 | - | Glitchtip, Istio, development | 0 | 0 |

**Additional Resources Needed**:
- CPU: +18,000m (18 cores)
- RAM: +12,000 Mi (12 GB)

### Per-Node Resource Projection (After HA Upgrade)

#### Scenario 1: Even Distribution (Ideal)
Assumes perfect pod distribution with anti-affinity:

| Node | Current CPU | Add CPU | Total CPU | Current RAM | Add RAM | Total RAM | CPU % | RAM % |
|------|-------------|---------|-----------|-------------|---------|-----------|-------|-------|
| Zephyr | 4150m | +4500m | 8650m | 8306 Mi | +3000 Mi | 11306 Mi | 27% | 34% |
| Nexus | 8650m | +6000m | 14650m | 11698 Mi | +4000 Mi | 15698 Mi | 61% | 33% |
| Sentry | 2150m | +4500m | 6650m | 3916 Mi | +3000 Mi | 6916 Mi | 42% | 21% |
| Forge | 7350m | +3000m | 10350m | 6586 Mi | +2000 Mi | 8586 Mi | 172% | 53% |

**Problem**: Forge exceeds 100% CPU (only 6 cores = 6000m)
**Note**: Forge has 4 GPUs (2x NVIDIA 4060, 2x AMD 5700 XT) - dedicated GPU worker architecture

#### Scenario 2: Control Plane Consolidation (Realistic)
Keep critical services on masters, move GPU workloads to Forge:

| Node | Services | CPU Usage | RAM Usage | CPU % | RAM % | Status |
|------|----------|-----------|-----------|-------|-------|--------|
| Zephyr | API server, etcd, scheduler, controller, CoreDNS (3), Ingress (2), Mining (2 GPU) | 8000m | 9000 Mi | 25% | 28% | ✅ Healthy |
| Nexus | API server, etcd, scheduler, controller, CoreDNS (3), Mining (1 AMD), Storage | 11000m | 13000 Mi | 46% | 27% | ✅ Healthy |
| Sentry | API server, etcd, scheduler, controller, CoreDNS (3), Monitoring (2), AI inference (3) | 7000m | 9000 Mi | 44% | 28% | ✅ Healthy |
| Forge | GPU miners (3 NVIDIA), AI workloads | 9000m | 7000 Mi | 150% | 44% | ⚠️ Overcommitted |

**Problem**: Forge still overcommitted on CPU (6 cores limit)

### Resource Bottlenecks Identified

1. **Forge CPU constraint**: Only 6 cores = 6000m capacity
   - Current: 7350m (122%)
   - After HA: 9000m+ (150%+)
   - **Solution**: Move non-GPU workloads off Forge, or upgrade CPU

2. **Swap memory causing etcd slowdown**: 72 GB swap active
   - Zephyr: 16 GB swap (50% used)
   - Impact: etcd snapshots slow → API instability
   - **Solution**: Disable swap, add RAM if needed

3. **Zephyr memory pressure**: 62% RAM used, 32 GB total
   - Gaming + AI inference + control plane = high RAM usage
   - After HA: 34% RAM (acceptable with swap disabled)

4. **Sentry underutilized**: Only 13% CPU, 13% RAM
   - Opportunity: Move more services to Sentry
   - Constraint: Only 16 cores (vs 32 on Zephyr, 24 on Nexus)

---

## 4. Resource Allocation Plan

### Phase 1: Resource Optimization (Pre-Upgrade)

**Action 1: Disable Swap** (CRITICAL for etcd stability)
```bash
# On all 4 nodes
sudo swapoff -a
# Remove swap entry from /etc/fstab
# Verify: cat /proc/swaps (should be empty)
```
**Impact**: Eliminates etcd snapshot slowdown, fixes API instability

**Action 2: Move Non-GPU Workloads Off Forge**
- Move CPU-intensive pods to Nexus/Sentry
- Keep only GPU miners on Forge
- Target: Reduce Forge CPU to <5000m

**Action 3: Optimize Sentry Utilization**
- Move monitoring stack from Zephyr to Sentry (already there)
- Add AI inference workloads to Sentry
- Target: Increase Sentry usage to 30-40%

### Phase 2: Namespace Resource Quotas

Define quotas per namespace (prevent noisy neighbor):

| Namespace | CPU Quota | Memory Quota | Rationale |
|-----------|-----------|--------------|-----------|
| **mining** | 15000m | 10000 Mi | Critical, GPU-intensive |
| **ai-inference** | 6000m | 8000 Mi | High priority, CPU-bound |
| **akash-services** | 4000m | 6000 Mi | High priority, revenue-generating |
| **monitoring** | 2000m | 4000 Mi | High priority, cluster health |
| **ai-coding** | 3000m | 6000 Mi | Medium priority, development |
| **kube-system** | 4000m | 4000 Mi | Critical, cluster operations |
| **yunikorn** | 1000m | 2000 Mi | Critical, scheduling |

**Total Quota**: 35,000m CPU (45 cores), 40,000 Mi RAM (40 GB)

### Phase 3: PriorityClasses Implementation

Define 3-tier priority system:

| PriorityClass | Value | Use Cases | Preemption |
|---------------|-------|-----------|------------|
| **critical-production** | 1000000 | Mining revenue, Akash provider, etcd, API server | Never preempted |
| **high-priority** | 500000 | AI inference, monitoring, core services | Preempts low-priority |
| **low-priority** | 50000 | Development, testing, batch jobs | First to be preempted |

### Phase 4: Overprovisioning Buffer

**Target**: 20% free capacity for failover

| Node | Total CPU | Used CPU | Free CPU | Target Free | Status |
|------|-----------|----------|----------|-------------|--------|
| Zephyr | 32000m | 8650m | 23350m | 6400m | ✅ Excess |
| Nexus | 24000m | 11000m | 13000m | 4800m | ✅ Excess |
| Sentry | 16000m | 7000m | 9000m | 3200m | ✅ Excess |
| Forge | 6000m | 6000m | 0m | 1200m | ❌ No buffer |

**Problem**: Forge has zero buffer, needs optimization or hardware upgrade
**Note**: Forge is GPU-optimized (4 GPUs: 2x NVIDIA 4060 + 2x AMD 5700 XT) - CPU constraint is intentional tradeoff for GPU density

---

## 5. Multi-Replica Deployment Plan

### Critical Services (3 Replicas)

| Service | Current | Target | Node Distribution | CPU Cost | RAM Cost |
|---------|---------|--------|-------------------|----------|----------|
| **CoreDNS** | 2 | 3 | Zephyr, Nexus, Sentry | +300m | +300 Mi |
| **Ingress** | 1 | 3 | Zephyr, Nexus, Sentry | +400m | +400 Mi |
| **Yunikorn** | 1 | 3 | Zephyr, Nexus, Sentry | +1000m | +1000 Mi |
| **GPU Miners** | 6 | 6 | Forge (6 pods) | 0 | 0 |

**Total Critical**: +1700m CPU, +1700 Mi RAM

### High Priority Services (2 Replicas)

| Service | Current | Target | Node Distribution | CPU Cost | RAM Cost |
|---------|---------|--------|-------------------|----------|----------|
| **n8n** | 1 | 2 | Nexus, Sentry | +500m | +500 Mi |
| **PostgreSQL** | 1 | 2 | Zephyr, Nexus | +500m | +1000 Mi |
| **Redis** | 1 | 2 | Nexus, Sentry | +200m | +200 Mi |
| **Qdrant** | 1 | 2 | Zephyr, Sentry | +500m | +1000 Mi |
| **Akash Provider** | 1 | 2 | Nexus, Sentry | +1000m | +1000 Mi |
| **Prometheus** | 1 | 2 | Sentry, Zephyr | +500m | +500 Mi |
| **Grafana** | 1 | 2 | Sentry, Nexus | +200m | +200 Mi |
| **Claude Code** | 1 | 2 | Zephyr, Nexus | +1000m | +1000 Mi |
| **OpenCode** | 1 | 2 | Nexus, Sentry | +500m | +500 Mi |

**Total High Priority**: +4900m CPU, +5900 Mi RAM

### Medium Priority Services (2 Replicas)

| Service | Current | Target | Node Distribution | CPU Cost | RAM Cost |
|---------|---------|--------|-------------------|----------|----------|
| **Volcano Scheduler** | 1 | 2 | Zephyr, Nexus | +500m | +500 Mi |
| **Volcano Admission** | 1 | 2 | Zephyr, Nexus | +500m | +500 Mi |
| **Volcano Controller** | 1 | 2 | Nexus, Sentry | +500m | +500 Mi |

**Total Medium**: +1500m CPU, +1500 Mi RAM

### Total Resource Impact

| Tier | CPU Addition | RAM Addition |
|------|--------------|--------------|
| Critical (3 replicas) | +1700m | +1700 Mi |
| High (2 replicas) | +4900m | +5900 Mi |
| Medium (2 replicas) | +1500m | +1500 Mi |
| **Total** | **+8100m** | **+9100 Mi** |

**Cluster-Wide Impact**: +8.1 cores CPU, +9 GB RAM

---

## 6. Feasibility Assessment

### Resource Availability vs Requirements

| Node | Available CPU | Required CPU | Available RAM | Required RAM | Feasible? |
|------|---------------|--------------|---------------|--------------|-----------|
| **Zephyr** | 23350m | +2500m | 20 GB | +3 GB | ✅ Yes |
| **Nexus** | 13000m | +3500m | 36 GB | +4 GB | ✅ Yes |
| **Sentry** | 9000m | +2100m | 28 GB | +2 GB | ✅ Yes |
| **Forge** | 0m | 0m | 9 GB | 0 GB | ⚠️ Tight |

**Overall Assessment**: ✅ **FEASIBLE with constraints**

### Constraints and Tradeoffs

1. **Forge CPU bottleneck**
   - Only 6 cores = 6000m capacity
   - Already at 122% utilization
   - **Solution**: Move non-GPU workloads to masters, rely on GPU isolation

2. **Swap must be disabled**
   - Current: 72 GB swap active cluster-wide
   - Impact: etcd slowdown during snapshots
   - **Solution**: Disable swap, add 16 GB RAM to Zephyr if needed

3. **Asymmetric resource distribution**
   - Zephyr, Nexus, Sentry have 72 cores (92%)
   - Forge has only 6 cores (8%)
   - **Solution**: Run GPU workloads on Forge, everything else on masters

### Risk Mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Forge CPU exhaustion | High | High | Move non-GPU pods to masters, add PriorityClasses |
| API instability from swap | Medium | High | Disable swap before HA upgrade |
| Resource contention on masters | Low | Medium | Implement resource quotas, overprovisioning buffer |
| Single worker failure | Low | High | Keep Forge as GPU-only, quick recovery procedures |

---

## 7. Recommendations

### Immediate Actions (Pre-Upgrade)

1. **Disable swap on all 4 nodes** (CRITICAL)
   ```bash
   sudo swapoff -a
   # Edit /etc/fstab to remove swap entry
   # Reboot to verify
   ```

2. **Optimize Forge workload**
   - Move CPU-only miners to masters
   - Keep only GPU miners on Forge
   - Target: <5000m CPU usage on Forge

3. **Implement Resource Quotas**
   - Apply quotas per namespace (see Phase 2)
   - Prevent noisy neighbor problem
   - Enable fair resource allocation

4. **Create PriorityClasses**
   - Define 3-tier priority system
   - Apply to all deployments
   - Enable graceful degradation

### HA Upgrade Execution Plan

**Phase 1: Foundation (Week 1)**
- Disable swap
- Implement resource quotas
- Create PriorityClasses
- Add resource requests/limits to all deployments

**Phase 2: Critical Services (Week 2)**
- Scale CoreDNS to 3 replicas
- Scale Ingress to 3 replicas
- Scale Yunikorn to 3 replicas
- Add required anti-affinity

**Phase 3: High Priority Services (Week 3-4)**
- Scale AI inference to 2 replicas
- Scale Akash to 2 replicas
- Scale monitoring to 2 replicas
- Add preferred anti-affinity

**Phase 4: Validation (Week 5)**
- Test node drain with PDBs
- Simulate master failure
- Validate resource quotas
- Load test at 2x capacity

### Long-Term Considerations

1. **Forge CPU upgrade**
   - Current: i5-9500 (6 cores)
   - Recommendation: Upgrade to i7 or i9 (8-12 cores)
   - Benefit: Headroom for GPU workloads + failover capacity

2. **Add RAM to Zephyr**
   - Current: 32 GB
   - Recommendation: Upgrade to 64 GB
   - Benefit: Eliminate swap, support more AI workloads

3. **Consider 5th node**
   - Purpose: Dedicated GPU worker
   - Benefit: Remove Forge bottleneck, true GPU HA
   - Cost: ~$500-1000 for used GPU + CPU/mobo/RAM

---

## 8. Success Metrics

### Quantitative Targets

| Metric | Current | Target | Status |
|--------|---------|--------|--------|
| SPOF count | 26 | 0 | ⏳ In Progress |
| Multi-replica services | 4 | 20+ | ⏳ In Progress |
| Resource quota coverage | 0% | 100% | ⏳ In Progress |
| Health probe coverage | 20% | 100% | ⏳ In Progress |
| Swap usage | 72 GB | 0 GB | ❌ Action Needed |
| Forge CPU utilization | 122% | <100% | ❌ Action Needed |
| Cluster overprovisioning | 0% | 20% | ⏳ In Progress |

### Qualitative Targets

- ✅ No service degradation during deployments
- ✅ API server stable (no restarts for 30 days)
- ✅ Graceful degradation under resource pressure
- ✅ Clear runbooks for all failure scenarios
- ✅ Team confident in cluster reliability

---

## 9. Conclusion

**Can we achieve 9/10 HA?** ✅ **YES, with constraints**

### Key Success Factors

1. **3-master control plane** (Zephyr, Nexus, Sentry) provides stable foundation
2. **Sufficient cluster resources** (78 cores, 123 GB RAM) for tiered replication
3. **Resource optimization** required (disable swap, move workloads off Forge)
4. **Gradual phased approach** reduces risk
5. **Resource quotas + PriorityClasses** prevent resource exhaustion

### Critical Path

1. **Week 1**: Disable swap, optimize Forge workload ⚠️ **BLOCKER**
2. **Week 2-4**: Implement multi-replica deployments with anti-affinity
3. **Week 5**: Validate with chaos testing, load testing
4. **Week 6**: Production cutover, monitor for 30 days

### Risks and Mitigations

| Risk | Mitigation | Owner |
|------|------------|-------|
| Swap causing etcd slowdown | Disable swap immediately | Cluster Ops |
| Forge CPU exhaustion | Move non-GPU workloads to masters | Cluster Ops |
| Resource contention | Implement quotas + PriorityClasses | Cluster Ops |
| Deployment failures | Use PDBs + gradual rollout | Cluster Ops |

**Final Recommendation**: Proceed with HA upgrade, starting with swap disable and Forge optimization. Cluster has sufficient capacity for 9/10 HA with asymmetric 3-master architecture.

---

**Version**: 1.0
**Created**: 2026-03-21
**Author**: Cluster Operations Team
**Status**: Ready for Review
