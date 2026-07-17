#!/usr/bin/env python3
"""
Simple test script for TP-Link switch automation
Tests the updated Python library without Playwright dependencies
"""

import sys

sys.path.insert(0, "/etc/nixos/packages/tplink-switch")
from tplink_switch import TPLinkSwitch


def test_switch(ip: str):
    """Test switch connectivity and API endpoints"""
    print(f"\n{'=' * 60}")
    print(f"Testing switch: {ip}")
    print(f"{'=' * 60}\n")

    switch = TPLinkSwitch(ip, "admin", "ee80cb9718")

    # Test login
    print("1. Testing login...")
    if switch.login():
        print("   ✓ Login successful")
    else:
        print("   ✗ Login failed")
        return

    # Test system info
    print("\n2. Testing system info...")
    info = switch.get_system_info()
    print(f"   System Info: {info}")

    # Test port statistics
    print("\n3. Testing port statistics...")
    ports = switch.get_port_status()
    print(f"   Ports: {len(ports)} detected")
    for p in ports[:3]:  # Show first 3 ports
        print(
            f"     Port {p['port']}: enabled={p.get('enabled', 'N/A')}, link_status={p.get('linkStatus', 'N/A')}"
        )

    switch.logout()
    print(f"\n{'=' * 60}")
    print("Test completed!")
    print(f"{'=' * 60}\n")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 test_switch.py <switch-ip>")
        sys.exit(1)

    test_switch(sys.argv[1])
