# Kubernetes Container Pruning Guide

## Quick Reference: Common Pruning Commands

### 1. **Prune Completed/Succeeded Pods** (Safe)
```bash
# Find completed pods
kubectl get pods -A | grep -E "Completed|Succeeded"

# Delete specific completed pods
kubectl delete pod <pod-name> -n <namespace> --ignore-not-found=true

# Bulk delete completed pods
kubectl get pods -A | grep Completed | awk '{print $1}' | \
  xargs -I {} bash -c "kubectl delete pod $(echo {} | awk '{print $1}') -n $(echo {} | awk '{print $2}') --ignore-not-found=true"
```

### 2. **Prune Evicted Pods** (Safe)
```bash
# Find evicted pods
kubectl get pods -A | grep Evicted

# Delete all evicted pods
kubectl get pods -A | grep Evicted | awk '{print $1}' | \
  xargs -I {} bash -c "kubectl delete pod $(echo {} | awk '{print $1}') -n $(echo {} | awk '{print $2}') --ignore-not-found=true"
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

### 4. **Clean Up Old Jobs** (Safe)
```bash
# Find completed jobs
kubectl get jobs -A | grep 1/1

# Delete completed jobs
kubectl get jobs -A | grep 1/1 | awk '{print $1}' | \
  xargs -I {} bash -c "kubectl delete job $(echo {} | awk '{print $1}') -n $(echo {} | awk '{print $2}')"

# Or prune by age (older than 7 days)
kubectl get jobs -A -o json | jq -r '.items[] |
  select(.status.completionTime != null and
    (.status.completionTime | fromdateiso8601) < (now - 604800)) |
  "\(.metadata.namespace)/\(.metadata.name)"' | \
  xargs -I {} bash -c "kubectl delete job $(echo {} | cut -d'/' -f1) -n $(echo {} | cut -d'/' -f2)"
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
kubectl describe pod <pod-name> -n <namespace}

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
   kubectl get pod <pod-name> -n <namespace} -o jsonpath='{.metadata.ownerReferences}'
   ```
   - If owned by Deployment: Safe to delete (will be recreated)
   - If owned by StatefulSet: **CAUTION** - may have persistent data
   - If no owner: **WARNING** - orphaned pod

2. ✅ Check pod age
   ```bash
   kubectl get pod <pod-name> -n <namespace} -o jsonpath='{.metadata.creationTimestamp}'
   ```
   - Young pods (<1 hour): May still be starting normally
   - Old pods (>1 hour) in bad states: Safe to prune

3. ✅ Check pod status
   ```bash
   kubectl get pod <pod-name> -n <namespace} -o yaml
   ```
   - Read termination message
   - Check exit codes
   - Review resource limits

### **After Pruning**
1. ✅ Verify replacement pods are running (if managed by controller)
   ```bash
   kubectl get pods -n <namespace} -w
   ```

2. ✅ Check for resource pressure
   ```bash
   kubectl top nodes
   kubectl describe nodes
   ```

3. ✅ Review events for new errors
   ```bash
   kubectl get events -n <namespace} --sort-by='.lastTimestamp'
   ```

---

## Automation: Pruning CronJob

### Create Automated Cleanup Job
```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: pod-cleanup
  namespace: kube-system
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  concurrencyPolicy: Forbid
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: pod-cleanup
          restartPolicy: OnFailure
          containers:
          - name: cleanup
            image: bitnami/kubectl:latest
            command:
            - /bin/bash
            - -c
            - |
              # Delete evicted pods
              kubectl get pods -A | grep Evicted | awk '{print $1}' | \
                xargs -I {} bash -c "kubectl delete pod $(echo {} | awk '{print $1}') -n $(echo {} | awk '{print $2}')"

              # Delete completed jobs older than 1 day
              kubectl get jobs -A -o json | jq -r '.items[] |
                select(.status.succeeded == 1 and
                  (.status.completionTime | fromdateiso8601) < (now - 86400)) |
                "\(.metadata.namespace)/\(.metadata.name)"' | \
                xargs -I {} kubectl delete job $(echo {} | cut -d'/' -f2) -n $(echo {} | cut -d'/' -f1)
```

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
kubectl delete pod <pod-name> -n <namespace} --force --grace-period=0

# If still stuck, check node health
kubectl get nodes -o wide

# SSH to affected node and check kubelet
ssh <node> 'systemctl status kubelet'
```

### **Issue**: Deleted pods keep coming back
```bash
# Check if managed by controller
kubectl get deployment,statefulset,daemonset -n <namespace}

# Stop the controller first (if desired)
kubectl scale deployment <deployment-name> -n <namespace} --replicas=0

# Then delete pods
kubectl delete pods -l app=<app-label> -n <namespace}
```

### **Issue**: Too many completed pods to delete manually
```bash
# Bulk delete using jq
kubectl get pods -A -o json | jq -r '.items[] |
  select(.status.phase == "Succeeded") |
  "\(.metadata.namespace)/\(.metadata.name)"' | \
  xargs -I {} bash -c "kubectl delete pod $(echo {} | cut -d'/' -f2) -n $(echo {} | cut -d'/' -f1)"
```

---

## Summary

**Safe to Always Prune**:
- ✅ Completed/Succeeded pods
- ✅ Evicted pods
- ✅ Completed Jobs
- ✅ Pods with status: Unknown (if node is healthy)
- ✅ Orphaned pods (no owner references)

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
