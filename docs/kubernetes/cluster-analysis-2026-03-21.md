# Kubernetes Cluster Analysis: Resource Distribution & Pod Antipatterns

**Analysis Date**: 2026-03-21
**Cluster**: 4-node NixOS cluster (Zephyr, Nexus, Forge, Sentry)
**Kubernetes Version**: v1.35.2

---

## Executive Summary

**Critical Issues Found**:
1. 🚨 **CRITICAL**: 150+ failed mining pods on Nexus (resource waste)
2. ⚠️ **HIGH**: 27 pods without resource requests (risk of OOM)
3. ⚠️ **HIGH**: 33 pods without resource limits (no resource throttling)
4. ⚠️ **MEDIUM**: Widespread use of default service accounts (security risk)

**Positive Findings**:
- ✅ GPU device plugins properly distributed across nodes
- ✅ Core workloads have resource limits defined
- ✅ Critical system pods properly identified

---

## Cluster Overview

### Node Capacity Distribution

| Node | CPU Cores | Memory | AMD GPUs | NVIDIA GPUs | Max Pods | Role |
|------|-----------|--------|----------|-------------|----------|------|
| **Zephyr** | 32 | 31.7 GiB | 0 | 2 (RTX 4060) | 110 | Control plane |
| **Nexus** | 24 | 47.0 GiB | 0 | 1 | 110 | Storage/GPU |
| **Forge** | 6 | 15.6 GiB | 2 (RX 5700/5600 XT) | 2 (RTX 4060) | 110 | GPU computing |
| **Sentry** | 16 | 31.3 GiB | 1 (RX 5600 XT) | 0 | 110 | Monitoring |

**Total Cluster Capacity**:
- CPU: 78 cores
- Memory: 125.6 GiB
- AMD GPUs: 3
- NVIDIA GPUs: 5

### Workload Distribution

- **Total Namespaces**: 22
- **Running Pods**: 49
- **Total Workloads** (Deployments/StatefulSets/DaemonSets): 43

---

## 🚨 Critical Issues

### 1. Massive Pod Explosion on Nexus (CRITICAL)

**Issue**: 150+ failed mining pods on Nexus node

```
gpu-miner-nexus-78b95d94f7-*: 150+ pods
Status: ContainerStatusUnknown
Node: nexus
Age: 0-26 seconds (rapidly cycling)
```

**Impact**:
- **Resource waste**: Each failed pod consumes etcd storage, API server memory
- **API load**: 150+ pod objects create unnecessary load on control plane
- **Monitoring noise**: Failed pods obscure real issues
- **Scheduler overhead**: Kubernetes attempts to schedule pods that can't run

**Root Cause**: Likely deployment configuration issue or GPU scheduling conflict

**Recommendation**:
```bash
# Delete all failed pods
kubectl delete pods -n mining -l app=gpu-miner-nexus --field-selector=status.phase!=Running

# Scale down to 0 replicas
kubectl scale deployment gpu-miner-nexus -n mining --replicas=0

# Investigate the deployment
kubectl describe deployment gpu-miner-nexus -n mining
kubectl logs -l app=gpu-miner-nexus -n mining --tail=50
```

**Prevention**:
- Add `restartPolicy: OnFailure` for mining jobs (not deployments)
- Use `backoffLimit` in Jobs to prevent unlimited retries
- Implement pod failure monitoring and alerting

---

## ⚠️ High Priority Issues

### 2. Missing Resource Requests (27 pods)

**Issue**: 27 pods running without resource requests

**Why This Matters**:
- **No scheduling guarantees**: Kubernetes can't make intelligent scheduling decisions
- **Risk of OOM**: Pods without requests can be killed by OOMKiller
- **No resource fairness**: Pods without requests get lowest priority

**Examples**:
```bash
# Akash operator pods
akash-services/operator-inventory-hardware-discovery-*

# Cron jobs
default/memory-monitor-*

# Mining pods (some)
```

**Recommendation**:
```yaml
# Add minimal resource requests to ALL pods
resources:
  requests:
    cpu: "100m"
    memory: "128Mi"
```

**Priority Targets**:
1. Akash services (5 pods)
2. Cron jobs (3+ pods)
3. Any long-running workloads

---

### 3. Missing Resource Limits (33 pods)

**Issue**: 33 pods without resource limits

**Why This Matters**:
- **No resource throttling**: Misbehaving pods can consume unlimited resources
- **Noisy neighbor problem**: One pod can starve others on same node
- **Cost unpredictability**: Resource usage can spike unexpectedly

**Examples**:
```bash
# Device plugins (expected)
kube-system/amdgpu-device-plugin-daemonset-*
kube-system/nvidia-device-plugin-daemonset-*

# CoreDNS
kube-system/coredns-*

# Network plugins
kube-flannel/kube-flannel-ds-*
```

**Recommendation**:
```yaml
# Add resource limits based on observed usage
resources:
  requests:
    cpu: "100m"
    memory: "128Mi"
  limits:
    cpu: "500m"
    memory: "512Mi"
```

**Exception**: Device plugins and system-critical pods may intentionally have no limits

---

### 4. Pods with High Restart Counts

**Issue**: Several pods with excessive restarts

| Pod | Restarts | Node | Issue |
|-----|----------|------|-------|
| `operator-inventory-5854686d79-lxs6t` | **140** | sentry | CRASH LOOP |
| `akash-node-1-0` | **11** | nexus | Unstable |
| `kube-flannel-ds-sgm89` | **9** | zephyr | Network issues |
| `nvidia-device-plugin-*` | 7-8 | multiple | GPU driver issues |

**Recommendation**:
```bash
# Investigate crash loops
kubectl describe pod operator-inventory-5854686d79-lxs6t -n akash-services
kubectl logs operator-inventory-5854686d79-lxs6t -n akash-services --previous

# Check for resource issues
kubectl top pod operator-inventory-5854686d79-lxs6t -n akash-services
```

---

## ⚠️ Medium Priority Issues

### 5. Default Service Account Usage

**Issue**: 20+ pods using the `default` service account

**Why This Matters**:
- **Security risk**: Default SA has more permissions than needed
- **RBAC bypass**: Can't implement least-privilege access control

**Examples**:
```bash
ai-inference/grafana-5c8f6744dd-2snc9
ai-inference/n8n-b87d66945-svlb4
akash-cpu-test/nginx-test-*
akash-services/cloudflared-*
glitchtip/web-7944656db4-pq6r9
```

**Recommendation**:
```yaml
# Create dedicated service accounts
apiVersion: v1
kind: ServiceAccount
metadata:
  name: workload-sa
  namespace: my-namespace
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: workload-role
rules:
  - apiGroups: [""]
    resources: ["configmaps"]
    verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: workload-rolebinding
subjects:
  - kind: ServiceAccount
    name: workload-sa
roleRef:
  kind: Role
    name: workload-role
```

---

### 6. Privileged Container Usage

**Issue**: 11 pods running with `privileged: true`

**List**:
- Device plugins (7): AMDGPU + NVIDIA device plugins
- Mining pods (4): GPU miners require direct hardware access

**Assessment**: ✅ **ACCEPTABLE** for this use case

**Why**: GPU mining and device plugins require privileged mode for:
- Direct GPU access (`/dev/kfd`, `/dev/nvidia0`)
- Hardware memory management
- Device driver loading

**Recommendation**: Continue monitoring, but acceptable for these specific workloads

---

### 7. hostPath Volume Usage

**Issue**: Widespread use of hostPath volumes

**Users**:
- **Flannel** (networking): Required for CNI
- **Device plugins**: Required for `/dev`, `/sys`, `/var/lib/kubelet/device-plugins`
- **Akash provider**: `/root/.akash/k8s-config`

**Assessment**: ⚠️ **REVIEW NEEDED**

**Risks**:
- **Node coupling**: Pods tied to specific nodes
- **Security**: Direct host filesystem access
- **Portability**: Harder to migrate to different nodes

**Recommendation**:
1. **Accept**: Device plugins and Flannel (required)
2. **Review**: Akash provider hostPath usage
3. **Consider**: Use ConfigMaps/Secrets instead of hostPath where possible

---

## Resource Allocation Analysis

### Well-Configured Workloads

**Examples of good resource management**:

| Workload | Requests | Limits | Ratio |
|----------|----------|--------|-------|
| Grafana | 100m CPU / 128Mi RAM | 500m CPU / 512Mi RAM | 5x / 4x |
| Prometheus | 200m CPU / 512Mi RAM | 1 CPU / 2Gi RAM | 5x / 4x |
| Akash provider | 1 CPU / 2Gi RAM | 2 CPU / 4Gi RAM | 2x / 2x |
| n8n | 250m CPU / 256Mi RAM | 500m CPU / 1Gi RAM | 2x / 4x |

**Best Practices Followed**:
- ✅ Requests < Limits (bursting capacity)
- ✅ Reasonable limits (prevent resource starvation)
- ✅ Memory limits to prevent OOM

### Workloads Needing Attention

**Missing limits** (CPU only, no memory):
- ingress-nginx-controller
- istiod
- CoreDNS

**Missing both requests and limits**:
- Device plugins (intentional)
- Flannel (intentional)
- Discovery pods (should have minimum requests)

---

## Pod Distribution by Namespace

| Namespace | Running Pods | Issues |
|-----------|--------------|--------|
| **mining** | 4 | 150+ failed pods on nexus |
| **akash-services** | 6 | High restart count (140) |
| **kube-system** | 11 | Missing limits (expected) |
| **ai-inference** | 5 | Using default SA |
| **akash-cpu-test** | 2 | Using default SA |
| **glitchtip** | 2 | Using default SA |

---

## Antipatterns Detected

### 1. Pod Explosion Antipattern ⚠️

**Location**: `mining/gpu-miner-nexus` deployment
**Issue**: 150+ failed pods, deployment creating new pods every few seconds
**Antipattern**: Using Deployment for GPU mining instead of Job/CronJob

**Fix**:
```yaml
# Don't use Deployment for mining
apiVersion: apps/v1  # ❌ WRONG
kind: Deployment

# Use DaemonSet or Job instead
apiVersion: batch/v1  # ✅ BETTER
kind: Job
spec:
  backoffLimit: 3  # Prevent unlimited retries
  template:
    spec:
      restartPolicy: OnFailure  # Don't restart automatically
```

---

### 2. Missing Health Checks

**Issue**: Many pods lack liveness/readiness probes

**Impact**:
- Kubernetes can't detect unhealthy pods
- Traffic sent to unready pods
- No automatic restart on failure

**Recommendation**:
```yaml
livenessProbe:
  httpGet:
    path: /healthz
    port: 8080
  initialDelaySeconds: 15
  periodSeconds: 20
readinessProbe:
  httpGet:
    path: /ready
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 10
```

---

### 3. Using Latest Tag

**Issue**: Several deployments use `:latest` image tags

**Risks**:
- Unpredictable updates
- Rollback difficult
- Can't track which version is running

**Recommendation**:
```yaml
# ❌ BAD
image: nginx:latest

# ✅ GOOD
image: nginx:1.25.2
```

---

## GPU Resource Distribution

### AMD GPUs

| Node | GPUs | Allocated | Available | Status |
|------|------|-----------|-----------|--------|
| Forge | 2 | 0 | 2 | ✅ Idle (mining via systemd) |
| Sentry | 1 | 0 | 1 | ✅ Available for K8s |

### NVIDIA GPUs

| Node | GPUs | Allocated | Available | Status |
|------|------|-----------|-----------|--------|
| Zephyr | 2 | 0 | 2 | ✅ Available |
| Nexus | 1 | 1 | 0 | ⚠️ Fully utilized |
| Forge | 2 | 2 | 0 | ✅ Mining active |

**Observation**: GPU resources are properly allocated and tracked by device plugins

---

## Priority Action Items

### Immediate (Today)

1. **CRITICAL**: Clean up 150+ failed mining pods on Nexus
   ```bash
   kubectl delete pods -n mining -l app=gpu-miner-nexus --field-selector=status.phase!=Running
   kubectl scale deployment gpu-miner-nexus -n mining --replicas=0
   ```

2. **HIGH**: Investigate operator-inventory crash loop (140 restarts)
   ```bash
   kubectl logs operator-inventory-5854686d79-lxs6t -n akash-services --previous
   kubectl describe pod operator-inventory-5854686d79-lxs6t -n akash-services
   ```

3. **HIGH**: Add resource requests to critical workloads
   - Akash services
   - Cron jobs
   - Mining pods

### This Week

4. **MEDIUM**: Create service accounts for non-system pods
   - ai-inference namespace
   - glitchtip namespace
   - akash-* namespaces

5. **MEDIUM**: Add resource limits to workloads missing them
   - ingress-nginx
   - CoreDNS
   - istiod

6. **LOW**: Add health checks to stateful workloads
   - Databases (if any)
   - Message queues
   - Long-running services

### Next Sprint

7. **LOW**: Implement pod disruption budgets for critical services
8. **LOW**: Set up resource quotas per namespace
9. **LOW**: Implement network policies for network segmentation

---

## Monitoring Recommendations

### Metrics to Track

1. **Pod Restart Rate**
   ```bash
   kubectl get pods -A -o json | jq -r '.items[] | "\(.metadata.namespace)/\(.metadata.name) \(.status.containerStatuses[0].restartCount)"' | awk '$2 > 5'
   ```

2. **Resource Usage**
   ```bash
   # Install metrics-server for kubectl top
   kubectl top pods -A
   kubectl top nodes
   ```

3. **Failed Pod Count**
   ```bash
   kubectl get pods -A --field-selector=status.phase!=Running
   ```

### Alerts to Configure

- Pod restart count > 5
- Pod in pending state > 5 minutes
- Pod in failed state > 1 minute
- Node memory usage > 90%
- Node CPU usage > 85%

---

## Best Practices Checklist

### Resource Management
- [ ] All pods have resource requests
- [ ] All pods have resource limits
- [ ] Limits >= Requests (no impossible constraints)
- [ ] Requests based on actual usage (not guessed)

### Security
- [ ] No default service accounts for app workloads
- [ ] RBAC configured for least privilege
- [ ] Network policies defined (if needed)
- [ ] Secrets used for sensitive data

### Reliability
- [ ] Liveness probes configured
- [ ] Readiness probes configured
- [ ] Pod disruption budgets for critical services
- [ ] Appropriate update strategies configured

### Observability
- [ ] Pods have meaningful labels
- [ ] Pods have annotations for documentation
- [ ] Logging configured
- [ ] Metrics exposed where applicable

---

## Conclusion

### Cluster Health Score: **6.5/10**

**Strengths**:
- ✅ GPU device plugins properly configured
- ✅ Core workloads have good resource limits
- ✅ Node capacity well-distributed
- ✅ Critical addons identified

**Weaknesses**:
- ❌ CRITICAL: Pod explosion on Nexus (150+ failed pods)
- ❌ HIGH: Missing resource requests (27 pods)
- ❌ HIGH: Missing resource limits (33 pods)
- ❌ MEDIUM: Default service account overuse
- ❌ MEDIUM: Missing health checks

### Next Steps

1. **Immediate**: Clean up failed mining pods
2. **Today**: Fix crash loop in operator-inventory
3. **This week**: Add resource requests to all pods
4. **Ongoing**: Implement monitoring and alerting

---

**Report Generated**: 2026-03-21
**Analyzer**: Claude Code (Kubernetes Specialist)
**Cluster Version**: v1.35.2
