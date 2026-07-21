# Cluster Recovery Plan - 2026-03-27

## Current Status

### Working Nodes
- ✅ **Zephyr (10.1.1.110)**: Fully operational
  - DNS working
  - SSH working
  - Kubernetes Ready
  - All services operational

- ⚠️  **Sentry (10.1.1.140)**: Partially operational
  - Kubernetes Ready
  - SSH blocked (firewall issue)
  - Pods running but can't exec/logs

### Failed Nodes
- ❌ **Nexus (10.1.1.120)**: Complete network failure
  - SSH timeout
  - Ping unreachable
  - Kubernetes NotReady
  - **CAUSE**: Deployment broke network stack

- ❌ **Forge (10.1.1.130)**: Complete network failure
  - SSH timeout
  - Ping unreachable
  - Kubernetes NotReady
  - **CAUSE**: Deployment broke network stack

## What Happened

1. Attempted to deploy cluster-networking.nix to Nexus
2. Deployment failed due to DNS resolution issues (couldn't reach cache.nixos.org)
3. NetworkManager restart during deployment broke network connectivity
4. Nexus went completely offline
5. Attempt to deploy to Forge/Sentry failed (they were already unreachable)

## Recovery Steps

### IMMEDIATE: Recover Nexus and Forge

**Option 1: Hard Reboot (FASTEST)**
```bash
# Physically power cycle Nexus and Forge
# Or if you have IPMI/iDRAC:
ipmitool -H <nexus-ip> power cycle
ipmitool -H <forge-ip> power cycle
```

**Option 2: Console Recovery**
```bash
# Physical keyboard/monitor or serial console
# Login and check network:
sudo systemctl status NetworkManager
sudo systemctl restart NetworkManager
sudo systemctl restart networking
```

**Option 3: Tailscale Recovery (if Tailscale is running)**
```bash
# From Zephyr, try Tailscale SSH:
ssh root@100.92.246.98  # Nexus Tailscale IP
ssh root@100.x.x.x      # Forge Tailscale IP

# Then restart NetworkManager:
sudo systemctl restart NetworkManager
```

### AFTER NODES RECOVER: Deploy DNS Fix

Once nodes are back online, deploy the DNS firewall fix:

```bash
# From Zephyr:
just deploy nexus
just deploy forge
just deploy sentry

# This will apply the permanent DNS firewall rules
```

## DNS Fix Details

The fix adds these rules to `/etc/nixos/modules/system/networking.nix`:

```nix
# Allow DNS traffic (prevent Calico/K8s from blocking DNS)
iptables -C OUTPUT -p udp --dport 53 -j ACCEPT || iptables -I OUTPUT 1 -p udp --dport 53 -j ACCEPT
iptables -C OUTPUT -p udp --dport 853 -j ACCEPT || iptables -I OUTPUT 2 -p udp --dport 853 -j ACCEPT
iptables -C INPUT -p udp --sport 53 -j ACCEPT || iptables -I INPUT 3 -p udp --sport 53 -j ACCEPT
iptables -C INPUT -p udp --sport 853 -j ACCEPT || iptables -I INPUT 4 -p udp --sport 853 -j ACCEPT
iptables -C INPUT -p tcp --sport 53 -j ACCEPT || iptables -I INPUT 5 -p tcp --sport 53 -j ACCEPT
iptables -C INPUT -p tcp --sport 853 -j ACCEPT || iptables -I INPUT 6 -p tcp --sport 853 -j ACCEPT

# Allow DNS through Calico chains
iptables -I cali-INPUT 1 -p udp --dport 53 -j ACCEPT
iptables -I cali-INPUT 2 -p udp --sport 53 -j ACCEPT
```

## Backup DNS Configuration

If DNS breaks again, emergency fallback:

```bash
# Restore backup DNS config:
sudo cp /etc/resolv.conf.backup /etc/resolv.conf

# Or manually:
echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf
echo "nameserver 8.8.4.4" | sudo tee -a /etc/resolv.conf
```

## Current Workloads Status

### Mining Pods (7 total)
- ✅ gpu-miner-forge-nvidia-0: Running
- ✅ gpu-miner-forge-nvidia-1: Running
- ✅ gpu-miner-nexus: Running

### Kubernetes Status
- Control plane: 2/4 nodes ready (Zephyr, Sentry)
- Calico: Degraded (3/4 nodes failing)
- CoreDNS: Working on Zephyr
- 70 pods affected by node failures

## Prevention

**DO NOT deploy to multiple nodes simultaneously when:**
1. DNS is unstable
2. Network is being reconfigured
3. Multiple deployments are running

**Safe deployment pattern:**
```bash
# Test locally first
just switch

# If successful, deploy ONE remote node
just deploy nexus

# Wait for node to recover, verify with:
ssh nexus "systemctl is-active NetworkManager"

# Then deploy next node
just deploy forge
```

## Created: 2026-03-27 10:47 CDT
## Status: AWAITING NODE RECOVERY
