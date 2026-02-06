# System Reality Check & Infrastructure Audit

**Date:** 2026-02-06
**Status:** ✅ Active - OpenClaw Running
**Auditor:** AI Code Assistant

## Executive Summary

This document records the infrastructure status as of Feb 6, 2026. The cluster uses **Home Manager-based OpenClaw** with secure loopback binding and **Tailscale-only access**.

### Key Changes (2026-02-06)
1. **OpenClaw:** Running via Home Manager user service (loopback only)
2. **Secrets:** Simplified - no agenix (using environment variables)
3. **Node Hosts:** New module for connecting remote nodes via SSH tunnels
4. **Tailscale:** Used for secure node-to-gateway communication

---

## 🔧 Current Configuration

### Hosts
| Host | Role | GPU | Status |
|------|------|-----|--------|
| zephyr | Master Workstation | RTX 3090 | ✅ Active - OpenClaw Running |
| nexus | Build Server | 2x RTX 3060 Ti | Pending config |
| forge | Mining Rig | 2x RTX 4060 + 2x RX 5700 XT | Pending config |
| sentry | Monitoring | RX 5600 XT | Pending config |

### Services
| Service | Status | Notes |
|---------|--------|-------|
| OpenClaw | ✅ Running | Loopback-only on zephyr |
| LM Studio | ✅ Working | Via nix-openclaw |
| Mining | ✅ Active | NVIDIA + AMD pools |
| Distributed Builds | ✅ Enabled | 51 cores |

---

## 📁 Quick Commands

### Deployment
```bash
# Deploy to all nodes (via colmena)
just deploy

# Deploy to specific host
just forge
just nexus

# Push and deploy to current host
just push
```

### OpenClaw
```bash
# Check status
openclaw status

# View logs
journalctl --user -u openclaw-gateway.service -f

# Restart gateway
systemctl --user restart openclaw-gateway.service
```

### Cluster Management
```bash
# Check cluster status
just status

# Copy age keys to all nodes
just prep

# Validate configuration
nix flake check
```

---

## 🔐 Security Model

### Gateway (zephyr)
- Binds to `loopback` only (127.0.0.1)
- Accessible only via Tailscale SSH tunnel
- Token authentication enabled

### Node Hosts (nexus, forge, sentry)
- Connect via SSH tunnel through Tailscale
- SSH tunnel: `ssh -N -L 18790:127.0.0.1:18789 j_kro@zephyr`
- Node host then connects to `127.0.0.1:18790`

### SSH Access
- Passwordless sudo configured for j_kro on all hosts
- SSH key authentication via `~/.ssh/id_ed25519`
- Tailscale IPs used for cluster communication

---

## 🖥️ Node Host Configuration

### Architecture
```
[Tailscale Mesh: 100.x.x.x]
     |
     v
[zephyr:100.81.182.5] (Gateway - loopback:18789)
     ^
     | SSH Tunnel (localhost:18790)
     |
[nexus/forge/sentry] (Node Hosts)
```

### Node Host Setup
Each node hosts run `openclaw node run` which connects to the gateway via SSH tunnel:
```bash
# On node host (nexus/forge/sentry)
ssh -N -L 18790:127.0.0.1:18789 j_kro@zephyr &
openclaw node run --host 127.0.0.1 --port 18790 --display-name "Build Node"
```

### Exec Allowlist
Node hosts enforce an allowlist for `exec` commands. Common commands:
- `/run/current-system/sw/bin/uname`
- `/run/current-system/sw/bin/sw_vers`

---

## 🔐 Secrets Management

Secrets are managed via **Agenix** with age encryption:

### Age Key Location
```
/root/.config/sops/age/keys.txt
```

### Secrets Directory
```
/etc/nixos/secrets/
├── anthropic-api-key.age
├── openai-api-key.age
├── openclaw-env.age
└── openclaw-gateway-token.age
```

### Generating New Secrets
```bash
# Generate age key (if needed)
nix shell nixpkgs#age -c age-keygen -o /root/.config/sops/age/keys.txt

# Encrypt a secret
echo "my-secret-value" | nix shell nixpkgs#age -c age -r "age1..." -o secret.age
```

---

## 📊 Configuration Stats

| Metric | Value |
|--------|-------|
| Nix Files | 85+ |
| Total Lines | ~11,000+ |
| Hosts | 4 |
| Container Backend | Podman |

---

## 🐛 Troubleshooting

### OpenClaw Won't Start
```bash
# Check logs
journalctl --user -u openclaw-gateway.service -f

# Verify binding
curl http://127.0.0.1:18789/health

# Restart service
systemctl --user restart openclaw-gateway.service
```

### SSH Tunnel Issues
```bash
# Test SSH to zephyr
ssh j_kro@zephyr

# Verify Tailscale
tailscale status

# Check tunnel is running
ps aux | grep ssh
```

### Colmena Deployment Fails
```bash
# Check SSH access
ssh -o ConnectTimeout=5 j_kro@forge "hostname"

# Verify flake is clean
nix flake check

# Try direct deployment
ssh j_kro@forge "sudo nixos-rebuild switch --flake /etc/nixos#forge"
```
