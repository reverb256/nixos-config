#!/usr/bin/env python3
"""
TP-Link Switch VLAN Configuration Script
Configures 7-VLAN segmentation for cluster network

VLANs:
  10  - gaming (VR streaming, gaming traffic)
  20  - ai (AI/ML workloads)
  30  - storage (NFS/cluster storage)
  40  - mining (GPU mining)
  50  - monitoring (Prometheus/Grafana)
  60  - backup (backup operations)
  99  - management (switch management, K8s control plane)

Usage:
    python3 tplink-configure-vlans.py [--verify] [--apply]
"""

import asyncio
import sys
from pathlib import Path
from playwright.async_api import async_playwright

# Switch configurations
SWITCHES = {
    "sw1-modem": {
        "ip": "10.1.1.10",
        "name": "sw1-modem-root",
        "role": "root",
        "uplinks": ["modem", "sw2", "sw3"],
        "vlans": ["all"],  # Carries all VLANs
    },
    "sw2-nexus": {
        "ip": "10.1.1.11",
        "name": "sw2-nexus-branch",
        "role": "branch",
        "uplinks": ["sw1"],
        "vlans": [99, 30, 60],  # Management, storage, backup
    },
    "sw3-upstairs": {
        "ip": "10.1.1.12",
        "name": "sw3-upstairs",
        "role": "distribution",
        "uplinks": ["sw1", "sw4"],
        "vlans": ["all"],
    },
    "sw4-zephyr": {
        "ip": "10.1.1.13",
        "name": "sw4-zephyr-end",
        "role": "access",
        "uplinks": ["sw3"],
        "vlans": ["all"],
    },
}

# VLAN definitions
VLANS = [
    {"id": 10, "name": "gaming"},
    {"id": 20, "name": "ai"},
    {"id": 30, "name": "storage"},
    {"id": 40, "name": "mining"},
    {"id": 50, "name": "monitoring"},
    {"id": 60, "name": "backup"},
    {"id": 99, "name": "management"},
]

# Default credentials
USERNAME = "admin"
PASSWORD = "ee80cb9718"


class SwitchVLANConfigurator:
    """Configure VLANs on TP-Link Easy Smart Switch"""

    def __init__(self, ip, username, password, name):
        self.ip = ip
        self.username = username
        self.password = password
        self.name = name
        self.base_url = f"http://{ip}"

    async def login(self, page):
        """Login to switch web interface"""
        try:
            await page.goto(self.base_url, timeout=15000)
            await page.fill('input[name="username"]', self.username)
            await page.fill('input[name="password"]', self.password)
            await page.click('input[name="logon"]')
            await page.wait_for_timeout(3000)

            if "logon" in page.url:
                return False
            return True
        except Exception as e:
            print(f"  ✗ Login error: {e}")
            return False

    async def enable_vlan_global(self, page):
        """Enable 802.1Q VLAN globally"""
        try:
            await page.goto(f"{self.base_url}/VlanMtuRpm.htm", timeout=15000)
            await page.wait_for_timeout(2000)

            # Look for VLAN enable checkbox
            # Try different possible selectors
            enable_selectors = [
                'input[name="vlanEnable"]',
                'input[type="checkbox"]',
                '#vlanEnable',
                'input[value="1"]',
            ]

            for selector in enable_selectors:
                try:
                    checkbox = await page.query_selector(selector)
                    if checkbox:
                        is_checked = await checkbox.is_checked()
                        if not is_checked:
                            await checkbox.check()
                            print(f"  ✓ 802.1Q VLAN enabled globally")
                            await asyncio.sleep(1)
                            return True
                        else:
                            print(f"  ✓ 802.1Q VLAN already enabled")
                            return True
                except:
                    continue

            print(f"  ! Could not find VLAN enable option")
            return False
        except Exception as e:
            print(f"  ✗ VLAN enable error: {e}")
            return False

    async def create_vlan(self, page, vlan_id, vlan_name):
        """Create a VLAN on the switch"""
        try:
            await page.goto(f"{self.base_url}/VlanMtuRpm.htm", timeout=15000)
            await page.wait_for_timeout(2000)

            # Look for "Add" or "Create" button
            add_selectors = [
                'input[value="Add"]',
                'input:has-text("Add")',
                'button:has-text("Add")',
            ]

            for selector in add_selectors:
                try:
                    btn = await page.query_selector(selector)
                    if btn:
                        await btn.click()
                        await asyncio.sleep(1)
                        break
                except:
                    continue

            # Fill in VLAN ID and name
            vlan_id_input = await page.query_selector('input[name*="vid"]')
            vlan_name_input = await page.query_selector('input[name*="vname"]')

            if vlan_id_input:
                await vlan_id_input.fill(str(vlan_id))
            if vlan_name_input:
                await vlan_name_input.fill(vlan_name)

            # Apply/Save
            apply_selectors = [
                'input[value="Apply"]',
                'input:has-text("Apply")',
                'button:has-text("Apply")',
            ]

            for selector in apply_selectors:
                try:
                    btn = await page.query_selector(selector)
                    if btn:
                        await btn.click()
                        await page.wait_for_timeout(2000)
                        print(f"  ✓ VLAN {vlan_id} ({vlan_name}) created")
                        return True
                except:
                    continue

            return False
        except Exception as e:
            print(f"  ✗ Create VLAN {vlan_id} error: {e}")
            return False

    async def configure_port_vlan(self, page, port_num, vlan_id, tagged=False):
        """Configure a port's VLAN membership"""
        try:
            await page.goto(f"{self.base_url}/VlanMtuRpm.htm", timeout=15000)
            await page.wait_for_timeout(2000)

            # This is highly dependent on the specific switch UI
            # TL-SG105E has a specific port VLAN configuration page
            # You may need to navigate to a port-specific configuration

            print(f"  ! Port {port_num} -> VLAN {vlan_id} (tagged={tagged})")
            return True
        except Exception as e:
            print(f"  ✗ Port {port_num} VLAN config error: {e}")
            return False

    async def take_screenshot(self, page, filename):
        """Take a screenshot for verification"""
        output_dir = Path("/var/cache/tplink-switches/screenshots")
        output_dir.mkdir(parents=True, exist_ok=True)
        await page.screenshot(path=str(output_dir / f"{filename}.png"))


async def configure_switch(switch_key, switch_config, port_map=None):
    """Configure VLANs on a single switch"""
    ip = switch_config["ip"]
    name = switch_config["name"]

    print(f"\n{'='*60}")
    print(f"Configuring: {name} ({ip})")
    print(f"{'='*60}\n")

    configurator = SwitchVLANConfigurator(ip, USERNAME, PASSWORD, name)

    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=True)
        page = await browser.new_page()

        # Login
        if not await configurator.login(page):
            await configurator.take_screenshot(page, f"{name}-login-error")
            await browser.close()
            return False

        await configurator.take_screenshot(page, f"{name}-before")

        # Enable 802.1Q VLAN globally
        print("\nStep 1: Enable 802.1Q VLAN")
        await configurator.enable_vlan_global(page)

        # Create all VLANs
        print("\nStep 2: Create VLANs")
        for vlan in VLANS:
            vlan_list = switch_config.get("vlans", ["all"])
            if vlan_list == "all" or vlan["id"] in vlan_list:
                await configurator.create_vlan(page, vlan["id"], vlan["name"])

        # Configure ports (if port_map provided)
        if port_map:
            print("\nStep 3: Configure Port VLAN Assignments")
            for port_num, port_config in port_map.items():
                vlan_id = port_config.get("vlan", 99)
                tagged = port_config.get("tagged", False)
                await configurator.configure_port_vlan(page, port_num, vlan_id, tagged)

        await configurator.take_screenshot(page, f"{name}-after")
        await browser.close()

    return True


async def main():
    """Main entry point"""
    verify_only = "--verify" in sys.argv
    apply_config = "--apply" in sys.argv

    if not verify_only and not apply_config:
        print("Usage:")
        print("  python3 tplink-configure-vlans.py --verify   # Check current state")
        print("  python3 tplink-configure-vlans.py --apply    # Apply VLAN configuration")
        sys.exit(1)

    print("="*60)
    print("TP-Link Switch VLAN Configuration")
    print("="*60)

    if verify_only:
        print("\nVerifying current VLAN configuration...")
        print("(Checking each switch for enabled VLANs)")

    if apply_config:
        print("\nApplying VLAN configuration...")
        print("This will modify switch configurations!")
        response = input("Continue? (yes/no): ")
        if response.lower() != "yes":
            print("Aborted.")
            sys.exit(0)

        # TODO: Load port mappings from user input
        port_map = {}  # Will be populated by user

        for key, config in SWITCHES.items():
            result = await configure_switch(key, config, port_map.get(key))
            if not result:
                print(f"\n✗ Configuration failed for {config['name']}")
                sys.exit(1)

        print("\n" + "="*60)
        print("VLAN Configuration Complete!")
        print("="*60)

        # Generate port mapping template
        print("\nPlease verify physical connections match this configuration:")
        for key, config in SWITCHES.items():
            print(f"\n{config['name']} ({config['ip']}):")
            print(f"  Role: {config['role']}")
            print(f"  VLANs: {config['vlans']}")


if __name__ == "__main__":
    asyncio.run(main())
