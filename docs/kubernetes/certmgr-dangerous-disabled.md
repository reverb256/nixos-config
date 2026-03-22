# certmgr Service - DANGEROUS FOR KUBERNETES CONTROL PLANE

**Status**: ❌ **DISABLED** - Service causes cluster outages
**Date Disabled**: 2026-03-22 07:58 UTC
**Reason**: Automatic service restarts caused complete Kubernetes cluster outage

---

## What certmgr Does

**Purpose**: Automatically manage TLS certificates and restart services

**Configuration**:
- Checks certificates every 30 minutes
- Renews certificates 72 hours before expiration
- Executes `systemctl restart` commands after certificate renewal
- Manages 13 Kubernetes certificates

**Certificates Managed**:
1. apiserverEtcdClient.json → `systemctl restart kube-apiserver.service`
2. apiServer.json → `systemctl restart kube-apiserver.service`
3. apiserverKubeletClient.json → `systemctl restart kube-apiserver.service`
4. apiserverProxyClient.json → `systemctl restart kube-apiserver.service`
5. clusterAdmin.json → (no restart action)
6. controllerManagerClient.json → `systemctl restart kube-controller-manager.service`
7. controllerManager.json → `systemctl restart kube-controller-manager.service`
8. etcd.json → `systemctl restart etcd.service`
9. kubeletClient.json → `systemctl restart kubelet.service`
10. kubelet.json → `systemctl restart kubelet.service`
11. kubeProxyClient.json → `systemctl restart kube-proxy.service`
12. schedulerClient.json → `systemctl restart kube-scheduler.service`
13. serviceAccount.json → (no restart action)

---

## Why certmgr is DANGEROUS for Kubernetes

### Problem 1: Simultaneous Service Restarts

When certmgr renews ONE certificate, it may restart MULTIPLE services:

**Example**: kube-apiserver-kubelet-client certificate is used by:
- kube-apiserver
- kube-controller-manager
- kube-scheduler

Result: certmgr restarts ALL THREE simultaneously → **cluster outage**

### Problem 2: No Health Checks

certmgr does NOT:
- ✅ Verify services are healthy before restart
- ✅ Verify services recovered after restart
- ✅ Check if restart was successful
- ✅ Coordinate multiple restarts

It blindly executes `systemctl restart` commands.

### Problem 3: Critical Infrastructure Impact

Kubernetes control plane components should NOT be automatically restarted:
- **kube-apiserver**: Core of Kubernetes - all operations fail when down
- **kube-controller-manager**: Manages controllers, replicasets, etc.
- **kube-scheduler**: Schedules pods to nodes

Restarting these simultaneously = **cluster downtime**

### Problem 4: No Warning or Approval

certmgr:
- ❌ Does NOT warn administrators before restarting
- ❌ Does NOT require approval
- ❌ Does NOT log upcoming maintenance
- ❌ Does NOT provide rollback option

It just restarts services automatically.

---

## Incident: 2026-03-22 Outage

**Timeline**:
- 07:55:55 UTC - certmgr renewed kube-apiserver-kubelet-client certificate
- 07:55:55 UTC - certmgr executed restart commands for:
  - kube-apiserver.service
  - kube-controller-manager.service
  - kube-scheduler.service
- 07:55:55 - 07:56:56 - kube-apiserver shutdown hung (took 60 seconds to stop)
- 07:55:55 - 07:58:20 - kube-controller-manager and kube-scheduler stayed down
- **Result**: Complete Kubernetes API outage for ~3 minutes

**Impact**:
- All cluster operations failed
- cloudflared tunnel interrupted
- Akash provider couldn't lease GPUs
- CI/CD pipelines failed
- Monitoring dashboards went dark

---

## Root Cause Analysis

### Why certmgr Renewed the Certificate

**Mystery**: The certificate was valid for 27 more days (until Apr 18), but certmgr renewed it.

**Possible Explanations**:
1. **Configuration mismatch**: Certificate spec didn't match actual certificate
2. **CA mismatch**: CA at https://10.1.1.100:8888 expected different certificate properties
3. **Bug in certmgr**: Software bug caused unnecessary renewal
4. **Manual trigger**: Something triggered certmgr to check/renew this specific certificate

**Investigation Needed**:
- Check CA logs (if available)
- Check certmgr debug logs
- Compare old vs new certificate properties
- Check for recent configuration changes

### Why the Restart Failed

**kube-apiserver shutdown sequence**:
1. certmgr executed: `systemctl restart kube-apiserver.service`
2. kube-apiserver began graceful shutdown (SIGTERM)
3. Shutdown **hung** for 60 seconds (waiting for connections to drain?)
4. Eventually forced to kill
5. New kube-apiserver process started

**Why kube-controller-manager and kube-scheduler didn't restart**:
- They were stopped at 07:55:55
- certmgr logs show: "exit status 1" - restart command failed
- They didn't come back until manually started at 07:58:20

---

## Permanent Fix

### Option 1: Keep certmgr Disabled (RECOMMENDED)

**Pros**:
- No automatic restarts of critical infrastructure
- Manual control over certificate renewals
- Can schedule maintenance windows

**Cons**:
- Manual certificate renewal required
- Need to track certificate expiration

**Procedure**:
1. ✅ Keep certmgr disabled: `systemctl disable certmgr --now`
2. Monitor certificate expiration (add monitoring alerts)
3. Manually renew certificates 72 hours before expiration
4. Schedule maintenance windows for control plane restarts

### Option 2: Modify certmgr Configuration

**Changes Required**:
1. Remove `"action"` from ALL Kubernetes certificate specs
2. Add monitoring for certificate expiration
3. Create manual renewal procedures
4. Document safe restart procedures

**Example Modified Spec**:
```json
{
  "action": null,  // REMOVE automatic restart
  "certificate": {
    "path": "/var/lib/kubernetes/secrets/kube-apiserver-kubelet-client.pem"
  },
  "alert": "kubernetes.certificate.expiringSoon"  // Add alert instead
}
```

**This still requires**:
- Rebuilding NixOS configuration
- Testing modified certmgr behavior
- Adding monitoring alerts
- Creating manual renewal runbooks

### Option 3: Use Different Certificate Management

**Alternatives**:
- **kubeadm**: Built-in certificate management with better controls
- **cert-manager**: Kubernetes-native certificate manager
- **Manual renewal**: Complete control, no automation

---

## Certificate Renewal Procedure (Manual)

### Step 1: Check Certificate Expiration

```bash
# Check all Kubernetes certificates
for cert in /var/lib/kubernetes/secrets/*.pem; do
  echo "=== $cert ==="
  openssl x509 -in "$cert" -noout -subject -issuer -dates
  echo ""
done
```

### Step 2: Renew Expiring Certificates

**72 hours before expiration**:
1. Schedule maintenance window (low-traffic time)
2. Notify all teams of planned downtime
3. Renew certificates:
   ```bash
   # Option A: Use certmgr in one-shot mode (if available)
   certmgr -f /path/to/certmgr.yaml --once

   # Option B: Manual certificate generation
   # (Use kubeadm or manual OpenSSL commands)
   ```

### Step 3: Restart Control Plane (STAGGERED)

**IMPORTANT**: Restart one component at a time, verify health before proceeding.

```bash
# 1. Restart kube-scheduler first
systemctl restart kube-scheduler.service
sleep 10
kubectl get cs  # Verify scheduler healthy

# 2. Restart kube-controller-manager
systemctl restart kube-controller-manager.service
sleep 10
kubectl get cs  # Verify controller-manager healthy

# 3. Restart kube-apiserver LAST (most critical)
systemctl restart kube-apiserver.service
sleep 15
kubectl get nodes  # Verify API server healthy
```

### Step 4: Verify Cluster Health

```bash
# Check all control plane components
kubectl get cs

# Check all nodes
kubectl get nodes

# Check system pods
kubectl get pods -n kube-system

# Verify cluster operations
kubectl create deploy test --image=nginx --replicas=1
kubectl delete deploy test
```

---

## Monitoring Requirements

### Alert Rules

Add these Prometheus alerts:

```yaml
# Certificate expiration alerts
- alert: KubernetesCertificateExpiring
  expr: |
    (certificate_expiration_timestamp / 1000) - time() < 72 * 3600
  for: 1h
  annotations:
    summary: "Kubernetes certificate expiring within 72 hours"
    description: "Certificate {{ $labels.cert_path }} expires on {{ $value | humanizeTimestamp }}"

# Control plane component down
- alert: KubernetesControlPlaneDown
  expr: |
    up{job="kube-apiserver"} == 0
    or
    up{job="kube-controller-manager"} == 0
    or
    up{job="kube-scheduler"} == 0
  for: 1m
  annotations:
    summary: "Kubernetes control plane component is down"
    description: "{{ $labels.job }} has been down for >1 minute"
```

---

## Lessons Learned

### What certmgr Does Well
- ✅ Automates certificate renewal
- ✅ Prevents certificate expiration
- ✅ Integrates with NixOS

### What certmgr Does Poorly
- ❌ Restarts critical infrastructure without coordination
- ❌ No health checks before/after restart
- ❌ No warning or approval mechanism
- ❌ Cannot stagger multiple restarts
- ❌ No rollback mechanism

### For Kubernetes: Use kubeadm Instead

**kubeadm** has:
- Built-in certificate management
- Safe certificate renewal procedures
- Proper control plane restart coordination
- Well-documented runbooks
- Community best practices

**Recommendation**: Migrate from custom NixOS Kubernetes setup to kubeadm.

---

## Action Items

### Immediate (Completed)
- [x] Disable certmgr service
- [x] Restart control plane components
- [x] Verify cluster recovery
- [x] Document incident

### Short Term (This Week)
- [ ] Add certificate expiration monitoring
- [ ] Add control plane health monitoring
- [ ] Create manual certificate renewal runbook
- [ ] Test manual renewal procedure
- [ ] Schedule certificate renewal before expiration

### Long Term (Next Month)
- [ ] Evaluate migrating to kubeadm
- [ ] Evaluate cert-manager for Kubernetes
- [ ] Implement 3-master control plane (planned for HA upgrade)
- [ ] Create change management process for control plane

---

## Related Documents

- **Incident Report**: `/etc/nixos/docs/kubernetes/k8s-control-plane-outage-2026-03-22.md`
- **HA Upgrade Plan**: `/etc/nixos/kubernetes-manifests/pod-disruption-budgets/IMPLEMENTATION-PLAN.md`
- **Rollback Procedures**: `/etc/nixos/kubernetes-manifests/ROLLBACK.md`

---

**Status**: certmgr is **PERMANENTLY DISABLED** until safer alternative implemented.
**Next Certificate Renewal**: ~April 11-14, 2026 (30 days from now)
**Maintainer**: Cluster Operations Team
