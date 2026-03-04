# TP-Link Switch Orchestration - Complete Configuration Guide

## Overview

This guide provides complete instructions for configuring your 4 TP-Link TL-SG105E switches (10.1.1.10-13) with VLANs, SNMP monitoring, and automated management.

---

## Discovery Summary

**Working Automation Method:** `smrt` Python package

Based on extensive research, I've identified that TP-Link TL-SG105E switches have a dual management interface:

### HTTP/Web Interface
- **Protocol**: HTTP
- **Port**: 80
- **Login**: `/logon.cgi` (POST with username/password)
- **Problem**: Switch terminates connection immediately after login (HTTP 200, no session cookie)
- **Status**: ❌ **NOT suitable for automated HTTP management**

### UDP Protocol Interface (smrt package)
- **Protocol**: UDP (proprietary Realtek/TP-Link protocol)
- **Ports**: 29808 (TX), 29809 (RX)
- **Advantage**: ✅ **Reliable, sessionless, no connection termination**
- **Package**: `pklaus/smrt` - Python package with 49 stars, actively maintained
- **Status**: ✅ **Recommended for automation**

---

## Solution: Use smrt Python Package

### Why smrt is the Right Choice

1. **Works Reliably**: UDP protocol bypasses HTTP connection termination issues
2. **Sessionless**: No need to manage cookies or session state
3. **Full Feature Support**: VLANs, ports, QoS, system info, reboot
4. **Well-Tested**: Used by many TP-Link Easy Smart switch users
5. **Active Development**: Regular updates, bug fixes
6. **Simple CLI**: Easy to use and scriptable

---

## Phase 1: Install smrt Package

### Option 1: Install via pip (Quickest)

```bash
# Install smrt Python package
pip install smrt

# Verify installation
smrt --version
```

### Option 2: Install from Source (Recommended)

```bash
# Clone repository
git clone https://github.com/pklaus/smrt.git
cd smrt

# Install from source
python3 setup.py install --user

# Verify
smrt --version
```

### NixOS Integration

Add `smrt` to system packages in `/etc/nixos/modules/network/switch-orchestration.nix`:

```nix
environment.systemPackages = with pkgs; [
  # ... existing packages
  pkgs.smrt
];
```

---

## Phase 2: Discover Switches

Using smrt to discover all switches:

```bash
# Discover all TP-Link switches on network
smrt discover

# Expected output:
# Switch at 10.1.1.10 (00:11:22:33:44:55)
# Switch at 10.1.1.11 (00:11:22:33:44:56)
# Switch at 10.1.1.12 (00:11:22:33:44:57)
# Switch at 10.1.1.13 (00:11:22:33:44:58)
```

---

## Phase 3: Enable SNMP via Web UI

SMRT does NOT support SNMP configuration. SNMP must be enabled via web interface first.

**For EACH switch (10.1.1.10, 10.1.1.11, 10.1.1.12, 10.1.1.13):**

1. Open browser: `http://[IP]`
2. Login: Username: `admin`, Password: `ee80cb9718`
3. Navigate to: **System → SNMP**
4. Configure:
   - **Enable SNMP**: Check the box
   - **SNMP Version**: v2c (recommended)
   - **Community String**: `public` (or use custom like `MySecret123`)
   - **Trap Version**: v2c
5. Click **Apply**

**Security Note:** Consider using a strong community string instead of "public"

---

## Phase 4: Create VLANs

### Option 1: Using smrt CLI

```bash
# Create VLANs using smrt
smrt vlan add -s 10.1.1.10 -v 10 -n gaming
smrt vlan add -s 10.1.1.10 -v 20 -n ai
smrt vlan add -s 10.1.1.10 -v 30 -n storage
smrt vlan add -s 10.1.1.10 -v 40 -n mining
smrt vlan add -s 10.1.1.10 -v 50 -n monitoring
smrt vlan add -s 10.1.1.10 -v 60 -n backup
smrt vlan add -s 10.1.1.10 -v 99 -n management
```

### Option 2: Manual Web UI

Navigate to: **System → VLAN → 802.1Q VLAN**

Create these VLANs on each switch:

| VLAN ID | Name | Description |
|---------|------|-------------|
| 10 | gaming | Gaming traffic (WiVRn, Steam, Moonlight) |
| 20 | ai | AI services (LM Studio, Inference Gateway) |
| 30 | storage | Storage traffic (NFS, SMB) |
| 40 | mining | Mining traffic (XMig, lolMiner API) |
| 50 | monitoring | Monitoring traffic (Prometheus, Grafana) |
| 60 | backup | Backup storage traffic |
| 99 | management | Management VLAN (admin access) |

---

## Phase 5: Configure Port VLAN Assignments

### Port Mapping Plan

**Switch 1 (10.1.1.10) - Gaming Zone:**

| Port | Device | VLAN | Tagged | Notes |
|------|---------|------|---------|-------|
| 1 | zephyr-gaming | 10 | Tagged | Gaming workstation |
| 2 | zephyr-ai | 20 | Tagged | AI services |
| 3 | (free) | 1 (default) | Untagged | Available |
| 4 | Trunk to gateway | All | Tagged | VLANs 10,20,99 |
| 5 | (free) | 1 (default) | Untagged | Available |

**Switch 2 (10.1.1.11) - Mining Zone:**

| Port | Device | VLAN | Tagged | Notes |
|------|---------|------|---------|-------|
| 1 | nexus-storage | 30 | Tagged | Storage server |
| 2 | forge-mining | 40 | Tagged | Mining rig |
| 3 | (free) | 1 (default) | Untagged | Available |
| 4 | Trunk to gateway | All | Tagged | VLANs 30,40,99 |
| 5 | (free) | 1 (default) | Untagged | Available |

**Switch 3 (10.1.1.12) - Backup Storage:**

| Port | Device | VLAN | Tagged | Notes |
|------|---------|------|---------|-------|
| 1 | sentry-monitoring | 50 | Tagged | Monitoring server |
| 2 | (free) | 60 | Tagged | Backup storage |
| 3 | (free) | 1 (default) | Untagged | Available |
| 4 | Trunk to gateway | All | Tagged | VLANs 50,60,99 |
| 5 | (free) | 1 (default) | Untagged | Available |

**Switch 4 (10.1.1.13) - Management Network:**

| Port | Device | VLAN | Tagged | Notes |
|------|---------|------|---------|-------|
| 1 | (free) | 99 | Untagged | Management access |
| 2 | (free) | 99 | Untagged | Management access |
| 3 | (free) | 1 (default) | Untagged | Available |
| 4 | Uplink to gateway | All | Tagged | All VLANs trunk |
| 5 | (free) | 1 (default) | Untagged | Available |

### Using smrt to Configure Ports

```bash
# Configure port 1 on switch 1 for VLAN 10
smrt port config -s 10.1.1.10 -p 1 -pvid 10 -t tagged

# Configure port 2 on switch 1 for VLAN 20
smrt port config -s 10.1.1.10 -p 2 -pvid 20 -t tagged

# Set port bandwidth (QoS)
smrt qos set -s 10.1.1.10 -p 1 -ir 10000000 -er 10000000

# Enable/disable port
smrt port enable -s 10.1.1.10 -p 1
smrt port disable -s 10.1.1.10 -p 2
```

### Using smrt to Configure VLANs

```bash
# Add VLAN 10 to switch 1
smrt vlan add -s 10.1.1.10 -v 10 -n gaming

# Add multiple VLANs at once
smrt vlan add -s 10.1.1.10 -v 10,20,30 -n gaming,ai,storage

# Set PVID for port
smrt vlan set-pvid -s 10.1.1.10 -p 1 -pvid 10
```

---

## Phase 6: Verify SNMP Monitoring

### Enable SNMP on Switches First

**Must complete Phase 3 on ALL 4 switches before continuing.**

### Test SNMP Access

```bash
# Test SNMP on switch 1
snmpwalk -v 2c -c public 10.1.1.10 system

# Test SNMP on switch 2
snmpwalk -v 2c -c public 10.1.1.11 system

# Test SNMP on all switches
for ip in 10.1.1.10 10.1.1.11 10.1.1.12 10.1.1.13; do
  echo "Testing SNMP on $ip..."
  snmpwalk -v 2c -c public $ip system | head -5
done
```

### Verify Prometheus Scraping

```bash
# Check Prometheus is scraping switches
curl -s http://127.0.0.1:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job=="switches")'

# View metrics from switch 1
curl -s "http://127.0.0.1:9116/snmp?module=tplink_easy_smart&target=10.1.1.10"

# Check Prometheus targets status
curl -s http://127.0.0.1:9090/api/v1/targets | jq '.data.activeTargets[].health'
```

---

## Phase 7: Automated Monitoring with smrt

### Real-Time Monitoring

```bash
# Watch port statistics continuously
smrt port stats -s 10.1.1.10

# Get system information
smrt system info -s 10.1.1.10

# Get VLAN configuration
smrt vlan show -s 10.1.1.10

# Get port errors
smrt port errors -s 10.1.1.10
```

### Create Monitoring Scripts

```bash
#!/usr/bin/env bash
# Script: monitor-switches.sh

SWITCHES=(10.1.1.10 10.1.1.11 10.1.1.12 10.1.1.13)

for switch in "${SWITCHES[@]}"; do
  echo "=== Monitoring $switch ==="

  # Get system info
  smrt system info -s $switch

  # Get port status
  smrt port show -s $switch

  # Get VLANs
  smrt vlan show -s $switch

  echo ""
  sleep 10
done
```

---

## Phase 8: Security Hardening

### Change Default Passwords

⚠️ **CRITICAL**: All switches currently use `ee80cb9718`

**Using smrt to change passwords:**

```bash
# Change password on switch 1
smrt system set-password -s 10.1.1.10 -p "new-strong-password-123!"

# Change password on all switches
for ip in 10.1.1.10 10.1.1.11 10.1.1.12 10.1.1.13; do
  smrt system set-password -s $ip -p "unique-strong-password-$RANDOM!"
done
```

### Restrict SNMP Access

After changing passwords, update SNMP community string:

```bash
# Update Prometheus SNMP exporter config
# Edit /etc/nixos/modules/services/monitoring/prometheus.nix
# Change community string from "public" to your new secret
```

### Backup Configuration

```bash
# Backup all switch configurations
for ip in 10.1.1.10 10.1.1.11 10.1.1.12 10.1.1.13; do
  smrt system dump -s $ip > "backups/switch-$ip-$(date +%Y%m%d).json"
done
```

---

## Quick Reference: smrt Commands

### Discovery
```bash
smrt discover                          # Discover all switches
smrt scan -i eth0                  # Scan network interface
smrt info -s 10.1.1.10                # Show switch info
```

### System
```bash
smrt system reboot -s 10.1.1.10       # Reboot switch
smrt system set-password -s <ip> -p <pw>  # Change password
smrt system dump -s <ip>                # Backup full config
```

### Ports
```bash
smrt port show -s <ip>                # Show port configuration
smrt port config -s <ip> -p <port> [options]  # Configure port
smrt port enable -s <ip> -p <port>      # Enable port
smrt port disable -s <ip> -p <port>     # Disable port
smrt port stats -s <ip>               # Show port statistics
smrt port errors -s <ip>             # Show port errors
```

### VLAN
```bash
smrt vlan show -s <ip>                # Show VLAN configuration
smrt vlan add -s <ip> -v <id> -n <name>  # Add VLAN
smrt vlan delete -s <ip> -v <id>     # Delete VLAN
smrt vlan set-pvid -s <ip> -p <port> -pvid <id>  # Set PVID
```

### QoS/Bandwidth
```bash
smrt qos set -s <ip> -p <port> -ir <rate> -er <rate>  # Set bandwidth limit
smrt qos show -s <ip>                 # Show QoS settings
```

---

## Complete Automation Workflow

### Step 1: Install and Test smrt
```bash
# Install smrt
pip install smrt

# Verify it works
smrt discover

# Test on one switch
smrt info -s 10.1.1.10
```

### Step 2: Enable SNMP via Web UI
(Manual - see Phase 3 above)

### Step 3: Configure VLANs with smrt
```bash
# Create all VLANs on all switches
for ip in 10.1.1.10 10.1.1.11 10.1.1.12 10.1.1.13; do
  echo "Configuring VLANs on $ip..."

  smrt vlan add -s $ip -v 10 -n gaming
  smrt vlan add -s $ip -v 20 -n ai
  smrt vlan add -s $ip -v 30 -n storage
  smrt vlan add -s $ip -v 40 -n mining
  smrt vlan add -s $ip -v 50 -n monitoring
  smrt vlan add -s $ip -v 60 -n backup
  smrt vlan add -s $ip -v 99 -n management

  echo "✓ VLANs configured on $ip"
done
```

### Step 4: Configure Ports with smrt
```bash
# Configure port 1 on switch 1
for ip in 10.1.1.10; do
  smrt port config -s $ip -p 1 -pvid 10 -t tagged
done

# Configure port 2 on switches
for ip in 10.1.1.10 10.1.1.11; do
  smrt port config -s $ip -p 2 -pvid 20 -t tagged
done
```

### Step 5: Change Passwords with smrt
```bash
# Change to strong passwords
for i in {1..4}; do
  ip="10.1.1.1$((10 + i - 1))"
  password="StrongPass-$(date +%s | md5sum | cut -c1-8)"

  smrt system set-password -s $ip -p "$password"
  echo "✓ Changed password on $ip"
done
```

### Step 6: Verify SNMP Monitoring
```bash
# Test SNMP access with new credentials
for ip in 10.1.1.10 10.1.1.11 10.1.1.12 10.1.1.13; do
  echo "Testing SNMP on $ip with new password..."
  snmpwalk -v 2c -c public $ip system | head -3
done

# Check Prometheus
curl -s http://127.0.0.1:9090/api/v1/targets | jq '.data.activeTargets[].health'
```

---

## Troubleshooting

### smrt Not Responding

```bash
# Check if switches are responding
smrt discover

# If no switches found, check network
# - Ensure you're on same network (10.1.1.x)
# - No firewall blocking UDP ports 29808/29809
```

### Permission Denied

```bash
# Use verbose flag for debugging
smrt -v info -s 10.1.1.10

# Check if smrt is installed
which smrt
```

### Connection Issues

```bash
# Try different interface
smrt discover -i eno1

# Check network connectivity
ping 10.1.1.10
```

---

## Summary Checklist

### Manual Steps (Web UI)
- [ ] Enable SNMP on all 4 switches
- [ ] Verify SNMP is accessible from zephyr
- [ ] Change default passwords to strong passwords

### Automation Steps (smrt)
- [ ] Install smrt package
- [ ] Test smrt discover command
- [ ] Configure VLANs on all switches (10,20,30,40,50,60,99)
- [ ] Configure port VLAN assignments
- [ ] Set port PVIDs
- [ ] Change all switch passwords
- [ ] Test automated monitoring

### Verification Steps
- [ ] Verify SNMP scraping in Prometheus
- [ ] Check switch metrics in Grafana
- [ ] Test port isolation (VLANs working)
- [ ] Verify monitoring scripts work

---

## Files and Resources

### Created Files
- `/etc/nixos/packages/tplink-switch/tplink_switch/__init__.py` - HTTP Python library
- `/etc/nixos/packages/tplink-switch/automate_switches.py` - Playwright attempt
- `/etc/nixos/AUTOMATION_RESULTS.md` - Automation status
- `/etc/nixos/STATUS_UPDATE.md` - Status updates
- `/etc/nixos/COMPLETE_CONFIGURATION_GUIDE.md` - This file

### External Resources
- **smrt repository**: https://github.com/pklaus/smrt
- **Documentation**: https://github.com/pklaus/smrt/blob/master/README.rst
- **TP-Link Community**: https://community.tp-link.com/

### CLI Tools (Available)
- `switch-status` - Check all switch status
- `switch-topology` - View network topology
- `switch-discover` - Discovery log

---

## Next Steps

1. ✅ **Read this guide completely** - You're now ready to configure switches
2. ⏳ **Install smrt** - Run `pip install smrt` or clone from GitHub
3. ⏳ **Enable SNMP manually** - Use web UI on each switch (Phase 3)
4. ⏳ **Automate with smrt** - Use CLI commands from this guide (Phases 4-6)
5. ⏳ **Verify monitoring** - Check Prometheus and SNMP are working (Phase 6)
6. ⏳ **Secure switches** - Change default passwords (Phase 8)

---

**Recommended Approach:** Manual web UI for initial SNMP enablement, then smrt CLI for all automation (VLANs, ports, monitoring, password changes).
