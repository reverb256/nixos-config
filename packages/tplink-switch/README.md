# TP-Link Switch Python Library

Python library for managing TP-Link Easy Smart Switches (TL-SG105E, TL-SG108E, etc.) via HTTP.

## Usage

```python
from tplink_switch import TPLinkSwitch

# Connect to switch
switch = TPLinkSwitch('10.1.1.10', 'admin', 'password')

# Context manager handles login/logout automatically
with switch:
    # Get system information
    info = switch.get_system_info()
    print(info)

    # Get port status
    ports = switch.get_port_status()
    for port in ports:
        print(f"Port {port['port']}: {port['status']} ({port['speed']} Mbps)")

    # Get VLAN configuration
    vlans = switch.get_vlan_config()
    print(vlans)
```

## Features

- HTTP-based authentication and session management
- System information retrieval
- Port status monitoring
- VLAN configuration
- Port enable/disable control
- Switch reboot
- Automatic login/logout via context manager

## Requirements

- Python 3.8+
- requests
- urllib3
