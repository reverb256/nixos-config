# Initial Setup Guide

## Prerequisites

- NixOS 26.05+ with flakes enabled
- SSH access to cluster nodes
- Agenix for secret management

## Quick Start

```bash
# Clone repository
git clone <repo-url> /etc/nixos
cd /etc/nixos

# Enter dev shell
nix develop

# Validate configuration
nix flake check

# Deploy locally
just switch

# Deploy to cluster
just deploy
```

## Secret Setup (Agenix)

```bash
# Create required secrets
agenix -e anthropic-api-key.age
agenix -e mining-wallet.age
```

## Network Setup

### Tailscale VPN
```bash
tailscale up --ssh
```

See: [TAILSCALE_SETUP.md](TAILSCALE_SETUP.md)

### Static IPs
Configured in `hosts/<host>/configuration.nix` via NetworkManager.

## SSH Setup

See: [ROOT_SSH_SETUP.md](ROOT_SSH_SETUP.md)

## Verification

```bash
# Check services
systemctl status lolminer-nvidia
systemctl status tailscale

# Test distributed builds
nix build --builders-use-substitutes nixpkgs#hello

# Check cluster connectivity
just status
```
