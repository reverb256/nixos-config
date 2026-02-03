# AIStor Deployment Guide

**Version**: 2026-02-01 | **Security Hardened**

## Overview
This document describes how to deploy AIStor (S3-compatible object storage) on the nexus node and configure it for AI/ML workloads with the security-hardened OpenClaw infrastructure.

## Architecture
- **Server**: nexus (10.1.1.120:9000) - AIStor/MinIO server
- **Client**: zephyr - Uses AIStor as private S3 cache and OpenClaw storage backend
- **Buckets**: ai-models, training-data, experiments, ai-logs, nix-cache
- **Security**: All credentials encrypted with agenix, services isolated

## Security Model

### Service Isolation
- **Lobster user**: `isSystemUser = true` (no login, no sudo)
- **No privilege escalation**: AI service cannot become root
- **Localhost-only**: OpenClaw services bind to 127.0.0.1 only
- **Nginx proxy**: External access via SSL/TLS with rate limiting

### Credentials Management
All credentials are stored in `secrets/` directory and encrypted with agenix:
- `minio-cache-credentials.age` - AIStor S3 access keys
- `openclaw-env.age` - OpenClaw gateway environment

**Never store plaintext credentials in the repository!**

## Prerequisites

### 1. Set Up MinIO Root Credentials on Nexus

Create the root credentials file on nexus:

```bash
ssh nexus
sudo mkdir -p /etc/minio
sudo tee /etc/minio/minio-root.env << 'EOF'
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=your-secure-password-here
EOF
sudo chmod 600 /etc/minio/minio-root.env
```

**Important**: Choose a strong password and store it securely.

### 2. Create and Encrypt AIStor Credentials for OpenClaw

**Step A: Create the plaintext credentials file**

```bash
cd ~/@projects/infra/nixos

# Create credentials file
cat > /tmp/minio-cache-credentials << 'EOF'
MINIO_ACCESS_KEY=minioadmin
MINIO_SECRET_KEY=your-secure-password-here
EOF
```

**Step B: Encrypt with agenix**

```bash
# Get the age public keys from secrets.nix
cat secrets/secrets.nix

# Encrypt for all 4 hosts (use the public keys from secrets.nix)
age -r age175jstqazl7sj20xzuhc4l9qn0xt0ag0nvh2paxkk6veav95se4ysjua4e5 \
    -r age19r77h4d3d93fla0ptc4zu3yvdxhvykdusd23c5wmrmzut55rn96qk0kc3n \
    -r age1chus24x5vg85993trehnms4gndw9e7qm0m3z5q65997c8az7rf6svffh4w \
    -r age14duc9p3yrmelfjd94tfkzgenpfcfarucn3ax6ygl0w4erh9p0ddqr674ly \
    -o secrets/minio-cache-credentials.age \
    /tmp/minio-cache-credentials

# Clean up plaintext file
shred -u /tmp/minio-cache-credentials

# Verify the encrypted file exists
ls -la secrets/minio-cache-credentials.age
```

**Note**: The secrets file is now defined in `secrets/age-secrets.nix` and will be automatically decrypted at `/run/agenix/minio-cache-credentials` on each host.

### 3. Verify Secret Configuration

Check that `secrets/age-secrets.nix` includes:

```nix
"minio-cache-credentials" = {
  file = ./minio-cache-credentials.age;
};
```

And `configuration.nix` references it:

```nix
services.openclaw-storage = {
  enable = true;
  aistorCredentialsFile = "/run/agenix/minio-cache-credentials";
};
```

## Deployment Steps

### Step 1: Deploy nexus (AIStor Server)

```bash
cd ~/@projects/infra/nixos
just deploy-nexus
# or: colmena apply --on nexus
```

This will:
- Start MinIO/AIStor on 10.1.1.120:9000
- Open firewall ports 9000 and 9001 (only on nexus)
- Create data directory at /var/lib/minio
- Use the credentials from `/etc/minio/minio-root.env`

### Step 2: Verify AIStor is Running

```bash
ssh nexus

# Check service status
systemctl status minio

# Test health endpoint
curl http://10.1.1.120:9000/minio/health/live

# Should return 200 OK
```

### Step 3: Configure MinIO Client (mc)

After deployment, configure the MinIO client:

```bash
# SSH to nexus
ssh nexus

# Set up alias
mc alias set aistor http://10.1.1.120:9000 minioadmin your-secure-password

# Verify connection
mc admin info aistor
```

### Step 4: Create Buckets

```bash
# Create all buckets
for bucket in ai-models training-data experiments ai-logs nix-cache; do
    mc mb aistor/$bucket
done

# Verify
mc ls aistor
```

### Step 5: Configure Bucket Features

Run the setup script:

```bash
cd ~/@projects/infra/nixos
./scripts/setup-aistor-full-capabilities.sh
```

This configures:
- Lifecycle policies (auto-tiering and expiry)
- Object versioning for ai-models and experiments
- Bucket policies (public/private access)
- Object locking (WORM) for compliance
- Quotas and monitoring

### Step 6: Deploy zephyr (OpenClaw + Cache Client)

```bash
cd ~/@projects/infra/nixos
just deploy-zephyr
# or: colmena apply --on zephyr
```

This will:
- Enable the nix-cache S3 backend (using encrypted credentials)
- Start OpenClaw gateway on localhost:18789
- Start OpenClaw Storage MCP on localhost:18800
- Create the isolated lobster service user
- Enable 30-second health monitoring with auto-restart

### Step 7: Verify OpenClaw Services

```bash
ssh zephyr

# Check all OpenClaw services
systemctl status openclaw
systemctl status openclaw-storage
systemctl status openclaw-health.timer
systemctl status openclaw-storage-health.timer

# Test health endpoints
curl http://127.0.0.1:18789/health
curl http://127.0.0.1:18800/health

# View logs
journalctl -u openclaw -n 50
journalctl -u openclaw-health -n 20
```

### Step 8: Test Configuration

```bash
# Test S3 cache upload
nix store info --store s3://nix-cache?endpoint=http://10.1.1.120:9000

# Test OpenClaw workflows
python3 ~/@projects/infra/nixos/scripts/openclaw-aistor-workflows.py checkpoint \
    --run-id test-001 \
    --model-path /path/to/test-model.pt \
    --metrics '{"accuracy": 0.95}'

# Test storage stats
mc du aistor/
```

## Optional: Enable Nginx Reverse Proxy

For secure external access, enable nginx:

### 1. Edit Host Configuration

Edit `hosts/zephyr/configuration.nix`:

```nix
services.openclaw.nginx = {
  enable = true;
  domain = "openclaw.local";  # Or your domain
  enableSSL = false;  # Set true for Let's Encrypt (requires public domain)
  allowedIPs = [ "127.0.0.1" "::1" "10.0.0.0/8" "192.168.0.0/16" ];
};
```

### 2. Rebuild

```bash
just deploy-zephyr
```

### 3. Access Endpoints

```bash
# Via nginx (recommended)
curl http://openclaw.local/health
curl http://openclaw.local/gateway  # WebSocket
curl http://openclaw.local/storage/api/v1/buckets

# Direct access (localhost only)
curl http://127.0.0.1:18789/health
curl http://127.0.0.1:18800/health
```

## OpenClaw Storage MCP Usage

### Natural Language Commands

```bash
# Via MCP server
echo '{"command": "natural_language", "params": {"query": "store model from /path/to/model.pt"}}' | \
    python3 ~/@projects/infra/nixos/modules/openclaw-storage-mcp.py

# Direct commands
echo '{"command": "get_storage_stats", "params": {}}' | \
    python3 ~/@projects/infra/nixos/modules/openclaw-storage-mcp.py

# Backup to cloud
echo '{"command": "backup_to_cloud", "params": {"bucket_type": "models", "cloud_remote": "gdrive"}}' | \
    python3 ~/@projects/infra/nixos/modules/openclaw-storage-mcp.py
```

### Python API

```python
from openclaw_aistor_workflows import AIStorWorkflows

workflows = AIStorWorkflows()

# Store training checkpoint
result = await workflows.training_checkpoint_workflow(
    run_id="experiment-47",
    local_path="/models/final-model.pt",
    metrics={"accuracy": 0.947, "loss": 0.023}
)
# Automatically: stores model, logs metrics, triggers cloud backup if high accuracy
```

## Rclone Cloud Backups

### Setup rclone

```bash
# SSH to zephyr as lobster user
ssh zephyr
sudo -u lobster -i

# Configure rclone
rclone config
# Follow prompts to add Google Drive (gdrive) or other remotes

# Test
rclone listremotes
```

### Automated Backups

Enable automated backups in `configuration.nix`:

```nix
services.openclaw-backups = {
  enable = true;
  remote = "gdrive";  # or b2, wasabi, s3, etc.
  buckets = [ "ai-models" "experiments" ];
};
```

Then rebuild:
```bash
just deploy-zephyr
```

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

### Check OpenClaw Services

```bash
# Check all services
systemctl status openclaw openclaw-storage

# Check health monitoring
systemctl status openclaw-health.timer
systemctl status openclaw-storage-health.timer

# View logs
journalctl -u openclaw -f
journalctl -u openclaw-storage -f
journalctl -u openclaw-health -f
```

### Test Health Endpoints

```bash
# Gateway health
curl http://127.0.0.1:18789/health

# Storage MCP health
curl http://127.0.0.1:18800/health

# If nginx is enabled
curl http://openclaw.local/health
```

## Troubleshooting

### Connection Refused

```bash
# Check firewall
sudo iptables -L -n | grep 9000

# Verify MinIO is running
systemctl status minio

# Check network connectivity
curl http://10.1.1.120:9000/minio/health/live
```

### Authentication Failed

```bash
# Verify credentials file exists and is decrypted
ls -la /run/agenix/minio-cache-credentials

# Check file contents (should show MINIO_ACCESS_KEY and MINIO_SECRET_KEY)
sudo cat /run/agenix/minio-cache-credentials

# Ensure mc alias uses correct credentials
mc alias list
```

### Permission Denied

```bash
# Check MinIO policies
mc policy list aistor/nix-cache

# Verify bucket exists
mc ls aistor

# Check user permissions (lobster user needs access)
id lobster
groups lobster  # Should show lobster and rclone only
```

### Service Won't Start

```bash
# Check for port conflicts
ss -tlnp | grep 18789
ss -tlnp | grep 18800

# Check logs
journalctl -u openclaw -n 100
journalctl -u openclaw-storage -n 100

# Verify configuration syntax
nixos-rebuild test --flake .#zephyr
```

## Security Best Practices

### Credentials Management
1. **Rotate regularly**: Change MinIO credentials monthly
   ```bash
   agenix -e secrets/minio-cache-credentials.age
   ```
2. **Never commit plaintext**: Always use `*.age` encrypted files
3. **Limit access**: Only decrypt credentials on hosts that need them

### Network Security
1. **AIStor internal only**: Never expose port 9000/9001 externally
2. **Use nginx for external access**: SSL/TLS + rate limiting
3. **IP allowlisting**: Restrict nginx access to known IPs
   ```nix
   services.openclaw.nginx.allowedIPs = [ "10.0.0.0/8" "192.168.0.0/16" ];
   ```

### Service Isolation
1. **Lobster has no sudo**: Verify with `sudo -u lobster sudo whoami` (should fail)
2. **Services bind to localhost**: Verify with `ss -tlnp | grep 18789`
3. **Systemd hardening enabled**: Check with `systemctl cat openclaw`

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

## Deployment Checklist

- [ ] Create `/etc/minio/minio-root.env` on nexus with strong password
- [ ] Encrypt `minio-cache-credentials.age` with agenix
- [ ] Verify `secrets/age-secrets.nix` includes the secret
- [ ] Run `just check` to validate flake
- [ ] Deploy to nexus first
- [ ] Verify AIStor is running: `systemctl status minio`
- [ ] Create buckets with mc
- [ ] Run `setup-aistor-full-capabilities.sh`
- [ ] Deploy to zephyr
- [ ] Verify OpenClaw services: `systemctl status openclaw openclaw-storage`
- [ ] Test health endpoints: `curl http://127.0.0.1:18789/health`
- [ ] Verify lobster security: `sudo -u lobster sudo whoami` (should fail)
- [ ] (Optional) Enable nginx for external access
- [ ] (Optional) Configure cloud backups

## Next Steps

1. ✅ Deploy AIStor server to nexus
2. ✅ Create buckets and configure lifecycle
3. ✅ Set up encrypted credentials for zephyr
4. ✅ Enable OpenClaw Storage MCP
5. ✅ Configure health monitoring
6. ✅ Security harden services
7. 🔄 Test training checkpoint workflow
8. 🔄 Set up Prometheus/Grafana monitoring
9. 🔄 Configure automatic cleanup policies

## References

- [AIStor Documentation](https://min.io/docs/aistor)
- [MinIO S3 API](https://min.io/docs/minio/linux/reference/minio-mc)
- [OpenClaw Workflows](~/@projects/infra/nixos/scripts/openclaw-aistor-workflows.py)
- [NixOS MinIO Module](https://search.nixos.org/options?channel=unstable&show=services.minio.enable)
- [Agenix Documentation](https://github.com/ryantm/agenix)

---

*Updated: 2026-02-01*
*Security Hardening: Complete*
*Branch: feature/openclaw-secure*
