# 4-Node NixOS Cluster with OpenClaw AI Integration

This repository contains the NixOS configuration for a 4-node cluster with distributed builds, CI/CD, and OpenClaw AI node management.

## Cluster Topology

- **zephyr** (10.1.1.110): Main node with OpenClaw gateway, primary compute
- **nexus** (10.1.1.120): AI Storage (AIStor) and build node
- **forge** (10.1.1.130): GPU mining and compute node  
- **sentry** (10.1.1.140): Monitoring and secondary compute

## Features Implemented

### 1. Distributed Builds
- Configured across all 4 nodes using Nix's distributed build system
- nexus: 6 max jobs
- forge: 3 max jobs
- sentry: 4 max jobs
- Adaptive configuration that scales based on cluster availability

### 2. Colmena Cluster Management
- Centralized deployment configuration
- Single command deployment to all nodes
- Host-specific configurations in `/etc/nixos/hosts/`

### 3. GitHub Actions CI/CD
- `.github/workflows/ci.yml`: Continuous integration testing
- `.github/workflows/deploy.yml`: Production deployment
- `.github/workflows/openclaw-nodes.yml`: Node management

### 4. OpenClaw Multi-Node Setup
- Gateway running on zephyr (port 18789)
- Node pairing and management capabilities
- Scripts to facilitate node joining

## Deployment

### Local Deployment
```bash
# Apply configuration to local node
sudo nixos-rebuild switch
```

### Cluster Deployment
```bash
# Deploy to all nodes
cd /etc/nixos
colmena apply --on-change build

# Deploy to specific node
colmena apply --on-change build --target nexus
```

### Testing Distributed Builds
```bash
# Test distributed build functionality
nix build --dry-run -L nixpkgs.hello
```

## OpenClaw Node Management

### Check Node Status
```bash
openclaw nodes status
openclaw nodes list
openclaw nodes pending
```

### Approve New Nodes
```bash
openclaw nodes approve <node-id>
```

## Repository Structure

```
/etc/nixos/                    # Main configuration
├── configuration.nix          # Base configuration
├── hosts/                     # Host-specific configs
│   ├── zephyr/
│   ├── nexus/
│   ├── forge/
│   └── sentry/
├── modules/                   # Custom modules
├── .github/workflows/         # GitHub Actions
├── scripts/                   # Utility scripts
└── colmena.nix               # Cluster deployment config
```

## Getting Started

1. Clone this repository to `/etc/nixos/`
2. Run `sudo nixos-rebuild switch` to apply local configuration
3. Test distributed builds connectivity
4. Deploy to cluster using colmena
5. Set up OpenClaw nodes on remaining devices
6. Push changes to GitHub to activate CI/CD pipelines

## Scripts

- `scripts/deploy-cluster.sh`: Deploy complete cluster configuration
- `scripts/setup-openclaw-nodes.sh`: Set up OpenClaw node pairing