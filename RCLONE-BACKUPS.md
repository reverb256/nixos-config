# Rclone Cloud Backups for OpenClaw AIStor

## Overview
Automated cloud backups for your AIStor data using rclone. Supports multiple cloud providers with scheduled backups via systemd timers.

## Supported Cloud Providers

| Provider | Remote Name | Cost | Best For |
|----------|-------------|------|----------|
| **Google Drive** | `gdrive` | Free 15GB | Small backups, easy setup |
| **Backblaze B2** | `b2` | $0.005/GB/month | Cost-effective, S3-compatible |
| **Wasabi** | `wasabi` | $6.99/TB/month | Unlimited egress, predictable cost |
| **AWS S3** | `s3` | Pay per use | Enterprise, glacier archiving |
| **Azure Blob** | `azure` | Pay per use | Microsoft ecosystem |
| **Dropbox** | `dropbox` | Free 2GB | Sync and share |

## Quick Setup

### Option A: Interactive Setup Script

```bash
# Run the setup script
sudo -u lobster -i ~/@projects/infra/nixos/scripts/setup-rclone-cloud-backups.sh
```

This will:
1. Configure rclone with your chosen cloud provider
2. Set up AIStor as an S3 remote
3. Create backup scripts
4. Optionally set up automated systemd timers

### Option B: NixOS Module (Recommended)

Enable in your host configuration:

```nix
# hosts/zephyr/configuration.nix
{
  imports = [
    ../../modules/openclaw-backups.nix
  ];

  services.openclaw-backups = {
    enable = true;
    remote = "gdrive";  # or b2, s3, wasabi, etc.
    buckets = [ "ai-models" "experiments" ];
    interval = "daily";  # systemd calendar format
    user = "lobster";
    aistorEndpoint = "http://10.1.1.120:9000";
  };
}
```

Then deploy:
```bash
just deploy-zephyr
```

## Manual Configuration

### Step 1: Configure Cloud Remote

```bash
# Switch to lobster user
sudo -u lobster -i

# Configure your cloud provider
rclone config

# Follow prompts for your provider:
# - Google Drive: Select 'drive', follow OAuth flow
# - Backblaze B2: Select 'b2', enter account ID and key
# - Wasabi: Select 's3', enter access/secret keys, set endpoint
```

### Step 2: Configure AIStor Remote

```bash
# Create AIStor S3 remote
rclone config create aistor s3 \
  provider=Minio \
  env_auth=false \
  access_key_id=minioadmin \
  secret_access_key=your-password \
  endpoint=http://10.1.1.120:9000 \
  region=us-east-1 \
  force_path_style=true
```

### Step 3: Test Configuration

```bash
# List AIStor buckets
rclone ls aistor:

# List your cloud storage
rclone ls gdrive:  # or your remote name

# Test sync (dry run)
rclone sync aistor:ai-models gdrive:openclaw-ai-models-backup --dry-run
```

## Backup Commands

### Manual Backup

```bash
# Backup specific bucket
rclone sync aistor:ai-models gdrive:openclaw-ai-models-backup

# Backup experiments
rclone sync aistor:experiments gdrive:openclaw-experiments-backup

# Backup with progress and logging
rclone sync aistor:ai-models gdrive:openclaw-ai-models-backup \
  --progress \
  --log-file /var/lib/lobster/storage/logs/backup-$(date +%Y%m%d).log
```

### Automated Backups

If using the NixOS module, backups run automatically via systemd timer:

```bash
# Check timer status
systemctl status openclaw-backup.timer

# View scheduled backups
systemctl list-timers openclaw-backup.timer

# Trigger manual backup
systemctl start openclaw-backup.service

# View backup logs
journalctl -u openclaw-backup.service -f
```

### Using Backup Scripts

```bash
# Run all backups
/etc/openclaw/backup-all.sh

# Or individual buckets
/etc/openclaw/backup-models.sh
/etc/openclaw/backup-experiments.sh
```

## Provider-Specific Setup

### Google Drive

1. **Create OAuth credentials:**
   - Visit https://console.cloud.google.com/
   - Create a new project
   - Enable Google Drive API
   - Create OAuth 2.0 credentials
   - Download client ID and secret

2. **Configure rclone:**
   ```bash
   rclone config create gdrive drive \
     client_id=YOUR_CLIENT_ID \
     client_secret=YOUR_CLIENT_SECRET \
     scope=drive
   
   # Authenticate
   rclone config reconnect gdrive:
   ```

3. **Folder setup:**
   - Backups go to `openclaw-ai-models-backup/` and `openclaw-experiments-backup/`
   - Create these folders in Google Drive first (optional)

### Backblaze B2

1. **Get credentials:**
   - Sign up at https://www.backblaze.com/b2
   - Create a bucket (or use rclone to create)
   - Generate Application Key

2. **Configure rclone:**
   ```bash
   rclone config create b2 b2 \
     account=YOUR_ACCOUNT_ID \
     key=YOUR_APPLICATION_KEY
   ```

3. **Bucket naming:**
   - rclone will create `openclaw-ai-models-backup` and `openclaw-experiments-backup` buckets
   - Or use existing buckets with `--s3-bucket` flag

### Wasabi

1. **Get credentials:**
   - Sign up at https://wasabi.com
   - Create access keys in console

2. **Configure rclone:**
   ```bash
   rclone config create wasabi s3 \
     provider=Wasabi \
     env_auth=false \
     access_key_id=YOUR_ACCESS_KEY \
     secret_access_key=YOUR_SECRET_KEY \
     endpoint=s3.wasabisys.com \
     region=us-east-1
   ```

## Advanced Options

### Bandwidth Limiting

```bash
# Limit to 10MB/s upload
rclone sync aistor:ai-models gdrive:openclaw-ai-models-backup \
  --bwlimit 10M
```

### Exclude Patterns

```bash
# Exclude temporary files
rclone sync aistor:ai-models gdrive:openclaw-ai-models-backup \
  --exclude ".tmp/**" \
  --exclude "*.temp" \
  --exclude "checkpoint-*.pt"
```

### Encryption

```bash
# Encrypt backups with rclone crypt
rclone config create crypt remote=gdrive:openclaw-encrypted \
  filename_encryption=standard \
  directory_name_encryption=true \
  password=YOUR_PASSWORD

# Sync to encrypted remote
rclone sync aistor:ai-models crypt:ai-models
```

### Multi-Remote Backups

```bash
# Backup to multiple clouds
/etc/openclaw/backup-all.sh gdrive
/etc/openclaw/backup-all.sh b2

# Or use a script
for remote in gdrive b2 wasabi; do
    echo "Backing up to $remote..."
    rclone sync aistor:ai-models "$remote:openclaw-ai-models-backup"
done
```

## Monitoring

### Check Backup Status

```bash
# View backup logs
ls -la /var/lib/lobster/storage/logs/
tail -f /var/lib/lobster/storage/logs/backup-$(date +%Y%m%d).log

# Check cloud storage usage
rclone size gdrive:openclaw-ai-models-backup
rclone size aistor:ai-models
```

### Alerting

Add to your backup scripts:

```bash
#!/bin/bash
# backup-with-alert.sh

if ! rclone sync aistor:ai-models gdrive:openclaw-ai-models-backup; then
    # Send alert (replace with your notification method)
    echo "Backup failed!" | mail -s "OpenClaw Backup Alert" admin@example.com
    exit 1
fi
```

## Troubleshooting

### Authentication Issues

```bash
# Re-authenticate a remote
rclone config reconnect gdrive:

# Check remote status
rclone about gdrive:
```

### Rate Limiting

```bash
# Add delays between transfers
rclone sync aistor:ai-models gdrive:openclaw-ai-models-backup \
  --tpslimit 10 \
  --transfers 2
```

### Large File Issues

```bash
# Enable chunked transfer for large models
rclone sync aistor:ai-models gdrive:openclaw-ai-models-backup \
  --s3-chunk-size 100M \
  --s3-upload-cutoff 200M
```

### Network Timeouts

```bash
# Increase timeouts
rclone sync aistor:ai-models gdrive:openclaw-ai-models-backup \
  --timeout 10m \
  --retries 5 \
  --low-level-retries 10
```

## Cost Optimization

### Free Tier Management

| Provider | Free Tier | Strategy |
|----------|-----------|----------|
| Google Drive | 15GB | Keep only critical models |
| Dropbox | 2GB | Use for configs only |
| Backblaze B2 | 10GB/day egress | Archive old experiments |
| Wasabi | None | Delete after 90 days |

### Automated Cleanup

```bash
# Delete old backups (keep last 30 days)
rclone delete gdrive:openclaw-ai-models-backup --min-age 30d

# Or use lifecycle policies (provider-specific)
```

## Integration with OpenClaw Workflows

The OpenClaw workflows can automatically trigger cloud backups:

```python
# In openclaw-aistor-workflows.py
async def training_checkpoint_workflow(self, run_id, local_path, metrics):
    # ... existing code ...
    
    # Trigger cloud backup if high accuracy
    if metrics.get("accuracy", 0) > 0.95:
        await self.backup_to_cloud("models", "gdrive")
    
    return {"success": True, "backed_up": metrics.get("accuracy", 0) > 0.95}
```

## Security Best Practices

1. **Encrypt credentials**: Use agenix for rclone config files
2. **Limit permissions**: Create dedicated cloud accounts with minimal access
3. **Rotate keys**: Regularly rotate cloud access keys
4. **Monitor access**: Enable access logging on cloud buckets
5. **Local-only AIStor**: Keep AIStor on internal network only

## References

- [rclone Documentation](https://rclone.org/)
- [rclone S3 Backend](https://rclone.org/s3/)
- [Backblaze B2 Pricing](https://www.backblaze.com/b2/cloud-storage-pricing.html)
- [Wasabi Pricing](https://wasabi.com/cloud-storage-pricing/)
- [OpenClaw AIStor Workflows](~/@projects/infra/nixos/scripts/openclaw-aistor-workflows.py)
