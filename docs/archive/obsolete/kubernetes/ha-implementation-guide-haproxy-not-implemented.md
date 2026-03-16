# Kubernetes HA Implementation Guide

**Status:** Implementation Complete, Not Deployed | **Created:** 2026-03-13 | **Owner:** j_kro

## Overview

This document describes the complete High Availability (HA) Kubernetes implementation for the homelab cluster. The implementation provides:

- **3-master control plane** with automatic failover
- **etcd 3-node cluster** with quorum-based operation
- **Virtual IP (VIP)** for unified API access
- **HAProxy load balancing** across API servers
- **External PKI** with cfssl for flexible certificate management

---

## Architecture

```
                    ┌─────────────────────────────────────┐
                    │         VIP: 10.1.1.100              │
                    │     (Keepalived failover)           │
                    └─────────────────┬───────────────────┘
                                      │
                    ┌─────────────────┴─────────────────┐
                    │           HAProxy Layer 4         │
                    │  (Zephyr, Nexus, Sentry each run) │
                    └─────────────────┬─────────────────┘
                                      │
         ┌────────────────────────────┼────────────────────────────┐
         │                            │                            │
    ┌────▼────┐                  ┌───▼────┐                  ┌───▼────┐
    │ Zephyr  │                  │ Nexus  │                  │ Sentry │
    │110:6443 │                  │120:6443│                  │140:6443 │
    └────┬────┘                  └───┬────┘                  └───┬────┘
         │                            │                            │
         └────────────┬───────────────┴────────────────────────────┘
                      │
         ┌────────────▼──────────────┐
         │    etcd Cluster (TLS)      │
         │  Zephyr  Nexus  Sentry    │
         │  2379    2379    2379     │
         └───────────────────────────┘
```

### Components

| Component | Purpose | Nodes |
|-----------|---------|-------|
| **etcd** | Distributed key-value store | Zephyr, Nexus, Sentry |
| **API Server** | Kubernetes API endpoint | Zephyr, Nexus, Sentry |
| **Controller Manager** | Controller loops | Zephyr, Nexus, Sentry (leader election) |
| **Scheduler** | Pod scheduling | Zephyr, Nexus, Sentry (leader election) |
| **HAProxy** | Load balancer for API | Zephyr, Nexus, Sentry |
| **Keepalived** | VIP failover | Zephyr (110), Nexus (100), Sentry (90) |

---

## Files Created

### PKI Infrastructure (`/etc/nixos/modules/pki/`)

| File | Purpose |
|------|---------|
| `ca-config.json` | CA configuration with profiles |
| `ca-csr.json` | CA certificate signing request |
| `apiserver-csr.json` | API server CSR with VIP in SANs |
| `etcd-peer-csr.json` | etcd peer certificate (shared) |
| `etcd-*-csr.json` | Per-node etcd server certificates |
| `admin-csr.json` | Admin client certificate |
| `controller-manager-csr.json` | Controller manager certificate |
| `scheduler-csr.json` | Scheduler certificate |
| `gen-certs.sh` | Certificate generation script |

### NixOS Modules (`/etc/nixos/modules/services/`)

| File | Purpose |
|------|---------|
| `kubernetes-ha.nix` | External PKI integration |
| `etcd-cluster.nix` | etcd 3-node cluster |
| `haproxy-lb.nix` | HAProxy + Keepalived |
| `ha-test.sh` | Comprehensive validation script |

---

## Deployment Procedure

### Phase 1: Generate Certificates

```bash
# 1. Install cfssl (one-time)
nix-shell -p cfssl

# 2. Generate all certificates
cd /etc/nixos/modules/pki
./gen-certs.sh

# 3. Review certificates
cfssl certinfo -cert output/certs/apiserver.pem | grep SAN
# Should include: 10.1.1.100, 10.1.1.110, 10.1.1.120, 10.1.1.140

# 4. Encrypt private keys with agenix
cd /etc/nixos
agenix -e secrets/kubernetes-ca.age
# Paste: output/private/ca-key.pem

agenix -e secrets/apiserver-key.age
# Paste: output/private/apiserver-key.pem

# Repeat for all private keys...
```

### Phase 2: Configure Master Nodes

Add to each master node configuration (`hosts/zephyr/configuration.nix`, etc.):

```nix
# Import HA modules
imports = [
  ../../modules/services/kubernetes-ha.nix
  ../../modules/services/etcd-cluster.nix
  ../../modules/services/haproxy-lb.nix
];

# Enable HA
services.kubernetes.ha.enable = true;

# Configure etcd cluster (per-node)
services.etcd-cluster = {
  enable = true;
  nodeName = "zephyr";  # or "nexus" or "sentry"
};

# Configure HAProxy (per-node priority)
services.haproxy-kubernetes = {
  enable = true;
  priority = 110;  # Zephyr: 110, Nexus: 100, Sentry: 90
};
```

### Phase 3: Deployment Order

**IMPORTANT:** Deploy in this exact order to avoid quorum loss.

1. **Zephyr (Priority 110 - primary master)**
   ```bash
   just test && just deploy --on zephyr
   ```

2. **Verify Zephyr is healthy**
   ```bash
   ssh zephyr 'kubectl get nodes'
   ssh zephyr 'systemctl status etcd kube-apiserver'
   ```

3. **Nexus (Priority 100)**
   ```bash
   just test && just deploy --on nexus
   ```

4. **Verify cluster health**
   ```bash
   ssh zephyr 'kubectl get nodes'
   ssh zephyr 'kubectl get cs'  # Component status
   ```

5. **Sentry (Priority 90)**
   ```bash
   just test && just deploy --on sentry
   ```

6. **Final verification**
   ```bash
   cd /etc/nixos/modules/services
   ./ha-test.sh all
   ```

---

## Validation

### Run All Tests

```bash
cd /etc/nixos/modules/services
./ha-test.sh all
```

### Run Specific Tests

```bash
./ha-test.sh certificates    # Validate certificates
./ha-test.sh etcd           # Test etcd cluster
./ha-test.sh apiserver      # Test API servers
./ha-test.sh vip            # Test VIP failover
./ha-test.sh controller     # Test controller manager
./ha-test.sh scheduler      # Test scheduler
```

### Expected Output

```
[PASS] Certificate valid: /etc/kubernetes/pki/ca.pem
[PASS] Certificate valid: /etc/kubernetes/pki/apiserver.pem
[PASS] API server certificate includes VIP: 10.1.1.100
[PASS] etcd endpoint healthy: https://10.1.1.110:2379
[PASS] etcd endpoint healthy: https://10.1.1.120:2379
[PASS] etcd endpoint healthy: https://10.1.1.140:2379
[PASS] etcd cluster has 3 members (quorum achieved)
[PASS] etcd has exactly 1 leader
[PASS] API server reachable via VIP: 10.1.1.100
[PASS] All 4 nodes are Ready
[PASS] Controller manager leader elected: zephyr
[PASS] Scheduler leader elected: zephyr
```

---

## Failover Testing

### Test VIP Failover

```bash
# 1. Identify current VIP holder
ip addr show | grep 10.1.1.100

# 2. Stop HAProxy on current master
systemctl stop haproxy

# 3. Verify VIP moves to next priority node
# Should move to: Zephyr → Nexus → Sentry

# 4. Restore HAProxy
systemctl start haproxy
```

### Test etcd Failover

```bash
# etcd can tolerate 1 node failure (2/3 quorum)

# Stop etcd on one node
systemctl stop etcd

# Verify cluster still operational
kubectl get nodes

# Etcd should show 2/3 members
ETCDCTL_API=3 etcdctl \
  --endpoints=https://10.1.1.110:2379 \
  --cacert=/etc/kubernetes/pki/ca.pem \
  --cert=/etc/kubernetes/pki/apiserver.pem \
  --key=/etc/kubernetes/pki/apiserver-key.pem \
  endpoint status
```

### Test API Server Failover

```bash
# Stop API server on one master
systemctl stop kube-apiserver

# Verify cluster still accessible via VIP
kubectl --server=https://10.1.1.100:6443 get nodes

# HAProxy health checks should detect failure
echo "show backend" | socat /run/haproxy/admin.sock stdio
```

---

## Rollback Procedure

If anything fails, rollback to single-master configuration:

```bash
# 1. Disable HA modules on all nodes
# Edit each configuration.nix and remove/comment:
#   services.kubernetes.ha.enable = false;
#   services.etcd-cluster.enable = false;
#   services.haproxy-kubernetes.enable = false;

# 2. Restore easyCerts configuration
# Add back to each master:
services.kubernetes.easyCerts = true;
services.kubernetes.apiserver.address = "10.1.1.110";  # Direct IP

# 3. Deploy
just test && just deploy
```

---

## Troubleshooting

### Certificate Issues

**Problem:** `x509: certificate valid for X, not Y`

**Solution:**
- Regenerate certificates with correct SANs
- Ensure VIP is included in API server SANs

### etcd Quorum Loss

**Problem:** etcd cluster cannot form quorum

**Solution:**
```bash
# Check each etcd member
ETCDCTL_API=3 etcdctl member list

# If quorum lost, may need to force removal:
etcdctl member remove <member-id>
```

### VIP Not Assigned

**Problem:** VIP (10.1.1.100) not responding

**Solution:**
- Check Keepalived: `systemctl status keepalived`
- Verify priorities are correct
- Check VRRP multicast is allowed

### HAProxy Backend Down

**Problem:** API server backends showing DOWN

**Solution:**
- Check API server health: `systemctl status kube-apiserver`
- Verify certificates are correct
- Check HAProxy configuration: `echo "show backend" | socat /run/haproxy/admin.sock stdio`

---

## Known Limitations

1. **Forge not in control plane** - Only 3 masters (Zephyr, Nexus, Sentry)
2. **Storage** - etcd data not replicated across nodes
3. **Backup** - Automated etcd backup not yet implemented
4. **Monitoring** - HAProxy metrics not yet integrated

---

## Next Steps

1. ✅ Implementation complete
2. ⏳ Generate and encrypt certificates
3. ⏳ Deploy to master nodes
4. ⏳ Validate with ha-test.sh
5. ⏳ Configure automated etcd backups
6. ⏳ Integrate HAProxy metrics with Prometheus
7. ⏳ Update documentation with production values

---

## References

- **Kubernetes HA:** https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/high-availability/
- **etcd HA:** https://etcd.io/docs/latest/op-guide/cluster-management/
- **cfssl:** https://github.com/cloudflare/cfssl
- **HAProxy:** https://www.haproxy.org/
- **Keepalived:** https://www.keepalived.org/

---

**Version:** 1.0 | **Status:** Implementation Complete, Awaiting Deployment
