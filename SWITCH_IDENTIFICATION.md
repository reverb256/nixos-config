# Switch Identification Summary

**Last Updated**: 2026-03-10
**Status**: All switches reconfigured to sequential IPs

## FINAL SWITCH CONFIGURATION

All 4 switches are now configured with sequential IP addresses for easy management.

| Switch | IP Address | MAC Address | Model | Status |
|--------|------------|-------------|-------|--------|
| **sw1-modem** | **10.1.1.10** | 8C:90:2D:AE:4D:27 | TL-SG105E 5.0 | ✅ Root/Gateway Switch |
| **sw2-tv** | **10.1.1.11** | 60:83:E7:F7:DF:C4 | TL-SG105E 5.0 | ✅ TV Area Switch (Nexus) |
| **sw3-upstairs** | **10.1.1.12** | 60:83:E7:F7:F4:6C | TL-SG105E 5.0 | ✅ Distribution Switch |
| **sw4-zephyr** | **10.1.1.13** | A8:29:48:02:2A:1D | TL-SG105E 5.0 | ✅ Zephyr Room Switch |

## Switch Roles & VLANs

| Switch | Role | VLANs Carried | Trunk Connections |
|--------|------|---------------|-------------------|
| sw1-modem | Root/Gateway | All (distribution) | sw3-upstairs, sw2-tv |
| sw2-tv | Access (Nexus) | 99, 30, 60 | sw1-modem |
| sw3-upstairs | Distribution | All | sw1-modem, sw4-zephyr |
| sw4-zephyr | Access (Zephyr) | All | sw3-upstairs |

## Port Configuration Summary

### sw1-modem (10.1.1.10) - Root/Gateway
- Port 1: Modem/Gateway (trunk: all VLANs)
- Port 2: Printer (VLAN 10 - gaming/work)
- Port 3: Deco XE75 WiFi (VLANs 10, 99 - gaming + management)
- Port 4: sw3-upstairs TRUNK (trunk: all VLANs)
- Port 5: sw2-tv TRUNK (trunk: VLANs 99, 30, 60)

### sw2-tv (10.1.1.11) - TV Area
- Port 1: sw1-modem TRUNK (VLANs 99, 30, 60)
- Port 2: Nexus (trunk: VLANs 99, 30, 60)
- Port 3: krash3 PC (VLAN 10 - gaming)
- Port 4: krash1.5 PC (VLAN 10 - gaming)
- Port 5: Available

### sw3-upstairs (10.1.1.12) - Distribution
- Port 1: sw1-modem TRUNK (all VLANs)
- Port 2: sw4-zephyr TRUNK (all VLANs)
- Port 3: WIP PC (VLAN 99 or 10)
- Port 4: Sentry (trunk: VLANs 99, 40, 50)
- Port 5: Forge (trunk: VLANs 99, 20, 40)

### sw4-zephyr (10.1.1.13) - Zephyr Room
- Port 1: sw3-upstairs TRUNK (all VLANs)
- Port 2: Available
- Port 3: Deco XE75 6GHz (VLANs 10, 99)
- Port 4: Available
- Port 5: Zephyr (trunk: VLANs 99, 10, 20)

## 7 VLAN Configuration

All switches configured with the following VLANs:
- VLAN 10 (gaming): VR streaming, gaming traffic
- VLAN 20 (ai): AI/ML workloads
- VLAN 30 (storage): NFS/cluster storage
- VLAN 40 (mining): GPU mining
- VLAN 50 (monitoring): Prometheus/Grafana
- VLAN 60 (backup): Backup operations
- VLAN 99 (management): Switch management, K8s control plane

## Credentials

- Username: `admin`
- Password: `ee80cb9718`

## Reference Documents

- Design document: `/etc/nixos/docs/plans/2026-03-09-switch-vlan-design.md`
- Network map: `/etc/nixos/docs/networking/network-map.md`
- VLAN script: `/etc/nixos/scripts/tplink-configure-vlans.py`
