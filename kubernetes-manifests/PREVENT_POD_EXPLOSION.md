# Pod Explosion Prevention Rules

**CRITICAL:** Follow these rules to prevent replica set cascades and pod explosions.

## Root Cause
When deployments can't schedule pods (nodeSelector conflicts, OOM, resource constraints), Kubernetes creates NEW replica sets trying to satisfy the request. Old replica sets are NOT auto-cleaned up, causing exponential growth.

## Prevention Rules

### 1. ALWAYS Check Replica Sets First
```bash
# BEFORE making ANY deployment change:
kubectl get replicasets -A --no-headers | wc -l
# If > 20, STOP and clean up first
kubectl get replicasets -A -o json | jq -r '.items[] | select(.status.replicas==0 and .status.readyReplicas==0) | "\(.metadata.namespace)/\(.metadata.name)"' | xargs -I {} kubectl delete replicetset {}
```

### 2. Set revisionHistoryLimit Low
```yaml
spec:
  revisionHistoryLimit: 2  # NOT 10 (default)
```
Apply to ALL deployments:
```bash
kubectl get deploy -A -o jsonpath='{range .items[?(@.spec.revisionHistoryLimit>3)]}{.metadata.namespace}{"\t"}{.metadata.name}{"\n"}{end}' | while read ns deploy; do
  kubectl patch deploy -n "$ns" "$deploy" -p '{"spec":{"revisionHistoryLimit":2}}' --type=merge
done
```

### 3. Disable maxSurge in Rolling Updates
```yaml
spec:
  strategy:
    rollingUpdate:
      maxSurge: 0  # NOT 1 (default)
      maxUnavailable: 1
```

### 4. Scale to 0 BEFORE Deleting
```bash
# NEVER delete deployments directly
kubectl scale deploy <name> --replicas=0
kubectl delete deploy <name>
```

### 5. Clean Up Old Replica Sets Before Changes
```bash
# Delete all zero-replica replica sets
kubectl get replicasets -A -o json | jq -r '.items[] | select(.status.replicas==0) | "\(.metadata.namespace)/\(.metadata.name)"' | xargs -I {} kubectl delete replicetset {} --force --grace-period=0
```

### 6. Use nodeSelector Carefully
```bash
# BEFORE applying nodeSelector:
# 1. Check if target node has capacity
kubectl top nodes
kubectl describe node <node> | grep -A 5 "Allocated resources"

# 2. Apply to ONE deployment first
kubectl patch deploy <name> -p '{"spec":{"template":{"spec":{"nodeSelector":{"kubernetes.io/hostname":"nexus"}}}}}'

# 3. Wait and verify pods schedule
kubectl get pods -w

# 4. ONLY then apply to others
```

### 7. Never Use --all Flags Blindly
```bash
# WRONG - can cascade out of control
kubectl delete pods --all --all-namespaces
kubectl scale deploy --all --all-namespaces --replicas=1

# CORRECT - be specific
kubectl delete pods -n <namespace> -l <label>
kubectl scale deploy -n <namespace> <name> --replicas=1
```

## Emergency Response

If you see pod counts exploding (>100 pods in namespace):

```bash
# 1. IMMEDIATELY scale to 0
kubectl scale deploy --all -n <namespace> --replicas=0

# 2. Delete all pods in namespace
kubectl delete pods -n <namespace> --all --force --grace-period=0

# 3. Delete all replica sets
kubectl delete replicasets -n <namespace> --all --force --grace-period=0

# 4. Delete namespace if needed
kubectl delete namespace <namespace> --force --grace-period=0
```

## Monitoring

Add these checks to your workflow:

```bash
# Check replica set count (alert if >20)
kubectl get replicasets -A --no-headers | wc -l

# Check for deployments with high replica counts
kubectl get deploy -A -o jsonpath='{range .items[?(@.spec.replicas>3)]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.spec.replicas}{"\n"}{end}'

# Check pending pods (alert if >5)
kubectl get pods -A --field-selector=status.phase=Pending --no-headers | wc -l
```

## NixOS Integration

Add to `/etc/nixos/modules/services/kubernetes.nix`:

```nix
# Prevent pod explosions
{
  # Limit replica set history
  apps.kubes.io.io.default-revision-history-limit = "2";

  # Disable surge in rolling updates
  # Must be applied per-deployment in manifests
}
```

## Recovery

If cluster is already exploding:

1. **STOP making changes** - every kubectl command creates more replica sets
2. **Delete the namespace** containing the explosion
3. **Restart affected deployments** with clean state
4. **Apply prevention rules** before redeploying

## Summary

- Replica sets accumulate when pods can't schedule
- RollingUpdate with maxSurge=1 creates extra pods
- revisionHistoryLimit=10 keeps old replica sets around
- Always clean up replica sets before changes
- Scale to 0, never delete directly
