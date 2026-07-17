# Kubernetes Safety Rules - PREVENT POD EXPLOSIONS

These rules are enforced by hookify. Violations will BLOCK dangerous operations.

## Forbidden Patterns

### 1. BULK KUBERNETES OPERATIONS
**BLOCKED**: Commands that can cascade out of control
```bash
# FORBIDDEN:
kubectl delete pods --all
kubectl delete pods --all-namespaces
kubectl scale deploy --all --all-namespaces
kubectl delete pods -A

# REQUIRED: Be specific
kubectl delete pods -n <namespace> -l <label>
kubectl scale deploy -n <namespace> <name> --replicas=1
```

### 2. NODE SELECTOR WITHOUT CAPACITY CHECK
**BLOCKED**: Applying nodeSelector without verifying target node has resources
```bash
# FORBIDDEN:
kubectl patch deploy <name> -p '{"spec":{"template":{"spec":{"nodeSelector":{"kubernetes.io/hostname":"nexus"}}}}}'
kubectl apply -f deployment-with-node-selector.yaml

# REQUIRED: Check capacity FIRST
kubectl top nodes
kubectl describe node nexus | grep -A 5 "Allocated resources"
kubectl get pods -n <namespace> --no-headers | wc -l
# THEN apply nodeSelector
```

### 3. SCALING DEPLOYMENTS WITHOUT REPLICA SET CHECK
**BLOCKED**: Scaling when replica sets are accumulating
```bash
# FORBIDDEN:
kubectl scale deploy <name> --replicas=5

# REQUIRED: Check replica set count first
REPLICASETS=$(kubectl get replicasets -A --no-headers | wc -l)
if [ $REPLICASETS -gt 20 ]; then
  echo "ERROR: Too many replica sets ($REPLICASETS). Clean up first."
  kubectl get replicasets -A -o json | jq -r '.items[] | select(.status.replicas==0) | "\(.metadata.namespace)/\(.metadata.name)"' | xargs -I {} kubectl delete replicetset {}
fi
kubectl scale deploy <name> --replicas=5
```

### 4. DELETING DEPLOYMENTS WITHOUT SCALING TO 0
**BLOCKED**: Deleting deployments directly (leaves orphaned replica sets)
```bash
# FORBIDDEN:
kubectl delete deployment <name>

# REQUIRED: Scale to 0 first
kubectl scale deploy <name> --replicas=0
kubectl delete deploy <name>
```

### 5. SCHEDULING WORKLOADS ON ZEPHYR
**BLOCKED**: Creating pods/deployments on Zephyr without explicit override
```bash
# FORBIDDEN:
kubectl apply -f workload.yaml  # Will schedule on Zephyr by default
kubectl run test --image=nginx

# REQUIRED: Explicitly schedule on Nexus
kubectl apply -f workload-with-node-selector.yaml  # Must have nodeSelector
kubectl run test --image=nginx --overrides='{"spec":{"nodeSelector":{"kubernetes.io/hostname":"nexus"}}}'
```

## Required Patterns

### Before ANY Kubernetes Change
```bash
# 1. Check pod count
kubectl get pods -A --no-headers | wc -l
# IF > 100, STOP and investigate

# 2. Check replica set count
kubectl get replicasets -A --no-headers | wc -l
# IF > 20, STOP and clean up

# 3. Check pending pods
kubectl get pods -A --field-selector=status.phase=Pending --no-headers | wc -l
# IF > 5, STOP and investigate scheduling failure

# 4. Check failed pods
kubectl get pods -A --field-selector=status.phase=Failed --no-headers | wc -l
# IF > 10, STOP and investigate
```

### Deployment Manifest Requirements
All deployment manifests MUST have:
```yaml
spec:
  replicas: 1  # NEVER use high replica counts without explicit reason
  revisionHistoryLimit: 2  # NOT default 10
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 0  # NOT default 1
      maxUnavailable: 1
  template:
    spec:
      nodeSelector:
        kubernetes.io/hostname: nexus  # REQUIRED for all non-infrastructure
```

### Emergency Cleanup Commands
If pod explosion detected (>100 pods in namespace):
```bash
# 1. Scale everything to 0
kubectl scale deploy --all -n <namespace> --replicas=0

# 2. Delete all pods
kubectl delete pods -n <namespace> --all --force --grace-period=0

# 3. Delete all replica sets
kubectl delete replicasets -n <namespace> --all --force --grace-period=0

# 4. Delete namespace if needed
kubectl delete namespace <namespace> --force --grace-period=0
```

## Monitoring Thresholds

Set up alerts for:
- **Total pods**: Alert if > 100
- **Replica sets**: Alert if > 20
- **Pending pods**: Alert if > 5
- **Failed pods**: Alert if > 10
- **Pods on Zephyr**: Alert if > 10 (excluding infrastructure)
- **Namespace pod count**: Alert if any namespace > 50

## Verification

After any deployment change:
```bash
# Wait for rollout to complete
kubectl rollout status deploy/<name>

# Verify replica count
kubectl get replicasets -n <namespace> | wc -l

# Verify no pods pending
kubectl get pods -n <namespace> --field-selector=status.phase=Pending

# Verify pods are on correct node
kubectl get pods -n <namespace> -o wide
```

## Documentation

See complete prevention guide:
- `/etc/nixos/kubernetes-manifests/PREVENT_POD_EXPLOSION.md`
- `/etc/nixos/docs/kubernetes/comprehensive-audit-2026-03-24.md`

## Incident History

- **2026-03-24**: Mining namespace pod explosion (800+ pods)
  - Root cause: nodeSelector conflicts + rollingUpdate maxSurge + no replica set cleanup
  - Resolution: Deleted namespace, applied prevention rules
  - Impact: OOM kills on Zephyr, cluster instability
