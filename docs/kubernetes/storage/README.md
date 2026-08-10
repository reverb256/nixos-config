# Kubernetes Storage Integration

> **Status:** Reference material
> **Last Verified:** 2026-08-09 (checked-in paths and source boundaries)
> **Source:** `kubernetes/`, `kubernetes-manifests/`, host storage modules, and the live Kubernetes API
>
> Treat the manifests in this directory as reference or bootstrap material unless the
> owning module explicitly identifies one as active. Verify storage classes, paths,
> provisioners, and claims before applying anything.

**Purpose:** Kubernetes manifests and configuration for integrating cluster storage with Kubernetes workloads.

## Overview

This directory contains Kubernetes manifests for storage integration with the existing cluster storage infrastructure (NFS, Garage S3, local disks). The storage is **decoupled from Kubernetes** - the same storage serves both systemd services and Kubernetes pods.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    STORAGE BACKENDS                         │
│  (Running on systemd, independent of K8s)                  │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        │
│  │  NFS (v4)   │  │  Garage S3  │  │  Local      │        │
│  │  Nexus      │  │  Zephyr     │  │  All nodes  │        │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘        │
└─────────┼─────────────────┼─────────────────┼──────────────┘
          │                 │                 │
          │                 │                 │
┌─────────▼─────────────────▼─────────────────▼──────────────┐
│                 KUBERNETES STORAGE LAYER                    │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  StorageClasses (tier definitions)                  │   │
│  │  - fast-local-ssd    (Zephyr, for databases)       │   │
│  │  - nfs-shared-storage (Nexus, for shared data)     │   │
│  │  - slow-hdd-storage  (Sentry, for logs/archive)    │   │
│  │  - garage-s3         (S3 object storage)           │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  PersistentVolumes (physical storage mapping)       │   │
│  │  PVs map to actual cluster storage paths            │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  PersistentVolumeClaims (pod requests)              │   │
│  │  PVCs bind to PVs based on labels and storage class │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
          │                 │                 │
┌─────────▼─────────────────▼─────────────────▼──────────────┐
│                      KUBERNETES PODS                        │
│  Applications use PVCs like normal filesystems             │
└─────────────────────────────────────────────────────────────┘
```

## Files

| File | Purpose |
|------|---------|
| `storage-classes.yaml` | StorageClass definitions for each storage tier |
| `persistent-volumes.yaml` | Pre-provisioned PVs mapping to cluster storage |
| `persistent-volume-claims.yaml` | Example PVCs for common use cases |
| `garage-s3-secret.yaml` | S3 credentials for Garage access |
| Historical CSI plan | No current file is present; do not follow an unverified CSI procedure |
| `README.md` | This file |

## Quick Start

### 1. Apply StorageClasses
```bash
kubectl apply -f docs/kubernetes/storage/storage-classes.yaml
```

### 2. Create Required Directories
```bash
# On Zephyr
sudo mkdir -p /data/kubernetes/databases /data/kubernetes/ml-models

# On Nexus
sudo mkdir -p /data/shared/kubernetes /data/media/kubernetes /data/backups/kubernetes

# On Sentry
sudo mkdir -p /storage/kubernetes/logs /storage/kubernetes/archive
```

### 3. Apply PersistentVolumes
```bash
kubectl apply -f docs/kubernetes/storage/persistent-volumes.yaml
```

### 4. Apply Secrets (update credentials first)
```bash
# Edit garage-s3-secret.yaml with actual credentials
kubectl apply -f docs/kubernetes/storage/garage-s3-secret.yaml
```

### 5. Apply PVCs
```bash
kubectl apply -f docs/kubernetes/storage/persistent-volume-claims.yaml
```

### 6. Verify
```bash
kubectl get sc
kubectl get pv
kubectl get pvc
```

## Storage Tier Selection

| Use Case | Recommended StorageClass | Example |
|----------|--------------------------|---------|
| **Databases** | `fast-local-ssd` | PostgreSQL, MySQL |
| **ML Models** | `fast-local-ssd` | vLLM, model caches |
| **Shared Files** | `nfs-shared-storage` | Nextcloud data, media |
| **Backups** | `garage-s3` or `nfs-shared-storage` | Backup archives |
| **Logs** | `slow-hdd-storage` | Application logs |
| **Archives** | `slow-hdd-storage` | Infrequently accessed data |

## Example Pod Usage

### Using NFS shared storage
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nfs-test
spec:
  volumes:
    - name: shared-data
      persistentVolumeClaim:
        claimName: generic-storage
  containers:
    - name: app
      image: nginx
      volumeMounts:
        - name: shared-data
          mountPath: /usr/share/nginx/html
```

### Using fast local SSD
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: database
spec:
  volumes:
    - name: db-data
      persistentVolumeClaim:
        claimName: postgres-data
  containers:
    - name: postgres
      image: postgres:16
      volumeMounts:
        - name: db-data
          mountPath: /var/lib/postgresql/data
```

## S3 Integration

Two options for S3 (Garage) access:

### Option 1: Direct S3 API (Recommended)
Use S3 API directly from applications. No CSI driver needed.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: s3-app
spec:
  containers:
    - name: app
      image: myapp
      env:
        - name: AWS_ENDPOINT_URL
          value: "http://10.1.1.110:3900"
        - name: AWS_ACCESS_KEY_ID
          valueFrom:
            secretKeyRef:
              name: garage-s3-env
              key: AWS_ACCESS_KEY_ID
        - name: AWS_SECRET_ACCESS_KEY
          valueFrom:
            secretKeyRef:
              name: garage-s3-env
              key: AWS_SECRET_ACCESS_KEY
```

### Option 2: CSI Driver (For POSIX semantics)

No current CSI-driver procedure is maintained in this repository. Do not deploy a
CSI driver from an unverified historical plan.

## Maintenance

### Check PV/PVC Status
```bash
kubectl get pv,pvc -A
kubectl describe pv <pv-name>
```

### Resize PVC (if StorageClass allows expansion)
```bash
kubectl patch pvc my-pvc -p '{"spec":{"resources":{"requests":{"storage":"200Gi"}}}}'
```

### Cleanup

Do not run a cluster-wide delete. Identify the specific claim or volume, confirm its
owner and backup status, then use a targeted command only after review.

```bash
kubectl delete pvc <pvc-name> -n <namespace>
kubectl delete pv <pv-name>
```

## Troubleshooting

### PVC stuck in Pending
```bash
kubectl describe pvc <pvc-name>
# Check for:
# - No matching PV (labels don't match)
# - StorageClass doesn't exist
# - Node not available (for local storage)
```

### PV in Failed state
```bash
kubectl delete pv <pv-name>
# Recreate PV and check node path exists
```

### NFS mount issues
```bash
# Test NFS mount manually
mount -t nfs4 10.1.1.120:/data/shared/kubernetes /mnt/test

# Check NFS server
ssh nexus "showmount -e localhost"
```

### S3 access issues
```bash
# Test from pod
kubectl run aws-cli --image=amazon/aws-cli -it --rm --restart=Never --command -- bash
aws --endpoint-url http://10.1.1.110:3900 s3 ls
```

## Related Documentation

- [Current-state authority](../../current-state.md) - Checked-in architecture and source boundaries
- Historical CSI planning material is not present as a current repository file.
- [ROADMAP.md](../../../ROADMAP.md) - Kubernetes migration phases

## Historical Status Snapshot

The following table is retained from the original document and is not current runtime
truth. Verify each component against the checked-in modules and live API before acting.

| Component | Historical Status | Notes |
|-----------|--------|-------|
| StorageClasses | ✅ Ready | Applied to cluster |
| PersistentVolumes | ⏳ Pending | Need directory creation |
| PVCs | ✅ Ready | Examples defined |
| S3 Secrets | Historical/verify | Confirm the current SecretSpec or secret source before use |
| CSI Driver | ❌ Not Started | Phase 2 item |
