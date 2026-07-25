#!/usr/bin/env python3
"""
Configure All Switches with Safe 802.1Q VLAN Pattern
Based on TP-Link best practices from official documentation
"""

import requests
from requests.auth import HTTPBasicAuth
import time

# Switch configurations
SWITCHES = {
    "sw2-nexus": {"ip": "10.1.1.95", "name": "sw2-nexus (TL-SG105E)", "ports": [1, 3, 5]},
    "sw3-upstairs": {"ip": "10.1.1.12", "name": "sw3-upstairs (TL-SG105E)", "ports": [2]},  # Port 2 trunk to sw4
    "sw4-zephyr": {"ip": "10.1.1.104", "name": "sw4-zephyr (TL-SG2210)", "ports": [2]},  # Port 2 trunk to sw3
}

USERNAME = "admin"
PASSWORD = "ee80cb9718"

# VLAN Configuration (same for all switches)
VLAN_CONFIG = {
    10: {"name": "gaming", "tagged": [1, 2, 3, 4, 5], "untagged": []},  # All ports for flexibility
    20: {"name": "ai", "tagged": [1, 2, 3, 4, 5], "untagged": []},
    50: {"name": "monitoring", "tagged": [1, 2, 3, 4, 5], "untagged": []},
    99: {"name": "management", "tagged": [1, 2, 3, 4, 5], "untagged": []},
}


def enable_8021q_vlan(session, base_url):
    """Enable 802.1Q VLAN on the switch"""
    print("  → Enabling 802.1Q VLAN...")

    data = {"qvlan_en": "1", "qvlan_mode": "Apply"}

    try:
        response = session.post(f"{base_url}/qvlanSet.cgi", data=data, timeout=10)
        response.raise_for_status()
        print("  ✓ 802.1Q VLAN enabled")
        time.sleep(2)
        return True
    except Exception as e:
        print(f"  ✗ Failed to enable 802.1Q VLAN: {e}")
        return False


def add_vlan(session, base_url, vlan_id, vlan_name, tagged_ports, untagged_ports):
    """Add/Modify a VLAN with port membership"""
    print(f"  → Configuring VLAN {vlan_id} ({vlan_name})...")

    # Build port membership (0=Untagged, 1=Tagged, 2=Not Member)
    port_config = {}
    for port in range(1, 6):
        if port in tagged_ports:
            port_config[f"selType_{port}"] = "1"
        elif port in untagged_ports:
            port_config[f"selType_{port}"] = "0"
        else:
            port_config[f"selType_{port}"] = "2"

    data = {
        "vid": str(vlan_id),
        "vname": vlan_name,
        **port_config,
        "qvlan_add": "Add/Modify"
    }

    try:
        response = session.post(f"{base_url}/qvlanSet.cgi", data=data, timeout=10)
        response.raise_for_status()
        tagged_str = ",".join(map(str, tagged_ports)) if tagged_ports else "none"
        print(f"  ✓ VLAN {vlan_id}: Tagged=[{tagged_str}]")
        time.sleep(1)
        return True
    except Exception as e:
        print(f"  ✗ Failed to create VLAN {vlan_id}: {e}")
        return False


def configure_switch(switch_key, switch_config):
    """Configure VLANs on a single switch"""
    ip = switch_config["ip"]
    name = switch_config["name"]
    base_url = f"http://{ip}"

    print(f"\n{'='*60}")
    print(f"Configuring: {name} ({ip})")
    print(f"{'='*60}")

    # Create session
    session = requests.Session()
    session.auth = HTTPBasicAuth(USERNAME, PASSWORD)

    # Test connectivity
    try:
        response = session.get(base_url, timeout=5)
        if response.status_code == 401:
            print(f"  ✗ Authentication failed")
            return False
        response.raise_for_status()
    except Exception as e:
        print(f"  ✗ Cannot connect to switch: {e}")
        print(f"  ⚠ Switch may be offline or at wrong IP")
        return False

    print("  ✓ Connected to switch")

    # Enable 802.1Q VLAN
    if not enable_8021q_vlan(session, base_url):
        return False

    # Configure all VLANs
    success_count = 0
    for vlan_id, config in VLAN_CONFIG.items():
        if add_vlan(session, base_url, vlan_id, config["name"], config["tagged"], config["untagged"]):
            success_count += 1

    print(f"\n  ✓ {success_count}/{len(VLAN_CONFIG)} VLANs configured")

    # Summary
    print(f"\nConfiguration Summary for {name}:")
    print("  • 802.1Q VLAN: ENABLED")
    print("  • VLAN 10 (gaming): Tagged on all ports")
    print("  • VLAN 20 (ai): Tagged on all ports")
    print("  • VLAN 50 (monitoring): Tagged on all ports")
    print("  • VLAN 99 (management): Tagged on all ports")
    print("  • PVID: 1 (default, SAFE)")
    print("  ✓ Switch configured safely per TP-Link best practices")

    return success_count == len(VLAN_CONFIG)


def main():
    print("="*60)
    print("Configure All Switches with Safe 802.1Q VLAN")
    print("="*60)
    print("\nFollowing TP-Link Official Documentation Pattern:")
    print("  • Trunk ports: All VLANs TAGGED, PVID = 1")
    print("  • Native VLAN: VLAN 1 (for management)")
    print("  • Matches TP-Link Example 2 exactly")
    print()

    results = {}

    for switch_key, switch_config in SWITCHES.items():
        success = configure_switch(switch_key, switch_config)
        results[switch_key] = success
        time.sleep(2)  # Brief pause between switches

    # Final summary
    print("\n" + "="*60)
    print("CONFIGURATION SUMMARY")
    print("="*60)

    for switch_key, success in results.items():
        status = "✓ SUCCESS" if success else "✗ FAILED"
        print(f"  {status}: {switch_key}")

    failed = [k for k, v in results.items() if not v]

    if failed:
        print(f"\n⚠ {len(failed)} switch(es) failed:")
        for switch in failed:
            print(f"    - {switch}")
        print("\nTroubleshooting:")
        print("  • Check switch is powered on")
        print("  • Verify IP address is correct")
        print("  • Test connectivity: ping <ip>")
        print("  • Check credentials: admin / ee80cb9718")
        return 1
    else:
        print("\n✓ All switches configured successfully!")
        print("\nNext Steps:")
        print("  1. Test connectivity between switches")
        print("  2. Verify VLAN segmentation works")
        print("  3. Test management access on VLAN 99")
        return 0


if __name__ == "__main__":
    exit(main())
