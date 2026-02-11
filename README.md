# 🎯 Reverb-OS: Personal AI Assistant Platform

[![NixOS](https://img.shields.io/badge/NixOS-26.05-blue.svg)](https://nixos.org)
[![Flakes](https://img.shields.io/badge/Flakes-Enabled-5277C3)](https://nixos.wiki/wiki/Flakes)
[![Colmena](https://img.shields.io/badge/Colmena-0.4.0-9cf)](https://colmena.cli.rs)
[![MIT License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Garnix Build](https://img.shields.io/endpoint.svg?url=https%3A%2F%2Fgarnix.io%2Fapi%2Fbadge%2Fgithub.com%2Fyour-username%2Fyour-repo)](https://garnix.io)

**Reverb-OS** is a NixOS-based personal AI assistant platform that serves as a comprehensive portfolio and demonstration system for the AstralVibe.ca ecosystem. Built entirely on Nix and NixOS, Reverb-OS showcases the power of declarative system configuration, distributed computing, and AI orchestration through its core interface: **** - the embedded AI assistant.

## 🏗️ Architecture Overview

### **Cluster Nodes**
| Host | Local IP | Tailscale IP | Role | CPU Cores | Memory | GPU | Purpose |
|------|----------|--------------|------|-----------|--------|-----|---------|
| **zephyr** | 10.1.1.110 | 100.81.182.5 | Master Node | 32 cores (Ryzen 9 5950X) | 32GB | RTX 3090 | VR Gaming, Development, Build Coordination |
| **nexus** | 10.1.1.120 | 100.86.158.18 | Build/AIStor | 24 cores (Ryzen 9 3900X) | 32GB | 2x RTX 3060 Ti | Distributed Builds, AIStor Storage |
| **forge** | 10.1.1.130 | 100.95.222.45 | GPU Compute | 6 cores | 32GB | 2x RTX 4060 + 2x RX 5700 XT | GPU Compute, Mining |
| **sentry** | 10.1.1.140 | 100.82.210.39 | Monitoring | 16 cores (Ryzen 7 1700) | 32GB | RX 5600 XT | Monitoring, Light Builds |

**Total Build Capacity:** **78 cores** across all hosts (includes distributed builds)

### **Network Topology**
```
Internet ── Router (10.1.1.1)
                     │
                     ├── zephyr (10.1.1.110, 100.81.182.5) - Master Workstation
                     ├── nexus  (10.1.1.120, 100.86.158.18) - Build/AIStor Server
                      ├── forge  (10.1.1.130, 100.95.222.45) - Mining/Build Worker
                     └── sentry (10.1.1.140, 100.82.210.39) - Monitoring Server
```

### **Directory Structure**
```
/etc/nixos/
├── flake.nix                 # Main flake with Colmena hosts and inputs
├── configuration.nix         # Shared cluster configuration
├── home.nix                 # Home Manager user configuration
├── justfile                 # Automation and management commands
├── garnix.yaml              # CI/CD configuration
├── hardware-configuration.nix # Auto-generated hardware config
├── network.nix              # Network configuration
├── hosts/                   # Host-specific configurations
│   ├── zephyr/              # Master workstation (RTX 3090)
│   ├── nexus/               # Build/AIStor server
│   ├── forge/               # Mining/build worker
│   └── sentry/              # Monitoring server
├── modules/                 # Shared configuration modules
│   ├── tailscale.nix        # Tailscale mesh VPN
│   ├── -declarative-container.nix  # AI orchestration
│   ├── -storage.nix                 # AIStor integration
│   ├── mining.nix                          # Mining services
│   ├── gaming.nix                          # VR/gaming setup
│   └── ...                                # Other modules
├── secrets/                 # Agenix encrypted secrets
├── scripts/                 # Utility scripts
├── docs/                    # Additional documentation
├── doc-archive/             # Archived documentation
├── examples/                # Example configurations
├── lib/                     # Library functions
├── packages/                # Package definitions
├── .github/workflows/       # GitHub Actions for GitOps
└── ...
```

### **GitOps Deployment Workflow**
```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  Push to    │────▶│ GitHub      │────▶│ Auto-merge  │────▶│ Deploy via  │
│  main       │     │ Actions     │     │ to infra    │     │ Colmena     │
│  branch     │     │ validation  │     │ branch      │     │             │
└─────────────┘     └─────────────┘     └─────────────┘     └─────────────┘
                                                               │
                            ┌─────────────────────────────────┤
                            │
                    ┌───────▼────────┐
                    │   nexus        │
                    │  (coordinator) │
                    └───────┬────────┘
                            │
        ┌───────────────────┼───────────────────┐
        │                   │                   │
  ┌─────▼─────┐       ┌─────▼─────┐       ┌─────▼─────┐
  │  zephyr   │       │  forge    │       │  sentry   │
  │  (master) │       │  (worker) │       │  (monitor)│
  └───────────┘       └───────────┘       └───────────┘
```

## 🚀 Key Features

### **🏭 Distributed Build System**
- **51-core cluster** with SSH-based remote building
- **Binary cache integration** with multiple substituters (Garnix, Cuda Maintainers)
- **Trusted user authentication** for restricted settings
- **Real-time build monitoring** and status tracking
- **High availability** with automatic failover

### **🌐 Tailscale Mesh VPN**
- **Secure mesh networking** across all 4 cluster nodes
- **Tailscale SSH** enabled on all hosts (no traditional SSH needed)
- **Subnet routing** for 10.1.1.0/24 network
- **Exit node** configured on zephyr for external access
- **Magic DNS** for easy hostname resolution
- **100.x.x.x addressing** for encrypted connections

### **🤖 : The Embedded AI Assistant**
- **Natural language interface** for system operations
- **AIStor object storage** for model artifacts and training data
- **MCP server integration** for AI assistants (Kilo Code, Claude Code)
- **RAG support** with AIStor vector database capabilities
- **Health monitoring** with auto-restart on failure
- **Service isolation** via lobster user (no sudo access)

### **🎮 VR Gaming & Mining**
- **ScopeBuddy Integration** ✅ NEW: Declarative gamescope wrapper with system-wide auto-detection
- **SteamVR/WiVRn support** with Quest Pro streaming (100Mbps HEVC)
- **Smart mining pause** during gaming/VR sessions (auto-detects applications)
- **GameMode integration** with NVIDIA +150MHz overclock
- **GPU mining** (lolMiner) and CPU mining (XMRig)
- **Mining troubleshooting** and fixes documented in `docs/MINING_TROUBLESHOOTING.md`
- **Performance monitoring** across all hosts

**🎯 ScopeBuddy Auto-Detection:**
- **Resolution**: Automatically detects display resolution
- **HDR**: Auto-enables HDR for HDR-capable displays
- **VRR**: Auto-enables adaptive sync for VRR displays  
- **System-wide**: Applies to ALL users via declarative NixOS configuration
- **Steam Integration**: Use `scb -- %command%` in launch options

**🎯 ScopeBuddy Auto-Detection:**
- **Resolution**: Automatically detects display resolution
- **HDR**: Auto-enables HDR for HDR-capable displays
- **VRR**: Auto-enables adaptive sync for VRR displays  
- **System-wide**: Applies to ALL users via declarative NixOS configuration
- **Steam Integration**: Use `scb -- %command%` in launch options

### **🛡️ Security**
- **Agenix encrypted secrets** management
- **Systemd hardening** with NoNewPrivileges and PrivateTmp
- **Lobster user isolation** (no sudo access for AI services)
- **Nginx reverse proxy** with SSL/TLS and IP allowlisting
- **Localhost-only service binding** for security

## 📋 Quick Start

### **Prerequisites**
- NixOS 26.05+ with flakes enabled
- SSH access to cluster nodes (or Tailscale access)
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

### **Cluster Deployment (GitOps)**
```bash
# Deploy to all hosts (pulls from infra branch)
just cluster-deploy

# Deploy to specific host
just deploy nexus
just deploy-zephyr

# Check cluster status
just cluster-status

# Monitor resources
just cluster-resources
```

### **Tailscale Access**
```bash
# Connect to any node via Tailscale IP
ssh 100.86.158.18          # nexus
ssh 100.95.222.45          # forge
ssh 100.82.210.39          # sentry

# Or use Magic DNS
ssh nexus.tigris-ule.ts.net
```

## 📖 Documentation

### **Architecture & System Overview**
- **[MASTER_DOCS.md](MASTER_DOCS.md)** - Complete system documentation (single source of truth)
- **[DOCS_INDEX.md](DOCS_INDEX.md)** - Documentation navigation map
- **[DOCUMENTATION_STRATEGY.md](DOCUMENTATION_STRATEGY.md)** - Documentation governance
- **[DOC_CONSOLIDATION_PLAN.md](DOC_CONSOLIDATION_PLAN.md)** - Consolidation methodology
- **[REVERB-OS-ARCHITECTURE.md](docs/REVERB-OS-ARCHITECTURE.md)** - Complete system design
- **[PORTFOLIO.md](docs/PORTFOLIO.md)** - Technical achievements and portfolio showcase

### **AI Assistant Access Points**
- **[CLAUDE.md](CLAUDE.md)** - *(symlink to MASTER_DOCS.md)* - Claude access point
- **[QWEN.md](QWEN.md)** - *(symlink to MASTER_DOCS.md)* - Qwen access point

### **Historical Documentation**
- **[doc-archive/](doc-archive/)** - Archived original documentation for reference

### **Development & Security**
- **[CONTRIBUTING.md](CONTRIBUTING.md)** - Contribution guidelines and standards
- **[PERFORMANCE_OPTIMIZATION_PLAN.md](docs/PERFORMANCE_OPTIMIZATION_PLAN.md)** - System optimization

### **Quick Wins for New Contributors**
- **Validate configuration**: `nix flake check`
- **Format code**: `just format` or `nix fmt`
- **Lint files**: `just lint` (statix)
- **Find dead code**: `just deadnix`
- **Check shell scripts**: `shellcheck .`
- **Test build**: `sudo nixos-rebuild build --flake .#zephyr`
- **Review changes**: `git diff` and `git status`
- **Run development shell**: `nix develop` or use direnv

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
# Mining operations
just mining-start
just mining-status  
just mining-stop

# Gaming mode with ScopeBuddy
just gaming-start
just gaming-status

# Manual mining pause (for testing)
just gaming-trigger

# ScopeBuddy usage (system-wide auto-detection)
scb -- %command%  # Steam integration
scb -O DP-3 -- %command%  # Multi-monitor
SCB_AUTO_RES=0 scb -- %command%  # Manual override
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

### **Tailscale Commands**
```bash
# Check Tailscale status
tailscale status

# Test connectivity to other nodes
tailscale ping 100.86.158.18
tailscale ping 100.95.222.45
tailscale ping 100.82.210.39

# Check your Tailscale IP
tailscale ip --4
tailscale ip --6
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
│   ├── zephyr/              # Master workstation (RTX 3090)
│   ├── nexus/               # Build/AIStor server
│   ├── forge/               # Mining/build worker
│   └── sentry/              # Monitoring server
├── modules/                 # Shared configuration modules
│   ├── tailscale.nix       # Tailscale mesh VPN
│   ├── -declarative-container.nix  # AI orchestration
│   ├── -storage.nix                 # AIStor integration
│   ├── -nginx.nix                   # Reverse proxy
│   ├── mining.nix                          # Mining services
│   ├── gaming.nix                          # VR/gaming setup
│   └── ...                                # Other modules
├── secrets/                 # Agenix encrypted secrets
└── .github/workflows/       # GitHub Actions for GitOps
    └── nix.yml             # CI/CD pipeline
```

## 🌐 GitOps Workflow

### **Continuous Deployment**
1. **Push to `main` branch** - Development changes
2. **GitHub Actions validates**:
   - `nix flake check`
   - Build all 4 host configurations
   - ~5 minutes total
3. **Auto-merge to `infra` branch** - Production-ready
4. **Deploy via `just cluster-deploy`**:
   - Pulls from `infra` branch
   - Runs `colmena apply` on nexus
   - Deploys to all 4 hosts

### **Idempotent Deployment Commands**
All deployment commands work consistently from any cluster node and any directory:
```bash
# Full cluster deployment (executes on nexus via SSH)
just cluster-deploy

# Update flake and deploy (executes on nexus via SSH)
just cluster-update

# Deploy to single host (executes on nexus via SSH)
just deploy <host>
just deploy-nexus
just deploy-forge
just deploy-sentry

# Local system switch (executes locally on current node only)
just switch
```

### **Idempotent Properties**
- **Node Independence**: Commands work identically from zephyr, nexus, forge, or sentry
- **Directory Independence**: Commands work from any working directory
- **Execution Consistency**: Deployment operations always run from nexus (coordinator)
- **Local Operations**: Only `just switch` runs on the current node
- **SSH Coordination**: All cluster operations use Tailscale VPN for secure communication

### **Multi-User Session Support**
- **User Isolation**: Operations maintain separate user contexts and permissions
- **Concurrent Sessions**: Multiple users can execute operations simultaneously
- **Operation Locking**: Prevents conflicting deployments between users with timeout handling
- **Session Auditing**: All operations logged with user identity and session context
- **Resource Isolation**: Per-user temporary files and processes
- **Identity Preservation**: Full user attribution for all actions across cluster
- **Security Validation**: Confirmed secure operation isolation and access controls

## 🌐 AstralVibe.ca Ecosystem Integration

Reverb-OS serves as a **core component** of the AstralVibe.ca ecosystem, providing:

### **AstralDev Integration**
- **GitHub Actions**: CI/CD automation for infrastructure changes
- **Garnix CI**: Free CI/CD with binary cache integration  
- **Colmena**: Declarative cluster deployment
- **Direnv**: Automatic development environment setup
- **MCP Servers**: AI assistant integration (Kilo Code, Claude Code)
- **Tailscale**: Secure mesh VPN for cluster connectivity

### **Portfolio Showcase**
Reverb-OS demonstrates expertise in:
- **NixOS system design** and declarative configuration
- **Distributed computing** at scale (51-core cluster)
- **AI orchestration** and personal assistant development
- **Security hardening** and isolation practices
- **Performance optimization** for VR gaming and mining
- **GitOps workflows** for infrastructure-as-code

## 🎯 : The Embedded AI Assistant

### **Services**
| Service | Port | Access | Purpose |
|---------|------|--------|---------|
| **** | 18789 | localhost only | AI agent gateway |
| **-storage** | 18800 | localhost only | AIStor S3 MCP |
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
-  gateway tokens
- Tailscale auth keys

### **System Hardening**
```nix
# Systemd hardening for 
systemd.services.-container-declarative.serviceConfig = {
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
- Tailscale mesh VPN for secure inter-node communication

## 🐛 Troubleshooting

### **Common Issues**
```bash
# Check  status
systemctl status -container-declarative

# View container logs
journalctl -u -container-declarative -f

# Check AIStor connection
mc alias set aistor http://10.1.1.120:9000 $MINIO_ACCESS_KEY $MINIO_SECRET_KEY
mc ls aistor

# Check mining status
just mining-status

# Check VR/gaming mode
just gaming-status

# Check Tailscale connectivity
tailscale status
tailscale ping <node-ip>
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

# Tailscale network status
tailscale status
tailscale netcheck
```

### **Health Checks**
```bash
#  health
curl -s http://127.0.0.1:18789/health

# AIStor health
curl -s http://127.0.0.1:18800/health

# Nginx health
curl -s http://127.0.0.1/health

# Tailscale health
tailscale status
```

## 🤝 Contributing

We welcome contributions! Please see our [CONTRIBUTING.md](docs/CONTRIBUTING.md) for guidelines.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🌟 Showcase

For a detailed portfolio showcase of this infrastructure, see [PORTFOLIO.md](docs/PORTFOLIO.md).

---

**Reverb-OS** - NixOS-based personal AI assistant platform with GitOps deployment, Tailscale mesh VPN, and  AI orchestration.

### **🚀 New Features (2026-02-07)**

#### GPU-Accelerated Builds
- **CUDA support** on nexus (2x RTX 3060 Ti), forge (2x RTX 4060), and zephyr (RTX 3090)
- **ROCm support** on forge (2x RX 5700 XT) and sentry (RX 5600 XT)
- Automatic GPU detection for intelligent build routing

#### Network Optimization
- **1Gbps networking** with TP-Link Easy Smart Switches
- **100 parallel HTTP connections** for faster dependency downloads
- Optimized for fast binary cache access

#### Binary Cache Enhancement
- Added **cuda.cachix.org** for NVIDIA GPU packages
- Added **rocm.cachix.org** for AMD GPU packages
- Total of **5 binary caches** configured

#### Mining-Aware Build Scheduling
- Build capacity adjusted based on active mining operations
- Forge: 2 jobs (conservative due to heavy mining)
- Zephyr: 6 jobs (reduced due to active CPU+GPU mining)
- Nexus: 12 jobs (prioritized - 48GB RAM, moderate GPU mining)

#### Documentation
- **`docs/GPU_BUILDS.md`** - Comprehensive GPU build user guide
- **`docs/MINING_STATUS.md`** - Current mining configuration across cluster
- Updated build comments with mining awareness

### **📚 New Documentation**

- [GPU Build Guide](docs/GPU_BUILDS.md) - Complete guide for GPU-accelerated builds
- [Mining Status](docs/MINING_STATUS.md) - Mining configuration per node
- [Distributed Builds](modules/distributed-builds.nix) - Build configuration with GPU features

