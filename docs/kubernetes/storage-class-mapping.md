# Kubernetes Storage Classes - Complete Mapping

**Last Updated:** 2026-03-25 | **K8s Version:** v1.35.0 | **Provisioners:** 3 active

---

## Overview

This document maps all Kubernetes storage classes to their underlying provisioners, node affinity rules, capacity, and performance characteristics.

---

## Storage Classes Summary

| Storage Class | Provisioner | Node(s) | Capacity | Type | Use Case |
|---------------|-------------|---------|----------|------|----------|
| **local-path** | rancher.io/local-path | All nodes | Varies | Local SSD/HDD | General purpose, low IOPS |
| **fast-local-ssd** | rancher.io/local-path | Zephyr | 922GB | NVMe SSD | High IOPS, databases |
| **large-nfs-storage** | kubernetes.io/no-provisioner | Nexus (via NFS) | 3.6TB | NFS mount | Media, backups, archival |
| **default-local-storage** | rancher.io/local-path | Nexus | ~100GB | btrfs | Provider data |

---

## Storage Class Details

### 1. local-path (Default)

**Provisioner:** `rancher.io/local-path`
**DaemonSet:** `local-path-provisioner` (runs on all nodes)
**Manifest:** `kubernetes-manifests/storage/local-path-provisioner.yaml`

**Node Paths:**
```yaml
Zephyr:  /var/local-path-provisioner  (system disk)
Nexus:   /data/containers/k8s-local   (bcache0 - large capacity)
Forge:   /var/local-path-provisioner  (system disk)
Sentry:  /storage/k8s-local           (HDD - archival)
```

**Capacity:**
- Zephyr: ~100GB (root partition)
- Nexus: ~3.6TB (bcache0)
- Forge: ~200GB (root partition)
- Sentry: ~1TB (HDD)

**Performance:**
- Zephyr: Medium (NVMe SSD, but shared with OS)
- Nexus: Low-Medium (bcache0 - SSD-backed HDD cache)
- Forge: Medium (SSD)
- Sentry: Low (HDD, 5400 RPM)

**Use Cases:**
- ✅ Stateless applications (can be recreated)
- ✅ Caching layers (Redis, temp data)
- ✅ Development/testing environments
- ❌ Critical databases (use fast-local-ssd instead)
- ❌ High-throughput workloads (use fast-local-ssd)

**Reclaim Policy:** Delete
**Volume Binding Mode:** WaitForFirstConsumer

---

### 2. fast-local-ssd (High Performance)

**Provisioner:** `rancher.io/local-path` (same as local-path)
**Manifest:** `kubernetes-manifests/storage/local-path-provisioner.yaml`
**Special Path:** `kubernetes-manifests/storage/fast-local-ssd-pv.yaml` (pre-provisioned PVs)

**Node Path (Zephyr only):**
```yaml
Zephyr:  /data/k8s-local  (NVMe SSD, 922GB)
```

**Capacity:** 922GB (Zephyr NVMe)
**Performance:** **Very High** (NVMe SSD, ~3GB/s sequential, ~500k IOPS)

**Use Cases:**
- ✅ PostgreSQL databases (GlitchTip, Nextcloud)
- ✅ Vector databases (Qdrant)
- ✅ AI model storage (faster loading)
- ✅ High-throughput workloads
- ❌ Large file storage (use large-nfs-storage)

**Reclaim Policy:** Retain
**Volume Binding Mode:** WaitForFirstConsumer
**Node Affinity:** `kubernetes.io/hostname: zephyr` (forced)

**Current Users:**
- `qdrant-deployment.yaml` - Vector database
- `glitchtip/02-postgres-statefulset.yaml` - Error tracking DB
- `home-assistant/deployment-fixed.yaml` - Home Assistant data

---

### 3. large-nfs-storage (Network Attached)

**Provisioner:** `kubernetes.io/no-provisioner` (static PVs, no dynamic provisioning)
**Manifest:** `kubernetes-manifests/storage/nfs-storage.yaml`
**NFS Server:** Zephyr (10.1.1.110) → `/run/nixos-shared` (NFS mount)

**Node Paths (NFS-mounted on all nodes):**
```yaml
All nodes: /mnt/nfs-shared  (mounted from Zephyr:/run/nixos-shared)
```

**Capacity:** 3.6TB (Nexus bcache0, exported via NFS from Zephyr)
**Performance:** **Low** (network overhead, 1Gbps LAN bottleneck)

**Use Cases:**
- ✅ Large file storage (Nextcloud data)
- ✅ Backups and archival
- ✅ Media files (photos, videos)
- ✅ Shared data across nodes
- ❌ Databases (too slow, use fast-local-ssd)
- ❌ High-IOPS workloads (network bottleneck)

**Reclaim Policy:** Retain
**Volume Binding Mode:** Immediate
**Access Modes:** ReadWriteMany (multiple pods can write simultaneously)

**Pre-Provisioned PVs:**
- `nfs-storage-pg-data.yaml` - PostgreSQL data (8GB)
- `nfs-storage-nextcloud-data.yaml` - Nextcloud files (100GB)
- `nfs-storage-ml-models.yaml` - ML model storage (50GB)
- `nfs-storage-logs.yaml` - Application logs (10GB)

**Current Users:**
- None currently (PVs defined but not claimed)

---

### 4. default-local-storage (Provider)

**Provisioner:** `rancher.io/local-path` (same as local-path)
**Manifest:** `kubernetes-manifests/storage/default-pv-nexus.yaml`
**Special Path:** Pre-provisioned PV on Nexus only

**Node Path (Nexus only):**
```yaml
Nexus: /data/default  (bcache0, 100GB allocated)
```

**Capacity:** ~100GB (allocated from Nexus 3.6TB)
**Performance:** Medium (bcache0 - SSD-backed HDD cache)

**Use Cases:**
- ✅ Provider lease data
- ✅ Container images for workloads
- ✅ Temporary deployment storage

**Reclaim Policy:** Retain
**Volume Binding Mode:** Immediate
**Node Affinity:** `kubernetes.io/hostname: nexus` (forced)

**Current Users:**
- `default/` deployments

---

## Provisioner Architecture

### Rancher Local-Path Provisioner

**Type:** DaemonSet (runs on all nodes)
**Manifest:** `kubernetes-manifests/storage/local-path-provisioner.yaml`
**Version:** v0.0.26
**Helper Image:** `rancher/local-path-provisioner-helper:v0.0.26`

**How It Works:**
1. Pod requests PVC with `storageClassName: local-path`
2. Provisioner creates directory on node's local filesystem
3. PersistentVolume created with `hostPath` to that directory
4. Pod binds to PV (VolumeBindingMode: WaitForFirstConsumer)

**Node Path Mapping:**
```yaml
# Defined in local-path-provisioner ConfigMap
data:
  config.json: |
    {
      "nodePathMap": [
        {
          "node": "DEFAULT_PATH_FOR_NON_LISTED_NODES",
          "paths": ["var/local-path-provisioner"]
        }
      ]
    }
```

**Custom Node Paths (NixOS-managed):**
```nix
# modules/services/kubernetes.nix
systemd.tmpfiles.rules = [
  "d /var/local-path-provisioner 0777 root root -"  # Default (Forge, Sentry)
  "d /data/k8s-local 0777 root root -"              # Zephyr (fast)
  "d /data/containers/k8s-local 0777 root root -"   # Nexus (large)
  "d /storage/k8s-local 0777 root root -"           # Sentry (archival)
];
```

---

### NFS Static Provisioner

**Type:** Manual PV provisioning (no dynamic provisioning)
**Manifest:** `kubernetes-manifests/storage/nfs-storage.yaml`
**NFS Server:** Zephyr (10.1.1.110)
**Export:** `/run/nixos-shared` (NFS mount from Nexus)

**How It Works:**
1. Administrator manually creates PV with `nfs` volume type
2. PV specifies NFS server (10.1.1.110) and export path
3. Pod requests PVC with matching capacity and access mode
4. Pod mounts NFS share directly (ReadWriteMany supported)

**Limitations:**
- ❌ No dynamic provisioning (must create PVs manually)
- ❌ Capacity planning manual (must pre-allocate)
- ✅ ReadWriteMany support (multiple pods can write)
- ✅ Shared storage across nodes

---

## Performance Comparison

| Storage Class | Sequential Read | Sequential Write | Random IOPS | Latency | Best For |
|---------------|-----------------|------------------|-------------|---------|----------|
| **fast-local-ssd** | ~3 GB/s | ~2.5 GB/s | ~500k | <1ms | Databases, AI models |
| **local-path** | ~500 MB/s | ~400 MB/s | ~50k | ~2ms | General purpose |
| **large-nfs-storage** | ~100 MB/s | ~100 MB/s | ~1k | ~10ms | Backups, media |

**Notes:**
- fast-local-ssd: NVMe SSD on Zephyr (best performance)
- local-path: Varies by node (Zephyr > Forge > Nexus > Sentry)
- large-nfs-storage: Limited by 1Gbps network (~125 MB/s theoretical)
- default-local-storage: bcache0 on Nexus (SSD cache + HDD storage)

---

## Usage Guidelines

### When to Use Each Storage Class

**fast-local-ssd** (Zephyr NVMe)
- ✅ **Databases:** PostgreSQL, MySQL, MongoDB
- ✅ **Vector databases:** Qdrant, Milvus
- ✅ **AI models:** Model weights, embeddings
- ✅ **High-throughput apps:** Prometheus TSDB, Grafana dashboards
- ❌ **Large files:** Wastes fast storage (use NFS instead)

**local-path** (Default)
- ✅ **Stateless apps:** Caching, temp data
- ✅ **Development:** Test environments, CI/CD
- ✅ **Low-priority workloads:** Logs, metrics (short-term)
- ❌ **Critical data:** No replication, node loss = data loss

**large-nfs-storage** (NFS)
- ✅ **Media files:** Nextcloud, photo/video storage
- ✅ **Backups:** Automated backups, snapshots
- ✅ **Archival:** Logs, historical data
- ✅ **Shared data:** ReadWriteMany access required
- ❌ **Databases:** Too slow, network overhead

**default-local-storage** (Nexus)
- ✅ **Provider:** Lease data, container images
- ✅ **GPU workloads:** Temporary storage for deployments
- ❌ **General use:** Node affinity to Nexus required

---

## Storage Class Selection Matrix

| Requirement | Recommended Storage Class | Reason |
|-------------|---------------------------|---------|
| **PostgreSQL database** | fast-local-ssd | High IOPS, low latency |
| **Nextcloud data** | large-nfs-storage | Large capacity, shared access |
| **Qdrant vectors** | fast-local-ssd | High IOPS for vector search |
| **Redis cache** | local-path | Ephemeral, can be recreated |
| **ML model storage** | fast-local-ssd | Fast loading for inference |
| **Backups** | large-nfs-storage | Large capacity, archival |
| **Provider** | default-local-storage | Node affinity to Nexus |
| **Prometheus metrics** | fast-local-ssd | High write throughput |
| **Grafana dashboards** | local-path | Low IOPS requirement |
| **Home Assistant** | fast-local-ssd | Database performance |

---

## Troubleshooting

### PVC Stuck in Pending State

**Check 1: Storage Class Exists**
```bash
kubectl get storageclass
# Should see: fast-local-ssd, local-path, large-nfs-storage, default-local-storage
```

**Check 2: PV Available**
```bash
kubectl get pv
# Look for PVs with STATUS: Available
# For NFS: Check if pre-provisioned PVs exist
```

**Check 3: Node Affinity**
```bash
kubectl describe pvc <pvc-name>
# Look for events like:
# "no matching nodes found" → Node affinity issue
# "waiting for a volume to be created" → Provisioner issue
```

**Check 4: Provisioner Logs**
```bash
# Local-path provisioner
kubectl logs -n kube-system -l app=local-path-provisioner

# NFS: No provisioner (static PVs only)
# Check NFS mount instead:
ssh zephyr "showmount -e localhost | grep nixos-shared"
```

---

### PV Capacity Issues

**Problem:** PV too small for workload
**Solution:** Pre-provision larger PV or use different storage class

```bash
# For NFS: Edit PV spec.capacity.storage
kubectl edit pv nfs-storage-pg-data

# For local-path: Cannot resize (must recreate)
# Delete old PVC/PV and create larger one
kubectl delete pvc <pvc-name>
# Then apply updated PVC with larger request
```

---

### Performance Issues

**Symptom:** Slow database queries, high latency
**Diagnosis:**
```bash
# Check storage class
kubectl get pvc <pvc-name> -o jsonpath='{.spec.storageClassName}'

# If local-path: Switch to fast-local-ssd
# If NFS: Switch to fast-local-ssd (NFS too slow for DBs)
```

**Resolution:**
1. Backup data
2. Delete PVC/PV
3. Update deployment to use fast-local-ssd
4. Restore data to new PVC

---

## Migration Paths

### Migrate from local-path to fast-local-ssd

**Use Case:** Database moved to fast storage
**Steps:**
1. Backup data from old PVC
2. Delete old PVC
3. Update deployment YAML: `storageClassName: fast-local-ssd`
4. Apply new deployment
5. Restore data to new PVC

**Example:**
```yaml
# OLD (slow)
spec:
  storageClassName: local-path
  resources:
    requests:
      storage: 10Gi

# NEW (fast)
spec:
  storageClassName: fast-local-ssd
  resources:
    requests:
      storage: 10Gi
  nodeAffinity:  # Enforced by fast-local-ssd
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - zephyr
```

---

## Best Practices

1. **Use fast-local-ssd for all databases** (PostgreSQL, Qdrant, etc.)
2. **Use large-nfs-storage for media and backups** (Nextcloud, backups)
3. **Avoid NFS for databases** (network latency kills performance)
4. **Pre-provision NFS PVs** (no dynamic provisioning)
5. **Monitor PV capacity** (don't let nodes fill up)
6. **Set appropriate reclaim policies** (Retain for critical data, Delete for cache)
7. **Use WaitForFirstConsumer** (ensures pod scheduled on correct node)
8. **Test PV/PVC before production** (create test PVC, verify mount)

---

## References

- **Storage Architecture:** `docs/kubernetes/storage/storage-architecture.md`
- **Storage Manifests:** `kubernetes-manifests/storage/`
- **NixOS Storage Module:** `modules/system/cluster-storage.nix`
- **Kubernetes Storage Docs:** https://kubernetes.io/docs/concepts/storage/

---

**Document Owner:** j_kro
**Version:** 1.0 | **Created:** 2026-03-25
**Last Updated:** 2026-03-25
