# System Reality Check & Infrastructure Audit

**Date:** 2026-02-05
**Status:** Post-Audit Remediation Complete
**Auditor:** AI Code Assistant

## Executive Summary

This document records the "Harsh Reality" audit conducted on Feb 3, 2026, and remediation actions. The infrastructure has evolved to use **Home Manager-based OpenClaw** and **nixpkgs LM Studio with steam-run**.

### Key Changes (2026-02-05)
1. **OpenClaw:** Migrated from container-based to nix-openclaw Home Manager module
2. **LM Studio:** Working with NVIDIA GPU support via steam-run FHS wrapper
3. **Home Manager:** Properly configured via flake.nix for all 4 hosts
4. **Peripherals:** OpenRazer fixed using built-in module, ckb-next added for Corsair

---

## 🔧 Current Configuration

### Hosts
| Host | Role | GPU | Status |
|------|------|-----|--------|
| zephyr | Master Workstation | RTX 3090 | ✅ Active |
| nexus | Build Server | 2x RTX 3060 Ti | ✅ Active |
| forge | Mining Rig | 2x RTX 4060 + 2x RX 5700 XT | ✅ Active |
| sentry | Monitoring | RX 5600 XT | ✅ Active |

### Services
| Service | Status | Notes |
|---------|--------|-------|
| OpenClaw | ✅ Running | Via nix-openclaw HM module |
| LM Studio | ✅ Working | steam-run with NVIDIA libs |
| Mining | ✅ Active | NVIDIA + AMD pools |
| Distributed Builds | ✅ Enabled | 51 cores |
| OpenRazer | ✅ Fixed | Using hardware.openrazer module |
| ckb-next | ✅ Added | Corsair device support |

---

## 📁 Quick Commands

### System Management
```bash
# Deploy to all nodes
just deploy

# Push and deploy to current host
just push

# Update flake and deploy all
just update

# Validate configuration
nix flake check
```

### OpenClaw
```bash
# Check status
openclaw status

# View logs
openclaw logs --follow

# Start gateway
systemctl --user start openclaw-gateway.service
```

### LM Studio
```bash
# CLI server mode
lms server start --host 127.0.0.1 --port 1234

# GUI mode
lm-studio
```

### Mining
```bash
# Check status
systemctl status lolminer-nvidia.service
systemctl status xmrig.service
```

---

## 🎮 Peripheral Support

### Razer Devices (OpenRazer)
```nix
hardware.openrazer.enable = true;
users.users.j_kro.extraGroups = ["openrazer"];
```

### Corsair Devices (ckb-next)
```nix
hardware.peripherals.corsair.ckbNext = true;
```

### Troubleshooting
See [RAZER_CORSAIR_TROUBLESHOOTING.md](./RAZER_CORSAIR_TROUBLESHOOTING.md) for detailed fixes and verification steps.

- **Mining APIs:** Bound to `127.0.0.1` only
- **OpenClaw:** Tailscale-only access via HM configuration
- **Secrets:** Agenix with age key at `/root/.config/sops/age/keys.txt`

---

## 📊 Configuration Stats

| Metric | Value |
|--------|-------|
| Nix Files | 81+ |
| Total Lines | ~10,600+ |
| Hosts | 4 |
| Container Backend | Podman |
