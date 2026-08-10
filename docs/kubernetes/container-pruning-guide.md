# Kubernetes Container Pruning Guide

> **Status:** Reference procedure
> **Last Verified:** 2026-08-09 (command syntax and safety review)
> **Source:** Kubernetes API commands and the repository's workload/scheduling policy
>
> Review controller ownership, persistent storage, and live workload state before
> deleting anything. Never use the bulk commands below as a substitute for review.

## Quick Reference: Common Pruning Commands

### 1. **Prune Completed/Succeeded Pods** (Review first)
```bash
# Inspect completed pods before deleting anything.
kubectl get pods -A --field-selector=status.phase==Succeeded

# Delete one reviewed pod.
kubectl delete pod <pod-name> -n <namespace> --ignore-not-found=true

# Generate a reviewable list; run deletion only after checking the output.
kubectl get pods -A -o json | jq -r '
  .items[] | select(.status.phase == "Succeeded") |
  "\(.metadata.namespace)/\(.metadata.name)"'
```

### 2. **Review Evicted Pods**
```bash
# List evicted pods. Check the owning controller and node before deletion.
kubectl get pods -A -o json | jq -r '
  .items[] | select(.status.reason == "Evicted") |
  "\(.metadata.namespace)/\(.metadata.name)"'

# Delete one reviewed evicted pod.
kubectl delete pod <pod-name> -n <namespace> --ignore-not-found=true
```

### 3. **Restart Pods with High Restarts** (Use Caution)
```bash
# Find pods with >5 restarts
kubectl get pods -A | awk '$5 > 5 {print}'

# Restart a deployment (will recreate pods)
kubectl rollout restart deployment <deployment-name> -n <namespace>

# Force delete specific pod (Deployment will recreate it)
kubectl delete pod <pod-name> -n <namespace> --force --grace-period=0
```

### 4. **Review Old Jobs**
```bash
# List completed jobs for review.
kubectl get jobs -A -o json | jq -r '
  .items[] | select(.status.completionTime != null) |
  "\(.metadata.namespace)/\(.metadata.name)"'

# Delete one reviewed job.
kubectl delete job <job-name> -n <namespace> --ignore-not-found=true

# Generate a list of jobs older than seven days. Review it before deletion.
kubectl get jobs -A -o json | jq -r '
  .items[] | select(.status.completionTime != null and
    (.status.completionTime | fromdateiso8601) < (now - 604800)) |
  "\(.metadata.namespace)/\(.metadata.name)"'
```

### 5. **Clean Up Container Images** (Free Disk Space)
```bash
# On each node, prune unused images
ssh forge 'sudo crictl images prune -a'
ssh nexus 'sudo crictl images prune -a'
ssh zephyr 'sudo crictl images prune -a'
ssh sentry 'sudo crictl images prune -a'

# Or using containerd directly
ssh forge 'sudo ctr image prune'

# Check image disk usage
ssh forge 'sudo crictl images'
ssh forge 'df -h /var/lib/containerd'
```

---

## Container States Explained

### **Normal States** (No Action Needed)
- **Running**: Pod is functioning normally
- **Pending**: Pod is waiting for resources (normal)
- **Succeeded/Completed**: Job/pod finished successfully

### **Warning States** (Monitor)
- **ImagePullBackOff**: Container image cannot be pulled
  - Check: `kubectl describe pod <pod-name> -n <namespace>`
  - Fix: Verify image name, registry access, credentials

- **ErrImagePull**: Error pulling image
  - Check: Image exists, registry accessible
  - Fix: Correct image reference or registry issues

### **Error States** (Action Needed)
- **CrashLoopBackOff**: Container repeatedly crashes
  - Check logs: `kubectl logs <pod-name> -n <namespace`
  - Check previous crash: `kubectl logs <pod-name> -n <namespace> --previous`
  - Fix: Debug application issues, resource limits, configuration

- **Error**: Generic container error
  - Check: `kubectl describe pod <pod-name> -n <namespace`
  - Fix: Address specific error from describe output

- **Unknown**: Pod state cannot be determined
  - Check: Node health, API server connectivity
  - Fix: Restart kubelet on affected node

- **Evicted**: Pod was evicted from node
  - Reason: Resource pressure (memory, disk, PID)
  - Fix: Delete pod, will be rescheduled on another node

---

## High Restart Count Analysis

### **When High Restarts Are Normal**
- **operator-inventory** (122 restarts): Known issue, log spam only, functionally working
- **nvidia-device-plugin-daemonset** (7 restarts): Normal for GPU drivers
- **kube-flannel** (9 restarts): Network plugin, normal churn

### **When High Restarts Are Problematic**
- **Application pods** with >5 restarts in <1 hour: Indicates crash loop
- **Database pods** with restarts: Possible resource limits or data corruption
- **StatefulSet pods** with restarts: Possible storage or config issues

### **Investigating High Restarts**
```bash
# 1. Check pod logs
kubectl logs <pod-name> -n <namespace> --tail=50

# 2. Check previous container logs
kubectl logs <pod-name> -n <namespace> --previous

# 3. Describe pod for events
kubectl describe pod <pod-name> -n <namespace>

# 4. Check resource usage
kubectl top pod <pod-name> -n <namespace>

# 5. Check pod events
kubectl get events -n <namespace> --field-selector involvedObject.name=<pod-name>
```

---

## Safe Pruning Practices

### **Before Pruning**
1. ✅ Check if pod is managed by a controller (Deployment/StatefulSet/DaemonSet)
   ```bash
   kubectl get pod <pod-name> -n <namespace> -o jsonpath='{.metadata.ownerReferences}'
   ```
   - If owned by Deployment: Safe to delete (will be recreated)
   - If owned by StatefulSet: **CAUTION** - may have persistent data
   - If no owner: **WARNING** - orphaned pod

2. ✅ Check pod age
   ```bash
   kubectl get pod <pod-name> -n <namespace> -o jsonpath='{.metadata.creationTimestamp}'
   ```
   - Young pods (<1 hour): May still be starting normally
   - Old pods (>1 hour) in bad states: Safe to prune

3. ✅ Check pod status
   ```bash
   kubectl get pod <pod-name> -n <namespace> -o yaml
   ```
   - Read termination message
   - Check exit codes
   - Review resource limits

### **After Pruning**
1. ✅ Verify replacement pods are running (if managed by controller)
   ```bash
   kubectl get pods -n <namespace> -w
   ```

2. ✅ Check for resource pressure
   ```bash
   kubectl top nodes
   kubectl describe nodes
   ```

3. ✅ Review events for new errors
   ```bash
   kubectl get events -n <namespace> --sort-by='.lastTimestamp'
   ```

---

## Automation: Pruning CronJob

### Automated Cleanup Job

Do not install an unattended deletion CronJob from this reference document. The
former example deleted resources selected by broad text pipelines without a human
review step. If automation is needed, implement it declaratively with an explicit
retention policy, dry-run/report mode, owner checks, and a tested rollback path.

### Create ServiceAccount for Cleanup
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: pod-cleanup
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: pod-cleanup
rules:
- apiGroups: [""]
  resources: ["pods", "jobs"]
  verbs: ["get", "list", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: pod-cleanup
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: pod-cleanup
subjects:
- kind: ServiceAccount
  name: pod-cleanup
  namespace: kube-system
```

---

## Troubleshooting Pruning Issues

### **Issue**: Cannot delete pod, stuck in Terminating state
```bash
# Force delete pod
kubectl delete pod <pod-name> -n <namespace> --force --grace-period=0

# If still stuck, check node health
kubectl get nodes -o wide

# SSH to affected node and check kubelet
ssh <node> 'systemctl status kubelet'
```

### **Issue**: Deleted pods keep coming back
```bash
# Check if managed by controller
kubectl get deployment,statefulset,daemonset -n <namespace>

# Stop the controller first (if desired)
kubectl scale deployment <deployment-name> -n <namespace> --replicas=0

# Then delete pods
kubectl delete pods -l app=<app-label> -n <namespace>
```

### **Issue**: Too many completed pods to review manually
```bash
# Produce a reviewable list. Delete entries individually after checking
# ownership, retention, and backup requirements.
kubectl get pods -A -o json | jq -r '.items[] |
  select(.status.phase == "Succeeded") |
  "\(.metadata.namespace)/\(.metadata.name)"'
```

---

## Summary

**Usually eligible for pruning after review**:
- Completed/Succeeded pods
- Evicted pods after checking their owner and node
- Completed Jobs after checking retention requirements
- Orphaned pods after confirming they are not part of a recovery workflow

**Prune with Caution**:
- ⚠️ CrashLoopBackOff pods (check logs first)
- ⚠️ Pods managed by StatefulSets (may have data)
- ⚠️ High-restart pods (investigate root cause)

**Never Prune**:
- ❌ Running pods without understanding impact
- ❌ Pods with active network connections
- ❌ Pods with persistent data without backup
- ❌ System-critical pods (kube-system, etc.)

**Pruning Frequency**:
- Daily: Automated cleanup of completed/evicted pods
- Weekly: Review high-restart pods
- Monthly: Clean up unused container images
