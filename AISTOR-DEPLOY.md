# AIStor Deployment Guide

## Overview
This document describes how to deploy AIStor (S3-compatible object storage) on the nexus node and configure it for AI/ML workloads.

## Architecture
- **Server**: nexus (10.1.1.120:9000) - AIStor/MinIO server
- **Client**: zephyr - Uses AIStor as private S3 cache and OpenClaw storage backend
- **Buckets**: ai-models, training-data, experiments, ai-logs, nix-cache

## Prerequisites

### 1. Generate MinIO Root Credentials
On nexus, you need to set the MinIO root user credentials. You can do this via:

```bash
# Option A: Environment file (recommended)
sudo mkdir -p /etc/minio
echo 'MINIO_ROOT_USER=minioadmin' | sudo tee /etc/minio/minio-root.env
echo 'MINIO_ROOT_PASSWORD=your-secure-password-here' | sudo tee -a /etc/minio/minio-root.env

# Option B: Via nix configuration (edit hosts/nexus/configuration.nix)
# Add to services.minio.environmentFile = "/etc/minio/minio-root.env";
```

### 2. Create and Encrypt Cache Credentials

For zephyr to access the nix-cache bucket, you need to create an encrypted credentials file:

```bash
# Enter the nixos devshell to get agenix
direnv allow  # or: nix develop

# Create the plaintext credentials file
cat > /tmp/minio-cache-credentials << 'EOF'
MINIO_ACCESS_KEY=minioadmin
MINIO_SECRET_KEY=your-secure-password-here
EOF

# Encrypt it with agenix (encrypts for all 4 hosts)
age -r age175jstqazl7sj20xzuhc4l9qn0xt0ag0nvh2paxkk6veav95se4ysjua4e5 \
    -r age19r77h4d3d93fla0ptc4zu3yvdxhvykdusd23c5wmrmzut55rn96qk0kc3n \
    -r age1chus24x5vg85993trehnms4gndw9e7qm0m3z5q65997c8az7rf6svffh4w \
    -r age14duc9p3yrmelfjd94tfkzgenpfcfarucn3ax6ygl0w4erh9p0ddqr674ly \
    -o secrets/minio-cache-credentials.age \
    /tmp/minio-cache-credentials

# Clean up plaintext
shred -u /tmp/minio-cache-credentials

# Verify
cat secrets/minio-cache-credentials.age
```

### 3. Configure nexus for MinIO

Edit `hosts/nexus/configuration.nix` to add the environment file:

```nix
services.minio = {
  enable = true;
  listenAddress = "10.1.1.120:9000";
  consoleAddress = "10.1.1.120:9001";
  region = "us-east-1";
  dataDir = "/var/lib/minio";
  environmentFile = "/etc/minio/minio-root.env";  # Add this line
};
```

## Deployment Steps

### Step 1: Deploy nexus (AIStor Server)

```bash
just deploy-nexus
```

This will:
- Start MinIO/AIStor on 10.1.1.120:9000
- Open firewall ports 9000 and 9001
- Create data directory at /var/lib/minio

### Step 2: Configure MinIO Client (mc)

After deployment, configure the MinIO client:

```bash
# SSH to nexus
ssh nexus

# Set up alias
mc alias set aistor http://10.1.1.120:9000 minioadmin your-secure-password

# Verify connection
mc admin info aistor
```

### Step 3: Create Buckets

```bash
# Create all buckets
for bucket in ai-models training-data experiments ai-logs nix-cache; do
    mc mb aistor/$bucket
done

# Verify
mc ls aistor
```

### Step 4: Configure Bucket Features

Run the setup script:

```bash
cd /etc/nixos
./scripts/setup-aistor-full-capabilities.sh
```

This configures:
- Lifecycle policies (auto-tiering and expiry)
- Object versioning
- Bucket policies (public/private access)
- Object locking (WORM)
- Quotas

### Step 5: Deploy zephyr (Cache Client)

```bash
just deploy-zephyr
```

This will:
- Enable the nix-cache S3 backend
- Configure OpenClaw Storage MCP (if enabled)
- Set up mc alias pointing to nexus

### Step 6: Test Configuration

```bash
# Test S3 cache upload
nix store info --store s3://nix-cache?endpoint=http://10.1.1.120:9000

# Test OpenClaw workflows (if enabled)
python3 /etc/nixos/scripts/openclaw-aistor-workflows.py checkpoint \
    --run-id test-001 \
    --model-path /path/to/test-model.pt \
    --metrics '{"accuracy": 0.95}'

# Test storage stats
mc du aistor/
```

## OpenClaw Storage MCP

### Enable on zephyr

Edit `hosts/zephyr/configuration.nix`:

```nix
imports = [
  # ... other imports ...
  ../../modules/openclaw-storage.nix
];

services.openclaw-storage = {
  enable = true;
  aistorCredentialsFile = config.age.secrets.minio-cache-credentials.path;
  rcloneConfigFile = "/var/lib/lobster/.config/rclone/rclone.conf";
};
```

### Usage Examples

```bash
# Natural language commands
echo '{"command": "natural_language", "params": {"query": "store model from /path/to/model.pt"}}' | \
    python3 modules/openclaw-storage-mcp.py

# Direct commands
echo '{"command": "get_storage_stats", "params": {}}' | \
    python3 modules/openclaw-storage-mcp.py

# Backup to cloud
echo '{"command": "backup_to_cloud", "params": {"bucket_type": "models", "cloud_remote": "gdrive"}}' | \
    python3 modules/openclaw-storage-mcp.py
```

## Rclone Cloud Backups

### Setup rclone

```bash
# SSH to zephyr as lobster user
sudo -u lobster -i

# Configure rclone
rclone config
# Follow prompts to add Google Drive (gdrive) or other remotes

# Test
rclone listremotes
```

### Automated Backups

The OpenClaw workflows can automatically trigger cloud backups when high-accuracy models are detected. Configure thresholds in the workflow scripts.

## Monitoring

### Check AIStor Status

```bash
# Server info
mc admin info aistor

# Bucket usage
mc du aistor/

# Bucket stats
for bucket in ai-models training-data experiments ai-logs nix-cache; do
    echo "=== $bucket ==="
    mc du aistor/$bucket
done
```

### Systemd Services

```bash
# Check AIStor server (on nexus)
systemctl status minio

# Check OpenClaw Storage (on zephyr)
systemctl status openclaw-storage

# View logs
journalctl -u minio -f
journalctl -u openclaw-storage -f
```

## Troubleshooting

### Connection Refused
- Check firewall: `sudo iptables -L -n | grep 9000`
- Verify MinIO is running: `systemctl status minio`
- Check network connectivity: `curl http://10.1.1.120:9000/minio/health/live`

### Authentication Failed
- Verify credentials file exists and is decrypted: `ls -la /run/agenix/minio-cache-credentials`
- Check file contents: `sudo cat /run/agenix/minio-cache-credentials`
- Ensure mc alias uses correct credentials: `mc alias list`

### Permission Denied
- Check MinIO policies: `mc policy list aistor/nix-cache`
- Verify bucket exists: `mc ls aistor`
- Check user permissions (lobster user needs access)

## Free Tier Management

AIStor Free License:
- **Cost**: $0
- **Deployment**: Single-node
- **Storage**: Unlimited (disk-limited)
- **API**: Full S3 compatibility
- **Limits**: No distributed mode, limited enterprise features

Use the free tier monitoring script:
```bash
./scripts/free-tier-monitor.sh
```

## Security Considerations

1. **Root credentials**: Keep MINIO_ROOT_PASSWORD secure, rotate regularly
2. **Network**: AIStor is on internal network only (10.1.1.120)
3. **Firewall**: Only ports 9000/9001 open, restrict to cluster IPs if needed
4. **Encryption**: Use agenix for all credential storage
5. **Access**: Create separate users/buckets per workload, don't use root for apps

## Next Steps

1. ✅ Deploy AIStor server to nexus
2. ✅ Create buckets and configure lifecycle
3. ✅ Set up cache credentials on zephyr
4. ✅ Enable OpenClaw Storage MCP
5. ✅ Configure rclone for cloud backups
6. 🔄 Test training checkpoint workflow
7. 🔄 Set up monitoring and alerting
8. 🔄 Configure automatic cleanup policies

## References

- [AIStor Documentation](https://min.io/docs/aistor)
- [MinIO S3 API](https://min.io/docs/minio/linux/reference/minio-mc)
- [OpenClaw Workflows](/etc/nixos/scripts/openclaw-aistor-workflows.py)
- [NixOS MinIO Module](https://search.nixos.org/options?channel=unstable&show=services.minio.enable)
