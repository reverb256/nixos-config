# 🎯 NixOS Distributed Build System & AI Cluster

[![NixOS](https://img.shields.io/badge/NixOS-26.05-blue.svg)](https://nixos.org)
[![Flakes](https://img.shields.io/badge/Flakes-Enabled-5277C3)](https://nixos.wiki/wiki/Flakes)
[![Colmena](https://img.shields.io/badge/Colmena-0.4.0-9cf)](https://colmena.cli.rs)
[![MIT License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Garnix Build](https://img.shields.io/endpoint.svg?url=https%3A%2F%2Fgarnix.io%2Fapi%2Fbadge%2Fgithub.com%2Fyour-username%2Fyour-repo)](https://garnix.io)

A comprehensive NixOS flake-based configuration for a high-performance distributed build cluster with VR gaming, cryptocurrency mining, and AI capabilities.

## 🏗️ Architecture Overview

### **Cluster Nodes**
| Host | IP Address | Role | CPU Cores | Memory | GPU | Purpose |
|------|------------|------|-----------|--------|-----|---------|
| **zephyr** | 10.1.1.110 | Master Node | 32 cores (Ryzen 9 5950X) | 64GB | RTX 3090 | VR Gaming, Development, Build Coordination |
| **nexus** | 10.1.1.120 | Build/AIStor | 24 cores (Ryzen 9 3900X) | 32GB | 2x RTX 3060 Ti | Distributed Builds, AIStor Storage |
| **forge** | 10.1.1.130 | GPU Compute | 6 cores | 32GB | 2x RTX 4060 + 2x RX 5700 XT | GPU Compute, Mining |
| **sentry** | 10.1.1.140 | Monitoring | 8 cores (Ryzen 7 1700) | 32GB | RX 5600 XT | Monitoring, Light Builds |

**Total Build Capacity:** **51 cores** across all hosts

### **Network Topology**
```
Internet ── Router (10.1.1.1)
                    │
                    ├── zephyr (10.1.1.110) - Master Workstation
                    ├── nexus  (10.1.1.120) - Build/AIStor Server
                    ├── forge  (10.1.1.130) - Mining/Build Worker
                    └── sentry (10.1.1.140) - Monitoring Server
```

## 🚀 Key Features

### **🏭 Distributed Build System**
- **51-core cluster** with SSH-based remote building
- **Binary cache integration** with multiple substituters (Garnix, Cuda Maintainers)
- **Trusted user authentication** for restricted settings
- **Real-time build monitoring** and status tracking
- **High availability** with automatic failover

### **🤖 AI Orchestration (OpenClaw)**
- **Declarative container deployment** for consistency
- **AIStor object storage** for model artifacts and training data
- **MCP server integration** for AI assistants (Kilo Code, Claude Code)
- **RAG support** with AIStor vector database capabilities
- **Health monitoring** with auto-restart on failure

### **🎮 VR Gaming & Mining**
- **SteamVR/WiVRn support** with Quest Pro streaming (100Mbps HEVC)
- **Smart mining pause** during gaming/VR sessions (auto-detects applications)
- **GameMode integration** with NVIDIA +150MHz overclock
- **GPU mining** (lolMiner) and CPU mining (XMRig)
- **Performance monitoring** across all hosts

### **🛡️ Security**
- **Agenix encrypted secrets** management
- **Systemd hardening** with NoNewPrivileges and PrivateTmp
- **Lobster user isolation** (no sudo access for AI services)
- **Nginx reverse proxy** with SSL/TLS and IP allowlisting
- **Localhost-only service binding** for security

## 📋 Quick Start

### **Prerequisites**
- NixOS 26.05+ with flakes enabled
- SSH access to cluster nodes
- Git for version control
- Agenix for secret management

### **Initial Setup**
```bash
# Clone the repository
git clone <repository-url> /etc/nixos
cd /etc/nixos

# Enter development shell
direnv allow

# Format and lint code
just dev-setup

# Deploy to local system
just switch
```

### **Cluster Deployment**
```bash
# Deploy to all hosts
just cluster-deploy

# Check cluster status
just cluster-status

# Monitor resources
just cluster-resources
```

## 📖 Documentation

### **Architecture**
- **[ARCHITECTURE.md](docs/ARCHITECTURE.md)** - Complete system design and architecture
- **[PORTFOLIO.md](docs/PORTFOLIO.md)** - Technical achievements and portfolio showcase

### **Setup & Deployment**
- **[SETUP.md](docs/SETUP.md)** - Step-by-step setup guide
- **[DEPLOYMENT_INSTRUCTIONS.md](docs/DEPLOYMENT_INSTRUCTIONS.md)** - Detailed deployment instructions
- **[QUICK_START.md](docs/QUICK_START.md)** - Fast track to running the cluster

### **Development**
- **[CONTRIBUTING.md](docs/CONTRIBUTING.md)** - Development guidelines
- **[AGENTS.md](docs/AGENTS.md)** - Comprehensive system documentation
- **[SECURITY_AUDIT.md](docs/SECURITY_AUDIT.md)** - Security hardening guide

### **Maintenance**
- **[QUICK_FIXES.md](docs/QUICK_FIXES.md)** - Immediate security and performance improvements
- **[PERFORMANCE_OPTIMIZATION_PLAN.md](docs/PERFORMANCE_OPTIMIZATION_PLAN.md)** - System optimization
- **[CONSOLIDATION_PLAN.md](docs/CONSOLIDATION_PLAN.md)** - Infrastructure consolidation guide

## 🛠️ Usage

### **System Management**
```bash
# Update and switch system
just switch

# Clean old generations
just clean

# Check system performance
just perf-monitor
```

### **Distributed Builds**
```bash
# Build with distributed compilation (51 cores!)
nix build --builders-use-substitutes nixpkgs#package-name

# Monitor build status
just build-stats
```

### **Mining Operations**
```bash
# Start GPU mining (auto-pauses during gaming)
just mining-start

# Check mining status across cluster
just mining-status

# Stop mining
just mining-stop
```

### **Gaming Mode**
```bash
# Enable gaming optimizations
just gaming-start

# Check gaming status and VR apps
just gaming-status

# Manual mining pause (for testing)
just gaming-trigger
```

## 🔧 Configuration Structure

```
/etc/nixos/
├── flake.nix                 # Main flake with Colmena hosts
├── configuration.nix        # Shared cluster configuration
├── home.nix                 # Home Manager user configuration
├── justfile                 # Automation and management commands
├── colmena.nix              # Cluster deployment config
├── hosts/                   # Host-specific configurations
│   ├── zephyr/              # Master workstation
│   ├── nexus/               # Build/AIStor server
│   ├── forge/               # Mining/build worker
│   └── sentry/              # Monitoring server
├── modules/                 # Shared configuration modules
│   ├── openclaw-declarative-container.nix  # AI orchestration
│   ├── openclaw-storage.nix                 # AIStor integration
│   ├── openclaw-nginx.nix                   # Reverse proxy
│   ├── mining.nix                          # Mining services
│   ├── gaming.nix                          # VR/gaming setup
│   └── ...                                # Other modules
├── secrets/                 # Agenix encrypted secrets
└── scripts/                 # Automation scripts
    ├── setup/               # Initial setup
    ├── maintenance/         # Maintenance tasks
    ├── monitoring/          # Performance monitoring
    └── testing/             # Testing procedures
```

## 🎯 OpenClaw AI Platform

### **Services**
| Service | Port | Access | Purpose |
|---------|------|--------|---------|
| **openclaw** | 18789 | localhost only | AI agent gateway |
| **openclaw-storage** | 18800 | localhost only | AIStor S3 MCP |
| **nginx** | 80/443 | external | Reverse proxy with SSL |

### **Capabilities**
- **Natural language interface** for system operations
- **RAG (Retrieval Augmented Generation)** with AIStor vector DB
- **AI/ML integration** for data analysis and prediction
- **Automated backups** with rclone cloud sync
- **Health monitoring** with auto-healing

## 📊 AIStor Object Storage

### **Features**
- **S3-compatible API** for easy integration
- **AI/ML optimized** for training data and model storage
- **High durability** with erasure coding
- **RAG support** with vector database capabilities
- **Free single-node license** (AIStor Free)

### **Buckets**
- `ai-models`: Trained models and checkpoints
- `training-data`: Datasets and corpora
- `experiments`: ML experiment artifacts
- `ai-logs`: Training logs and metrics
- `nix-cache`: Nix binary cache

## 🔒 Security

### **Secret Management**
All secrets are encrypted using Agenix:
- API keys (Anthropic, OpenAI, Claude)
- Mining credentials and wallet addresses
- AIStor access keys
- OpenClaw gateway tokens

### **System Hardening**
```nix
# Systemd hardening for OpenClaw
systemd.services.openclaw-container-declarative.serviceConfig = {
  NoNewPrivileges = true;
  ProtectSystem = "strict";
  ProtectHome = true;
  PrivateTmp = true;
};
```

### **Network Security**
- All services bind to localhost by default
- External access only via Nginx reverse proxy
- VR streaming ports (9757-9760) restricted to local network
- Firewall rules managed in `modules/networking.nix`

## 🐛 Troubleshooting

### **Common Issues**
```bash
# Check OpenClaw status
systemctl status openclaw-container-declarative

# View container logs
journalctl -u openclaw-container-declarative -f

# Check AIStor connection
mc alias set aistor http://10.1.1.120:9000 $MINIO_ACCESS_KEY $MINIO_SECRET_KEY
mc ls aistor

# Check mining status
just mining-status

# Check VR/gaming mode
just gaming-status
```

## 📈 Performance Monitoring

### **System Metrics**
```bash
# Cluster overview
just cluster-info

# Resource usage
just cluster-resources

# Mining performance
just cluster-mining-status

# Build statistics
just build-stats
```

### **Health Checks**
```bash
# OpenClaw health
curl -s http://127.0.0.1:18789/health

# AIStor health
curl -s http://127.0.0.1:18800/health

# Nginx health
curl -s http://127.0.0.1/health
```

## 🤝 Contributing

We welcome contributions! Please see our [CONTRIBUTING.md](docs/CONTRIBUTING.md) for guidelines.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🌟 Showcase

For a detailed portfolio showcase of this infrastructure, see [PORTFOLIO.md](docs/PORTFOLIO.md).