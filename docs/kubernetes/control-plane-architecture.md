# Kubernetes HA Control Plane Architecture

**Status:** ✅ Operational | **Last Updated:** 2026-03-16 | **K8s Version:** v1.35.0

---

## Overview

This document describes the 3-node high-availability (HA) control plane architecture for the NixOS Kubernetes cluster.

---

## Architecture Summary

**Control Plane Nodes:** 3 masters with VIP failover
| Node | IP | Role | Keepalived Priority | etcd Name |
|------|-----|------|---------------------|-----------|
| **Zephyr** | 10.1.1.110 | Primary Master | 110 | zephyr |
| **Nexus** | 10.1.1.120 | Secondary Master | 100 | nexus |
| **Sentry** | 10.1.1.140 | Tertiary Master | 90 | sentry |

**Virtual IP (VIP):** 10.1.1.100 (floating via Keepalived)
**API Server Access:** `https://10.1.1.100:6443` (VIP) or direct node IPs

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                        HA Control Plane                             │
├─────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │                    Virtual IP: 10.1.1.100                      │ │
│  │                    (Keepalived Floating VIP)                  │ │
│  └───────────────────────────┬────────────────────────────────────┘ │
│                              │                                         │
│          ┌───────────────────┼───────────────────┐                    │
│          ▼                   ▼                   ▼                    │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐               │
│  │   Zephyr    │    │    Nexus    │    │   Sentry   │               │
│  │ 10.1.1.110  │    │ 10.1.1.120  │    │ 10.1.1.140  │               │
│  │ Priority 110│    │ Priority 100│    │  Priority 90 │               │
│  ├─────────────┤    ├─────────────┤    ├─────────────┤               │
│  │ apiserver   │    │ apiserver   │    │ apiserver   │               │
│  │ scheduler   │    │ scheduler   │    │ scheduler   │               │
│  │ controller  │    │ controller  │    │ controller  │               │
│  │ etcd        │◄───│ etcd        │◄───│ etcd        │               │
│  │ kubelet     │    │ kubelet     │    │ kubelet     │               │
│  │ proxy       │    │ proxy       │    │ proxy       │               │
│  └─────────────┘    └─────────────┘    └─────────────┘               │
│         ▲                   ▲                   ▲                     │
│         └───────────────────┴───────────────────┘                     │
│                              │                                         │
│                    ┌─────────▼──────────┐                              │
│                    │  etcd Quorum (3/3) │                              │
│                    │  zephyr:nexus:sentry                          │
│                    └────────────────────┘                              │
│                                                                       │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Component Details

### 1. API Server (kube-apiserver)

**Purpose:** Kubernetes API endpoint, authentication, authorization

**Configuration:**
```nix
services.kubernetes.apiserver = {
  enable = true;
  securePort = 6443;
  # Bind to all interfaces for VIP access
  bindAddress = "0.0.0.0";
  # Advertised address for cluster members
  advertisedAddress = cfg.masterAddress;  # VIP: 10.1.1.100
};
```

**Access Methods:**
- **VIP:** `https://10.1.1.100:6443` (recommended, automatic failover)
- **Direct Zephyr:** `https://10.1.1.110:6443`
- **Direct Nexus:** `https://10.1.1.120:6443`
- **Direct Sentry:** `https://10.1.1.140:6443`

### 2. etcd Cluster

**Purpose:** Distributed key-value store for cluster state

**Configuration:**
```nix
services.kubernetes.etcd = {
  enable = true;
  name = "zephyr";  # per-node: zephyr, nexus, sentry
  listenPeerUrls = ["http://10.1.1.110:2380"];
  listenClientUrls = ["http://10.1.1.110:2379"];
  initialCluster = [
    "zephyr=http://10.1.1.110:2380"
    "nexus=http://10.1.1.120:2380"
    "sentry=http://10.1.1.140:2380"
  ];
  initialClusterState = "existing";
};
```

**Cluster Members:**
- **zephyr:** `http://10.1.1.110:2380` (peer), `http://10.1.1.110:2379` (client)
- **nexus:** `http://10.1.1.120:2380` (peer), `http://10.1.1.120:2379` (client)
- **sentry:** `http://10.1.1.140:2380` (peer), `http://10.1.1.140:2379` (client)

**Quorum:** 2/3 nodes required for operation
**Data Directory:** `/var/lib/etcd` on each node

### 3. Keepalived VIP

**Purpose:** Floating virtual IP for API server high availability

**Configuration:**
```nix
services.keepalived-vip = {
  enable = true;
  vip = "10.1.1.100";
  interface = "enp7s0";  # Physical interface name
  priority = 110;  # Zephyr: 110, Nexus: 100, Sentry: 90
};
```

**Priority Settings:**
| Node | Priority | Role |
|------|----------|------|
| Zephyr | 110 | Primary (highest priority) |
| Nexus | 100 | Secondary |
| Sentry | 90 | Tertiary (backup) |

**Failover Behavior:**
- If Zephyr fails → Nexus takes over VIP (10.1.1.100)
- If Nexus fails → Zephyr retains VIP
- If both Zephyr and Nexus fail → Sentry takes over
- Automatic failback when higher-priority node recovers

### 4. Scheduler (kube-scheduler)

**Purpose:** Assigns pods to nodes based on resource requirements, constraints, policies

**Configuration:** Runs on all 3 master nodes, only leader active

### 5. Controller Manager (kube-controller-manager)

**Purpose:** Runs controller loops (replication, endpoints, service accounts)

**Configuration:** Runs on all 3 master nodes, only leader active

---

## Node Roles and Labels

**Master Nodes** (control plane + workload):
- `node-role.kubernetes.io/control-plane=""`
- `kubernetes.io/role=master`

**Worker Roles:**
- Zephyr: `ai-workstation` (desktop + control plane)
- Nexus: `storage` (storage + control plane)
- Forge: `gpu-compute` (compute only, worker)
- Sentry: `monitoring` (monitoring + control plane)

---

## Worker Nodes

### Forge (Worker Only)

**Purpose:** Dedicated GPU compute node (no control plane components)

**Configuration:**
```nix
services.kubernetes = {
  enable = true;
  roles = ["node"];  # Worker only
  masterAddress = "10.1.1.100";  # VIP for API access
};
```

---

## Firewall and Networking

### Firewall Rules

**Control Plane Ports (All Nodes):**
| Port | Protocol | Purpose | Source |
|------|----------|---------|--------|
| 6443 | TCP | Kubernetes API | Tailscale VPN only |
| 2379-2380 | TCP | etcd | Cluster network (10.1.1.0/24) |
| 10250 | TCP | Kubelet API | Cluster network |

**API Server Security:**
```nix
# Only allow Kubernetes API access via Tailscale
networking.firewall.interfaces."tailscale0".allowedTCPPorts = [6443];
```

### DNS Resolution

**API Server Access:**
- Internal: `https://kubernetes.default.svc.cluster.local:6443`
- External: `https://10.1.1.100:6443` (VIP)
- Direct: `https://<node-ip>:6443`

---

## Client Configuration

### kubeconfig

**Current Context Configuration:**
```yaml
apiVersion: v1
clusters:
  cluster:
    certificate-authority-data: <ca-cert>
    server: https://10.1.1.100:6443  # VIP
  name: cluster.local
contexts:
  context:
    cluster: cluster.local
    user: kubernetes-admin
  name: kubernetes-admin@cluster.local
users:
- name: kubernetes-admin
  user:
    client-certificate-data: <client-cert>
    client-key-data: <client-key>
```

**Location:** `/etc/kubernetes/cluster-admin.kubeconfig`

### Access from Any Node

```bash
# Use kubeconfig
export KUBECONFIG=/etc/kubernetes/cluster-admin.kubeconfig

# Or direct kubectl (reads kubeconfig automatically)
kubectl get nodes
```

---

## Operations

### Checking Control Plane Health

```bash
# Check all nodes
kubectl get nodes -o wide

# Check etcd health
etcdctl --endpoints=https://10.1.1.110:2379 member list
etcdctl --endpoints=https://10.1.1.110:2379,https://10.1.1.120:2379,https://10.1.1.140:2379 endpoint health

# Check control plane pods
kubectl get pods -n kube-system | grep -E "(apiserver|scheduler|controller|etcd)"

# Check VIP status
ip addr show | grep "10.1.1.100"
```

### Checking etcd Quorum

```bash
# List members
etcdctl member list

# Check health
etcdctl endpoint health --endpoints=https://10.1.1.110:2379,https://10.1.1.120:2379,https://10.1.1.140:2379

# Check status
etcdctl endpoint status --endpoints=https://10.1.1.110:2379,https://10.1.1.120:2379,https://10.1.1.140:2379 -w table
```

### Leader Election

**Scheduler and Controller Manager:**
- Use leader election (built-in to Kubernetes)
- Only one instance active at a time
- Automatic failover on leader failure

**Check Leaders:**
```bash
# Get scheduler leader
kubectl get endpoints kube-scheduler -n kube-system

# Get controller manager leader
kubectl get endpoints kube-controller-manager -n kube-system
```

### Keepalived Status

```bash
# Check Keepalived status
systemctl status keepalived-vip

# Check VIP ownership
ip addr show enp7s0 | grep "10.1.1.100"

# Check Keepalived logs
journalctl -u keepalived-vip -n 50 -f
```

---

## Disaster Recovery

### Single Node Failure

**Scenario:** One master node fails (e.g., Zephyr)

**Impact:**
- etcd quorum maintained (2/3 nodes)
- API server still accessible via VIP
- Scheduler/controller manager fail over to remaining nodes

**Recovery:** Automatic - no action required

### Dual Node Failure

**Scenario:** Two masters fail (e.g., Zephyr and Nexus)

**Impact:**
- etcd quorum LOST (1/3 nodes)
- API server may be inaccessible
- Cluster becomes READ-ONLY (no new pods)
- Existing pods continue running

**Recovery:**
1. Restore at least one failed node
2. Verify etcd quorum (2/3)
3. Resume normal operations

### Full Control Plane Loss

**Scenario:** All 3 masters fail

**Impact:**
- Complete cluster failure
- No API access
- No scheduling

**Recovery Procedure:**
1. Restart nodes in order: Zephyr → Nexus → Sentry
2. Verify etcd cluster forms
3. Verify API server starts
4. Verify workers reconnect
5. Check data persistence (etcd data should be intact)

---

## Backup and Restore

### etcd Backup

**Automated Backups:** Not currently configured

**Manual Backup:**
```bash
# Create etcd snapshot
etcdctl snapshot save /backup/etcd-snapshot-$(date +%Y%m%d).db

# Verify snapshot
etcdctl snapshot status /backup/etcd-snapshot-$(date +%Y%m%d).db
```

### etcd Restore

**From Snapshot:**
```bash
# Stop Kubernetes
systemctl stop kube-apiserver kube-scheduler kube-controller-manager

# Restore etcd
etcdctl snapshot restore /backup/etcd-snapshot-20260316.db \
  --name=zephyr \
  --data-dir=/var/lib/etcd

# Start Kubernetes
systemctl start kube-apiserver kube-scheduler kube-controller-manager
```

---

## Monitoring

### Key Metrics to Monitor

| Metric | Description | Alert Threshold |
|--------|-------------|-----------------|
| etcd_quorum | Etcd cluster has quorum | < 3 members |
| apiserver_up | API server is reachable | Down |
| scheduler_up | Scheduler is running | Down |
| controller_manager_up | Controller manager is running | Down |
| vip_active | VIP is assigned | Not assigned |

### Prometheus Alerts

**TODO:** Add Prometheus rules for control plane health monitoring

---

## Configuration Files

| File | Purpose | Location |
|------|---------|----------|
| `kubernetes.nix` | Main K8s module | `modules/services/kubernetes.nix` |
| `keepalived-vip.nix` | VIP configuration | `modules/services/keepalived-vip.nix` |
| Host configs | Node-specific settings | `hosts/<node>/configuration.nix` |

---

## References

- **ROADMAP.md:** Kubernetes migration plan
- **STATUS.md:** Real-time cluster status
- **NixOS Kubernetes Module:** https://search.nixos.org/options?query=kubernetes

**Last Updated:** 2026-03-16
**Maintainer:** j_kro
