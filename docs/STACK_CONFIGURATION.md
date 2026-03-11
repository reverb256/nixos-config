# NixOS Cluster - Stack Configuration Overview

**Last Updated**: 2026-03-10
**Cluster Version**: 1.0
**Status**: Production Ready

---

## Executive Summary

This document provides a comprehensive overview of the NixOS cluster configuration, including all modules, services, security configurations, and best practices. The cluster consists of 4 hosts with diverse workloads (gaming, mining, AI inference, monitoring).

### Cluster Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         ZEPHYR (10.1.1.110)                      │
│  Control Plane | Workstation | Gaming | VR | Mining | AI       │
│  AMD Zen + RTX 3090 + RTX 3060 Ti | AIO Cooling | RGB          │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │  /etc/nixos - NFS Export (Single Source of Truth)         ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────┬───────────────────────────────────────────────────┘
              │ NFS (ro, nofail, bg)
    ┌─────────┼─────────┬──────────┐
    ▼         ▼         ▼          ▼
┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐
│ NEXUS  │ │ FORGE  │ │ SENTRY │         │
│ .120   │ │ .130   │ │ .140   │         │
│ Gaming │ │ Mining │ │ Monito │         │
│ Mining │ │        │ │ Mining │         │
└────────┘ └────────┘ └────────┘         │
   2x RTX     2x RTX     1x RX            │
  3060 Ti    4060      5600 XT            │
            2x RX                      │
           5700 XT                     │
                                      │
│◄─────────────────────────────────────┘
     Shared NixOS Configuration
```

---

## Module System

### Module Organization

```
modules/
├── default.nix                    # Module aggregator
├── common-host-defaults.nix        # Shared defaults
├── network-constants.nix           # Network configuration
│
├── system/                         # System-level modules
│   ├── nix-config.nix             # NixOS settings
│   ├── users.nix                  # User accounts
│   ├── home-manager.nix           # Home Manager integration
│   ├── networking.nix             # Network configuration
│   ├── interface-naming.nix       # Interface naming
│   ├── ssh.nix                    # SSH + Tailscale SSH
│   ├── ssh-ca.nix                 # SSH certificate authority
│   ├── mosh.nix                   # Mosh for unstable connections
│   ├── polkit-rules.nix           # PolicyKit rules
│   ├── tailscale.nix              # Tailscale VPN
│   ├── kernel-hardening.nix       # Kernel security parameters
│   ├── fetch-tools.nix            # HTTP fetch tools
│   ├── boot-error-fixes.nix       # Boot error handling
│   ├── agenix-fixes.nix           # Agenix compatibility
│   ├── cluster-storage.nix        # Storage verification
│   ├── security-hardening.nix     # Firewall, fail2ban
│   ├── btrfs-compression.nix      # BTRFS compression
│   ├── compute-workload-monitor.nix # Dynamic CPU management
│   └── distributed-builds.nix     # Distributed build coordination
│
├── security/                       # Security modules
│   └── pam-vaultwarden.nix        # Vaultwarden PAM integration
│
├── desktop/                        # Desktop environment
│   ├── desktop.nix                # Desktop settings
│   ├── wayland-common.nix         # Wayland configuration
│   ├── flatpak.nix                # Flatpak support
│   ├── hyprland.nix               # Hyprland WM
│   ├── systems-intelligence-plasmoid.nix # Plasma 5 widget
│   └── spotify-spotx.nix          # Spotify customization
│
├── shell/                          # Shell configuration
│   ├── bash.nix                   # Bash system-level
│   └── fish.nix                   # Fish system-level
│
├── development/                    # Development tools
│   ├── tools.nix                  # Development tools
│   ├── lsp.nix                    # Language servers
│   ├── programming-languages.nix  # Language runtimes
│   ├── opencode.nix               # OpenCode integration
│   └── web-testing.nix            # Web testing tools
│
├── gaming/                         # Gaming configuration
│   ├── gaming.nix                 # Steam, Lutris
│   ├── gaming-hdr.nix             # HDR support
│   └── scopebuddy.nix             # Scope buddy tool
│
├── mining/                         # Mining configuration
│   ├── mining.nix                 # Mining core
│   ├── mining-build-wrapper.nix   # Build-time pause
│   ├── xmrig-proxy.nix            # XMRig proxy
│   └── mining-proxy.nix           # Mining proxy service
│
├── services/                       # Service modules
│   ├── mcp-servers.nix            # MCP server configuration
│   ├── tplink-switches.nix        # TP-Link switch management
│   ├── tplink-cli.nix             # TP-Link CLI tools
│   ├── lm-studio.nix              # LM Studio integration
│   ├── lm-studio-headless.nix     # LM Studio headless mode
│   ├── stability-matrix.nix       # Stability Matrix manager
│   ├── ai-inference/              # AI Gateway (subdirectory)
│   ├── nixos-share.nix            # NFS config sharing
│   ├── spacebot.nix               # Spacebot service
│   ├── podman-auto-update.nix     # Podman auto-update
│   ├── glitchtip-selfhosted.nix   # GlitchTip error tracking
│   ├── caddy.nix                  # Caddy web server
│   ├── nextcloud.nix              # Nextcloud file sharing
│   ├── service-gateway.nix        # Service gateway
│   ├── ci-runner.nix              # CI/CD runner
│   ├── garnix.nix                 # Garnix deployment
│   ├── auto-update.nix            # Auto-update service
│   ├── whisper-dictation.nix      # Whisper dictation
│   ├── unbound-cluster.nix        # Unbound DNS
│   ├── searxng.nix                # SearXNG search
│   ├── n8n.nix                    # n8n automation
│   ├── vaultwarden.nix            # Vaultwarden password manager
│   ├── health-checks.nix          # Service health monitoring
│   ├── kubernetes.nix             # Kubernetes cluster
│   ├── monitoring/
│   │   ├── prometheus.nix         # Prometheus metrics
│   │   ├── grafana.nix            # Grafana dashboards
│   │   ├── alertmanager.nix       # Alert routing
│   │   └── node-exporter.nix      # Node metrics
│   └── gpu-exporters.nix          # GPU metrics
│
├── hardware/                       # Hardware modules
│   ├── nvidia-common.nix          # NVIDIA GPU support
│   ├── monitoring.nix             # Hardware monitoring
│   ├── corsair.nix                # Corsair AIO + RGB
│   ├── nvidia-wayland.nix         # NVIDIA Wayland
│   └── amdgpu-wayland.nix         # AMDGPU Wayland
│
├── multimedia/                     # Multimedia
│   └── gstreamer.nix              # GStreamer codecs
│
├── network/                        # Network modules
│   └── cluster-hosts.nix          # Cluster host definitions
│
└── profiles/                       # Profile system
    ├── hardware/                  # Hardware profiles
    │   ├── default.nix            # Profile options
    │   └── implementations.nix    # Profile implementations
    ├── role/                      # Role profiles
    │   ├── default.nix            # Role options
    │   └── implementations.nix    # Role implementations
    └── network/                   # Network profiles
        ├── default.nix            # Network options
        └── implementations.nix    # Network implementations
```

### Profile System

The cluster uses a declarative profile system for composable configurations:

#### Hardware Profiles
```nix
hardware.profiles = {
  # CPU profiles
  amd.enable = true;          # AMD CPU optimizations
  amd.zen = true;             # Zen CPU specific optimizations
  intel.enable = true;        # Intel CPU optimizations

  # GPU profiles
  nvidia.enable = true;       # NVIDIA GPU support
  nvidia.multiGpu = true;     # Multi-GPU configuration
  amdgpu.enable = true;       # AMD GPU support
  amdgpu.wayland = true;      # AMDGPU Wayland optimizations

  # Other hardware
  corsair.enable = true;      # Corsair AIO + RGB
  monitoring.enable = true;   # Hardware monitoring (lm-sensors)
};
```

#### Role Profiles
```nix
profiles.role = {
  workstation.enable = true;   # Desktop + development
  gaming.enable = true;        # Steam, Lutris
  vr.enable = true;            # WiVRn, SteamVR
  mining.enable = true;        # GPU/CPU mining
  aiInference.enable = true;   # AI gateway + MCP
  desktop.enable = true;       # Plasma, Wayland
};
```

#### Network Profiles
```nix
profiles.network = {
  tailscale.enable = true;              # Enable Tailscale VPN
  tailscale.advertiseRoutes = true;     # Advertise subnet routes
};
```

---

## Security Configuration

### Kernel Hardening
- **Page Table Isolation**: Enabled (side-channel mitigation)
- **User Namespaces**: Allowed (required for Wayland, Podman)
- **L1 Cache Flush**: Conditional mitigation
- **LSM Stack**: landlock, lockdown, yama, integrity, apparmor, bpf
- **ZSWAP**: Enabled with zstd compression (20% RAM max)

### Network Security
- **Firewall**: Enabled with Tailscale trusted interface
- **Tailscale SSH**: Keyless authentication via Tailscale identity
- **Fail2Ban**: SSH brute-force protection (ignores Tailscale network)
- **Sysctl Hardening**:
  - ICMP redirects disabled
  - TCP SYN cookies enabled
  - IP spoofing protection (rp_filter)
  - Martian packet logging

### Service Hardening
All systemd services use the following hardening directives:
- `NoNewPrivileges = true` - Prevents privilege escalation
- `ProtectSystem = "strict"` - Read-only system directories
- `ProtectHome = true` - Home directory isolation
- `PrivateTmp = true` - Isolated /tmp
- `RestrictRealtime = true` - Prevents real-time priority abuse
- `RestrictAddressGroups = [...]` - Limits socket types
- `ReadWritePaths = [...]` - Explicit write permissions

### Secrets Management
- **Agenix**: Age-encrypted secrets at rest
- **Per-host access control**: Fine-grained secret access
- **Systemd Credentials**: Loaded at service start, not in environment

### Kubernetes Security
- **Pod Security Admission**: Enabled (restricted baseline)
- **Network Policies**: Default deny-all with selective allow
- **RBAC**: Namespace-scoped roles for developers
- **Service Account Tokens**: Not auto-mounted by default
- **Runtime**: containerd with nvidia-container-runtime

---

## Service Configuration

### AI Inference Gateway
- **Port**: 8080
- **Bind Address**: 127.0.0.1 (localhost only)
- **Backends**: LM Studio, ZAI MCP
- **Health Check**: `http://127.0.0.1:8080/health`
- **Timeout**: 300s (configurable)

### Mining Services
- **NVIDIA**: `xmrig@nvidia` service
- **AMD**: `xmrig@amdgpu` service
- **Proxy**: `mining-proxy` service (port 3334)
- **Auto-pause**: During nixos-rebuild (via mining-build-wrapper)

### Kubernetes
- **Control Plane**: Zephyr (10.1.1.110)
- **Runtime**: containerd
- **CNI**: Flannel (VXLAN)
- **Port Range**: 30000-32767 (NodePort)
- **Health Monitoring**: kubelet healthz endpoint

### Monitoring
- **Prometheus**: Port 9090 (localhost)
- **Grafana**: Port 3001 (Tailscale)
- **AlertManager**: Port 9093 (localhost)
- **Node Exporter**: Port 9100 (localhost)

---

## Network Configuration

### Cluster Network (10.1.1.0/24)
| Host | IP | Role |
|------|-----|------|
| zephyr | 10.1.1.110 | Control Plane, Config Master |
| nexus | 10.1.1.120 | Gaming, Mining |
| forge | 10.1.1.130 | Mining |
| sentry | 10.1.1.140 | Monitoring |

### Tailscale Network (100.x.x.x)
- VPN mesh for all hosts
- SSH access via Tailscale identity
- Subnet route advertisement enabled

### Interface Naming
- **LAN**: `lan0` (consistent across cluster)
- **Wireless**: `wlan0` (zephyr only)
- **Tailscale**: `tailscale0`

---

## Storage Configuration

### Zephyr
- **Root**: BTRFS on NVMe SSD
- **Data**: BTRFS on HDD (mounted at /data)
- **Compression**: zstd
- **Subvolumes**: worn, home, shared, backups, media

### Nexus
- **Root**: BTRFS on NVMe SSD
- **Data**: BTRFS on HDD (mounted at /data)
- **Subvolumes**: worn, home, shared, backups, media
- **Containers**: /var/lib/containers

### Forge
- **Root**: BTRFS on SSD
- **No separate data mount**

### Sentry
- **Root**: BTRFS on SSD
- **Storage**: BTRFS on HDD (mounted at /storage)

---

## Performance Optimizations

### Kernel Parameters (Gaming/Low Latency)
- `processor.max_cstate=1` - Limit CPU C-states
- `intel_idle.max_cstate=1` - Limit idle C-states
- `iommu=pt` - Passthrough IOMMU

### ZSWAP Configuration
- Compressor: zstd (best compression ratio)
- Allocator: z3fold (better than zbud)
- Max pool: 20% of RAM

### BTRFS Compression
- Algorithm: zstd
- Compress-force: enabled for data subvolumes

### Multi-GPU Configuration
- NVIDIA: `nvidia_uvm` module loaded
- AMD: ROCm stack configured
- CUDA: Multi-GPU context sharing enabled

---

## CI/CD Pipeline

### Build Commands
```bash
just test              # Verify configuration
just switch            # Apply to local host
just deploy            # Deploy to all hosts
just ci-local          # Run full CI pipeline
```

### Pre-flight Checks
- Nix flake validation
- Configuration syntax check
- Build verification
- Service health checks

### Deployment Strategy
1. Make changes on zephyr (config master)
2. Add new files to git (required for Nix)
3. Run `just test` to verify
4. Run `just deploy` to push to all hosts
5. Verify services are healthy

---

## Troubleshooting

### Common Issues

**Nix build fails with "ModuleNotFoundError"**
```bash
# Cause: New file not added to git
git add path/to/new/file.py
```

**Kubernetes pods stuck in "ContainerCreating"**
```bash
# Check containerd is running
systemctl status containerd

# Check kubelet logs
journalctl -u kubelet -n 50
```

**Mining doesn't auto-resume after build**
```bash
# Check compute-workload-monitor
systemctl status compute-workload-monitor

# Manual resume
systemctl start mining.target
```

### Health Checks
```bash
# AI Gateway
curl http://127.0.0.1:8080/health

# Mining Proxy
curl http://127.0.0.1:3334/api/health

# Kubernetes
kubectl get nodes
kubectl get pods -A
```

---

## Documentation Index

### Security
- [Security Audit Report](security/SECURITY_AUDIT_REPORT.md)
- [Hardening Summary](security/HARDENING_SUMMARY.md)
- [Pod Security Admission](security/pod-security-admission.md)
- [API Headers](security/api-headers.md)
- [Container Scanning](security/container-scanning.md)
- [Secrets Rotation](security/secrets-rotation.md)
- [Emergency Access](security/emergency-access.md)

### Kubernetes
- [Service Account Security](kubernetes/service-account-security.md)
- [Graceful Restart Procedure](kubernetes/graceful-restart-procedure.md)
- [Network Policies](kubernetes/network-policies/)

### Cluster
- [Networking Roadmap](NETWORKING_ROADMAP.md)
- [CI/CD Setup](ci-cd-setup.md)
- [CI/CD Usage](ci-cd-usage.md)

---

**Version**: 1.0
**Maintained**: 2026-03-10
**Next Review**: 2026-04-10
