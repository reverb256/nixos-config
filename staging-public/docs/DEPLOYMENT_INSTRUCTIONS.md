# Production Deployment Instructions
# Execute these commands on each cluster host to deploy the latest changes

## Prerequisites
- SSH access to all cluster hosts
- Git repository updated with latest changes
- Sudo privileges on each host

## Deployment Commands

### Option 1: Manual Deployment (Recommended for initial deployment)
```bash
# On zephyr (master node):
ssh USERNAME@HOST
cd /etc/nixos
git pull
sudo nixos-rebuild switch --flake .#zephyr

# On nexus (build node):
ssh USERNAME@HOST
cd /etc/nixos
git pull
sudo nixos-rebuild switch --flake .#nexus

# On forge (compute node):
ssh USERNAME@HOST
cd /etc/nixos
git pull
sudo nixos-rebuild switch --flake .#forge

# On sentry (monitoring node):
ssh USERNAME@HOST
cd /etc/nixos
git pull
sudo nixos-rebuild switch --flake .#sentry
```

### Option 2: Parallel Deployment Script
```bash
#!/bin/bash
# Run this from a management system with SSH access to all hosts

hosts=("WORKER_X" "WORKER_X" "WORKER_X" "WORKER_X")

for host in "${hosts[@]}"; do
    echo "🚀 Deploying to $host..."
    ssh USERNAME@HOST$host "
        cd /etc/nixos
        git pull
        sudo nixos-rebuild switch --flake .#$host
        echo "✅ $host deployment complete"
    " &
done

wait
echo "🎉 All deployments complete!"
```

## Post-Deployment Verification

### Mining Services Check
```bash
# Check mining status on all hosts
ssh USERNAME@HOST "systemctl status lolminer-nvidia xmrig"
ssh USERNAME@HOST "systemctl status lolminer-nvidia xmrig"
ssh USERNAME@HOST "systemctl status lolminer-nvidia"  # CPU mining disabled
ssh USERNAME@HOST "systemctl status lolminer-nvidia xmrig"
```

### Pool Verification
```bash
# Verify Kryptex pools are configured correctly
ssh USERNAME@HOST "grep 'kryptex' /etc/nixos/configuration.nix"
ssh USERNAME@HOST "grep 'kryptex' /etc/nixos/hosts/nexus/configuration.nix"
ssh USERNAME@HOST "grep 'kryptex' /etc/nixos/hosts/forge/configuration.nix"
ssh USERNAME@HOST "grep 'kryptex' /etc/nixos/hosts/sentry/configuration.nix"
```

### KDE Plasma Verification
```bash
# Test window management fixes (log out and back in after deployment)
ssh USERNAME@HOST "echo \$QT_QPA_PLATFORM"  # Should output 'wayland'
ssh USERNAME@HOST "echo \$QT_QPA_PLATFORM"   # Should output 'wayland'
ssh USERNAME@HOST "echo \$QT_QPA_PLATFORM"   # Should output 'wayland'
ssh USERNAME@HOST "echo \$QT_QPA_PLATFORM"  # Should output 'wayland'
```

## Emergency Rollback (if needed)
```bash
# Rollback to previous generation
ssh USERNAME@HOST "sudo nixos-rebuild switch --rollback"
ssh USERNAME@HOST "sudo nixos-rebuild switch --rollback"
ssh USERNAME@HOST "sudo nixos-rebuild switch --rollback"
ssh USERNAME@HOST "sudo nixos-rebuild switch --rollback"
```