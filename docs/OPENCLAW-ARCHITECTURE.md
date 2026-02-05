# OpenClaw System Architecture

## Overview

OpenClaw is an AI agent orchestration system designed to manage the entire end-to-end product lifecycle. This architecture provides a robust, extensible framework for handling diverse project types.

## Architectural Principles

1. **Security-First Design**: Services run in isolated environments with minimal privileges
2. **Extensibility**: Modular component design with pluggable skills ecosystem
3. **Scalability**: Horizontal scaling via containerization and distributed workflows
4. **Reliability**: Health monitoring, auto-recovery, and fault tolerance
5. **Observability**: Comprehensive logging, metrics, and traceability
6. **Automation**: Declarative configuration and workflow automation patterns

## System Components

### 1. OpenClaw Gateway (Podman Container)

**Purpose**: Core AI agent orchestration and workflow management

**Features**:
- WebSocket gateway for real-time agent communication
- REST API for management operations
- Skill lifecycle management
- Workflow engine for automation
- Lobster integration for typed pipelines and approvals

**Technical Specifications**:
- **Protocol**: WebSocket + REST API
- **Port**: 18789 (localhost only by default)
- **User**: `lobster` (UID 982, service account)
- **Container**: Podman with systemd hardening
- **Health Checks**: 30-second interval with auto-restart
- **Isolation**: Separate network namespace, read-only volume mounts for tools

**Shell Tools Mounted** (read-only):
- Package Managers: npm, pnpm, bun
- Utilities: coreutils, git, curl, wget, jq, ripgrep, fd, yq, miller
- Editors: vim, nano
- Compressors: gzip, tar, unzip

### 2. OpenClaw Storage MCP

**Purpose**: Natural language interface for AIStor object storage

**Features**:
- Natural language commands for storage operations
- Automated training checkpoint workflows
- Dataset ingestion with manifest generation
- Experiment tracking with versioning
- Cloud backup triggers
- Storage statistics and monitoring

**Technical Specifications**:
- **Protocol**: HTTP API + MCP
- **Port**: 18800 (localhost only)
- **Language**: Python/FastAPI
- **Storage**: AIStor/MinIO S3-compatible
- **Backups**: rclone integration

### 3. Lobster Workflow Engine

**Purpose**: Typed JSON pipelines and approval gates for AI agents

**Features**:
- Typed data pipelines (JSON, not text)
- YAML/JSON workflow files with steps, env, conditions
- Approval gates for sensitive operations
- Local-first execution
- No new auth surface

**Directory Structure**:
```
~/.openclaw/
├── state/          # Gateway state
├── data/           # Application data
├── config/         # Configuration files
├── logs/           # Log files
├── workspace/      # Skills and documents
├── workflows/      # Lobster workflow files
└── approvals/     # Approval files
```

### 4. Networking & Security

**Firewall Configuration** (ansible-style):
- Only localhost ports 18789/18800 exposed
- All external traffic via nginx reverse proxy
- Podman network isolation (`openclaw-network`)

**Systemd Hardening**:
- `NoNewPrivileges=yes`
- `PrivateTmp=yes`
- `ProtectHostname=yes`
- `ProtectKernelTunables=yes`
- `RestrictAddressFamilies=AF_INET AF_INET6`
- `CapabilityBoundingSet=CAP_NET_ADMIN`
- `cap-drop ALL` on container

### 5. Service Discovery (Avahi/mDNS)

**Purpose**: Device discovery for WiVRn VR streaming

**Hardened Configuration**:
- `enable-wide-area=no` - prevents DNS-SD leaking to internet
- `disable-user-service-publishing=no` - allows WiVRn to publish
- Interface restrictions: wired NICs only (`enp38s0`, `enp7s0`)
- VPN/wireless blocked: `tailscale0`, `wlan*`, `docker*`

### 6. AIStor Object Storage

**Purpose**: S3-compatible object storage for AI/ML workloads

**Buckets**:
- `ai-models` - Model checkpoints with versioning
- `training-data` - Datasets with metadata
- `experiments` - Experiment artifacts
- `ai-logs` - Training logs and metrics
- `nix-cache` - Binary cache

**Endpoint**: `http://10.1.1.120:9000` (internal network)

## Deployment

### Quick Start

```bash
# Deploy to zephyr (VR workstation)
sudo nixos-rebuild switch --flake .#zephyr

# Deploy to nexus (build server)
sudo nixos-rebuild switch --flake .#nexus

# Check status
systemctl status openclaw-declarative
journalctl -u openclaw-declarative -f
```

### Service Management

```bash
# Start/Stop/Restart
sudo systemctl start openclaw-declarative
sudo systemctl stop openclaw-declarative
sudo systemctl restart openclaw-declarative

# View logs
sudo journalctl -u openclaw-declarative -f

# Check health
curl http://localhost:18789/health
```

## Security Notes

- All services bind to localhost only
- External access via nginx reverse proxy (SSL/TLS)
- Podman containers run with minimal privileges
- Shell tools mounted read-only
- Firewall restricts to loopback interface
