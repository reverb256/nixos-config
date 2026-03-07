# Colmena Multi-Host Deployment Guide

## Quick Start

```bash
# Deploy to all hosts
just deploy

# Deploy to specific host
just zephyr  # or nexus, forge, sentry

# Test configuration (dry run)
just test

# Check cluster status
just cluster-status
```

## Architecture

- **Single Source of Truth**: flake.nix defines all hosts
- **Common Modules**: Shared across all hosts via commonModules array
- **Deployment Metadata**: colmena.nix adds targetHost configuration
- **Helper Functions**: mkNixosSystem and mkHost eliminate duplication

## Host Addresses

Uses Tailscale DNS for reliable connectivity:
- zephyr: 100.81.182.5 (local deployment host)
- nexus: 100.86.158.18
- forge: 100.95.222.45
- sentry: 100.82.210.39

## Adding a New Host

1. Create host config: `hosts/newhost/configuration.nix`
2. Add to flake.nix hosts object: `newhost = { hostName = "newhost"; };`
3. Add to colmena.nix hostDeployment: `newhost = { targetHost = "newhost"; };`
4. Add to colmena.nix hosts: `newhost = mkHost { inherit (hostDeployment.newhost) hostName targetHost; };`

## Deployment Goals

- **switch** (default): Activate immediately, check for inhibitors
- **boot**: Set as default for next reboot, skip inhibitor checks
- **test**: Activate immediately but don't set as default

**Note:** Remote hosts currently use `boot` goal to avoid switch inhibitors during dbus-broker migration. After reboot, can switch to `switch` goal.

## Privilege Escalation

Colmena automatically uses sudo on remote hosts when needed:
- Local deployment runs as current user (no sudo needed)
- Remote deployment uses `deployment.targetUser` (j_kro) with passwordless sudo
- Configuration changes require root, which Colmena handles automatically

## Troubleshooting

```bash
# Check distributed builds
just verify-db

# Rollback specific host (before reboot)
ssh <host> "sudo nixos-rebuild switch --rollback"

# View deployment logs
journalctl -u nixos-rebuild

# Verify host configuration
nix eval .#nixosConfigurations.<host>.config.system.build.toplevel
```

## Known Issues

### Switch Inhibitors (Remote Hosts)

Remote hosts (nexus, forge, sentry) use `boot` goal instead of `switch` due to dbus → dbus-broker migration triggering switch inhibitors. This is a one-time issue.

**After rebooting hosts with dbus-broker:**
1. Verify dbus-broker is active: `systemctl status dbus-broker`
2. Edit justfile: Change `boot` to `switch` for remote hosts
3. Test deployment: `just <host>`
4. If successful, use `switch` goal for future deployments
