# Setup Guide

This guide provides step-by-step instructions for setting up and deploying the NixOS cluster.

## Prerequisites

1. **NixOS 26.05 or later** with flakes enabled
2. **Git** for version control
3. **SSH access** to all cluster nodes with key-based authentication
4. **Agenix** for secret management

## Initial Setup

### 1. Clone the Repository
```bash
# Clone the repository to /etc/nixos
git clone <repository-url> /etc/nixos
cd /etc/nixos
```

### 2. Enter the Development Shell
```bash
# Allow direnv to automatically load the development environment
direnv allow

# The shell includes all necessary tools:
# - Nix formatters (alejandra) and linters (statix)
# - Cluster deployment tool (colmena)
# - Secret management (agenix)
# - AIStor tools (minio-client)
```

### 3. Verify Repository Health
```bash
# Format all files
just format

# Lint Nix files
just lint

# Check for dead code
deadnix .

# Verify flake
nix flake check
```

## Secret Management (Agenix)

### 1. Install Agenix (if not already installed)
```bash
# Already included in development shell
which agenix
```

### 2. Create Secrets Directory
```bash
# Secrets directory structure
cd /etc/nixos/secrets
ls -la

# Templates are in secrets/ directory with .template extension
# Copy templates and fill in with your actual secrets
```

### 3. Create Required Secrets

#### OpenClaw Environment
```bash
# Create openclaw-env.age (OpenClaw gateway environment variables)
agenix -e openclaw-env.age

# Add these variables:
OPENCLAW_GATEWAY_TOKEN=your_secret_token_here
```

#### AIStor Credentials
```bash
# Create minio-cache-credentials.age (AIStor S3 access)
agenix -e minio-cache-credentials.age

# Add these variables:
MINIO_ACCESS_KEY=your_access_key
MINIO_SECRET_KEY=your_secret_key
```

#### API Keys (Optional)
```bash
# For AI providers (if you use them)
agenix -e anthropic-api-key.age    # Anthropic API key
agenix -e openai-api-key.age       # OpenAI API key
agenix -e claude-api-key.age       # Claude API key
```

#### Mining Credentials
```bash
# For mining operations
agenix -e mining-wallet.age        # Mining wallet address
agenix -e mining-api-token.age     # Mining API token
```

### 4. Verify Secrets Configuration
```bash
# Check age secrets configuration
cat /etc/nixos/secrets/age-secrets.nix

# Verify secrets can be decrypted
agenix -d openclaw-env.age
```

## Host Configuration

### 1. Review Host-Specific Configurations
```bash
# Host configurations are in hosts/ directory
ls -la hosts/

# zephyr: Master workstation (RTX 3090)
# nexus: AIStor server (2x RTX 3060 Ti)
# forge: Mining/build worker (2x RTX 4060 + 2x RX 5700 XT)
# sentry: Monitoring server (RX 5600 XT)
```

### 2. Update Network Configuration
```bash
# Verify network settings in modules/networking.nix
cat /etc/nixos/modules/networking.nix
```

## Cluster Deployment

### 1. Deploy to All Hosts
```bash
# First build the cluster
just cluster-build

# Deploy to all hosts
just cluster-deploy

# Check deployment status
just cluster-status
```

### 2. Deploy to Specific Host
```bash
# Deploy to zephyr (master)
just deploy zephyr

# Deploy to nexus (AIStor)
just deploy nexus

# Deploy to forge (mining)
just deploy forge

# Deploy to sentry (monitoring)
just deploy sentry
```

### 3. Verify Deployment
```bash
# Check if OpenClaw is running on all hosts
just cluster-mining-status

# Check OpenClaw health
curl -s http://10.1.1.110:18789/health
curl -s http://10.1.1.120:18789/health
curl -s http://10.1.1.130:18789/health
curl -s http://10.1.1.140:18789/health
```

## Post-Deployment Verification

### 1. Check System Services
```bash
# On each host
systemctl status openclaw-container-declarative
systemctl status openclaw-storage
systemctl status nginx
```

### 2. Test OpenClaw
```bash
# Test gateway connection
curl -s http://127.0.0.1:18789/health

# Test storage MCP
curl -s http://127.0.0.1:18800/health
```

### 3. Test Mining
```bash
# Check mining status
just mining-status

# Start mining (auto-pauses during gaming/VR)
just mining-start
```

### 4. Test AIStor
```bash
# Configure minio-client
mc alias set aistor http://10.1.1.120:9000 $MINIO_ACCESS_KEY $MINIO_SECRET_KEY

# List buckets
mc ls aistor
```

### 5. Test VR Gaming
```bash
# Check WiVRn status
systemctl status wivrn

# Check SteamVR status
systemctl status steamvr
```

## Daily Operations

### System Management
```bash
# Update the system
just switch

# Clean old generations
just clean

# Check system performance
just perf-monitor
```

### Cluster Management
```bash
# Check cluster info
just cluster-info

# Check resource usage
just cluster-resources

# Update entire cluster
just cluster-update

# Clean old generations on all hosts
just cluster-clean
```

### Development Workflow
```bash
# Run development setup (format + lint)
just dev-setup

# Build without deploying
just cluster-build

# Search for packages
just search <package-name>
```

## Troubleshooting

### Common Issues

#### 1. OpenClaw Container Not Running
```bash
# Check container status
systemctl status openclaw-container-declarative

# View logs
journalctl -u openclaw-container-declarative -f

# Restart container
systemctl restart openclaw-container-declarative
```

#### 2. AIStor Connection Failed
```bash
# Check AIStor service
systemctl status minio

# Verify minio credentials are correct
agenix -d minio-cache-credentials.age

# Test connection
mc alias set aistor http://10.1.1.120:9000 $MINIO_ACCESS_KEY $MINIO_SECRET_KEY
mc ls aistor
```

#### 3. Mining Not Starting
```bash
# Check mining services
just mining-status

# Check if gaming mode is active (auto-pauses mining)
just gaming-status

# Start mining manually
just mining-start
```

#### 4. VR Streaming Issues
```bash
# Check WiVRn status
systemctl status wivrn

# Check firewall rules
sudo nft list ruleset

# Verify WiVRn configuration
cat /etc/nixos/modules/gaming.nix
```

## Maintenance

### Weekly Maintenance
```bash
# Update and deploy
just cluster-update

# Clean old generations
just cluster-clean

# Check for updates
nix flake update
```

### Monthly Maintenance
```bash
# Run full security audit
just security-audit

# Check disk usage
df -h

# Verify backups
rclone check aistor:ai-models gdrive:ai-models-backup
```

## Emergency Procedures

### Cluster Shutdown
```bash
# Emergency shutdown all services
just cluster-emergency-stop

# Stop specific service
just mining-stop
just gaming-stop
```

### Rollback to Previous Generation
```bash
# On individual host
sudo nixos-rebuild switch --rollback

# For cluster
just cluster-rollback
```

---

## Advanced Configuration

### Customizing OpenClaw
```nix
# In host configuration (hosts/zephyr/configuration.nix)
services.openclaw.declarative = {
  enable = true;
  port = 18789;
  gatewayMode = "local";
  gatewayBind = "127.0.0.1";
  environmentFile = "/run/agenix/openclaw-env";
  memory = "4G";
  cpuShares = 1024;
};
```

### Adding a New Host
1. Create new host directory: `mkdir -p hosts/<hostname>`
2. Create `configuration.nix` and `hardware-configuration.nix`
3. Update `flake.nix` to include new host
4. Update `colmena.nix` for cluster deployment
5. Deploy: `just deploy <hostname>`

### Adding a New Service
1. Create module file in `modules/`
2. Import module in `configuration.nix`
3. Add configuration options in module
4. Test: `just switch`
5. Deploy: `just cluster-deploy`

---

## Resources

- **NixOS Manual**: https://nixos.org/manual/nixos/stable/
- **Home Manager**: https://nix-community.github.io/home-manager/
- **Colmena**: https://colmena.cli.rs/
- **Agenix**: https://github.com/ryantm/agenix
- **AIStor**: https://aistorage.com/
- **OpenClaw**: https://github.com/openclaw/openclaw