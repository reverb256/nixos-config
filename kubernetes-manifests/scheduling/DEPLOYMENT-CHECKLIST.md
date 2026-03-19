# ✅ PRE-DEPLOYMENT CHECKLIST
## Complete Verification Before Going Live

---

## 📋 Pre-Flight Checks (15 minutes)

### 1. Cluster Health ✅
```bash
# Check all nodes are Ready
kubectl get nodes

# Check control plane is healthy
kubectl get cs  # if using kubeadm
kubectl cluster-info

# Check for any failing pods in system namespaces
kubectl get pods -n kube-system | grep -v Running
```

**Expected Output**: All nodes Ready, all control plane components Healthy

---

### 2. Prerequisites ✅
```bash
# Check kubectl version
kubectl version --short

# Check helm is installed
helm version --short

# Check cluster access
kubectl cluster-info

# Check existing schedulers
kubectl get pods -n yunikorn 2>/dev/null || echo "YuniKorn not installed"
kubectl get pods -n volcano-system 2>/dev/null || echo "Volcano not installed"
```

**Expected Output**: kubectl ≥ 1.25, helm ≥ 3.0, cluster accessible

---

### 3. Backup Current State ✅
```bash
# Backup existing deployments
kubectl get deployment -n mining -o yaml > /tmp/mining-backup.yaml
kubectl get deployment -n ai-inference -o yaml > /tmp/ai-backup.yaml

# Verify backup exists
ls -lh /tmp/*-backup.yaml
```

**Expected Output**: Backup files created with non-zero size

---

### 4. Network Policies ✅
```bash
# Check if CNI supports NetworkPolicy
kubectl get nodes -o wide

# Verify CNI is not "bridge" (doesn't support NetworkPolicy)
# Should be Calico, Cilium, Weave, etc.
```

**Expected Output**: CNI supports NetworkPolicy (not bridge)

---

## 🔒 Security Verification (10 minutes)

### 5. RBAC Setup ✅
```bash
# Verify ServiceAccounts exist
kubectl get sa -n mining gpu-miner-sa
kubectl get sa -n ai-inference ai-gateway-sa

# Verify RBAC permissions
kubectl describe role -n kube-system gpu-scheduler-state-updater
kubectl describe rolebinding -n kube-system gpu-scheduler-state-updater-client
```

**Expected Output**: ServiceAccounts and RBAC resources exist

---

### 6. Network Isolation ✅
```bash
# Check NetworkPolicies exist
kubectl get networkpolicy -n mining
kubectl get networkpolicy -n ai-inference

# Verify default-deny policy exists
kubectl get networkpolicy -n mining default-deny-all
kubectl get networkpolicy -n ai-inference default-deny-all
```

**Expected Output**: Default-deny + allow policies present

---

### 7. Pod Security Standards ✅
```bash
# Check PSS labels on namespaces
kubectl get namespace mining -o jsonpath='{.metadata.labels}'
kubectl get namespace ai-inference -o jsonpath='{.metadata.labels}'

# Verify PSS enforcement
kubectl get namespace mining -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}'
kubectl get namespace ai-inference -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}'
```

**Expected Output**: PSS enforce=baseline on all namespaces

---

## 🔧 Operational Readiness (10 minutes)

### 8. Resource Management ✅
```bash
# Check ResourceQuotas exist
kubectl get resourcequota -n mining
kubectl get resourcequota -n ai-inference

# Check LimitRanges exist
kubectl get limitrange -n mining
kubectl get limitrange -n ai-inference

# Verify PodDisruptionBudgets exist
kubectl get pdb -n ai-inference
```

**Expected Output**: Quotas, Limits, and PDBs present

---

### 9. Monitoring Setup ✅
```bash
# Check if Prometheus Operator is installed
kubectl get servicemonitor --all-namespaces 2>/dev/null | head -5

# If present, verify ServiceMonitors
kubectl get servicemonitor -n ai-inference
kubectl get servicemonitor -n mining
```

**Expected Output**: Prometheus Operator running (optional but recommended)

---

### 10. Storage Readiness ✅
```bash
# Check PV/PVC capacity
kubectl get pv
kubectl get pvc -A

# Verify storage class exists
kubectl get storageclass
```

**Expected Output**: Sufficient storage for workloads

---

## 🚀 Deployment Readiness (5 minutes)

### 11. Image Availability ✅
```bash
# Check if images exist (for local images)
docker images | grep lolminer
docker images | grep ai-inference

# For remote images, test pull
docker pull lolminer:1.98a-nixos
docker pull ghcr.io/j-kro/ai-inference-gateway:v3.1.0
```

**Expected Output**: All images are available

---

### 12. GPU Availability ✅
```bash
# Check GPU resources
kubectl get nodes -o custom-columns=NAME:.metadata.name,GPUS:.status.capacity.nvidia\.com/gpu

# Verify GPU device plugin is running
kubectl get pods -n kube-system | grep gpu
```

**Expected Output**: All nodes show GPU capacity

---

## ✅ Go/No-Go Decision

### GO if ALL of the following:
- ✅ All nodes Ready
- ✅ kubectl and helm working
- ✅ Backups created successfully
- ✅ ServiceAccounts and RBAC configured
- ✅ NetworkPolicies applied
- ✅ Pod Security Standards enforced
- ✅ ResourceQuotas and LimitRanges present
- ✅ Images available
- ✅ GPUs available

### NO-GO if ANY of the following:
- ❌ Nodes not Ready
- ❌ kubectl or helm not working
- ❌ Backups failed
- ❌ RBAC misconfigured
- ❌ NetworkPolicies missing
- ❌ Images not available
- ❌ No GPU resources

---

## 📝 Pre-Deployment Approval

| Checklist Item | Verified By | Date | Signature |
|----------------|-------------|------|-----------|
| Cluster Health | ___________ | ____ | ___________ |
| Prerequisites | ___________ | ____ | ___________ |
| Backup Complete | ___________ | ____ | ___________ |
| Security Policies | ___________ | ____ | ___________ |
| RBAC Configured | ___________ | ____ | ___________ |
| Network Isolation | ___________ | ____ | ___________ |
| Operational Resources | ___________ | ____ | ___________ |
| Images Available | ___________ | ____ | ___________ |
| GPUs Available | ___________ | ____ | ___________ |

---

## 🎯 Final Approval

**I certify that all pre-deployment checks have been completed successfully:**

☐ Cluster is healthy and ready
☐ All security policies are in place
☐ Operational resources are configured
☐ Backups are complete
☐ Images are available
☐ GPUs are accessible

**Approved By**: ___________
**Date**: ___________
**Comments**: ___________

---

**Document Version**: 1.0
**Last Updated**: 2026-03-19
