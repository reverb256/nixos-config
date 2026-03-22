# Kubernetes Disaster Recovery Runbook

**Purpose**: Complete disaster recovery procedures for the NixOS Kubernetes cluster
**Created**: 2026-03-22
**Version**: 1.0

---

## Table of Contents

1. [Quick Response Guide](#quick-response-guide)
2. [Disaster Scenarios](#disaster-scenarios)
3. [Recovery Procedures](#recovery-procedures)
4. [Verification Steps](#verification-steps)
5. [Escalation Contacts](#escalation-contacts)

---

## Quick Response Guide

### 🚨 IMMEDIATE ACTIONS (First 5 Minutes)

1. **Assess the Situation**
   ```bash
   # Check cluster status
   kubectl get nodes
   kubectl get pods --all-namespaces | grep -E "Error|CrashLoopBackOff"

   # Check critical services
   kubectl get pods -n akash-services | grep provider
   kubectl get svc -n ingress-nginx
   ```

2. **Identify the Scope**
   - Single node failure?
   - Multiple nodes affected?
   - Entire cluster down?
   - Specific service failure?

3. **Notify Stakeholders**
   - If critical: Send alert immediately
   - If provider: Check wallet status first
   - Document everything you're doing

4. **Start Recovery** (follow procedures below)

---

## Disaster Scenarios

### Scenario 1: Single Node Failure

**Severity**: 🟡 Medium
**Impact**: Reduced cluster capacity
**RTO**: 1 hour
**RPO**: 0 (no data loss)

#### Symptoms
- One node showing `NotReady`
- Pods evicted from failed node
- Reduced resource capacity

#### Recovery Steps

```bash
# 1. Identify failed node
kubectl get nodes
# Look for node with "NotReady" status

# 2. Check node status
kubectl describe node <failed-node>
# Look at conditions section

# 3. SSH to the node
ssh <failed-node>

# 4. Check common issues
# Check if kubelet is running
systemctl status kubelet
systemctl restart kubelet  # if not running

# Check if container runtime is running
systemctl status containerd
systemctl restart containerd  # if not running

# Check disk space
df -h
# If disk full, clean up: docker system prune, rm -rf /var/log/*

# 5. Reboot if needed (as last resort)
reboot

# 6. Verify recovery
kubectl get nodes
# Should show all nodes Ready
```

#### Preventive Measures
- ✅ Monitor disk space on all nodes
- ✅ Monitor kubelet/containerd health
- ✅ Set up node-level monitoring alerts

---

### Scenario 2: Akash Provider Failure

**Severity**: 🔴 Critical
**Impact**: No GPU deployments possible
**RTO**: 15 minutes
**RPO**: 0 (mnemonic backup available)

#### Symptoms
- Provider pod not running
- Provider not responding on /status endpoint
- Wallet not accessible

#### Recovery Steps

```bash
# 1. Check provider pod status
kubectl get pods -n akash-services | grep provider
kubectl describe pod akash-provider-akash-provider-fixed-0 -n akash-services

# 2. Check PSA issues (most common)
kubectl get ns akash-services -L pod-security.kubernetes.io/enforce
# Should be "privileged"

# 3. If PSA is blocking:
kubectl label ns akash-services pod-security.kubernetes.io/enforce=privileged --overwrite

# 4. Delete pod to trigger recreation
kubectl delete pod akash-provider-akash-provider-fixed-0 -n akash-services

# 5. Wait for recovery
kubectl wait --for=condition=Ready pod/akash-provider-akash-provider-fixed-0 -n akash-services --timeout=300s

# 6. Verify wallet address
curl -sk https://10.0.0.63:8443/status | jq '.address'
# Should output: akash1c6h804ky08tdpnxrv72vum783xuey09qgzt2p6

# 7. Verify inventory
curl -sk https://10.0.0.63:8443/status | jq '.cluster.inventory.available.nodes | length'
# Should output: 4
```

#### Complete PVC Loss Recovery

```bash
# If PVC is completely lost:

# 1. Delete PVC
kubectl delete pvc home-akash-provider-akash-provider-fixed-0 -n akash-services

# 2. Recreate PVC
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: home-akash-provider-akash-provider-fixed-0
  namespace: akash-services
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: akash-provider-akash-provider-fixed-local-storage
  resources:
    requests:
      storage: 10Gi
EOF

# 3. Provider will auto-recover from mnemonic Secret
# Delete pod to trigger re-initialization
kubectl delete pod akash-provider-akash-provider-fixed-0 -n akash-services

# 4. Wait and verify (as above)
kubectl wait --for=condition=Ready pod/akash-provider-akash-provider-fixed-0 -n akash-services
curl -sk https://10.0.0.63:8443/status | jq '.address'
```

---

### Scenario 3: Control Plane Failure

**Severity**: 🔴 Critical
**Impact**: No cluster management possible
**RTO**: 2 hours
**RPO**: Depends on etcd backup

#### Symptoms
- Cannot run kubectl commands
- API server not responding
- All nodes showing NotReady

#### Recovery Steps

```bash
# 1. Check control plane node (zephyr)
ssh zephyr

# 2. Check API server status
systemctl status k3s or kubelet

# 3. Check etcd status
systemctl status etcd
# Or for k3s:
systemctl status k3s

# 4. Check logs
journalctl -u k3s -n 50
journalctl -u kubelet -n 50

# 5. Restart services if needed
systemctl restart k3s  # for k3s
# Or for vanilla k8s:
systemctl restart kubelet
systemctl restart containerd

# 6. Verify cluster recovery
kubectl get nodes
kubectl get pods -n kube-system

# 7. If etcd is corrupted:
# Restore from backup (see Scenario 6)
```

---

### Scenario 4: Network Partition

**Severity**: 🟠 High
**Impact**: Nodes cannot communicate
**RTO**: 1 hour
**RPO**: 0

#### Symptoms
- Nodes showing NotReady
- Cannot SSH between nodes
- Pods in Unknown state

#### Recovery Steps

```bash
# 1. Check network connectivity
ping zephyr
ping nexus
ping forge
ping sentry

# 2. Check network interfaces
ip addr show
# Look for flannel.1 or cni0 interfaces

# 3. Check CNI plugin
kubectl get pods -n kube-flannel
kubectl get pods -n kube-system | grep cni

# 4. Restart CNI if needed
kubectl delete pods -n kube-flannel --all
kubectl delete pods -n kube-system -l k8s-app=kube-router

# 5. Verify recovery
kubectl get nodes
kubectl get pods --all-namespaces
```

---

### Scenario 5: etcd Data Corruption

**Severity**: 🔴 Critical
**Impact**: Cluster state lost
**RTO**: 4 hours
**RPO**: 24 hours (backup frequency)

#### Prevention (Do Now!)

```bash
# Set up etcd snapshots (for k3s)
# Add to k3s config:
etcd-snapshot-schedule-cron: "0 */6 * * *"  # Every 6 hours
etcd-snapshot-retention: 10  # Keep 10 snapshots
```

#### Recovery Steps

```bash
# 1. Stop all control plane components
ssh zephyr
systemctl stop k3s

# 2. List available snapshots
ls -lh /var/lib/rancher/k3s/server/db/snapshots/

# 3. Restore from snapshot
k3s server \
  --cluster-reset \
  --etcd-snapshot=/var/lib/rancher/k3s/server/db/snapshots/<snapshot-file>

# 4. Verify cluster recovery
kubectl get nodes
kubectl get all --all-namespaces

# 5. Restart worker nodes if needed
# Nodes should reconnect automatically
```

---

### Scenario 6: Complete Cluster Loss

**Severity**: 🔴 CRITICAL
**Impact**: Complete rebuild required
**RTO**: 1 day
**RPO**: 24 hours

#### Recovery Steps

```bash
# 1. Rebuild control plane (zephyr)
# This is in NixOS config - just rebuild:
cd /etc/nixos
just switch
# Or:
nixos-rebuild switch

# 2. Rebuild worker nodes
# SSH to each node and run:
cd /etc/nixos
just switch

# 3. Reinstall cluster components if needed
kubectl apply -f kubernetes-manifests/monitoring/
kubectl apply -f kubernetes-manifests/akash-services/

# 4. Restore Akash provider from mnemonic
# See Scenario 2 recovery steps

# 5. Verify all services
kubectl get pods --all-namespaces
kubectl get svc --all-namespaces
```

---

## Verification Steps

### Post-Recovery Checklist

```bash
# 1. Nodes are healthy
kubectl get nodes
# Expected: All 4 nodes Ready

# 2. Control plane is working
kubectl get pods -n kube-system
# Expected: All core pods running

# 3. Akash provider is operational
kubectl get pods -n akash-services | grep provider
curl -sk https://10.0.0.63:8443/status | jq '.address'
# Expected: Running, akash1c6h804ky08tdpnxrv72vum783xuey09qgzt2p6

# 4. Monitoring is working
kubectl get pods -n monitoring
# Expected: Prometheus, Grafana, etc. running

# 5. Storage is accessible
kubectl get pv
kubectl get pvc --all-namespaces

# 6. Network policies are in place
kubectl get networkpolicies --all-namespaces --no-headers | wc -l
# Expected: 38 (or more)

# 7. No security vulnerabilities
kubectl auth can-i list pods --all-namespaces --as=system:anonymous
# Expected: no (Forbidden)
```

---

## Escalation Contacts

### Primary Contacts
- **Cluster Operations**: [Your Name]
- **On-Call Engineer**: [Contact Info]
- **Infrastructure Team**: [Contact Info]

### Emergency Contacts
- **Data Center**: [Contact Info]
- **Network Team**: [Contact Info]
- **Security Team**: [Contact Info]

### External Support
- **NixOS Community**: #nixos on Libera IRC
- **Kubernetes Documentation**: https://kubernetes.io/docs
- **Akash Network Discord**: https://discord.gg/akashnetwork

---

## Runbook Maintenance

### Weekly
- [ ] Review backup logs
- [ ] Test backup restoration (dry run)
- [ ] Update runbook with any issues found

### Monthly
- [ ] Full disaster recovery test (staging)
- [ ] Update contact information
- [ ] Review and update RTO/RPO targets

### Quarterly
- [ ] Major incident review
- [ ] Update runbook based on lessons learned
- [ ] Team training on disaster recovery

---

## Important Notes

### Wallet Recovery Priority
1. **Mnemonic is the source of truth** - keep it secure
2. **PVC backups are convenience** - not required for recovery
3. **Provider auto-recovers** from mnemonic on startup
4. **Test wallet recovery** whenever provider is restarted

### Common Mistakes to Avoid
1. ❌ Don't delete the mnemonic Secret before confirming PVC backup works
2. ❌ Don't rebuild cluster without checking etcd backups
3. ❌ Don't force delete pods without saving logs first
4. ❌ Don't skip verification steps after recovery

### Time-Saving Tips
1. Keep kubectl aliases ready
2. Have SSH keys pre-configured for all nodes
3. Use `kubectl get events` to see recent cluster events
4. Check pod logs before deleting them: `kubectl logs <pod> --previous`

---

**Owner**: Cluster Operations Team
**Last Updated**: 2026-03-22
**Next Review**: 2026-04-22
