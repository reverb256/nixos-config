# Network Discovery Report - TP-Link Switch Infrastructure
# Generated: 2026-03-04

# Executive Summary
# -----------------
This report documents the discovery and analysis of 4 TP-Link switches deployed in the zephyr cluster.
All switches are currently operational and accessible via their management interfaces.

# Network Infrastructure Overview
# -----------------------------

| Component | IP Address | Status | Model | Zone |
|-----------|-------------|---------|---------|-------|
| Switch 1 | 10.1.1.10 | UP | TL-SG105E | Gaming Zone |
| Switch 2 | 10.1.1.11 | UP | TL-SG105E | Mining Zone |
| Switch 3 | 10.1.1.12 | UP | TL-SG105E | Backup Storage |
| Switch 4 | 10.1.1.13 | UP | TL-SG105E | Management Network |

# Switch Capabilities
# -------------------

## TL-SG105E Specifications

- **Ports**: 5 Gigabit ports
- **Management**: Web UI (HTTP) + CLI access
- **Login**: admin/ee80cb9718 (default credentials - CHANGE THIS!)
- **Protocol**: HTTP (port 80)
- **Firmware**: 2023 vintage
- **VLAN Support**: Full 802.1Q VLAN tagging
- **SNMP Support**: SNMPv2/v3
- **Management Interface**: Simple web interface with CGI backend

# Network Topology
# ----------------

```
                    ┌─────────────────────────────────────────────────┐
                    │          Internet Gateway                  │
                    │          10.1.1.1                      │
                    └──────────────┬──────────────────────────┘
                                   │
                     ┌─────────────┴─────────────┐
                     │                           │
                     ▼                           ▼
           ┌─────────────────┐       ┌─────────────────┐
           │ Switch 1       │       │ Switch 4       │
           │ 10.1.1.10      │       │ 10.1.1.13      │
           │ Gaming Zone     │       │ Management      │
           └────────┬────────┘       └────────┬────────┘
                    │                           │
            ┌───────────┴───────────┐       │
            │                       │       │
            ▼                       ▼       ▼
    ┌───────────┐      ┌───────────┐  ┌───────────┐
    │ zephyr     │      │ nexus     │  │ sentry    │
    │ 10.1.1.110 │      │ 10.1.1.120 │  │ 10.1.1.140 │
    └───────────┘      └───────────┘  └───────────┘
            │                       │
            └───────────┬───────────┘
                        │
                        ▼
               ┌─────────────────┐
               │ Switch 2       │
               │ 10.1.1.11      │
               │ Mining Zone     │
               └────────┬────────┘
                        │
                        ▼
                 ┌───────────┐
                 │ forge     │
                 │ 10.1.1.130 │
                 └───────────┘
```

# Current Host Assignments (Proposed)
# ----------------------------------

| Host | Interface | Switch | Port | VLAN | Zone |
|------|-----------|---------|-------|------|
| zephyr | eth0 (gaming) | Switch 1 (10.1.1.10) | Port 1 | VLAN 10 |
| zephyr | eth1 (AI) | Switch 1 (10.1.1.10) | Port 2 | VLAN 20 |
| nexus | eth0 (storage) | Switch 2 (10.1.1.11) | Port 1 | VLAN 30 |
| forge | eth0 (mining) | Switch 2 (10.1.1.11) | Port 2 | VLAN 40 |
| sentry | eth0 (monitor) | Switch 3 (10.1.1.12) | Port 1 | VLAN 50 |

# VLAN Segmentation Strategy
# -------------------------

| VLAN ID | Name | Description | Priority | Hosts |
|---------|------|-------------|----------|--------|
| 10 | gaming | Gaming traffic (WiVRn, Steam, Moonlight) | 1 | zephyr-gaming |
| 20 | ai | AI services (LM Studio, Inference Gateway) | 1 | zephyr-ai |
| 30 | storage | Storage traffic (NFS, SMB) | 1 | nexus-storage |
| 40 | mining | Mining traffic (XMig, lolMiner API) | 1 | forge-mining |
| 50 | monitoring | Monitoring traffic (Prometheus, Grafana) | 1 | sentry-monitor |
| 60 | backup | Backup storage traffic | 1 | TBD |
| 99 | management | Switch management VLAN | 0 | All switches |

# Orchestration Capabilities
# ---------------------------

## Current State
- ✅ Switch Discovery: Manual (curl-based)
- ✅ Status Monitoring: ping + port check
- ✅ Topology Documentation: Available (switch-topology)
- ⚠️  API Access: Requires authentication
- ❌ Automated Configuration: Not implemented
- ❌ Real-time Monitoring: Not integrated with Prometheus

## NixOS Module Implementation

A new module has been created at:
```
/etc/nixos/modules/network/switch-orchestration.nix
```

This module provides:
- `networking.switch-orchestration.enable` - Enable switch orchestration
- `networking.switch-orchestration.switches` - Switch configuration
- `networking.switch-orchestration.vlans` - VLAN definitions
- `networking.switch-orchestration.port_assignments` - Host-to-switch mapping

CLI Tools:
- `switch-discover` - Discover all switches and status
- `switch-status` - Check switch availability
- `switch-topology` - Display network topology

# Next Steps for Full Orchestration
# ----------------------------------

## Phase 1: Credential Management
1. Store switch passwords via agenix
2. Rotate default credentials (ee80cb9718 is weak)
3. Implement separate admin credentials per switch

## Phase 2: API Integration
1. Implement POST-based login to /logon.cgi
2. Extract session cookies
3. Access configuration pages
4. Document API endpoints for:
   - VLAN configuration
   - Port settings
   - LACP/port-channeling
   - QoS settings

## Phase 3: Monitoring Integration
1. Enable SNMP on switches
2. Create SNMP exporter for Prometheus
3. Monitor:
   - Port status
   - Traffic statistics
   - Error rates
   - CPU/memory usage

## Phase 4: Automation
1. Implement automated VLAN provisioning
2. Create topology change detection
3. Implement failover between switches
4. Add network performance optimization

# Security Recommendations
# ------------------------

1. **Change Default Passwords**: All switches use ee80cb9718 - MUST CHANGE
2. **Enable HTTPS**: Current web UI uses HTTP only
3. **VLAN Segmentation**: Isolate gaming, mining, and monitoring traffic
4. **Access Control**: Restrict web UI access to management VLAN only
5. **Audit Logging**: Regularly review switch logs

# Troubleshooting
# --------------

## Cannot Access Switch Web UI
1. Check physical connection: `ping 10.1.1.X`
2. Check web UI: `curl http://10.1.1.X`
3. Verify credentials: admin/ee80cb9718
4. Try direct cable connection to isolate network issues

## Switch Not Responding
1. Check power to switch
2. Verify port LEDs on switch
3. Check connected cable: `ethtool <interface>`
4. Try connecting to another port

# Network Performance Issues
1. Check for cable damage (CRC errors)
2. Verify VLAN tagging is correct
3. Check for spanning tree blocking
4. Review QoS settings for traffic shaping

# Appendix: Switch Access Commands
# ---------------------------------

## Manual Access via Web UI
```
URL: http://10.1.1.X
Username: admin
Password: ee80cb9718
```

## Manual Access via CLI (SSH/Telnet)
Note: TP-Link switches typically don't support SSH/Telnet CLI access.

## SNMP Access (if enabled)
```
snmpwalk -v 2c -c ee80cb9718 10.1.1.X 1.3.6.1.2.1
```

# Conclusion
# ----------

All 4 TP-Link switches are operational and ready for orchestration. The NixOS module provides a foundation for automated switch management. Priority tasks are:

1. Secure credentials via agenix
2. Implement API-based configuration
3. Add SNMP monitoring
4. Deploy VLAN segmentation

This infrastructure provides a solid foundation for network orchestration of the zephyr cluster.
