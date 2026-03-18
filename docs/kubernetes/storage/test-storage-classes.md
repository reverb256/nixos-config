# Storage Classes Testing Guide

## Overview
This guide explains how to test the Kubernetes storage classes to verify they work correctly.

## Storage Classes Available

| Storage Class | Provisioner | Node | Use Case |
|---------------|-------------|------|----------|
| `fast-local-ssd` | `rancher.io/local-path` | Zephyr | Databases, high-IOPS workloads |
| `slow-hdd` | `rancher.io/local-path` | Sentry | Logs, archival data |
| `large-nfs-storage` | `kubernetes.io/no-provisioner` | Nexus (NFS) | Shared data, media, backups |

## Testing Procedure

### 1. Apply Storage Classes and Local Path Provisioner
```bash
kubectl apply -f kubernetes-manifests/storage/local-path-provisioner.yaml
kubectl apply -f kubernetes-manifests/storage/nfs-storage.yaml
```

### 2. Apply Test PVCs
```bash
kubectl apply -f kubernetes-manifests/storage/test-pvcs.yaml
```

### 3. Check PVC Status
```bash
kubectl get pvc
```

Expected output:
```
NAME                    STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS
test-fast-local-ssd     Pending                                      fast-local-ssd
test-slow-hdd           Pending                                      slow-hdd
test-nfs-storage        Pending                                      large-nfs-storage
test-local-path         Pending                                      <none>
```

### 4. Apply Test Pods
```bash
kubectl apply -f kubernetes-manifests/storage/test-storage-pod.yaml
```

### 5. Check Pod Status
```bash
kubectl get pods
```

### 6. View Test Results
```bash
kubectl logs test-fast-local-ssd
kubectl logs test-slow-hdd
kubectl logs test-nfs-storage
kubectl logs test-local-path
```

## Expected Output

Each test pod should:
1. Show disk space usage (`df -h /data`)
2. Write a 10MB test file (`dd if=/dev/zero of=/data/test-file bs=1M count=10`)
3. List the file (`ls -lh /data/test-file`)
4. Output "Test completed successfully"

## Troubleshooting

### PVC Stuck in Pending
```bash
kubectl describe pvc <pvc-name>
```
Look for:
- No matching PV (labels don't match)
- StorageClass doesn't exist
- Node not available (for local storage)

### Pod Not Starting
```bash
kubectl describe pod <pod-name>
kubectl logs <pod-name> --previous
```

### Local Path Provisioner Issues
```bash
kubectl logs -n local-path-storage deployment/local-path-provisioner
```

## Cleanup
```bash
kubectl delete -f kubernetes-manifests/storage/test-storage-pod.yaml
kubectl delete -f kubernetes-manifests/storage/test-pvcs.yaml
```

## Status
- Storage classes: ✅ Defined in kubernetes-manifests/storage/
- Local path provisioner: ✅ Deployed
- NFS PVs: ✅ Pre-provisioned
- Test PVCs: ✅ Created
- Test pods: ✅ Ready to deploy
