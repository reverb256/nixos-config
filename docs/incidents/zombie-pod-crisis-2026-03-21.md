# Zombie Pod Crisis - 2026-03-21

## Critical Incident: Flannel IP Exhaustion

### What Happened

**Discovery Time:** 2026-03-21 12:00 UTC
**Trigger:** Akash audit revealed Sentry hardware-discovery pod stuck in `ContainerCreating`

### Root Cause

**7,020+ zombie pods consuming all Flannel IP addresses**

The Flannel overlay network assigns each pod a unique IP from a `/24` subnet (254 IPs per node). When pods fail but aren't deleted, they continue holding IP allocations.

**Impact:**
- Sentry node's Flannel pool: **10.244.2.1-10.244.2.254** (254 IPs total)
- All IPs exhausted by zombie pods
- New pods cannot be created (including Sentry hardware-discovery)

**Error:**
```
Failed to create pod sandbox: failed to setup network for sandbox:
plugin type="flannel" failed (add): failed to allocate for range 0:
no IP addresses available in range set: 10.244.2.1-10.244.2.254
```

---

## Zombie Pod Breakdown

### Before Cleanup
```
Total zombie pods: 7,020
Primary location: mining namespace (1,846 pods)
Status: Failed/Unknown/Evicted/ImagePullBackOff
Age: Up to 60 minutes old
```

### After Cleanup (by other agent)
```
Remaining zombie pods: 2,023
All in: mining namespace
Status: 0 (Evicted/Failed)
```

### Pod Lifecycle Issue

**What created these zombies?**
1. Mining deployments repeatedly scaled up/down
2. Pods failed or were evicted
3. Pods not properly cleaned up
4. Each failed pod retained its IP allocation

**Why weren't they deleted?**
- Evicted pods should auto-delete (garbage collection)
- Kubernetes garbage collector may be:
  - Disabled
  - Overwhelmed by volume
  - Not running due to resource constraints
  - Failing to process evicted pods

---

## Affected Services

### Direct Impact
1. **Sentry hardware-discovery pod** - Cannot be created
2. **Any new pods on Sentry** - Blocked by IP exhaustion
3. **Flannel network stability** - Degraded

### Indirect Impact
- Cluster resource tracking (showing 7,000+ "pods" that don't exist)
- Dashboard clutter
- Potential API server load from listing massive pod counts
- Memory usage in etcd (storing pod objects)

---

## Solutions

### Immediate: Clean Up Zombie Pods

**Script created:** `/etc/nixos/scripts/cleanup-zombie-pods.sh`

```bash
# Check status
./cleanup-zombie-pods.sh status

# Dry run
./cleanup-zombie-pods.sh dry-run

# Clean up (with confirmation)
./cleanup-zombie-pods.sh clean

# Force clean (no confirmation)
./cleanup-zombie-pods.sh force
```

**Progress:**
- Initial: 7,020 zombie pods
- After other agent: 2,023 remaining
- Target: 0 zombie pods

### Long-term: Prevent Recurrence

1. **Enable Kubernetes garbage collector**
   ```yaml
   # In kube-apiserver config
   --enable-garbage-collector=true
   --terminated-pod-gc-thresholds=60s
   ```

2. **Add automated cleanup CronJob**
   ```yaml
   apiVersion: batch/v1
   kind: CronJob
   metadata:
     name: cleanup-zombie-pods
   spec:
     schedule: "*/30 * * * *"  # Every 30 minutes
     jobTemplate:
       spec:
         template:
           spec:
             containers:
             - name: cleanup
               image: bitnami/kubectl:latest
               command:
               - /scripts/cleanup-zombie-pods.sh
               - --force
     ```

3. **Add resource quotas to prevent runaway pods**
   ```yaml
   apiVersion: v1
   kind: ResourceQuota
   metadata:
     name: pod-count-quota
     namespace: mining
   spec:
     hard:
       pods: "50"  # Max 50 pods in mining namespace
   ```

4. **Monitor Flannel IP usage**
   ```bash
   # Check IPs per node
   kubectl get pods -A --field-selector spec.nodeName=sentry --no-headers | wc -l

   # Should be < 250 (leaving room for system pods)
   ```

---

## Timeline

| Time | Event |
|------|-------|
| 11:55 | Cluster health improvements applied |
| 11:55 | Ingress-nginx RBAC fix applied |
| 12:00 | Akash audit requested by user |
| 12:00 | Discovered 7,020 zombie pods |
| 12:02 | Sentry hardware-discovery stuck (IP exhaustion) |
| 12:05 | Other agent began cleanup |
| 12:10 | 2,023 zombie pods remaining |
| 12:10 | Cleanup script created |

---

## 2-Hour Loop Status

You have **two** 2-hour recurring jobs:

### Job 1: `e1d79fee`
- **Cadence:** Every 2 hours (`*/2 * * * *`)
- **Prompt:** "please analyze/audit the system and services and debug all issues if something…"
- **Type:** System audit
- **Status:** Active (session-only)

### Job 2: `00eaf17c`
- **Cadence:** Every 2 hours (`*/2 * * * *`)
- **Prompt:** "please check on the akash status and make sure nothing is broken, and also chec…"
- **Type:** Akash-specific audit
- **Status:** Active (session-only)

**Note:** Both are **session-only** - will be lost when Claude Code exits. To make persistent, add to startup script or create Kubernetes CronJobs.

---

## Verification

### Check Flannel IP Pool Health
```bash
kubectl get nodes -o custom-name=NAME:.metadata.name \
  -o custom-name=POD_CIDR:.spec.podCIDR
```

### Count Zombie Pods
```bash
kubectl get pods -A | grep -E "Failed|Unknown|Evicted" | wc -l
```

### Check Sentry Node Pod Count
```bash
kubectl get pods -A --field-selector spec.nodeName=sentry --no-headers | wc -l
# Should be < 250
```

### Test New Pod Creation
```bash
kubectl run test-pod --image=nginx --restart=Never -n default
kubectl delete pod test-pod -n default
```

---

## Recommendations

### Immediate (Today)
1. ✅ **Cleanup script created** - Use `/etc/nixos/scripts/cleanup-zombie-pods.sh`
2. ⚠️ **Run cleanup** - Delete remaining 2,023 zombie pods
3. ⚠️ **Investigate garbage collector** - Why aren't pods auto-deleting?

### Short-term (This Week)
1. **Add automated cleanup** - CronJob every 30 minutes
2. **Add resource quotas** - Prevent runaway pod creation
3. **Monitor Flannel usage** - Alert when > 200 IPs/node
4. **Check garbage collector** - Verify kube-controller-manager flags

### Long-term (This Month)
1. **Increase Flannel subnet size** - Use /23 instead of /24 (512 IPs)
2. **Implement pod lifecycle policies** - Auto-delete old evicted pods
3. **Review deployment strategies** - Fix mining deployment churn
4. **Add monitoring** - Prometheus alerts for IP exhaustion

---

## Commands for Reference

### Quick Cleanup
```bash
# Check status
/etc/nixos/scripts/cleanup-zombie-pods.sh status

# Force cleanup
/etc/nixos/scripts/cleanup-zombie-pods.sh force
```

### Check Zombie Pods
```bash
# Count by namespace
kubectl get pods -A | grep -E "Failed|Unknown|Evicted" | awk '{print $1}' | sort | uniq -c

# Count by status
kubectl get pods -A | grep -E "Failed|Unknown|Evicted" | awk '{print $5}' | sort | uniq -c

# Show oldest 20
kubectl get pods -A | grep -E "Failed|Unknown|Evicted" | sort -k6 -h | head -20
```

### Check Flannel Health
```bash
# IPs per node
kubectl get pods -A --field-selector spec.nodeName=sentry --no-headers | wc -l

# All nodes
for node in forge nexus sentry zephyr; do
  count=$(kubectl get pods -A --field-selector spec.nodeName=$node --no-headers 2>/dev/null | wc -l | tr -d ' ')
  echo "$node: $count pods"
done
```

### Garbage Collector Status
```bash
# Check if enabled
kubectl get configmap -n kube-system kube-proxy -o yaml | grep garbage

# Check kube-controller-manager flags
ssh zephyr "systemctl cat kube-controller-manager | grep garbage"
```

---

## Summary

| Aspect | Status |
|--------|--------|
| **Issue** | Flannel IP exhaustion on Sentry |
| **Root Cause** | 7,020 zombie pods holding IPs |
| **Cleanup Progress** | 5,000+ deleted, 2,023 remaining |
| **Script** | ✅ Created `/etc/nixos/scripts/cleanup-zombie-pods.sh` |
| **Sentry Node** | ⚠️ Still blocked (254/254 IPs used) |
| **Other Nodes** | ✅ Operating normally |
| **2-Hour Loops** | ✅ Both active (session-only) |

---

**Created:** 2026-03-21 12:15 UTC
**Status:** ⚠️ Cleanup in progress
**Next Action:** Run `/etc/nixos/scripts/cleanup-zombie-pods.sh force`
