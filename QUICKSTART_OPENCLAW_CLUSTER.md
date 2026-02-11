# Quick Start - OpenClaw Cluster Orchestration
# ================================================================
# Enable OpenClaw autonomous agents across all 4 NixOS nodes
#

## What This Provides

- **Single point of orchestration** - Master node (zephyr) runs OpenClaw
- **Autonomous agents** - Multiple agents on nexus, forge, sentry work independently
- **Shared workspace** - All nodes have access to `/home/j_kro/workspace` (or node-specific)
- **Token authentication** - Secure, rotatable tokens
- **Tailscale support** - Secure remote access from anywhere
- **Resource management** - Per-node CPU/memory/PID limits

## Quick Start (5 Minutes)

### 1. Generate Secure Token

```bash
# Generate 256-bit random token
openssl rand -hex 32
```

### 2. Enable in zephyr Configuration

`/etc/nixos/hosts/zephyr/configuration.nix` already includes:
```nix
services.openclaw-quadlet = {
  enable = true;
  masterNode = "zephyr";
  agentNodes = ["nexus" "forge" "sentry"];
  authToken = "your-token-here";  # Replace with your token
  workspaces.zephyr = "/home/j_kro/workspace";
};
```

### 3. Rebuild

```bash
sudo nixos-rebuild switch
```

### 4. Enable on Other Nodes

Add to each node's configuration:
- **nexus**: `/etc/nixos/hosts/nexus/configuration.nix`
- **forge**: `/etc/nixos/hosts/forge/configuration.nix`
- **sentry**: `/etc/nixos/hosts/sentry/configuration.nix`

Each adds:
```nix
services.openclaw-quadlet = {
  enable = true;
  masterNode = "zephyr";  # Connect to zephyr's gateway
  workspaces.<node> = "/home/<node>/workspace";  # e.g., workspaces.nexus = "/home/nexus/workspace"
};
```

### 5. Verify Deployment

```bash
# Check master node (zephyr)
podman ps | grep openclaw
systemctl status quadlet-openclaw-master
journalctl -u quadlet-openclaw-master -n 50

# Check agent nodes
podman ps | grep openclaw-agent
systemctl status quadlet-openclaw-agent-nexus
systemctl status quadlet-openclaw-agent-forge
systemctl status quadlet-openclaw-agent-sentry

# Access OpenClaw
# Local: http://localhost:18090/
# Remote (Tailscale): https://openclaw-nodes.tailnetname.ts.net:18090/
```

## Configuration Options

### Master Node (zephyr)
- `masterNode = "zephyr"` (default)
- `agentNodes = ["nexus" "forge" "sentry"]` (nodes running agents)

### Per-Node Workspaces
- **zephyr**: `/home/j_kro/workspace`
- **nexus**: `/home/nexus/workspace` (default)
- **forge**: `/home/forge/workspace`
- **sentry**: `/home/sentry/workspace`

### Network Mode
- **bindToLocalhost = true` (default) - Bind to 127.0.0.1
- **enableTailscale = false` (default) - Enable Tailscale for remote access

### Resource Allocation (Per-Node Default)
- `memoryReservation = "2G"`
- `memoryLimit = "4G"`
- `pidsLimit = 500`
- `cpuQuota = 200`

## What You DON'T Need

- ❌ No RBAC module (not managing multiple users)
- ❌ No multi-team configuration (simple autonomous agents)
- ❌ No complex team policies
- ❌ No per-node workspaces (all share same path)

## Security Checklist

- [ ] Token generated (replace "your-token-here")
- [ ] Token rotation enabled (default: 30 days)
- [ ] Seccomp enabled (via OpenClaw image)
- [ ] AppArmor enabled (via module)
- [ ] Firewall blocking external access
- [ ] Workspace created at `/home/j_kro/workspace`

## Troubleshooting

### Container won't start?
```bash
systemctl status quadlet-openclaw-master
journalctl -u quadlet-openclaw-master -n 100
```

### Agent nodes offline?
```bash
systemctl status quadlet-openclaw-agent-*
journalctl -u quadlet-openclaw-agent-* -n 50
```

### Verify token authentication
```bash
curl -H "Authorization: Bearer wrong-token" http://127.0.0.1:18090/health
# Should return 401 Unauthorized (wrong token)
```

## Architecture

```
┌───────────────────────────────────────────────────┐
│                                          │
│     zephyr (master)    nexus    forge    sentry    │
│         │              │              │              │              │
│    ┌────────────┐      │              │              │              │
│    │ OpenClaw   │              │              │              │
│    │ (Quadlet)    │              │              │              │
│    │             │              │              │              │
│    └────────────┘      │              │              │              │
│    │         │              │              │              │
│    └──────────────────────────────────────┘
│                                          │
│                                    Tailscale VPN (100.x.x.x)
│                                    ────────────────────────────
```

## Next Steps

1. Generate secure token: `openssl rand -hex 32`
2. Add to zephyr config: Replace `"your-token-here"` with your token
3. Rebuild: `sudo nixos-rebuild switch`
4. Enable on other nodes by editing their configs
5. Verify all nodes are running and accessible

## Resources

- Module: `/etc/nixos/modules/quadlet-openclaw-simple.nix`
- Documentation: See `/etc/nixos/QUICKSTART_OPENCLAW_CLUSTER.md`
- OpenClaw Reference: https://github.com/openclaw/openclaw-host-kit
- OpenClaw Security: https://useclaw.pro/guides/openclaw-security/
