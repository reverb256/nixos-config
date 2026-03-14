# Kubernetes HA Deployment Checklist

**Purpose:** Step-by-step deployment checklist for HA Kubernetes implementation

**Pre-deployment Status:** Implementation Complete, Not Deployed

---

## Pre-Deployment Checks

### Prerequisites

- [ ] Read `ha-implementation-guide.md` completely
- [ ] Ensure all 3 master nodes are accessible (Zephyr, Nexus, Sentry)
- [ ] Verify current cluster is healthy
- [ ] Create backup of current configurations
- [ ] Have rollback plan ready

### Backup Current State

```bash
# 1. Backup etcd data
ETCDCTL_API=3 etcdctl \
  --endpoints=https://10.1.1.110:2379 \
  --cacert=/var/lib/secrets/kubernetes-ca.crt \
  --cert=/var/lib/secrets/kubernetes-apiserver.crt \
  --key=/var/lib/secrets/kubernetes-apiserver.key \
  snapshot save /backup/etcd-snapshot-pre-ha.db

# 2. Export current resources
kubectl get all --all-namespaces -o yaml > /backup/cluster-state-pre-ha.yaml

# 3. Copy current NixOS configs
cp -r /etc/nixos /backup/nixos-pre-ha
```

---

## Phase 1: PKI Infrastructure

### 1.1 Generate Certificates

- [ ] Install cfssl: `nix-shell -p cfssl`
- [ ] Navigate to PKI directory: `cd /etc/nixos/modules/pki`
- [ ] Run generation script: `./gen-certs.sh`
- [ ] Verify output directory created: `ls -la output/`

### 1.2 Review Certificates

```bash
# Check API server certificate includes VIP
cfssl certinfo -cert output/certs/apiserver.pem | grep SAN
# Should include: 10.1.1.100, 10.1.1.110, 10.1.1.120, 10.1.1.140

# Verify CA certificate
cfssl certinfo -cert output/certs/ca.pem

# Check expiration dates
for cert in output/certs/*.pem; do
    echo "=== $cert ==="
    openssl x509 -in "$cert" -noout -dates
done
```

- [ ] API server cert includes VIP (10.1.1.100)
- [ ] All certificates valid (not expired)
- [ ] Certificate CNs match expected values

### 1.3 Encrypt Private Keys

For each private key in `output/private/`:

- [ ] `agenix -e /etc/nixos/secrets/kubernetes-ca.age`
- [ ] `agenix -e /etc/nixos/secrets/apiserver-key.age`
- [ ] `agenix -e /etc/nixos/secrets/etcd-peer-key.age`
- [ ] `agenix -e /etc/nixos/secrets/etcd-zephyr-key.age`
- [ ] `agenix -e /etc/nixos/secrets/etcd-nexus-key.age`
- [ ] `agenix -e /etc/nixos/secrets/etcd-sentry-key.age`
- [ ] `agenix -e /etc/nixos/secrets/controller-manager-key.age`
- [ ] `agenix -e /etc/nixos/secrets/scheduler-key.age`
- [ ] `agenix -e /etc/nixos/secrets/admin-key.age`

### 1.4 Create Additional Secrets

- [ ] Generate bootstrap tokens (optional)
- [ ] Create admin kubeconfig
- [ ] Encrypt any additional secrets

---

## Phase 2: Configuration Updates

### 2.1 Update Zephyr Configuration

Edit `/etc/nixos/hosts/zephyr/configuration.nix`:

```nix
imports = [
  # ... existing imports
  ../../modules/services/kubernetes-ha.nix
  ../../modules/services/etcd-cluster.nix
  ../../modules/services/haproxy-lb.nix
];

# Enable HA
services.kubernetes.ha.enable = true;

# Configure etcd
services.etcd-cluster = {
  enable = true;
  nodeName = "zephyr";
};

# Configure HAProxy (highest priority)
services.haproxy-kubernetes = {
  enable = true;
  priority = 110;  # Primary master
};
```

- [ ] Added HA module imports
- [ ] Enabled kubernetes-ha
- [ ] Enabled etcd-cluster with nodeName = "zephyr"
- [ ] Enabled haproxy-kubernetes with priority = 110

### 2.2 Update Nexus Configuration

Edit `/etc/nixos/hosts/nexus/configuration.nix`:

- [ ] Added HA module imports
- [ ] Enabled kubernetes-ha
- [ ] Enabled etcd-cluster with nodeName = "nexus"
- [ ] Enabled haproxy-kubernetes with priority = 100

### 2.3 Update Sentry Configuration

Edit `/etc/nixos/hosts/sentry/configuration.nix`:

- [ ] Added HA module imports
- [ ] Enabled kubernetes-ha
- [ ] Enabled etcd-cluster with nodeName = "sentry"
- [ ] Enabled haproxy-kubernetes with priority = 90

### 2.4 Remove Worker from Masters

For Forge (worker only):

- [ ] Verify Forge does NOT have HA modules enabled
- [ ] Forge should remain as worker-only node

---

## Phase 3: Deployment

### 3.1 Pre-Deployment Test

```bash
# Test configuration builds
just test
```

- [ ] Configuration builds successfully
- [ ] No errors in nix eval

### 3.2 Deploy to Zephyr (Primary Master)

```bash
just deploy --on zephyr
```

- [ ] Deployment completes without errors
- [ ] etcd is running: `systemctl status etcd`
- [ ] API server is running: `systemctl status kube-apiserver`
- [ ] Controller manager is running: `systemctl status kube-controller-manager`
- [ ] Scheduler is running: `systemctl status kube-scheduler`
- [ ] HAProxy is running: `systemctl status haproxy`
- [ ] Keepalived is running: `systemctl status keepalived`

### 3.3 Verify Zephyr Health

```bash
# Check etcd health
ETCDCTL_API=3 etcdctl \
  --endpoints=https://10.1.1.110:2379 \
  --cacert=/etc/kubernetes/pki/ca.pem \
  --cert=/etc/kubernetes/pki/apiserver.pem \
  --key=/etc/kubernetes/pki/apiserver-key.pem \
  endpoint health

# Check API server
kubectl get nodes

# Check VIP assignment
ssh zephyr 'ip addr show | grep 10.1.1.100'

# Check HAProxy backends
echo "show backend" | ssh zephyr 'socat /run/haproxy/admin.sock stdio'
```

- [ ] etcd endpoint healthy
- [ ] API server responding
- [ ] VIP assigned to Zephyr
- [ ] HAProxy shows healthy backends

### 3.4 Deploy to Nexus

```bash
just deploy --on nexus
```

- [ ] Deployment completes without errors
- [ ] etcd joins cluster (check membership)
- [ ] VIP can failover to Nexus (if Zephyr stopped)

### 3.5 Verify Cluster Health

```bash
# Check both masters
kubectl get nodes

# Check etcd cluster size
ETCDCTL_API=3 etcdctl \
  --endpoints=https://10.1.1.110:2379 \
  --cacert=/etc/kubernetes/pki/ca.pem \
  --cert=/etc/kubernetes/pki/apiserver.pem \
  --key=/etc/kubernetes/pki/apiserver-key.pem \
  member list
```

- [ ] 2 masters visible in `kubectl get nodes`
- [ ] etcd shows 2 members
- [ ] Pods are scheduling correctly

### 3.6 Deploy to Sentry

```bash
just deploy --on sentry
```

- [ ] Deployment completes without errors
- [ ] etcd joins cluster
- [ ] All 3 masters operational

### 3.7 Final Verification

```bash
cd /etc/nixos/modules/services
./ha-test.sh all
```

- [ ] All certificate tests pass
- [ ] All etcd tests pass
- [ ] All API server tests pass
- [ ] VIP tests pass
- [ ] Controller manager tests pass
- [ ] Scheduler tests pass

---

## Phase 4: Post-Deployment

### 4.1 Verify HA Functionality

```bash
# Test 1: Check leader election
kubectl -n kube-system get endpoints kube-controller-manager
kubectl -n kube-system get endpoints kube-scheduler

# Test 2: Stop API server on Zephyr
ssh zephyr 'systemctl stop kube-apiserver'
# Verify: kubectl still works via VIP
ssh zephyr 'systemctl start kube-apiserver'

# Test 3: Stop HAProxy on Zephyr
ssh zephyr 'systemctl stop haproxy'
# Verify: VIP moves to Nexus
ssh zephyr 'systemctl start haproxy'

# Test 4: Stop etcd on Zephyr
ssh zephyr 'systemctl stop etcd'
# Verify: Cluster still operational (quorum: 2/3)
ssh zephyr 'systemctl start etcd'
```

- [ ] Leader election working
- [ ] API server failover working
- [ ] VIP failover working
- [ ] etcd quorum maintained

### 4.2 Update Documentation

- [ ] Update STATUS.md with HA enabled
- [ ] Update ROADMAP.md with Phase 2 complete
- [ ] Document any issues encountered

### 4.3 Configure Monitoring

- [ ] Add HAProxy metrics to Prometheus
- [ ] Add etcd metrics to Prometheus
- [ ] Create Grafana dashboards

### 4.4 Configure Backups

```bash
# Create automated etcd backup service
# (See backup-to-garage.nix for reference)
```

- [ ] Automated etcd backups configured
- [ ] Backup restore tested

---

## Rollback Procedure

If critical issues occur:

```bash
# 1. Disable HA modules on all masters
# Edit each configuration.nix and comment out:
services.kubernetes.ha.enable = false;
services.etcd-cluster.enable = false;
services.haproxy-kubernetes.enable = false;

# 2. Restore easyCerts
services.kubernetes.easyCerts = true;
services.kubernetes.apiserver.address = "10.1.1.110";

# 3. Deploy rollback
just deploy

# 4. Verify single-master operation
kubectl get nodes
```

- [ ] Rollback tested and documented
- [ ] Rollback procedure works

---

## Completion Criteria

- [ ] All 3 masters operational
- [ ] etcd 3-node cluster healthy
- [ ] VIP (10.1.1.100) accessible
- [ ] All ha-test.sh tests pass
- [ ] Failover tested and working
- [ ] Backups configured
- [ ] Monitoring configured
- [ ] Documentation updated

---

**Signature:** _________________ | **Date:** _____________

**Reviewer:** _________________ | **Date:** _____________
