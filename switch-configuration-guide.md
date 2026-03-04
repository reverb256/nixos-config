# TP-Link Switch Configuration Guide
# For TL-SG105E Easy Smart Switches

## Current State
- All 4 switches (10.1.1.10-13) are ONLINE
- NixOS module is configured but CLI tools not yet installed
- SNMP is not yet enabled on switches (requires manual web UI configuration)

## Required Manual Steps

### 1. Enable SNMP on Each Switch
**Access each switch web UI:**
- http://10.1.1.10 (Switch 1 - Gaming Zone)
- http://10.1.1.11 (Switch 2 - Mining Zone)
- http://10.1.1.12 (Switch 3 - Backup Storage)
- http://10.1.1.13 (Switch 4 - Management Network)

**Credentials:**
- Username: `admin`
- Password: `ee80cb9718`

**Steps to enable SNMP:**
1. Login to web UI
2. Navigate to: System → SNMP (or System Management → SNMP)
3. Enable SNMP: Set to "Enable"
4. SNMP Version: v2c (recommended)
5. Community String: `public` (or set custom string)
6. Click Apply/Save

**Security Note:** Consider using a custom SNMP community string instead of "public".

### 2. Verify SNMP Access
After enabling SNMP, test with:
```bash
snmpwalk -v 2c -c public 10.1.1.10 1.3.6.1.2.1
snmpwalk -v 2c -c public 10.1.1.11 1.3.6.1.2.1
snmpwalk -v 2c -c public 10.1.1.12 1.3.6.1.2.1
snmpwalk -v 2c -c public 10.1.1.13 1.3.6.1.2.1
```

### 3. Configure VLANs
**VLAN Plan:**
| VLAN ID | Name | Description | Priority |
|---------|------|-------------|----------|
| 10 | gaming | Gaming traffic (WiVRn, Steam, Moonlight) | 1 |
| 20 | ai | AI services (LM Studio, Inference Gateway) | 1 |
| 30 | storage | Storage traffic (NFS, SMB) | 1 |
| 40 | mining | Mining traffic (XMig, lolMiner API) | 1 |
| 50 | monitoring | Monitoring traffic (Prometheus, Grafana) | 1 |
| 60 | backup | Backup storage traffic | 1 |
| 99 | management | Switch management VLAN | 0 |

**Steps per switch:**
1. Login to web UI
2. Navigate to: VLAN → 802.1Q VLAN
3. Create VLANs with IDs above
4. Assign VLAN names and descriptions
5. Click Apply/Save

### 4. Configure Port Assignments
**Port Mapping Plan:**

**Switch 1 (10.1.1.10) - Gaming Zone:**
| Port | Device | VLAN | Tagged |
|------|---------|------|--------|
| 1 | zephyr-gaming | VLAN 10 | Tagged |
| 2 | zephyr-ai | VLAN 20 | Tagged |
| 3 | (free) | VLAN 1 (default) | Untagged |
| 4 | (uplink) | Trunk (all) | Tagged (10,20,99) |
| 5 | (free) | VLAN 1 (default) | Untagged |

**Switch 2 (10.1.1.11) - Mining Zone:**
| Port | Device | VLAN | Tagged |
|------|---------|------|--------|
| 1 | nexus-storage | VLAN 30 | Tagged |
| 2 | forge-mining | VLAN 40 | Tagged |
| 3 | (free) | VLAN 1 (default) | Untagged |
| 4 | (uplink) | Trunk (all) | Tagged (30,40,99) |
| 5 | (free) | VLAN 1 (default) | Untagged |

**Switch 3 (10.1.1.12) - Backup Storage:**
| Port | Device | VLAN | Tagged |
|------|---------|------|--------|
| 1 | sentry-monitoring | VLAN 50 | Tagged |
| 2 | (free) | VLAN 60 (backup) | Tagged |
| 3 | (free) | VLAN 1 (default) | Untagged |
| 4 | (uplink) | Trunk (all) | Tagged (50,60,99) |
| 5 | (free) | VLAN 1 (default) | Untagged |

**Switch 4 (10.1.1.13) - Management Network:**
| Port | Device | VLAN | Tagged |
|------|---------|------|--------|
| 1 | (free) | VLAN 99 (management) | Untagged |
| 2 | (free) | VLAN 99 (management) | Untagged |
| 3 | (free) | VLAN 1 (default) | Untagged |
| 4 | (uplink to gateway) | Trunk (all) | Tagged (all) |
| 5 | (free) | VLAN 1 (default) | Untagged |

## Automated Configuration (After Manual Setup)

Once CLI tools are fixed and installed:
```bash
# Check switch status
switch-status

# Get switch system info
switch-ctl info 10.1.1.10

# Get port status
switch-ctl ports 10.1.1.10

# Get VLAN configuration
switch-ctl vlan 10.1.1.10

# Enable/disable a port
switch-ctl port-set 10.1.1.10 3 1  # Enable port 3
switch-ctl port-set 10.1.1.10 3 0  # Disable port 3
```

## Prometheus Monitoring

Once SNMP is enabled, verify Prometheus is scraping:
```bash
# Check Prometheus targets
curl -s http://127.0.0.1:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job=="switches")'

# Check SNMP exporter is running
systemctl status snmp-exporter-switches.service

# View metrics
curl -s http://127.0.0.1:9116/snmp?module=tplink_easy_smart&target=10.1.1.10
```

## Security Recommendations

1. **Change Default Passwords**: All switches use `ee80cb9718` - this is weak!
2. **Enable HTTPS**: Currently only HTTP is available
3. **Restrict SNMP Access**: Only allow Prometheus server IP
4. **VLAN Segmentation**: Implement to isolate traffic
5. **Regular Audits**: Review switch logs and access patterns

## Troubleshooting

### Cannot Access Switch
```bash
# Check if switch is responding
ping 10.1.1.10

# Check web UI
curl http://10.1.1.10

# Check SNMP (after enabling)
snmpwalk -v 2c -c public 10.1.1.10 system
```

### SNMP Not Working
```bash
# Verify SNMP is enabled
curl http://10.1.1.10/snmp  # Check if SNMP page loads

# Check firewall
sudo nft list rules | grep 161

# Check SNMP exporter logs
journalctl -u snmp-exporter-switches -f
```

## Next Steps

1. ✅ Manually enable SNMP on all 4 switches
2. ✅ Configure VLANs on switches
3. ✅ Configure port VLAN assignments
4. ⏳ Fix NixOS module to install CLI tools (in progress)
5. ⏳ Verify Prometheus monitoring works
6. ⏳ Test automated switch management
