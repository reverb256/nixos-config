# Volcano Scheduler Incident - 2026-03-22

**Date:** March 22, 2026
**Severity:** High - Cluster-wide deployment failures
**Status:** ✅ Resolved
**Root Cause:** Volcano scheduler PodGroup authorization failures + GPU resource management issues

---

## Executive Summary

Volcano scheduler broke deployments cluster-wide by requiring PodGroup authorization that wasn't configured. Combined with GPU miners creating hundreds of zombie pods and external processes consuming GPU resources outside Kubernetes awareness, this caused 2058 non-running pods and deployment failures across multiple namespaces.

**Impact:**
- 2058 non-running pods (95% of cluster pods affected)
- GPU miners unable to schedule (OutOfnvidia.com/gpu)
- n8n, glitchtip, akash-provider failing with secret issues
- API server crash during recovery operations

**Resolution Time:** ~45 minutes
**Pods Cleaned:** 2057 zombie/failed pods deleted
**Cluster Health:** Restored to 54 Running pods, 5 non-running (cleanup helpers)

---

## Root Cause Analysis

### 1. Volcano Scheduler PodGroup Authorization Failures

**Problem:** Volcano scheduler's admission webhook was rejecting all deployments that didn't have explicit PodGroup RBAC configured.

**Error:**
```
Error from server (InternalError): Internal error occurred:
failed calling webhook "validatepod.volcano.sh":
Post "https://volcano-admission-service.volcano-system.svc:443/validate?timeout=3s":
no kind "PodGroup" is registered for version "scheduling.volcano.sh/v1beta1"
```

**Impact:**
- All GPU miner deployments on forge, nexus, zephyr failed
- Any deployment using Volcano scheduler couldn't create pods
- PodGroups stuck in "Inqueue" state forever

**Fix:** Switched affected deployments from `volcano-scheduler` to `default-scheduler`

### 2. GPU Miner Zombie Pod Explosion

**Problem:** `gpu-miner-forge-nvidia-0` and `gpu-miner-forge-nvidia-1` deployments created **452 zombie pods** in ContainerStatusUnknown state.

**Root Cause:**
- Deployment set to `volcano-scheduler` which couldn't schedule pods
- Kubernetes kept creating new replicas trying to achieve desired state
- Each replica failed and got stuck in Unknown state
- No resource limits on replicas

**Impact:**
- 452 dead pods consuming etcd storage
- Deployment chaos on forge node
- Confusion about actual pod status

**Fix:**
1. Killed external lolMiner processes consuming GPU 100%
2. Deleted both deployments
3. Force deleted all 452 zombie pods

### 3. External GPU Processes Not Visible to Kubernetes

**Problem:** lolMiner processes running outside Kubernetes (via systemd) were consuming 100% of GPU resources, making GPUs unavailable for K8s workloads.

**Discovery:**
```bash
ssh forge "nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv,noheader"
2894895, ./lolMiner, 6880 MiB
2894653, ./lolMiner, 6880 MiB
```

**Impact:**
- K8s GPU miners couldn't schedule (OutOfnvidia.com/gpu)
- GPU resources appeared free in K8s but were actually used
- nvidia-device-plugin reported 0 capacity on forge

**Fix:**
```bash
ssh forge "sudo pkill -9 lolMiner"
```

### 4. nvidia-device-plugin Registration Failures

**Problem:** nvidia-device-plugin on zephyr couldn't register with kubelet, causing GPU resources to not be advertised.

**Error:**
```
I0322 10:24:45.307506  163830 server.go:121] Could not register device plugin: context deadline exceeded
E0322 10:24:45.307722  163830 main.go:278] Could not contact Kubelet. Did you enable the device plugin feature gate?
```

**Impact:**
- Zephyr node reported 0 GPU capacity
- gpu-miner-zephyr pods failed with "cannot allocate unregistered device nvidia.com/gpu"

**Fix:** Restarted kubelet on zephyr, which triggered device plugin re-registration

### 5. Missing Secrets for Deployed Workloads

**Problem:** n8n and glitchtip deployments referenced secrets that were defined in manifests but never applied.

**Error:**
```
spec.containers{n8n}: Error: secret "n8n-secrets" not found
spec.containers{postgres}: Error: secret "glitchtip-secrets" not found
```

**Fix:** Applied secret manifests from kubernetes-manifests directories

---

## Resolution Steps

### Phase 1: Emergency Stabilization (First 10 minutes)

1. **Disabled Volcano scheduler admission webhook**
   - Attempted to delete validatingwebhookconfiguration (already gone)
   - Confirmed Volcano controller/scheduler running but webhooks disabled

2. **Switched deployments to default-scheduler**
   ```bash
   kubectl patch deployment xmrig-zephyr -n mining \
     -p '{"spec":{"template":{"spec":{"schedulerName":"default-scheduler"}}}}'
   ```

3. **Killed external GPU-consuming processes**
   ```bash
   ssh forge "sudo pkill -9 lolMiner"
   ssh zephyr "sudo pkill -9 lolMiner"  # if present
   ```

### Phase 2: GPU Resource Recovery (Minutes 10-25)

4. **Restarted kubelet on zephyr**
   ```bash
   ssh zephyr "sudo systemctl restart kubelet"
   ```

5. **Verified GPU registration**
   - Zephyr: 2 GPUs advertised (RTX 3060 Ti + RTX 3090)
   - Forge: 2 GPUs advertised (2x RTX 4060)
   - Nexus: 1 GPU advertised (RTX 3060 Ti)

6. **Deleted forge mining deployments**
   ```bash
   kubectl delete deployment gpu-miner-forge-nvidia-0 gpu-miner-forge-nvidia-1 -n mining
   ```

### Phase 3: Zombie Pod Cleanup (Minutes 25-35)

7. **Bulk deleted Failed pods**
   ```bash
   kubectl delete pods -A --field-selector=status.phase==Failed --force --grace-period=0
   # Result: 2055 pods deleted
   ```

8. **Scaled down problematic deployments**
   ```bash
   kubectl scale deployment gpu-miner-zephyr -n mining --replicas=0
   ```

9. **Deleted and recreated mining namespace**
   ```bash
   kubectl delete namespace mining --force --grace-period=0
   kubectl create namespace mining
   ```

### Phase 4: Secret and Workload Fixes (Minutes 35-45)

10. **Applied missing secrets**
    ```bash
    kubectl apply -f /etc/nixos/kubernetes-manifests/n8n/deployment-fixed.yaml
    kubectl apply -f /etc/nixos/kubernetes-manifests/glitchtip/01-secrets.yaml
    ```

11. **Restarted stuck pods**
    ```bash
    kubectl delete pod postgres-0 -n glitchtip
    ```

12. **Verified cluster health**
    - 54 Running pods
    - 5 non-running (cleanup helpers, not critical)
    - All 4 nodes Ready

---

## Prevention Measures

### 1. Volcano Scheduler Configuration

**DO NOT use Volcano for general workloads.** It's designed for batch/HPC/AI workloads with explicit PodGroup configuration.

**Recommendations:**
- Use `default-scheduler` for stateless services
- Use Volcano only for:
  - AI/ML training jobs with explicit PodGroup
  - Batch jobs with gang scheduling requirements
  - Workloads that can tolerate preemption

**Implementation:**
```yaml
# For regular deployments (DO NOT USE VOLCANO)
spec:
  template:
    spec:
      schedulerName: default-scheduler  # Explicit, not volcano

# For batch/AI workloads that need Volcano
apiVersion: scheduling.volcano.sh/v1beta1
kind: PodGroup
metadata:
  name: my-job-group
  namespace: mining
spec:
  minMember: 1
  queue: default
```

### 2. GPU Resource Management

**Problem:** External processes (lolMiner) consumed GPUs outside Kubernetes awareness.

**Solution:**
1. **Run ALL GPU workloads in Kubernetes** - no external systemd GPU miners
2. **Implement ResourceQuotas** per namespace for GPU limits
3. **Monitor GPU utilization** with Prometheus+nvidia_gpu_exporter

**Implementation:**
```yaml
# ResourceQuota for mining namespace
apiVersion: v1
kind: ResourceQuota
metadata:
  name: gpu-quota
  namespace: mining
spec:
  hard:
    requests.nvidia.com/gpu: "4"  # Max 4 GPUs across namespace
    limits.nvidia.com/gpu: "4"
  scopeSelector:
    matchExpressions:
    - key: priorityclass
      operator: In
      values: ["mining-low"]
```

### 3. Prevent Zombie Pod Explosions

**Problem:** Deployments created hundreds of replicas when pods couldn't schedule.

**Solution:** Set explicit resource limits on deployments.

**Implementation:**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gpu-miner-forge-nvidia-0
  namespace: mining
spec:
  replicas: 1  # ALWAYS set explicit replica count
  revisionHistoryLimit: 3  # Limit old replica sets
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 0  # CRITICAL: Don't create extra pods during update
      maxUnavailable: 1
  template:
    spec:
      schedulerName: default-scheduler
```

### 4. Namespace and Secret Management

**Problem:** Secrets defined in manifests but never applied.

**Solution:** Use GitOps (ArgoCD/Flux) or automated manifest application.

**Implementation:**
```bash
# Add to justfile or deployment script
kubectl apply -f kubernetes-manifests/n8n/
kubectl apply -f kubernetes-manifests/glitchtip/
# Ensure secrets applied BEFORE deployments
```

**Better:** Use Kustomize with dependency order:
```yaml
# kustomization.yaml
resources:
  - 01-secrets.yaml
  - 02-postgres-statefulset.yaml
  - 03-redis-deployment.yaml
  - 04-web-deployment.yaml
```

### 5. Monitoring and Alerting

**Problem:** No visibility into deployment failures until manual inspection.

**Solution:** Prometheus alerts for:
- Pods in ContainerStatusUnknown > 5 minutes
- Deployments creating > 10 replicas unexpectedly
- GPU utilization at 100% for > 10 minutes
- Failed pods per namespace rate

**Implementation:**
```yaml
# Alerting rules
groups:
- name: kubernetes-workloads
  rules:
  - alert: ZombiePodsDetected
    expr: |
      count(kube_pod_status_phase{phase="Unknown"}) > 10
    for: 5m
    labels:
      severity: critical
    annotations:
      summary: "Too many pods in Unknown state"

  - alert: GPUUtilizationHigh
    expr: |
      rate(nvidia_gpu_utilization_gpu[5m]) > 0.95
    for: 10m
    labels:
      severity: warning
    annotations:
      summary: "GPU at 100% for 10+ minutes"
```

---

## Lessons Learned

1. **Volcano scheduler is NOT a drop-in replacement for default-scheduler**
   - Requires explicit PodGroup configuration
   - Needs RBAC for PodGroups
   - Use only for batch/HPC workloads

2. **Never run GPU workloads outside Kubernetes if you want K8s to manage GPUs**
   - External processes bypass K8s resource awareness
   - Causes "OutOfnvidia.com/gpu" even when GPUs are busy
   - Defeats purpose of GPU resource management

3. **Always set replica limits on deployments**
   - Prevents replica explosions
   - Set `maxSurge: 0` for critical deployments
   - Use `revisionHistoryLimit: 3` to limit old ReplicaSets

4. **Apply secrets BEFORE deployments**
   - Use Kustomize dependency order
   - Or GitOps with dependency management
   - Never assume secrets exist

5. **Monitor for zombie pods**
   - ContainerStatusUnknown pods indicate crashes
   - Set up alerts for > 10 Unknown pods
   - Regular cleanup of stuck pods

---

## Verification

**Post-incident cluster health:**
```bash
# All nodes Ready
kubectl get nodes
# NAME     STATUS   ROLES           AGE     VERSION
# forge    Ready    <none>          3d20h   v1.35.2
# nexus    Ready    <none>          3d19h   v1.35.2
# sentry   Ready    <none>          3d19h   v1.35.2
# zephyr   Ready    control-plane   3d20h   v1.35.2

# Only 5 non-running pods (cleanup helpers)
kubectl get pods -A --field-selector=status.phase!=Running --no-headers | wc -l
# 5

# All critical services running
kubectl get pods -n ai-inference -l app=n8n
# NAME                   READY   STATUS    RESTARTS   AGE
# n8n-6ffb5d9d8f-4vtzh   1/1     Running   0          10m

kubectl get pods -n glitchtip -l app=postgres
# NAME         READY   STATUS    RESTARTS   AGE
# postgres-0   1/1     Running   0          12m
```

---

**Document Status:** ✅ Complete
**Next Review:** After implementing prevention measures
**Related Issues:** GPU marketplace coordination, secret management automation
