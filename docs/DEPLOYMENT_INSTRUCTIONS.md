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
ssh j_kro@zephyr
cd /etc/nixos
git pull
sudo nixos-rebuild switch --flake .#zephyr

# On nexus (build node):
ssh j_kro@nexus
cd /etc/nixos
git pull
sudo nixos-rebuild switch --flake .#nexus

# On forge (compute node):
ssh j_kro@forge
cd /etc/nixos
git pull
sudo nixos-rebuild switch --flake .#forge

# On sentry (monitoring node):
ssh j_kro@sentry
cd /etc/nixos
git pull
sudo nixos-rebuild switch --flake .#sentry
```

### Option 2: Parallel Deployment Script
```bash
#!/bin/bash
# Run this from a management system with SSH access to all hosts

hosts=("zephyr" "nexus" "forge" "sentry")

for host in "${hosts[@]}"; do
    echo "🚀 Deploying to $host..."
    ssh j_kro@$host "
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
ssh j_kro@zephyr "systemctl status lolminer-nvidia xmrig"
ssh j_kro@nexus "systemctl status lolminer-nvidia xmrig"
ssh j_kro@forge "systemctl status lolminer-nvidia"  # CPU mining disabled
ssh j_kro@sentry "systemctl status lolminer-nvidia xmrig"
```

### Pool Verification
```bash
# Verify Kryptex pools are configured correctly
ssh j_kro@zephyr "grep 'kryptex' /etc/nixos/configuration.nix"
ssh j_kro@nexus "grep 'kryptex' /etc/nixos/hosts/nexus/configuration.nix"
ssh j_kro@forge "grep 'kryptex' /etc/nixos/hosts/forge/configuration.nix"
ssh j_kro@sentry "grep 'kryptex' /etc/nixos/hosts/sentry/configuration.nix"
```

### KDE Plasma Verification
```bash
# Test window management fixes (log out and back in after deployment)
ssh j_kro@zephyr "echo \$QT_QPA_PLATFORM"  # Should output 'wayland'
ssh j_kro@nexus "echo \$QT_QPA_PLATFORM"   # Should output 'wayland'
ssh j_kro@forge "echo \$QT_QPA_PLATFORM"   # Should output 'wayland'
ssh j_kro@sentry "echo \$QT_QPA_PLATFORM"  # Should output 'wayland'
```

## Emergency Rollback (if needed)
```bash
# Rollback to previous generation
ssh j_kro@zephyr "sudo nixos-rebuild switch --rollback"
ssh j_kro@nexus "sudo nixos-rebuild switch --rollback"
ssh j_kro@forge "sudo nixos-rebuild switch --rollback"
ssh j_kro@sentry "sudo nixos-rebuild switch --rollback"
```