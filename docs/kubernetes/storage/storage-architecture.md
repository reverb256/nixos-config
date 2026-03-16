# Kubernetes Storage Architecture

**Status:** ✅ Operational | **Last Updated:** 2026-03-16 | **K8s Version:** v1.35.0

---

## Overview

This document describes the complete storage architecture for the NixOS Kubernetes cluster, including storage classes, provisioners, and node-local storage configurations.

---

## Storage Classes

### Available Storage Classes

| Storage Class | Provisioner | Reclaim Policy | Node | Use Case |
|--------------|-------------|----------------|------|----------|
| `beta2` | rancher.io/local-path | Delete | All nodes | General workloads (default) |
| `beta3` | rancher.io/local-path | Delete | All nodes | General workloads (alternate) |
| `ram` | rancher.io/local-path | Delete | All nodes | High-performance, ephemeral |
| `garage-s3` | Garage S3 | Delete | Nexus (10.1.1.120:3900) | S3-compatible object storage |

### Storage Class Details

**beta2** (Default):
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: beta2
  annotations:
    storageclass.kubernetes.io/is-default-class: "false"
provisioner: rancher.io/local-path
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
```

**beta3**:
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: beta3
provisioner: rancher.io/local-path
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
```

**ram** (High-performance):
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ram
provisioner: rancher.io/local-path
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
```

**garage-s3** (Object Storage):
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: garage-s3
provisioner: garage-s3.internal
reclaimPolicy: Delete
volumeBindingMode: Immediate
```

---

## Node Storage Capacity

### Zephyr (10.1.1.110)

| Path | Size | Type | Usage |
|------|------|------|-------|
| `/` | 931GB | SSD (BTRFS) | Root, system services |
| `/var/lib/rancher` | Part of root | SSD | Local-path provisioner |
| `/data` | 919GB | SSD (BTRFS) | Fast local storage |

**Recommended For:** Databases, AI models, high-IOPS workloads

### Nexus (10.1.1.120) - Primary Storage Node

| Path | Size | Type | Usage |
|------|------|------|-------|
| `/` | 223.6GB | NVMe (BTRFS) | Root, system services |
| `/data/home` | ~4TB | Bcache0 (BTRFS) | Home directories |
| `/data/shared` | ~4TB | Bcache0 (BTRFS) | NFS shared storage |
| `/data/backups` | ~4TB | Bcache0 (BTRFS) | Backup storage |
| `/data/media` | ~4TB | Bcache0 (BTRFS) | Media files |
| `/var/lib/containers` | ~4TB | Bcache0 (BTRFS) | Container storage |

**NFS Exports:**
- `/data/shared` - Read/write shared storage
- `/data/home` - Home directories (optional mount)

**Recommended For:** Large datasets, backups, media, persistent storage

### Forge (10.1.1.130)

| Path | Size | Type | Usage |
|------|------|------|-------|
| `/` | 446GB | SSD (BTRFS) | Root, system services, mining |

**Recommended For:** Compute workloads, temporary storage

### Sentry (10.1.1.140)

| Path | Size | Type | Usage |
|------|------|------|-------|
| `/` | 230GB | SSD (BTRFS) | Root, system services |
| `/storage` | 1TB | HDD | Logs, archival data |

**Recommended For:** Monitoring logs, long-term storage

---

## Garage S3 Object Storage

### Configuration

**Node:** Nexus (10.1.1.120)
**API Port:** 3900
**RPC Port:** 3901
**Replication Factor:** 1 (single-node operation)
**Consistency Mode:** consistent

### Buckets

| Bucket | Purpose | Access |
|--------|---------|--------|
| `ai-gateway-files` | AI Gateway file uploads | Internal |
| `kubernetes-backups` | K8s resource backups | Internal |
| `logs-archive` | Long-term log storage | Internal |

### S3 Configuration

```nix
# From modules/services/akash-provider.nix
garage-cluster = {
  enable = true;
  dataDir = "/data/shared/garage";
  replicationFactor = 1;
  consistencyMode = "consistent";
  enableMetrics = true;
  enableBackup = false;
};
```

### Access from Kubernetes

```bash
# S3-compatible endpoint
export S3_ENDPOINT="http://10.1.1.120:3900"
export AWS_ACCESS_KEY_ID="<key>"
export AWS_SECRET_ACCESS_KEY="<secret>"

# List buckets
aws s3 ls --endpoint-url $S3_ENDPOINT
```

---

## NFS Shared Storage

### Server (Nexus)

**Configuration:** `modules/services/nfs-server.nix`

```nix
services.nfs.server = {
  enable = true;
  exports = "/data/shared 10.1.1.0/24(rw,sync,no_subtree_check,no_root_squash)";
};
```

**Exported Paths:**
- `/data/shared` - Shared cluster storage (rw)
- `/data/home` - Home directories (optional)

### Client Configuration

All worker nodes mount NFS shares via `modules/services/nfs-client.nix`:

```nix
services.nfs-client = {
  enable = true;
  mountShared = true;   # Mount /data/shared
  mountHome = false;     # Optional: mount /data/home
  mountMedia = false;    # Optional: mount /data/media
};
```

**Mount Options:** `soft,timeo=10,retrans=3` (graceful failure if server unavailable)

### Kubernetes NFS Usage

**PV Example:**
```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: nfs-shared-pv
spec:
  capacity:
    storage: 100Gi
  accessModes:
    - ReadWriteMany
  nfs:
    server: 10.1.1.120
    path: /data/shared
```

---

## Storage Recommendations by Workload Type

| Workload Type | Recommended Storage | Reasoning |
|--------------|-------------------|-----------|
| Databases (PostgreSQL, MySQL) | fast-local-ssd (Zephyr) | High IOPS, low latency |
| AI Models (vLLM, LM Studio) | fast-local-ssd (Zephyr) | Fast loading, large files |
| Nextcloud Data | NFS shared (Nexus) | Large capacity, shared access |
| Backups | NFS shared (Nexus) | Large capacity, reliable |
| Logs/Metrics | slow-hdd (Sentry) | Low priority, archival |
| Build Caches | fast-local-ssd (Zephyr) | Speed during builds |
| Temporary/Scratch | ram storage class | In-memory, ephemeral |

---

## Storage Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Kubernetes Cluster                             │
├─────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐ │
│  │   Zephyr    │  │    Nexus    │  │    Forge    │  │   Sentry   │ │
│  │ 10.1.1.110  │  │ 10.1.1.120  │  │ 10.1.1.130  │  │ 10.1.1.140  │ │
│  ├─────────────┤  ├─────────────┤  ├─────────────┤  ├─────────────┤ │
│  │ 931GB SSD   │  │ 4.7TB Total │  │  446GB SSD  │  │ 1.23TB Total│ │
│  │             │  │             │  │             │  │             │ │
│  │ /data       │  │ /data/shared│  │             │  │ /storage    │ │
│  │ (fast)      │  │ (NFS export)│  │             │  │ (logs)      │ │
│  └──────┬──────┘  └──────┬──────┘  └─────────────┘  └─────────────┘ │
│         │                │                                              │
│         │                │                                              │
│  ┌──────▼────────────────▼──────────────────────────────────────┐  │
│  │              Persistent Storage Layer                          │  │
│  ├──────────────────────────────────────────────────────────────┤  │
│  │                                                              │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐        │  │
│  │  │ Local Path   │  │    NFS       │  │  Garage S3   │        │  │
│  │  │ Provisioner  │  │  Shared      │  │  (Object)    │        │  │
│  │  │              │  │  Storage     │  │              │        │  │
│  │  │ beta2/beta3  │  │ 10.1.1.120   │  │ 10.1.1.120   │        │  │
│  │  │ ram          │  │ /data/shared │  │ :3900        │        │  │
│  │  └──────────────┘  └──────────────┘  └──────────────┘        │  │
│  │                                                              │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                                                                       │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Troubleshooting

### PVC Issues

**Problem:** PVC stuck in `Pending` state

**Solution:**
```bash
# Check storage classes
kubectl get storageclass

# Check PV binding
kubectl get pv

# Describe PVC for events
kubectl describe pvc <pvc-name>

# Check local-path provisioner logs
kubectl logs -n kube-system -l app=local-path-provisioner
```

### NFS Mount Issues

**Problem:** Pods can't mount NFS share

**Solution:**
```bash
# Verify NFS server
showmount -e 10.1.1.120

# Test from node
mount -t nfs 10.1.1.120:/data/shared /mnt/test

# Check for firewall issues
iptables -L | grep 2049
```

### Garage S3 Issues

**Problem:** Can't connect to Garage S3

**Solution:**
```bash
# Check Garage status
systemctl status garage

# Check connectivity
curl http://10.1.1.120:3900

# Check Garage logs
journalctl -u garage -n 50
```

---

## Future Improvements

1. **Longhorn** - Distributed block storage with replication
2. **Velero** - Kubernetes backup automation
3. **Snapshot Controller** - CSI-based volume snapshots
4. **Storage Autoscaling** - Dynamic volume expansion

---

**References:**
- Garage S3: `modules/services/akash-provider.nix`
- NFS Server: `modules/services/nfs-server.nix`
- NFS Client: `modules/services/nfs-client.nix`
- STATUS.md: Real-time cluster storage status

**Last Updated:** 2026-03-16
**Maintainer:** j_kro
