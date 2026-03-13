# Kubernetes Storage Classes

## Storage Classes

### fast-local-ssd
- **Backend**: Local path provisioner on Zephyr
- **Capacity**: ~922GB NVMe
- **Use Cases**: Databases, AI models, high IOPS workloads
- **Node Selector**: zephyr

### large-nfs-storage
- **Backend**: NFS shares on Nexus (10.1.1.120)
- **Capacity**: ~3.6TB bcache0
- **Use Cases**: Media, backups, Nextcloud data
- **Exports**: /data/shared, /data/media, /data/backups

### slow-hdd
- **Backend**: Local path provisioner on Sentry
- **Capacity**: ~1TB HDD
- **Use Cases**: Logs, archival, low-priority data
- **Node Selector**: sentry

## Deployment

```bash
kubectl apply -f kubernetes-manifests/storage/
```

## Verification

```bash
kubectl get sc
kubectl get pv -A
kubectl get pvc -A
```

## Usage Example

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: database-pvc
spec:
  storageClassName: fast-local-ssd
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
```
