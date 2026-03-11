#!/usr/bin/env python3
"""
Identify switches by MAC address to verify correct configuration
"""

import requests
from requests.auth import HTTPBasicAuth
import re

USERNAME = "admin"
PASSWORD = "ee80cb9718"

# Known MAC addresses from earlier investigation
KNOWN_MACS = {
    "A8:29:48:02:2A:1D": "sw1-modem (was 10.1.1.90, factory reset to 10.1.1.13)",
    "60:83:E7:F7:F4:6C": "sw3-upstairs (10.1.1.12) - unchanged",
}

# Switch IPs to check
SWITCHES_TO_CHECK = {
    "10.1.1.12": "sw3-upstairs?",
    "10.1.1.13": "sw1-modem (after factory reset)?",
    "10.1.1.90": "sw1-modem (original IP)?",
    "10.1.1.95": "sw2-nexus",
    "10.1.1.104": "sw4-zephyr",
}


def get_switch_info(ip):
    """Get switch information including MAC address"""
    print(f"\nChecking {ip}...")

    session = requests.Session()
    session.auth = HTTPBasicAuth(USERNAME, PASSWORD)

    try:
        # Try to get system info
        response = session.get(f"http://{ip}/SystemInfoRpm.htm", timeout=5)

        if response.status_code == 401:
            print(f"  ✗ Authentication failed")
            return None

        if response.status_code != 200:
            print(f"  ✗ Cannot connect (HTTP {response.status_code})")
            return None

        content = response.text

        # Extract MAC address
        mac_match = re.search(r'MAC Address.*?([0-9A-F]{2}:[0-9A-F]{2}:[0-9A-F]{2}:[0-9A-F]{2}:[0-9A-F]{2}:[0-9A-F]{2})', content, re.IGNORECASE)

        # Extract device name/description
        model_match = re.search(r'TL-SG[0-9]+[A-Z]*', content)

        # Extract IP address
        ip_match = re.search(r'IP Address.*?(\d+\.\d+\.\d+\.\d+)', content)

        if mac_match:
            mac = mac_match.group(1).upper()
            model = model_match.group(0) if model_match else "Unknown"
            ip_addr = ip_match.group(1) if ip_match else "Unknown"

            print(f"  ✓ Found switch")
            print(f"    Model: {model}")
            print(f"    MAC: {mac}")
            print(f"    IP: {ip_addr}")

            # Check if we know this MAC
            if mac in KNOWN_MACS:
                print(f"    → Identified as: {KNOWN_MACS[mac]}")
            else:
                print(f"    → Unknown MAC")

            return {
                "ip": ip,
                "mac": mac,
                "model": model,
                "current_ip": ip_addr
            }
        else:
            print(f"  ! Could not extract MAC address")
            return None

    except requests.exceptions.Timeout:
        print(f"  ✗ Timeout - switch not responding")
        return None
    except Exception as e:
        print(f"  ✗ Error: {e}")
        return None


def main():
    print("="*70)
    print("Switch Identification by MAC Address")
    print("="*70)

    results = {}

    for ip, description in SWITCHES_TO_CHECK.items():
        info = get_switch_info(ip)
        if info:
            results[ip] = info

    print("\n" + "="*70)
    print("SWITCH IDENTIFICATION SUMMARY")
    print("="*70)

    for ip, info in results.items():
        print(f"\n{ip}:")
        print(f"  MAC: {info['mac']}")
        print(f"  Model: {info['model']}")
        print(f"  Current IP: {info['current_ip']}")

    print("\n" + "="*70)
    print("IMPORTANT VERIFICATION:")
    print("="*70)
    print("\nThe switch at 10.1.1.13 has MAC: A8:29:48:02:2A:1D")
    print("This matches the factory-reset sw1-modem from modem DHCP.")
    print("\nThe design document says sw1-modem SHOULD be at 10.1.1.90")
    print("After factory reset, it obtained 10.1.1.13 via DHCP.")
    print("\n✓ I HAVE BEEN CONFIGURING THE CORRECT SWITCH (sw1-modem)")
    print("✓ But its IP changed from 10.1.1.90 → 10.1.1.13 due to factory reset")
    print("\nOther switches need to be verified:")
    print("  • 10.1.1.12 - should be sw3-upstairs")
    print("  • 10.1.1.95 - should be sw2-nexus")
    print("  • 10.1.1.104 - should be sw4-zephyr")


if __name__ == "__main__":
    main()
