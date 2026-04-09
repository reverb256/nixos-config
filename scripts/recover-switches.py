#!/usr/bin/env python3
"""
Recover factory-reset TP-Link switches
1. Login with admin/empty
2. Change password to ee80cb9718
3. Configure IP address
4. Enable VLANs

Usage: python3 scripts/recover-switches.py
"""

import requests
import re
import sys
from pathlib import Path

# Configuration
NEW_PASSWORD = "ee80cb9718"
USERNAME = "admin"

# Factory-reset switches that need recovery
SWITCHES = {
    "10.1.1.95": {
        "name": "factory-reset-1",
        "target_ip": "10.1.1.11",  # Will become sw2-tv
    },
    "10.1.1.104": {
        "name": "factory-reset-2",
        "target_ip": "10.1.1.10",  # Will become sw1-modem
    },
    "10.1.1.90": {
        "name": "factory-reset-3",
        "target_ip": "10.1.1.13",  # Will become sw4-zephyr
    },
}


def login(ip, password=""):
    """Login to switch and return session"""
    session = requests.Session()

    # Get login page
    try:
        r = session.get(f"http://{ip}", timeout=10)
        r.raise_for_status()
    except Exception as e:
        print(f"  ✗ Cannot connect: {e}")
        return None

    # Check if password change is required
    errType = re.search(r'errType=logonInfo\[(\d+)\]', r.text)
    if errType and errType.group(1) == "6":
        # Password change mode
        print(f"  → Password change required")
        data = {
            "username": USERNAME,
            "password": NEW_PASSWORD,
            "cpassword": NEW_PASSWORD,
            "logon": "Confirm"
        }
    else:
        # Normal login
        data = {
            "username": USERNAME,
            "password": password,
            "logon": "Login"
        }

    # Post login
    try:
        r = session.post(f"http://{ip}/logon.cgi", data=data, timeout=10)
        r.raise_for_status()
    except Exception as e:
        print(f"  ✗ Login failed: {e}")
        return None

    # Check result
    errType = re.search(r'errType=logonInfo\[(\d+)\]', r.text)
    if errType:
        err = errType.group(1)
        if err == "1":
            print(f"  ✗ Wrong password")
            return None
        elif err == "6":
            print(f"  → Still in password change mode, trying again...")
            # Try password change again
            data = {
                "username": USERNAME,
                "password": NEW_PASSWORD,
                "cpassword": NEW_PASSWORD,
                "logon": "Confirm"
            }
            r = session.post(f"http://{ip}/logon.cgi", data=data, timeout=10)
            if "Logout" in r.text:
                print(f"  ✓ Password changed successfully")
                return session
            return None
        elif err == "0":
            # Check if actually logged in by looking for Logout
            if "Logout" in r.text or "System" in r.text:
                print(f"  ✓ Logged in")
                return session
            else:
                print(f"  ? Unknown state (errType=0 but no Logout)")
                return None

    # If no errType but got a page, check for success indicators
    if "Logout" in r.text or r.status_code in [302, 303]:
        print(f"  ✓ Logged in")
        return session

    print(f"  ✗ Login failed (unknown response)")
    return None


def configure_ip(session, ip, new_ip):
    """Configure switch IP address"""
    try:
        # Go to IP configuration page
        r = session.get(f"http://{ip}/IpTypeSettingRpm.htm", timeout=10)

        # Parse current settings
        # This would need to extract form fields and submit new IP
        print(f"  → IP configuration needs manual setup or further reverse engineering")
        print(f"     Target IP: {new_ip}")
        return False
    except Exception as e:
        print(f"  ✗ IP config failed: {e}")
        return False


def main():
    print("="*60)
    print("TP-Link Switch Recovery Tool")
    print("="*60)

    for current_ip, config in SWITCHES.items():
        print(f"\n[{config['name']}] {current_ip}")
        print("-" * 40)

        # Try login with empty password (factory default)
        session = login(current_ip, password="")

        if not session:
            print(f"  ✗ Failed to login, skipping")
            continue

        # Configure IP (requires reverse engineering of the IP config form)
        configure_ip(session, current_ip, config["target_ip"])


if __name__ == "__main__":
    main()
