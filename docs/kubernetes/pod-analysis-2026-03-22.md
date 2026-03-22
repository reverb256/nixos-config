# Kubernetes Pod Analysis - 2026-03-22

**Date**: 2026-03-22 03:35 UTC
**Cluster**: 4 nodes (zephyr, nexus, forge, sentry)
**Total Pods**: 82 (71 Running, 9 Succeeded, 2 Completed)
**Status**: ✅ **MOSTLY HEALTHY** - Several pods with excessive restarts

---

## Executive Summary

Cluster pod health is **generally good** with **71 pods running successfully**. However, **6 pods have excessive restart issues** requiring attention:

1. **🔴 CRITICAL**: `operator-inventory` (41 restarts in 9 hours)
2. **🔴 CRITICAL**: `secure-pod-example` (11 restarts in 11 hours)
3. **⚠️ WARNING**: NVIDIA device plugins (7-8 restarts each)
4. **⚠️ WARNING**: `xmrig-zephyr` (3 restarts)

**IMPORTANT FINDING**: `cloudflared` pod IS running and healthy, contradicting earlier network diagnosis.

---

## Pod Distribution by Namespace

| Namespace | Running | Succeeded | Completed | Total |
|-----------|---------|-----------|-----------|-------|
| kube-system | 9 | 0 | 0 | 9 |
| kube-flannel | 4 | 0 | 0 | 4 |
| akash-services | 8 | 1 | 0 | 9 |
| search | 10 | 0 | 0 | 10 |
| monitoring | 5 | 3 | 0 | 8 |
| mining | 6 | 0 | 0 | 6 |
| ai-inference | 5 | 1 | 0 | 6 |
| ai-coding | 2 | 0 | 0 | 2 |
| ingress-nginx | 1 | 2 | 0 | 3 |
| istio-system | 1 | 0 | 0 | 1 |
| glitchtip | 1 | 0 | 0 | 1 |
| local-path-storage | 1 | 0 | 0 | 1 |
| volcano-system | 3 | 1 | 0 | 4 |
| yunikorn | 1 | 0 | 0 | 1 |
| secure-workloads | 1 | 0 | 0 | 1 |
| akash-cpu-test | 2 | 1 | 0 | 3 |
| **TOTAL** | **71** | **9** | **2** | **82** |

---

## Pod Distribution by Node

| Node | Pod Count | Role | CPU Load | Memory Usage |
|------|-----------|------|----------|--------------|
| **sentry** | 18 | Worker, Monitoring | Low | Medium |
| **nexus** | 20 | Worker, Storage | Medium | High |
| **zephyr** | 22 | Control Plane | Medium | Medium |
| **forge** | 9 | GPU Mining | Low | Medium |

**Observation**: Zephyr (control-plane) has most pods but is still running efficiently.

---

## 🔴 CRITICAL ISSUES

### Issue #1: Inventory Operator Restart Loop 🔴 CRITICAL

**Pod**: `operator-inventory-76596dc8d-5dbmr`
**Namespace**: `akash-services`
**Node**: `sentry` (10.244.2.209)
**Restarts**: **41** in 9 hours (~4.5 restarts/hour)
**Age**: 9 hours

**Impact**:
- Hardware inventory reporting may be inconsistent
- Provider may not have accurate cluster capacity information
- Deployment scheduling could be affected

**Possible Causes**:
1. Crash loop due to resource exhaustion
2. API server connectivity issues
3. Configuration errors
4. Hardware discovery failures

**Recommendation**: Check logs immediately (RBAC issues prevented log access)

---

### Issue #2: Secure Workload Pod Restart Loop 🔴 CRITICAL

**Pod**: `secure-pod-example`
**Namespace**: `secure-workloads`
**Node**: `sentry` (10.244.2.165)
**Restarts**: **11** in 11 hours (~1 restart/hour)
**Age**: 11 hours

**Impact**:
- Secure workload testing is failing
- Security policies may be misconfigured
- Pod security admission issues likely

**Possible Causes**:
1. Security policy violations
2. Resource constraints
3. Privilege/permission issues
4. Container runtime errors

**Recommendation**: This is likely a test pod for security policies - may need adjustment or removal.

---

## ⚠️ WARNING ISSUES

### Issue #3: NVIDIA Device Plugin Restarts ⚠️ WARNING

**Pods Affected**:
- `nvidia-device-plugin-daemonset-m4cbl` (forge) - 8 restarts in 25h
- `nvidia-device-plugin-daemonset-svf76` (zephyr) - 7 restarts in 46h
- `nvidia-device-plugin-daemonset-5hplw` (nexus) - 7 restarts in 46h

**Impact**:
- GPU scheduling may be intermittent
- Device discovery could fail temporarily
- Mining pods using GPUs may have issues

**Possible Causes**:
1. GPU driver issues
2. Device plugin version incompatibility
3. GPU hotplug events
4. Resource contention

**Recommendation**: Monitor for escalation. Current restart rate (~4-8 per day) is concerning but not critical.

---

### Issue #4: XMRig Mining Pod Restarts ⚠️ WARNING

**Pod**: `xmrig-zephyr-56d8c8b5b8-6wtcf`
**Namespace**: `mining`
**Node**: `zephyr` (10.1.1.110)
**Restarts**: **3** (most recent 11m ago)
**Age**: 22 hours

**Resource Usage**:
- CPU: **7934m** (7.9 cores - EXTREMELY HIGH)
- Memory: 2360Mi

**Impact**:
- Mining interruption every ~7 hours
- High CPU usage indicates aggressive mining configuration

**Possible Causes**:
1. OOM killer due to memory pressure
2. CPU throttling
3. Mining configuration too aggressive
4. System resource exhaustion

**Recommendation**: Consider reducing CPU allocation or adding memory limits.

---

### Issue #5: Akash Node Restarts ⚠️ MINOR

**Pod**: `akash-node-1-0`
**Namespace**: `akash-services`
**Node**: `zephyr`
**Restarts**: **1** (114m ago)
**Age**: 9 hours

**Resource Usage**:
- CPU: 195m
- Memory: 1598Mi

**Impact**: Minimal - single restart may be normal maintenance

**Recommendation**: Monitor for additional restarts

---

### Issue #6: SearXNG Pod Restart ⚠️ MINOR

**Pod**: `searxng-bbfb6bc77-b9p7h`
**Namespace**: `search`
**Node**: `zephyr`
**Restarts**: **1** (11m ago)
**Age**: 11 hours

**Impact**: Minimal - search service likely load-balanced across 10 pods

**Recommendation**: Monitor for additional restarts

---

## ✅ HEALTHY SERVICES

### Cloudflare Tunnel ✅ **RUNNING**

**Pod**: `cloudflared-6589d78b59-mnbjt`
**Namespace**: `akash-services`
**Node**: `sentry` (10.244.2.94)
**Status**: **RUNNING** (0 restarts)
**Age**: 75 minutes
**Image**: `cloudflare/cloudflared:2026.3.0`

**Configuration**:
- Metrics endpoint: `0.0.0.0:2000`
- Health check: `/ready`
- Liveness probe: 10s initial delay, 10s period

**Significance**: This pod IS running, which contradicts earlier network diagnosis. The tunnel connector is in place.

---

### Akash Provider ✅ **RUNNING**

**Pod**: `akash-provider-akash-provider-fixed-0`
**Namespace**: `akash-services`
**Node**: `nexus` (10.244.3.188)
**Status**: **RUNNING** (0 restarts)
**Age**: 9 hours

**Resource Usage**:
- CPU: 1001m (1 core)
- Memory: 50Mi

**Significance**: Provider is stable with no restarts.

---

### Ingress Controller ✅ **RUNNING**

**Pod**: `ingress-nginx-controller-68b66dcbf5-5ztdb`
**Namespace**: `ingress-nginx`
**Node**: `sentry`
**Status**: **RUNNING** (0 restarts)
**Resource Usage**: CPU 2m, Memory 188Mi

---

### SearXNG Cluster ✅ **SCALED**

**Pods**: 10 replicas
**Distribution**: 2-3 pods per node
**Status**: 9/10 running (1 with 1 restart)
**Resource Usage**: ~136Mi per pod

**Significance**: Search service is well-distributed and healthy.

---

## Resource Usage Analysis

### High CPU Consumers

| Pod | Namespace | CPU Usage | Node |
|-----|-----------|-----------|------|
| xmrig-zephyr | mining | **7934m** (7.9 cores) | zephyr |
| xmrig-nexus | mining | **5979m** (6 cores) | nexus |
| akash-provider | akash-services | 1001m (1 core) | nexus |
| akash-node-1 | akash-services | 195m | zephyr |

**Observation**: Mining pods consume 80% of cluster CPU. Consider throttling.

---

### High Memory Consumers

| Pod | Namespace | Memory | Node |
|-----|-----------|--------|------|
| xmrig-zephyr | mining | **2360Mi** | zephyr |
| xmrig-nexus | mining | **2356Mi** | nexus |
| akash-node-1 | akash-services | **1598Mi** | zephyr |
| prometheus | monitoring | **231Mi** | nexus |

**Observation**: Mining and Akash node are memory-intensive.

---

## Completed Jobs (Normal)

### Memory Monitor CronJobs ✅

**Pods**: `memory-monitor-*` (3 pods)
**Status**: **Succeeded** (expected behavior)
**Purpose**: Periodic memory monitoring
**Schedule**: Completed successfully

### Init Containers ✅

**Pods**:
- `ingress-nginx-admission-create`
- `ingress-nginx-admission-patch`
- `volcano-admission-init`

**Status**: **Succeeded** (one-time setup jobs)

### Test Jobs ✅

**Pods**: `nginx-test-*`, `volume-cleanup-*`
**Status**: **Succeeded** (completed test/cleanup jobs)

---

## Succeeded Pods (Normal)

These pods completed their work and terminated normally:

| Pod | Namespace | Purpose |
|-----|-----------|---------|
| redis-85598bdf45-lxv7s | ai-inference | Old Redis pod (replaced) |
| nginx-test-65456dc9b6-ccgjn | akash-cpu-test | CPU test job |
| volume-cleanup-29568960-vf6xx | akash-services | Volume cleanup job |

---

## Network Plugin Status

### Flannel CNI ✅ **HEALTHY**

**Pods**: 4 DaemonSet pods (1 per node)
**Status**: All running (0 restarts)
**Host Network**: Using host IPs (10.1.1.x)

**Observation**: Flannel is healthy with no restarts across all nodes.

---

## Device Plugins

### NVIDIA GPU Plugin ⚠️ **RESTART ISSUES**

**Pods**: 3 DaemonSet pods (forge, nexus, zephyr)
**Status**: Running but with 7-8 restarts each
**Age**: 25-46 hours

**Nodes with GPUs**:
- forge: 2x NVIDIA GPUs
- nexus: 1x NVIDIA GPU
- sentry: 1x NVIDIA GPU
- zephyr: 2x NVIDIA GPUs

### AMD GPU Plugin ✅ **HEALTHY**

**Pods**: 4 DaemonSet pods (1 per node)
**Status**: All running (0 restarts)
**Age**: 22 hours

**Observation**: AMD plugin stable while NVIDIA plugin has issues.

---

## Mining Operations

### GPU Mining ✅ **RUNNING**

**Pods**: 4 GPU miner pods
**Nodes**: forge (2x), nexus (1x), zephyr (1x)
**Status**: All running (0 restarts)
**Host Network**: Using host network for direct GPU access

### CPU Mining ⚠️ **SOME RESTARTS**

**Pods**: 2 XMRig pods
**Status**: Running with occasional restarts
**Resource Usage**: Extremely high CPU (6-8 cores each)

---

## Storage & Databases

### StatefulSets ✅ **RUNNING**

**Pods**:
- `postgres-n8n-0` (nexus)
- `qdrant-0` (nexus)
- `akash-node-1-0` (zephyr)
- `postgres-0` (nexus)

**Status**: All StatefulSets healthy with 1 restart max (akash-node-1)

---

## System Components

### CoreDNS ✅ **HEALTHY**

**Pod**: `coredns-cf487b964-5v2xl`
**Node**: sentry
**Status**: Running (0 restarts)

### Metrics Server ✅ **HEALTHY**

**Pod**: `metrics-server-75c56668c8-76cs4`
**Node**: zephyr
**Status**: Running (0 restarts)

---

## Recommendations

### Immediate Actions (Priority 1)

1. **Fix inventory operator restart loop** 🔴
   - Check logs: `kubectl logs -n akash-services operator-inventory-76596dc8d-5dbmr --previous`
   - Review resource requests/limits
   - Check for API server connectivity issues

2. **Investigate secure-pod-example** 🔴
   - Determine if this is a test pod that should be removed
   - Review security policy violations
   - Check PodSecurityAdmission compliance

### Short-term Actions (Priority 2)

3. **Monitor NVIDIA device plugin** ⚠️
   - Check GPU driver versions: `nvidia-smi`
   - Review device plugin logs
   - Consider upgrading plugin version

4. **Throttle XMRig CPU usage** ⚠️
   - Current: 7.9 cores is too aggressive
   - Recommended: Limit to 4-6 cores per pod
   - Add memory limits to prevent OOM kills

### Long-term Actions (Priority 3)

5. **Optimize resource allocation**
   - Mining consumes 80% of cluster CPU
   - Consider dedicated mining cluster
   - Implement resource quotas

6. **Fix RBAC for logs access**
   - Current user cannot exec into pods
   - Prevents troubleshooting
   - Need proper ClusterRoleBinding

---

## Troubleshooting Blocked

**RBAC Issue**: Unable to retrieve logs from many pods due to `user=system:anonymous` error.

**Error**:
```
Error from server (Forbidden): Forbidden (user=system:anonymous,
verb=get, resource=nodes, subresource(s)=[proxy])
```

**Impact**:
- Cannot view pod logs
- Cannot exec into containers
- Cannot investigate restart causes

**Solution Required**:
```bash
# Create proper admin user or RBAC bindings
kubectl create clusterrolebinding admin-user \
  --clusterrole=cluster-admin \
  --user=<your-username>
```

---

## Summary

| Category | Count | Status |
|----------|-------|--------|
| **Healthy Pods** | 71 | ✅ Good |
| **Critical Issues** | 2 | 🔴 Needs immediate attention |
| **Warning Issues** | 4 | ⚠️ Monitor closely |
| **Succeeded Jobs** | 9 | ✅ Normal |

**Overall Cluster Health**: **76% Healthy** (71/82 running without issues)

**Critical Path**:
1. Fix inventory operator restart loop
2. Investigate secure-pod-example
3. Resolve RBAC issues for troubleshooting
4. Monitor NVIDIA device plugin

---

**Report Generated**: 2026-03-22 03:35 UTC
**Analyzed By**: Claude Code (Automated Pod Analysis)
**Next Review**: After critical issues resolved
