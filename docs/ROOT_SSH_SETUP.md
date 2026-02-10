# Root SSH Setup for Distributed Builds

## Problem

When running `sudo nixos-rebuild switch`, distributed builds fail because:
1. SSH agent socket is not accessible to root
2. Root doesn't have SSH keys to connect to remote nodes
3. "Permission denied" or "Too many authentication failures" errors

## Solution

Run the setup script to configure root SSH keys:

```bash
sudo /etc/nixos/scripts/setup-root-ssh.sh
```

This script:
1. Copies `id_nixbuild` key from j_kro to root
2. Creates `/root/.ssh/config` with proper host configurations
3. Sets up `known_hosts` for all cluster nodes
4. Tests SSH connections to all nodes

## Manual Setup

If the script doesn't work, manual setup:

```bash
# Create directories
sudo mkdir -p /root/.ssh/sockets
sudo chmod 700 /root/.ssh

# Copy SSH key
sudo cp ~/.ssh/id_nixbuild /root/.ssh/
sudo cp ~/.ssh/id_nixbuild.pub /root/.ssh/
sudo chown root:root /root/.ssh/id_nixbuild*
sudo chmod 600 /root/.ssh/id_nixbuild
sudo chmod 644 /root/.ssh/id_nixbuild.pub

# Create SSH config
sudo tee /root/.ssh/config << 'EOF'
Host nexus 10.1.1.120 100.86.158.18
  HostName 100.86.158.18
  User j_kro
  IdentityFile /root/.ssh/id_nixbuild
  IdentitiesOnly yes

Host forge 10.1.1.130 100.95.222.45
  HostName 100.95.222.45
  User j_kro
  IdentityFile /root/.ssh/id_nixbuild
  IdentitiesOnly yes

Host sentry 10.1.1.140 100.82.210.39
  HostName 100.82.210.39
  User j_kro
  IdentityFile /root/.ssh/id_nixbuild
  IdentitiesOnly yes
EOF

# Setup known hosts
sudo ssh-keyscan -H 100.86.158.18 100.95.222.45 100.82.210.39 | sudo tee -a /root/.ssh/known_hosts
```

## Verification

Test root SSH connections:

```bash
sudo sh -c 'ssh j_kro@nexus "echo OK"'
sudo sh -c 'ssh j_kro@forge "echo OK"'
sudo sh -c 'ssh j_kro@sentry "echo OK"'
```

All should return "OK".

## Testing Distributed Builds

```bash
# Build a package to test distributed builds
nix build nixpkgs#hello

# Or perform full system rebuild
sudo nixos-rebuild switch --flake .#zephyr --upgrade-all
```

## Persistence

Root SSH configuration is **NOT** automatically persisted across reboots. After a reboot, rerun:

```bash
sudo /etc/nixos/scripts/setup-root-ssh.sh
```

To make it persistent, add the script to systemd's ExecStartPost or use NixOS modules to manage SSH keys declaratively.
