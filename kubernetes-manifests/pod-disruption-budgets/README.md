# Pod Disruption Budgets (PDB) - High Availability Strategy

## Overview

Pod Disruption Budgets (PDBs) ensure critical services maintain minimum availability during:
- Voluntary disruptions (deployments, rolling updates)
- Node maintenance/drain operations
- Cluster upgrades
- CNI restarts (like the Flannel issue we experienced)

## PDB Strategy

### Priority Levels

**CRITICAL (minAvailable: 1)**
- DNS, Ingress, Monitoring
- AI inference services (n8n, databases)
- Akash provider services

**HIGH (minAvailable: 1)**
- AI coding tools
- StatefulSets (databases)

**MEDIUM (maxUnavailable: 1)**
- Mining workloads (interruptible, can tolerate brief downtime)

## Architecture

```
pod-disruption-budgets/
├── core-services-pdb.yaml       # DNS, Ingress, Device Plugins
├── ai-inference-pdb.yaml        # n8n, Redis, Postgres, Qdrant
├── ai-coding-pdb.yaml           # Claude Code, OpenCode
├── akash-services-pdb.yaml      # Akash Provider, Operators
├── mining-pdb.yaml              # GPU/CPU Mining (maxUnavailable)
├── glitchtip-pdb.yaml           # Error Tracking
├── kustomization.yaml           # Kustomize config
└── README.md                    # This file
```

## Usage

### Apply All PDBs
```bash
kubectl apply -k kubernetes-manifests/pod-disruption-budgets/
```

### Apply Individual PDBs
```bash
kubectl apply -f kubernetes-manifests/pod-disruption-budgets/core-services-pdb.yaml
```

### Check PDB Status
```bash
kubectl get pdb -A
kubectl describe pdb <name> -n <namespace>
```

### Test PDB Effectiveness
```bash
# Simulate node drain (will respect PDBs)
kubectl drain zephyr --ignore-daemonsets --dry-run=server

# Check which pods would be disrupted
kubectl get pods -A -o wide | grep zephyr
```

## PDB Status Monitoring

```bash
# View all PDBs
kubectl get pdb -A

# Detailed status
kubectl get pdb -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}{"\t"}{.status.disruptionsAllowed}{"\t"}{.status.currentHealthy}{"\t"}{.status.desiredHealthy}{"\n"}{end}'

# Check for violations
kubectl get events -A --field-selector reason=FailedScheduling
```

## Configuration Examples

### For Single-Pod Services (minAvailable: 1)
```yaml
spec:
  minAvailable: 1  # Never allow disruption
```

### For Multi-Pod Services (minAvailable: 1)
```yaml
spec:
  minAvailable: 1  # Keep at least 1 pod running
```

### For Interruptible Workloads (maxUnavailable: 1)
```yaml
spec:
  maxUnavailable: 1  # Allow 1 pod to be disrupted
```

### For High-Availability Services (minAvailable: 50%)
```yaml
spec:
  minAvailable: 50%  # Keep at least half the pods running
```

## Best Practices

1. **StatefulSets**: Always use PDBs with `minAvailable: 1`
2. **Single-pod deployments**: Use `minAvailable: 1` to prevent disruption
3. **Interruptible workloads**: Use `maxUnavailable` instead of `minAvailable`
4. **DaemonSets**: PDBs generally not needed (run on all nodes by design)
5. **Critical services**: Set `minAvailable: 1` even for single-pod services

## Troubleshooting

### PDB Blocking Deployment
```bash
# Check what's blocking
kubectl describe deployment <name> -n <namespace>

# Temporarily remove PDB (emergency only)
kubectl delete pdb <name> -n <namespace>
```

### Pods Not Respecting PDB
```bash
# Check PDB selectors match pod labels
kubectl get pdb <name> -n <namespace> -o yaml | grep -A 5 selector
kubectl get pods -n <namespace> -L app --show-labels
```

### During CNI Issues (Flannel restart)
- PDBs won't help with CNI failures (network-level issue)
- PDBs prevent voluntary disruptions during CNI recovery
- Monitor: `kubectl get pods -A | grep -E "Pending|FailedCreatePodSandBox"`

## Related Documentation

- [Kubernetes PDB Documentation](https://kubernetes.io/docs/concepts/workloads/pods/disruptions/)
- [Pod Priority & Preemption](https://kubernetes.io/docs/concepts/scheduling-eviction/pod-priority-preemption/)
- [Cluster Upgrade Best Practices](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade/)

## Incident Recovery

### 2026-03-21 IP Exhaustion Crisis
- **Issue**: Flannel restart caused "FailedCreatePodSandBox" errors
- **Root Cause**: No PDBs to protect against CNI restart window
- **Fix**: Deployed comprehensive PDBs across all namespaces
- **Prevention**: PDBs now ensure minimum availability during deployments

## Version

**Created**: 2026-03-21
**Last Updated**: 2026-03-21
**Maintainer**: Cluster Operations Team
