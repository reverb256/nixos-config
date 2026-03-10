# TP-Link Smart Switch Management

## Overview

This module provides Playwright-based automation for TP-Link Easy Smart Switches (TL-SG105E) on the local network.

## Switch Configuration

| IP Address | Name | Location |
|------------|------|----------|
| 10.1.1.10 | tl-sg105e-1 | Main switch |
| 10.1.1.11 | tl-sg105e-2 | Secondary |
| 10.1.1.12 | tl-sg105e-3 | Tertiary |
| 10.1.1.13 | tl-sg105e-4 | Quaternary |

## VLAN Configuration

| VLAN ID | Name | Purpose |
|---------|------|---------|
| 10 | gaming | Gaming traffic (VR, streaming) |
| 20 | ai | AI inference workloads |
| 30 | storage | NFS/cluster storage |
| 40 | mining | GPU mining operations |
| 50 | monitoring | Prometheus/Grafana metrics |
| 60 | backup | Backup operations |
| 99 | management | Switch management |

## Usage

### Enable the Service

Add to your host configuration:

```nix
{
  services.tplinkSwitches = {
    enable = true;

    # Enable monitoring (polls every 5 minutes)
    monitoring.enable = true;

    # Optional: Enable automated configuration
    # automation.enableAutomatedConfig = true;
  };
}
```

### CLI Commands

```bash
# List all switches with status
tplink list

# Get status of all switches
tplink status

# Get status of specific switch
tplink status 10.1.1.10
tplink status tl-sg105e-1

# Test connectivity
tplink test
tplink test 10.1.1.10

# Take screenshots of web UI
tplink screenshot

# Open web UI in browser
tplink web 10.1.1.10
tplink web tl-sg105e-1

# Configure switches (VLAN setup, etc.)
tplink configure
tplink configure tl-sg105e-1
```

### Fish Shell Abbreviations

After rebuild, these abbreviations are available:

```fish
sw       # Alias for: tplink status
swweb    # Alias for: tplink web
tplink   # Full CLI
```

## Output Locations

| Output Type | Location |
|-------------|----------|
| Screenshots | `/var/cache/tplink-switches/screenshots/` |
| Logs | `journalctl -u tplink-monitor` |
| Status JSON | `tplink status` (JSON output) |

## Default Credentials

Default credentials for TP-Link Easy Smart Switch:
- Username: `admin`
- Password: `admin`

**Important**: Change these after initial setup via the web UI.

## Troubleshooting

### Switch Not Responding

```bash
# Test basic connectivity
ping 10.1.1.10

# Check if web interface is accessible
curl -I http://10.1.1.10

# Check firewall rules
sudo iptables -L | grep 10.1.1
```

### Playwright Issues

```bash
# Install Playwright browsers
playwright install chromium

# Verify installation
playwright --version
```

### Service Not Starting

```bash
# Check service status
systemctl status tplink-monitor

# View logs
journalctl -xe -u tplink-monitor

# Test manually
/etc/tplink-switches/automate.py status
```

## API Integration

The service generates a Python automation script at `/etc/tplink-switches/automate.py` that can be used programmatically:

```python
# Get switch status as JSON
import json
import subprocess

result = subprocess.run(
    ["/etc/tplink-switches/automate.py", "status"],
    capture_output=True,
    text=True
)
status = json.loads(result.stdout)
print(status)
```

## Security Considerations

1. **Change default credentials** - Use the web UI to set strong passwords
2. **Network isolation** - Switches are on local network only
3. **HTTPS** - Current implementation uses HTTP (switch limitation)
4. **Monitoring** - Consider restricting monitoring data to Tailscale only

## Future Enhancements

- [ ] SNMP monitoring integration
- [ ] Port mirroring for traffic analysis
- [ ] Alert system for link status changes
- [ ] Integration with cluster automation
- [ ] Automated backup of switch configurations
