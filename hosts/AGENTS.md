# HOSTS KNOWLEDGE BASE

**Generated:** 2026-01-24
**Scope:** Multi-Host Cluster Configuration  
**Complexity:** Medium (4 hosts, distributed builds)

## OVERVIEW
Distributed NixOS build cluster with 4 hosts: zephyr (master), nexus (build/backup), forge (compute), sentry (monitoring). Total 51 cores across cluster.

## STRUCTURE
```
hosts/
├── forge/
│   ├── default.nix                # GPU compute node (6 cores, 4 GPUs)
│   └── hardware-configuration.nix  # Auto-generated hardware config
├── nexus/
│   ├── default.nix                # Build/backup server (24 cores, 2x RTX 3060 Ti)
│   └── hardware-configuration.nix  # Auto-generated hardware config
├── sentry/
│   ├── default.nix                # Monitoring node (8 cores, RX 5600 XT)
│   └── hardware-configuration.nix  # Auto-generated hardware config
└── zephyr/
    ├── default.nix                # Master workstation (32 cores, RTX 3090)
    └── hardware-configuration.nix  # Auto-generated hardware config
```

## WHERE TO LOOK
| Task | Location | Notes |
|------|----------|-------|
| Master config | hosts/zephyr/default.nix | 32 cores, RTX 3090, VR ports |
| Build/backup | hosts/nexus/default.nix | 24 cores, 2x RTX 3060 Ti |
| Compute/GPU | hosts/forge/default.nix | 6 cores, 4 GPUs (2x NVIDIA + 2x AMD) |
| Monitoring | hosts/sentry/default.nix | 8 cores, AMD GPU only |
| Build pool | machines.nix | 51-core distributed build config |
| Hardware specs | hosts/*/hardware-configuration.nix | Auto-generated, DO NOT EDIT |

## HOST CONFIGS

### ZEPHYR (Master) - 10.1.1.110
- **CPU:** 32 cores (Ryzen 9 5950X)
- **GPU:** RTX 3090 (24GB)
- **Role:** Desktop workstation + VR gaming + build coordination
- **Features:** High-performance kernel params, gaming sysctl, VR firewall ports
- **Networking:** NetworkManager static IP, VR ports (9757-9760, 27031, 27036)

### NEXUS (Build/Backup) - 10.1.1.120
- **CPU:** 24 cores (Ryzen 9 3900X)
- **GPU:** 2x RTX 3060 Ti (8GB each)
- **Role:** Distributed builds + backup storage
- **Features:** NVIDIA proprietary drivers, minimal firewall
- **Networking:** NetworkManager static IP, no extra ports

### FORGE (GPU Compute) - 10.1.1.130
- **CPU:** 6 cores
- **GPU:** 2x RTX 4060 + 2x RX 5700 XT (4 GPUs total)
- **Role:** GPU compute cluster + mining
- **Features:** AMD/NVIDIA dual drivers, ROCm support, mining focus
- **Networking:** NetworkManager static IP, AMD GPU kernel params

### SENTRY (Monitoring) - 10.1.1.140
- **CPU:** 8 cores (Ryzen 7 1700)
- **GPU:** RX 5600 XT (display only)
- **Role:** Monitoring + alerting + light builds
- **Features:** AMDGPU open source, minimal firewall
- **Networking:** systemd-networkd static IP (no NetworkManager)

## CONVENTIONS
- **Static IPs:** 10.1.1.110-140 range with gateway 10.1.1.1
- **Hardware configs:** Auto-generated, never edited manually
- **Bootloader:** All hosts use systemd-boot with EFI
- **Desktop:** All hosts run KDE Plasma 6 with auto-login for j_kro
- **DNS:** All hosts use local Unbound DNS (127.0.0.1,::1)
- **Host entries:** Each host maintains full cluster hosts file
- **Distributed builds:** Configured in machines.nix (51 cores total)

## ANTI-PATTERNS
- **NEVER edit** hardware-configuration.nix files (auto-generated)
- **NEVER use different networking approaches** without specific reason
- **NEVER duplicate host entries** - maintain consistency across all hosts
- **NEVER hardcode interfaces** - use appropriate interface names per host
- **NEVER mix NetworkManager and systemd-networkd** unless required
- **ALWAYS update machines.nix** when changing build capacity
- **ALWAYS test distributed builds** after host configuration changes