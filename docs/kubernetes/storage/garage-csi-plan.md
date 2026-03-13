# Garage S3 CSI Integration Plan

**Status:** Planning | **Created:** 2026-03-13

## Overview

Plan to integrate Garage S3 object storage with Kubernetes using the S3 CSI driver. This will allow Kubernetes pods to mount S3 buckets as volumes.

## Current State

- Garage S3 cluster operational with 3 nodes
- S3 API accessible at `http://10.1.1.110:3900`
- Buckets created: backups, media, projects, logs
- S3 credentials available (admin-key)

## CSI Driver Options

### Option 1: CSI-S3 Driver (Recommended)

**Project:** https://github.com/ctrox/csi-s3

**Pros:**
- Active community maintained
- Supports S3-compatible storage
- Mounting via geesefs, goofys, or s3fs
- Dynamic provisioning support

**Cons:**
- Not officially supported by Garage
- FUSE overhead (performance impact)

**Implementation:**
```bash
# Install CSI driver
kubectl apply -f https://raw.githubusercontent.com/ctrox/csi-s3/masterdeploy/kubernetes.yaml
```

**Configuration:**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: csi-s3-secret
type: Opaque
stringData:
  accessKeyID: GKac91d924fc76a30b9bcf6c3e
  secretAccessKey: <secret>
  endpoint: http://10.1.1.110:3900
```

### Option 2: Direct S3 API (Simplest)

Use S3 API directly from applications instead of mounting.

**Pros:**
- No CSI driver required
- Better performance (native S3 protocol)
- Works immediately
- No FUSE overhead

**Cons:**
- Requires application S3 support
- Not POSIX-compliant

**Implementation:**
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: s3-config
data:
  ENDPOINT: "http://10.1.1.110:3900"
  REGION: "garage"
  BUCKET: "backups"
---
apiVersion: v1
kind: Secret
metadata:
  name: s3-credentials
type: Opaque
stringData:
  ACCESS_KEY: "GKac91d924fc76a30b9bcf6c3e"
  SECRET_KEY: "<secret>"
```

### Option 3: Rclone Mount (Alternative)

Use rclone to mount S3 as FUSE filesystem.

**Pros:**
- Flexible, supports many storage backends
- Well-tested
- Can be deployed as sidecar

**Cons:**
- FUSE overhead
- Additional component to maintain

## Recommendation

**Phase 1 (Immediate):** Use Option 2 (Direct S3 API)
- No driver installation needed
- Works immediately
- Better performance for most applications

**Phase 2 (Future):** Install CSI-S3 Driver for POSIX requirements
- For applications that require filesystem semantics
- For workloads that expect POSIX behavior

## Implementation Steps

### Phase 1: Direct S3 API Integration

1. **Create S3 secret** (already done)
   ```bash
   kubectl apply -f docs/kubernetes/storage/garage-s3-secret.yaml
   ```

2. **Update applications to use S3**
   - GlitchTip: Configure S3 for file storage
   - Nextcloud: Use S3 as external storage
   - Backups: Send archives to S3

3. **Example: Pod using S3**
   ```yaml
   apiVersion: v1
   kind: Pod
   metadata:
     name: s3-example
   spec:
     containers:
       - name: app
         image: amazon/aws-cli:latest
         command: ["sleep", "3600"]
         env:
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
           - name: AWS_ENDPOINT_URL
             valueFrom:
               configMapKeyRef:
                 name: s3-config
                 key: ENDPOINT
   ```

### Phase 2: CSI-S3 Driver Installation

1. **Install Helm** (if not already installed)
   ```bash
   nix-shell -p helm
   ```

2. **Add CSI-S3 Helm repo**
   ```bash
   helm repo add csi-s3 https://ctrox.github.io/csi-s3
   helm repo update
   ```

3. **Install CSI driver**
   ```bash
   helm install csi-s3 csi-s3/csi-s3 \
     --namespace kube-system \
     --set secret.accessKey=GKac91d924fc76a30b9bcf6c3e \
     --set secret.secretKey=<secret> \
     --set secret.endpoint=http://10.1.1.110:3900
   ```

4. **Create StorageClass** (already defined in storage-classes.yaml)
   ```bash
   kubectl apply -f docs/kubernetes/storage/storage-classes.yaml
   ```

5. **Test mounting**
   ```bash
   kubectl apply -f docs/kubernetes/storage/persistent-volume-claims.yaml
   ```

## Testing

### Test S3 Access (Phase 1)
```bash
# From within a pod
kubectl run aws-cli --image=amazon/aws-cli --rm -it --restart=Never --command -- bash
aws --endpoint-url http://10.1.1.110:3900 s3 ls
aws --endpoint-url http://10.1.1.110:3900 s3 mb s3://test-bucket
echo "test" | aws --endpoint-url http://10.1.1.110:3900 s3 cp - s3://test-bucket/test.txt
```

### Test CSI Mount (Phase 2)
```bash
# Create test pod with PVC
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: s3-mount-test
spec:
  volumes:
    - name: s3-volume
      persistentVolumeClaim:
        claimName: garage-backups
  containers:
    - name: test
      image: busybox
      command: ["sleep", "3600"]
      volumeMounts:
        - name: s3-volume
          mountPath: /data
EOF

# Verify mount
kubectl exec s3-mount-test -- ls -la /data
```

## Rollback Plan

If CSI driver causes issues:
```bash
# Uninstall CSI driver
helm uninstall csi-s3 -n kube-system

# Remove StorageClass
kubectl delete storageclass garage-s3

# Delete PVCs using S3
kubectl delete pvc -l storage=s3
```

## References

- CSI-S3 Driver: https://github.com/ctrox/csi-s3
- Garage Documentation: https://garagehq.deuxfleurs.fr/
- AWS S3 SDKs: https://aws.amazon.com/tools/

## Next Steps

1. ✅ S3 credentials created
2. ✅ StorageClass defined
3. ⏳ Test S3 API access from pod
4. ⏳ Install CSI-S3 driver (Phase 2)
5. ⏳ Migrate applications to use S3 storage
