# PVC Backup Implementation Guide

**Purpose**: Automated backup of Akash provider wallet data
**Created**: 2026-03-22
**Status**: ⏳ Ready for deployment

---

## Backup Strategy

### What's Being Backed Up
- **PVC**: `home-akash-provider-akash-provider-fixed-0`
- **Contents**: Wallet keyring data (`/root/.akash/keyring-test/`)
- **Location**: `/var/backups/k8s-pvc` on zephyr (control plane)
- **Frequency**: Daily at 2 AM
- **Retention**: 30 days

---

## Quick Start (Manual Backup)

### Option 1: Use the Backup Script

```bash
# Run manual backup
sudo /etc/nixos/scripts/backup-pvc.sh

# Check backup files
ls -lh /var/backups/k8s-pvc/
```

### Option 2: Manual Backup with kubectl

```bash
# Create temporary pod to access PVC
kubectl run backup-pod -n akash-services \
  --image=ubuntu:22.04 \
  --restart=Never \
  --overrides='{"spec":{"nodeName":"zephyr","containers":[{"name":"backup","image":"ubuntu:22.04","command":["sleep","3600"],"volumeMounts":[{"name":"pvc","mountPath":"/data"}]}],"volumes":[{"name":"pvc","persistentVolumeClaim":{"claimName":"home-akash-provider-akash-provider-fixed-0"}}]}}'

# Wait for pod to be ready
kubectl wait --for=condition=Ready pod/backup-pod -n akash-services

# Create backup
kubectl exec backup-pod -n akash-services -- tar czf /tmp/wallet-backup.tar.gz -C /data .
kubectl cp akash-services/backup-pod:/tmp/wallet-backup.tar.gz /var/backups/k8s-pvc/akash-wallet-$(date +%Y%m%d).tar.gz

# Clean up
kubectl delete pod backup-pod -n akash-services
```

---

## Automated Backup (CronJob)

### Deploy the CronJob

```bash
# Apply CronJob manifest
kubectl apply -f /etc/nixos/docs/kubernetes/pvc-backup-cronjob.yaml

# Verify it's scheduled
kubectl get cronjob -n monitoring pvc-backup
```

### Configure Systemd Timer (Alternative)

```bash
# Create systemd service
cat > /etc/systemd/system/k8s-pvc-backup.service << 'EOF'
[Unit]
Description=Kubernetes PVC Backup
After=network.target

[Service]
Type=oneshot
ExecStart=/etc/nixos/scripts/backup-pvc.sh

[Install]
WantedBy=multi-user.target
EOF

# Create systemd timer
cat > /etc/systemd/system/k8s-pvc-backup.timer << 'EOF'
[Unit]
Description=Daily PVC Backup

[Timer]
OnCalendar=*-*-* 02:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Enable and start
systemctl enable k8s-pvc-backup.timer
systemctl start k8s-pvc-backup.timer

# Check status
systemctl list-timers k8s-pvc-backup.timer
```

---

## Testing Backup & Recovery

### Test Backup

```bash
# Run backup script
/etc/nixos/scripts/backup-pvc.sh

# Verify backup file exists
ls -lh /var/backups/k8s-pvc/
```

### Test Recovery

```bash
# Identify backup file
BACKUP_FILE=$(ls -t /var/backups/k8s-pvc/akash-services-home-*.tar.gz | head -1)
echo "Using backup: $BACKUP_FILE"

# Delete existing PVC (data will be lost!)
kubectl delete pvc home-akash-provider-akash-provider-fixed-0 -n akash-services

# Recreate PVC
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: home-akash-provider-akash-provider-fixed-0
  namespace: akash-services
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: akash-provider-akash-provider-fixed-local-storage
  resources:
    requests:
      storage: 10Gi
EOF

# Create temporary pod to restore data
kubectl run restore-pod -n akash-services \
  --image=ubuntu:22.04 \
  --restart=Never \
  --overrides='{"spec":{"nodeName":"zephyr","containers":[{"name":"restore","image":"ubuntu:22.04","command":["sleep","3600"],"volumeMounts":[{"name":"pvc","mountPath":"/data"}]}],"volumes":[{"name":"pvc","persistentVolumeClaim":{"claimName":"home-akash-provider-akash-provider-fixed-0"}}]}}'

# Wait for pod
kubectl wait --for=condition=Ready pod/restore-pod -n akash-services

# Copy backup to pod
kubectl cp "$BACKUP_FILE" akash-services/restore-pod:/tmp/backup.tar.gz

# Extract backup
kubectl exec restore-pod -n akash-services -- tar xzf /tmp/backup.tar.gz -C /data

# Clean up
kubectl delete pod restore-pod -n akash-services

# Restart provider to verify recovery
kubectl delete pod akash-provider-akash-provider-fixed-0 -n akash-services
kubectl wait --for=condition=Ready pod/akash-provider-akash-provider-fixed-0 -n akash-services --timeout=120s

# Verify wallet address
curl -sk https://10.0.0.63:8443/status | jq '.address'
# Should output: akash1c6h804ky08tdpnxrv72vum783xuey09qgzt2p6
```

---

## Monitoring Backup Health

### Check Last Backup

```bash
# List recent backups
ls -lt /var/backups/k8s-pvc/*.tar.gz | head -5

# Check backup size
du -sh /var/backups/k8s-pvc/*.tar.gz | tail -5
```

### Prometheus Alerts

```yaml
# Add to monitoring alerts
- alert: PVCBackupMissing
  expr: |
    time() - max(process_start_time_seconds{job="pvc-backup"}) > 86400 + 7200
  for: 10m
  labels:
    severity: warning
  annotations:
    summary: "PVC backup hasn't run in 26 hours"

- alert: PVCBackupFailed
  expr: |
    increase(kube_job_status_failed{jobname="pvc-backup"}[1h]) > 0
  labels:
    severity: critical
  annotations:
    summary: "Last PVC backup job failed"
```

---

## Off-Site Backup (Optional)

### Sync to S3

```bash
# Install AWS CLI
apt-get install awscli

# Configure credentials
aws configure

# Sync backups to S3
aws s3 sync /var/backups/k8s-pvc/ s3://your-bucket/k8s-backups/akash-provider/ \
  --storage-class STANDARD_IA \
  --delete

# Set up lifecycle policy (90-day retention)
aws s3api put-bucket-lifecycle-configuration \
  --bucket your-bucket \
  --lifecycle-configuration file:///tmp/s3-lifecycle.json
```

### Sync to Rclone Destination

```bash
# Install rclone
curl https://rclone.org/install.sh | sudo bash

# Configure remote
rclone config create s3-backup s3 ...
rclone config create b2-backup b2 ...

# Sync backups
rclone sync /var/backups/k8s-pvc/ s3-backup:k8s-backups/akash-provider/ \
  --backup-dir s3-backup:k8s-backups/.akash-provider-rclone

# Add to cron for daily sync
0 3 * * * rclone sync /var/backups/k8s-pvc/ s3-backup:k8s-backups/
```

---

## Verification Checklist

- [ ] Backup script created and executable
- [ ] Manual backup tested successfully
- [ ] Backup file verified (not empty, correct size)
- [ ] Automated backup scheduled (CronJob or systemd timer)
- [ ] Backup retention policy configured (30 days)
- [ ] Off-site backup configured (S3, B2, etc.)
- [ ] Recovery procedure tested
- [ ] Monitoring alerts configured
- [ ] Backup documentation complete

---

## Troubleshooting

### Backup Fails with "No PVC found"

**Problem**: PVC name or namespace is incorrect
**Solution**:
```bash
kubectl get pvc -n akash-services
# Verify PVC name matches script
```

### Backup Fails with "Pod scheduling timeout"

**Problem**: Node is unavailable or has taints
**Solution**:
```bash
kubectl get nodes
kubectl describe node <node-name>
# Remove taints if needed: kubectl taint nodes <node> key:NoSchedule-
```

### Backup File is Empty or Small

**Problem**: PVC mount failed or data is elsewhere
**Solution**:
```bash
# Check actual PVC usage
kubectl exec -it backup-pod -- df -h /data
# Verify path mapping
kubectl exec -it backup-pod -- ls -la /data
```

### Recovery Doesn't Work

**Problem**: Provider can't import key from backup
**Solution**: Use mnemonic recovery instead (see wallet backup procedure)

---

## Security Considerations

### Backup Encryption

```bash
# Encrypt backups with gpg
tar czf - /data | gpg --encrypt --recipient admin@reverb256.ca > backup.tar.gz.gpg

# Decrypt
gpg --decrypt backup.tar.gz.gpg | tar xzf -
```

### Access Control

```bash
# Restrict backup directory access
chmod 700 /var/backups/k8s-pvc/
chown root:root /var/backups/k8s-pvc/

# Restrict script access
chmod 700 /etc/nixos/scripts/backup-pvc.sh
chown root:root /etc/nixos/scripts/backup-pvc.sh
```

---

**Next Steps**:
1. ⏳ Deploy CronJob or systemd timer
2. ⏳ Configure off-site backup (S3/B2)
3. ⏳ Set up monitoring alerts
4. ⏳ Test recovery procedure
5. ⏳ Document backup locations

**Owner**: Cluster Operations Team
**Review Date**: 2026-03-29
