# HA Upgrade Rollback Procedures

**Version**: 1.0
**Created**: 2026-03-21
**Purpose**: Emergency rollback procedures for Kubernetes HA upgrade phases

---

## Emergency Rollback (Critical Service Degradation)

**Trigger**: Any phase causes critical service degradation (>5% impact)

### Step 1: Identify Last Good State

```bash
# View recent commits
cd /etc/nixos
git log --oneline -5

# Example output:
# 80432c2 feat(browser): improve banking compatibility
# abc1234 feat(ha): add PriorityClasses
# def5678 feat(ha): scale CoreDNS to 3 replicas
```

### Step 2: Rollback Most Recent Changes

```bash
# Option A: Revert last commit (if changes were committed)
git revert HEAD --no-edit

# Option B: Reset to previous commit (if changes not committed)
git reset --hard HEAD~1

# Option C: Checkout known-good commit
git checkout <known-good-commit-sha>
```

### Step 3: Apply Previous Configuration

```bash
# Deploy to all hosts via Colmena
just deploy

# Or deploy to specific host
just deploy zephyr
just deploy nexus
just deploy forge
just deploy sentry
```

### Step 4: Verify Service Recovery

```bash
# Check for problematic pods
kubectl get pods -A | grep -E "Pending|Error|CrashLoopBackOff"

# Verify all pods running
kubectl get pods -A

# Check deployment status
kubectl get deploy -A

# Verify StatefulSets
kubectl get sts -A
```

### Step 5: Verify Cluster Health

```bash
# Check node status
kubectl get nodes -o wide

# Check cluster components (if using kubeadm)
kubectl get cs

# Check API server connectivity
kubectl cluster-info

# View cluster events
kubectl get events -A --sort-by='.lastTimestamp'
```

### Step 6: Verify Resource Availability

```bash
# Check node resource usage
kubectl top nodes

# Check pod resource usage
kubectl top pods -A

# Verify no resource pressure
kubectl describe nodes | grep -A 5 "Pressure"
```

---

## Selective Rollback (Specific Component Failure)

**Use when**: Only one component failed, not entire cluster

### Rollback PDB Changes Only

```bash
# Delete all PDBs
kubectl delete pdb -A --all

# Reapply baseline PDBs
kubectl apply -f kubernetes-manifests/pod-disruption-budgets/v1/

# Verify PDBs restored
kubectl get pdb -A
```

### Rollback Replica Changes Only

```bash
# Scale specific deployment back to original
kubectl scale deployment -n <namespace> <deployment> --replicas=<original>

# Example: Rollback CoreDNS to 1 replica
kubectl scale deployment -n kube-system coredns --replicas=1

# Verify replica count
kubectl get deployment -n kube-system coredns
```

### Rollback PriorityClass Changes Only

```bash
# Delete PriorityClasses
kubectl delete priorityclass critical-production
kubectl delete priorityclass user-interactive
kubectl delete priorityclass production-services
kubectl delete priorityclass background-mining

# Verify removal
kubectl get priorityclasses
```

### Rollback Resource Quota Changes Only

```bash
# Delete all resource quotas
kubectl delete resourcequota -A --all

# Verify removal
kubectl get resourcequota -A
```

### Rollback Anti-Affinity Changes Only

```bash
# Patch deployments to remove anti-affinity
kubectl patch deployment -n <namespace> <deployment> --type json \
  -p='[{"op": "remove", "path": "/spec/template/spec/affinity"}]'

# Example: Remove anti-affinity from CoreDNS
kubectl patch deployment -n kube-system coredns --type json \
  -p='[{"op": "remove", "path": "/spec/template/spec/affinity"}]'
```

---

## Rollback by Phase

### Phase 1 Rollback (Foundation)

```bash
# Re-enable swap (if needed)
for host in zephyr nexus forge sentry; do
  ssh $host "sudo swapon -a"
done

# Remove PriorityClasses
kubectl delete priorityclass critical-production
kubectl delete priorityclass user-interactive
kubectl delete priorityclass production-services
kubectl delete priorityclass background-mining

# Remove resource requests/limits from deployments
kubectl patch deployment -n <namespace> <deployment> --type json \
  -p='[{"op": "remove", "path": "/spec/template/spec/containers/0/resources"}]'
```

### Phase 2 Rollback (Critical Services HA)

```bash
# Scale critical services back to 1 replica
kubectl scale deployment -n kube-system coredns --replicas=1
kubectl scale deployment -n ingress-nginx ingress-nginx-controller --replicas=1
kubectl scale deployment -n yunikorn yunikorn-scheduler --replicas=1

# Remove PDBs
kubectl delete pdb -n kube-system coredns-pdb
kubectl delete pdb -n ingress-nginx ingress-nginx-pdb
kubectl delete pdb -n yunikorn yunikorn-pdb
```

### Phase 3 Rollback (High-Priority Services HA)

```bash
# Scale AI services back to 1 replica
kubectl scale deployment -n ai-inference n8n --replicas=1
kubectl scale deployment -n ai-inference prometheus --replicas=1
kubectl scale deployment -n ai-inference redis --replicas=1

# Scale Akash services back to 1 replica
kubectl scale deployment -n akash-services operator-hostname --replicas=1
kubectl scale deployment -n akash-services cloudflared --replicas=1

# Scale monitoring back to 1 replica
kubectl scale deployment -n monitoring prometheus --replicas=1
kubectl scale deployment -n monitoring grafana --replicas=1
```

### Phase 4 Rollback (Preemptible Mining)

```bash
# Remove PriorityClasses from mining pods
kubectl set deployment -n mining --all \
  --overrides='{\"spec\":{\"template\":{\"spec\":{\"priorityClassName\":null}}}}'

# Scale mining back to dedicated GPUs
kubectl apply -f kubernetes-manifests/mining/dedicated-gpu-miners/
```

### Phase 5 Rollback (Resource Quotas)

```bash
# Delete all namespace quotas
kubectl delete resourcequota -A --all

# Delete LimitRanges
kubectl delete limitrange -A --all

# Verify removal
kubectl get resourcequota -A
kubectl get limitrange -A
```

### Phase 6 Rollback (AMD GPU AI Workloads)

```bash
# Scale down AI workloads on AMD GPUs
kubectl scale deployment -n ai-inference llamafile-sentry --replicas=0
kubectl delete job -n ai-training distributed-training

# Remove AMD GPU AI deployments
kubectl delete -f kubernetes-manifests/ai-workloads/amd-gpu/
```

---

## Git-Based Rollback (Full Configuration)

### Step 1: Identify Last Good Commit

```bash
cd /etc/nixos
git log --oneline -10

# Look for commit before HA upgrade started
# Example: 80432c2 feat(browser): improve banking compatibility
```

### Step 2: Create Rollback Branch

```bash
# Create rollback branch from current state
git checkout -b rollback-$(date +%Y%m%d)

# Reset to known-good commit
git reset --hard <known-good-commit-sha>

# Example:
# git reset --hard 80432c2
```

### Step 3: Deploy Rollback

```bash
# Test rollback on one host first
just deploy zephyr

# Verify zephyr is healthy
ssh zephyr "kubectl get nodes"
ssh zephyr "kubectl get pods -A"

# If zephyr is healthy, deploy to rest
just deploy
```

### Step 4: Verify Rollback

```bash
# Check cluster health
kubectl get nodes
kubectl get pods -A

# Verify services are accessible
kubectl cluster-info

# Check resource usage
kubectl top nodes
kubectl top pods -A
```

---

## Rollback Verification Checklist

After any rollback, verify:

- [ ] All nodes in Ready state
- [ ] No pods in Pending/Error/CrashLoopBackOff
- [ ] All deployments at correct replica count
- [ ] All StatefulSets at correct replica count
- [ ] API server responding
- [ ] DNS resolving (CoreDNS)
- [ ] Ingress routing traffic
- [ ] No resource pressure on nodes
- [ ] GPU workloads (mining/AI) running correctly
- [ ] Monitoring dashboards accessible

---

## Emergency Contact

**Cluster Operations Team**: [Contact Information]
**On-Call Engineer**: [Contact Information]
**Escalation Path**: [Contact Information]

---

## Rollback Decision Matrix

| Scenario | Rollback Type | Time to Recover | Data Loss Risk |
|----------|---------------|-----------------|----------------|
| Critical service degradation (>5% impact) | Emergency (full git reset) | 10-15 min | Low |
| Single deployment failure | Selective (kubectl scale) | 2-5 min | None |
| PDB causing eviction issues | Selective (delete PDB) | 1-2 min | None |
| PriorityClass causing preemption storm | Selective (delete PriorityClass) | 1-2 min | None |
| Resource quota preventing scheduling | Selective (delete quota) | 1-2 min | None |
| Entire phase failed | Phase-specific rollback | 5-10 min | Low |

---

**Last Updated**: 2026-03-21
**Maintainer**: Cluster Operations Team
