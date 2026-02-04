# Tailscale VPN Setup Guide

**Created:** 2026-02-03  
**Purpose:** Secure mesh VPN for the NixOS cluster

## Overview

All 4 cluster nodes are connected via Tailscale mesh VPN, providing secure communication between hosts regardless of physical location. This enables:

- **Secure remote access** to all cluster nodes
- **Encrypted communication** between all hosts
- **Tailscale SSH** (no traditional SSH needed)
- **Subnet routing** for the 192.168.100.X/24 network
- **Exit node** for secure internet access

## Cluster Tailscale IPs

| Host | Tailscale IP | Role | Status |
|------|--------------|------|--------|
| **zephyr** | 100.YYY.YYY.YYY | Master/Exit Node | ✅ Active |
| **nexus** | 100.YYY.YYY.YYY | Build/AIStor | ✅ Active |
| **forge** | 100.YYY.YYY.YYY | Mining/GPU | ✅ Active |
| **sentry** | 100.YYY.YYY.YYY | Monitoring | ✅ Active |

## Configuration

Each host is configured in its respective `hosts/<host>/configuration.nix`:

```nix
# Tailscale mesh VPN with full features
services.tailscale-custom = {
  enable = true;
  advertiseRoutes = ["192.168.100.X/24"];      # Advertise local subnet
  acceptRoutes = true;                       # Accept routes from other nodes
  useRoutingFeatures = "both";              # Enable routing features
  enableSSH = true;                         # Enable Tailscale SSH
};
```

### Special Configuration for zephyr (Exit Node)

```nix
services.tailscale-custom = {
  enable = true;
  advertiseRoutes = ["192.168.100.X/24"];
  advertiseExitNode = true;  # Advertise as exit node for internet access
  acceptRoutes = true;
  useRoutingFeatures = "both";
  enableSSH = true;
};
```

## Features Enabled

### ✅ IP Forwarding
```nix
boot.kernel.sysctl = {
  "net.ipv4.ip_forward" = 1;
  "net.ipv6.conf.all.forwarding" = 1;
};
```

### ✅ Subnet Routing
All nodes advertise the 192.168.100.X/24 network, enabling:
- Access to local network devices via Tailscale
- Cross-node communication through local IPs
- Fallback routing if direct connections fail

### ✅ Tailscale SSH
Enabled on all nodes - allows SSH without traditional SSH keys:
```bash
ssh 100.YYY.YYY.YYY          # Connect to nexus
ssh nexus.tigris-ule.ts.net # Using Magic DNS
```

### ✅ Exit Node (zephyr)
Routes internet traffic through zephyr for:
- Secure browsing from any location
- Consistent IP address for services
- Bypassing local network restrictions

## Commands

### Check Status
```bash
# View all connected nodes
tailscale status

# Check network connectivity
tailscale netcheck

# Get your Tailscale IPs
tailscale ip --4
tailscale ip --6

# Ping another node
tailscale ping 100.YYY.YYY.YYY
tailscale ping nexus
```

### Connect/Disconnect
```bash
# Connect to Tailscale (uses stored auth key)
sudo tailscale up

# Connect with auth key (first time or re-auth)
sudo tailscale up --auth-key=tskey-auth-KEYHERE

# Connect as exit node (zephyr only)
sudo tailscale up --advertise-exit-node

# Disconnect
sudo tailscale down
```

### SSH Access
```bash
# SSH via Tailscale IP (no traditional SSH keys needed)
ssh 100.YYY.YYY.YYY           # zephyr
ssh 100.YYY.YYY.YYY          # nexus
ssh 100.YYY.YYY.YYY        # forge
ssh 100.YYY.YYY.YYY          # sentry

# SSH via Magic DNS
ssh zephyr.tigris-ule.ts.net
ssh nexus.tigris-ule.ts.net
```

### Using Exit Node
```bash
# Route all traffic through zephyr (on any client device)
tailscale up --exit-node=100.YYY.YYY.YYY

# Stop using exit node
tailscale up --exit-node=
```

## Magic DNS

All nodes are accessible via DNS names:
- `zephyr.tigris-ule.ts.net` → 100.YYY.YYY.YYY
- `nexus.tigris-ule.ts.net` → 100.YYY.YYY.YYY
- `forge.tigris-ule.ts.net` → 100.YYY.YYY.YYY
- `sentry.tigris-ule.ts.net` → 100.YYY.YYY.YYY

## Troubleshooting

### Node Not Connecting
```bash
# Check if tailscaled is running
systemctl status tailscaled

# Restart tailscaled
sudo systemctl restart tailscaled

# Check logs
journalctl -u tailscaled -f

# Re-authenticate if needed
sudo tailscale up --auth-key=tskey-auth-KEYHERE
```

### Forge TUN Device Issue (Fixed)
**Problem:** `/dev/net/tun` not found
**Solution:** Added `tun` kernel module to `boot.kernelModules`

```nix
boot.kernelModules = [
  "amdgpu"
  "tun"  # Required for Tailscale VPN
];

# Also added tmpfiles rule:
systemd.tmpfiles.rules = [
  "c /dev/net/tun 666 root root - - - -"  # Create TUN device for Tailscale
];
```

### Connectivity Issues
```bash
# Check if node is online
tailscale status | grep <hostname>

# Test direct connection
tailscale ping <ip>

# Check if using DERP relay (slower)
tailscale status  # Look for "relay" in output

# Check network path
tailscale ping --verbose <ip>
```

### Auth Key Expired
```bash
# Generate new auth key from Tailscale admin console
# https://login.tailscale.com/admin/settings/keys

# Then apply to node:
sudo tailscale up --auth-key=tskey-auth-NEWKEYHERE --reset
```

## Security

### Key Features
- **WireGuard encryption** - All traffic encrypted end-to-end
- **No open ports** - No inbound firewall rules needed
- **SSH authentication** - Uses Tailscale identity, no key management
- **Audit logging** - All connections logged in Tailscale admin panel

### Best Practices
1. **Use Tailscale SSH** instead of traditional SSH when possible
2. **Enable exit node only on trusted nodes** (zephyr is the exit node)
3. **Rotate auth keys** periodically from Tailscale admin console
4. **Monitor access** in Tailscale admin panel
5. **Disable unused nodes** to reduce attack surface

## Tailscale Admin Console

Access your tailnet settings:
- **URL:** https://login.tailscale.com/admin
- **Features:**
  - View all connected nodes
  - Check connection status
  - Manage auth keys
  - Configure ACLs (access control)
  - View audit logs
  - Enable/disable features

## GitOps Integration

The Tailscale configuration is managed via GitOps:

1. Changes to `modules/tailscale.nix` → committed to `main`
2. GitHub Actions validates the configuration
3. Auto-merges to `infra` branch
4. `just cluster-deploy` applies changes to all nodes

## Additional Resources

- **Tailscale Documentation:** https://tailscale.com/kb/
- **Tailscale SSH:** https://tailscale.com/kb/1193/tailscale-ssh
- **Subnet Routes:** https://tailscale.com/kb/1019/subnets
- **Exit Nodes:** https://tailscale.com/kb/1103/exit-nodes
- **Magic DNS:** https://tailscale.com/kb/1081/magic-dns

## Network Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                    Tailscale Control Plane                           │
│                        (coordination only)                           │
└─────────────────────────────────────────────────────────────────────┘
                                │
              ┌─────────────────┼─────────────────┐
              │                 │                 │
    ┌─────────▼────────┐ ┌──────▼──────┐ ┌───────▼───────┐
    │    zephyr      │ │    nexus    │ │     forge     │
    │  100.YYY.YYY.YYY  │ │100.YYY.YYY.YYY│ │100.YYY.YYY.YYY│
    │   Exit Node    │ │  Deploy     │ │   Mining      │
    │   Master       │ │  AIStor     │ │   Worker      │
    └────────┬────────┘ └──────┬──────┘ └───────┬───────┘
             │               │                │
             └───────────────┼────────────────┘
                             │
                    ┌────────▼────────┐
                    │    sentry      │
                    │ 100.YYY.YYY.YYY   │
                    │   Monitor      │
                    └─────────────────┘

All nodes can communicate directly via encrypted WireGuard tunnels.
Subnet 192.168.100.X/24 is advertised by all nodes.
Internet traffic can route through zephyr (exit node).
```

---

**Last Updated:** 2026-02-03  
**Status:** All 4 nodes connected and operational
