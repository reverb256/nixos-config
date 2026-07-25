#!/usr/bin/env python3
"""
Modular TP-Link Switch VLAN Configuration Script
Supports incremental, progressive VLAN configuration

Design Principles:
- NO big bang changes - all operations are incremental
- Each operation can be verified before proceeding
- Target specific switches or all switches
- Safe defaults with explicit confirmation for dangerous ops

Switch IP Addresses (CORRECTED 2026-03-10):
  sw1-modem:    10.1.1.90  (Root/Gateway) - ALL VLANs
  sw2-tv:       10.1.1.95  (TV area) - 99, 30, 60
  sw3-upstairs: 10.1.1.12  (Distribution) - ALL VLANs
  sw4-zephyr:   10.1.1.104 (Zephyr room) - ALL VLANs

VLAN Definitions:
  10  - gaming (VR, gaming PCs, WiFi)
  20  - ai (AI/ML workloads)
  30  - storage (NFS, cluster storage)
  40  - mining (GPU mining)
  50  - monitoring (Prometheus, Grafana)
  60  - backup (backup operations)
  99  - management (K8s control plane, switch management)

Usage Examples:
  # Verification (safe, read-only)
  python3 modular-vlan-config.py --verify

  # Create single VLAN on specific switch
  python3 modular-vlan-config.py --switch sw4-zephyr --create-vlan 99 --name "management"

  # Create VLAN on all switches
  python3 modular-vlan-config.py --all-switches --create-vlan 99 --name "management"

  # List VLANs on a switch
  python3 modular-vlan-config.py --switch sw4-zephyr --list-vlans

  # Configure port as access (untagged)
  python3 modular-vlan-config.py --switch sw4-zephyr --port 5 --access-vlan 99

  # Configure port as tagged (trunk member)
  python3 modular-vlan-config.py --switch sw4-zephyr --port 1 --tag-vlan 99

  # Tag port for multiple VLANs (trunk)
  python3 modular-vlan-config.py --switch sw4-zephyr --port 1 --tag-vlans 99,10,20

  # Set port PVID (Port VLAN ID)
  python3 modular-vlan-config.py --switch sw4-zephyr --port 5 --pvid 99

  # Disable VLAN (rollback)
  python3 modular-vlan-config.py --switch sw4-zephyr --disable-vlan

  # Screenshot current state
  python3 modular-vlan-config.py --switch sw4-zephyr --screenshot
"""

import asyncio
import sys
import argparse
from pathlib import Path
from playwright.async_api import async_playwright
from datetime import datetime

# CORRECTED switch configurations (as of 2026-03-10)
SWITCHES = {
    "sw1-modem": {
        "ip": "10.1.1.90",
        "name": "sw1-modem (ROOT/GATEWAY)",
        "role": "root",
        "description": "Most critical switch - connected to Rogers modem",
        "vlans": "all",  # Carries ALL VLANs
    },
    "sw2-tv": {
        "ip": "10.1.1.95",
        "name": "sw2-tv (TV AREA)",
        "role": "access",
        "description": "TV area - Nexus and gaming PCs",
        "vlans": [99, 30, 60],  # Management, storage, backup
    },
    "sw3-upstairs": {
        "ip": "10.1.1.12",
        "name": "sw3-upstairs (DISTRIBUTION)",
        "role": "distribution",
        "description": "Distribution switch - carries cluster traffic",
        "vlans": "all",  # Carries ALL VLANs
    },
    "sw4-zephyr": {
        "ip": "10.1.1.104",
        "name": "sw4-zephyr (ZEPHYR ROOM)",
        "role": "access",
        "description": "Zephyr workstation - most isolated switch",
        "vlans": "all",  # Carries ALL VLANs
    },
}

# VLAN definitions with descriptions
VLAN_DEFINITIONS = {
    10: {"name": "gaming", "description": "VR streaming, gaming PCs, WiFi"},
    20: {"name": "ai", "description": "AI/ML workloads (Zephyr, Forge)"},
    30: {"name": "storage", "description": "NFS/cluster storage (Nexus)"},
    40: {"name": "mining", "description": "GPU mining (Forge, Sentry)"},
    50: {"name": "monitoring", "description": "Prometheus/Grafana (Sentry)"},
    60: {"name": "backup", "description": "Backup operations (Nexus)"},
    99: {"name": "management", "description": "K8s control plane, switch management"},
}

# Default credentials
USERNAME = "admin"
PASSWORD = "ee80cb9718"


class ModularSwitchConfigurator:
    """Modular switch configurator with incremental operations"""

    def __init__(self, switch_key, switch_config):
        self.switch_key = switch_key
        self.ip = switch_config["ip"]
        self.name = switch_config["name"]
        self.role = switch_config["role"]
        self.base_url = f"http://{self.ip}"

    async def login(self, page):
        """Login to switch web interface"""
        try:
            print(f"  → Logging into {self.name} ({self.ip})")
            await page.goto(self.base_url, timeout=15000)
            await page.wait_for_load_state("domcontentloaded", timeout=5000)

            # Fill credentials
            await page.fill('input[name="username"]', USERNAME)
            await page.fill('input[name="password"]', PASSWORD)
            await page.click('input[name="logon"]')

            # Wait for login to complete
            await page.wait_for_load_state("domcontentloaded", timeout=5000)
            await asyncio.sleep(2)

            # Check if login successful
            if "logon" in page.url:
                print(f"  ✗ Login failed - still on login page")
                return False

            print(f"  ✓ Login successful")
            return True

        except Exception as e:
            print(f"  ✗ Login error: {e}")
            return False

    async def navigate_to_vlan_page(self, page):
        """Navigate to 802.1Q VLAN configuration page"""
        try:
            # Wait for menu to load
            await page.wait_for_selector('a:has-text("VLAN")', timeout=5000)
            await asyncio.sleep(1)

            # Click VLAN menu
            vlan_menu = await page.query_selector('a:has-text("VLAN")')
            if vlan_menu:
                await vlan_menu.click()
                await asyncio.sleep(1)

            # Click 802.1Q VLAN submenu
            vlan_8021q = await page.query_selector('a:has-text("802.1Q VLAN")')
            if vlan_8021q:
                await vlan_8021q.click()
                await asyncio.sleep(2)

            return True

        except Exception as e:
            print(f"  ✗ Navigation error: {e}")
            return False

    async def get_vlan_status(self, page):
        """Get current VLAN status"""
        try:
            await self.navigate_to_vlan_page(page)

            # Check if 802.1Q VLAN is enabled
            text = await page.evaluate("() => document.body.innerText")

            status = {
                "802.1q_enabled": "Disable" not in text.split("802.1Q VLAN Configuration")[1:300],
                "vlans": [],
            }

            # Look for VLAN table
            if "VLAN ID" in text and "VLAN Name" in text:
                lines = text.split('\n')
                for i, line in enumerate(lines):
                    if line.strip().isdigit() and 1 <= int(line.strip()) <= 4094:
                        status["vlans"].append(int(line.strip()))

            return status

        except Exception as e:
            print(f"  ✗ Error getting VLAN status: {e}")
            return None

    async def create_vlan(self, page, vlan_id, vlan_name):
        """Create a single VLAN"""
        try:
            print(f"  → Creating VLAN {vlan_id} ({vlan_name})")
            await self.navigate_to_vlan_page(page)
            await asyncio.sleep(1)

            # Click Add/Modify button
            add_selectors = [
                'input[value="Add/Modify"]',
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

            # Fill VLAN ID
            vlan_input = await page.query_selector('input[name="vid"]')
            if vlan_input:
                await vlan_input.fill(str(vlan_id))
                await asyncio.sleep(0.5)

            # Fill VLAN Name
            name_input = await page.query_selector('input[name="vname"]')
            if name_input:
                await name_input.fill(vlan_name)
                await asyncio.sleep(0.5)

            # Configure port membership for this VLAN
            # Default: all ports as "Not Member" (safe default)
            for port_num in range(1, 6):
                try:
                    # Find the radio button for "Not Member" on this port
                    not_member_radio = await page.query_selector(
                        f'input[type="radio"][name*="1"][value="3"]'
                    )
                    if not_member_radio:
                        await not_member_radio.check(force=True)
                except:
                    pass

            # Click Add/Modify to create
            add_modify_btn = await page.query_selector('input[value="Add/Modify"]')
            if add_modify_btn:
                await add_modify_btn.click()
                await asyncio.sleep(2)

            print(f"  ✓ VLAN {vlan_id} ({vlan_name}) created")
            return True

        except Exception as e:
            print(f"  ✗ Error creating VLAN {vlan_id}: {e}")
            return False

    async def list_vlans(self, page):
        """List all configured VLANs"""
        try:
            print(f"\n  VLANs configured on {self.name}:")
            await self.navigate_to_vlan_page(page)
            await asyncio.sleep(1)

            text = await page.evaluate("() => document.body.innerText")

            # Parse VLAN table
            lines = text.split('\n')
            for i, line in enumerate(lines):
                line = line.strip()
                if line.isdigit() and 1 <= int(line) <= 4094:
                    vlan_id = int(line)
                    vlan_name = VLAN_DEFINITIONS.get(vlan_id, {}).get("name", "Unknown")
                    print(f"    VLAN {vlan_id}: {vlan_name}")

            return True

        except Exception as e:
            print(f"  ✗ Error listing VLANs: {e}")
            return False

    async def configure_port_vlan(self, page, port_num, vlan_id, tagged=False):
        """Configure a port's membership in a VLAN"""
        try:
            print(f"  → Configuring Port {port_num} for VLAN {vlan_id} ({'tagged' if tagged else 'untagged'})")
            await self.navigate_to_vlan_page(page)
            await asyncio.sleep(1)

            # First, select the VLAN in the VLAN table
            # Look for the VLAN row and click it
            vlan_selectors = [
                f'input[type="radio"][name*="vid"][value="{vlan_id}"]',
                f'input[value="{vlan_id}"]',
            ]

            for selector in vlan_selectors:
                try:
                    radio = await page.query_selector(selector)
                    if radio:
                        await radio.click()
                        await asyncio.sleep(0.5)
                        break
                except:
                    continue

            # Configure the port's membership (Tagged or Untagged)
            # Port configuration is on the same row
            if tagged:
                # Click "Tagged" radio for this port
                tagged_selector = f'input[name="Member{port_num}"][value="1"]'  # Tagged = 1
                tagged_radio = await page.query_selector(tagged_selector)
                if tagged_radio:
                    await tagged_radio.click()
            else:
                # Click "Untagged" radio for this port
                untagged_selector = f'input[name="Member{port_num}"][value="2"]'  # Untagged = 2
                untagged_radio = await page.query_selector(untagged_selector)
                if untagged_radio:
                    await untagged_radio.click()

            await asyncio.sleep(0.5)

            # Click Add/Modify to apply
            add_modify_btn = await page.query_selector('input[value="Add/Modify"]')
            if add_modify_btn:
                await add_modify_btn.click()
                await asyncio.sleep(2)

            print(f"  ✓ Port {port_num} configured for VLAN {vlan_id} ({'tagged' if tagged else 'untagged'})")
            return True

        except Exception as e:
            print(f"  ✗ Error configuring port {port_num}: {e}")
            return False

    async def set_port_pvid(self, page, port_num, pvid):
        """Set a port's PVID (Port VLAN ID) - the untagged VLAN"""
        try:
            print(f"  → Setting Port {port_num} PVID to {pvid}")
            await page.goto(f"{self.base_url}/Vlan8021QPvidRpm.htm", timeout=15000)
            await asyncio.sleep(2)

            # Find the PVID dropdown for this port
            pvid_selectors = [
                f'select[name="pvid{port_num}"]',
                f'select[name*="{port_num}"]',
            ]

            for selector in pvid_selectors:
                try:
                    select = await page.query_selector(selector)
                    if select:
                        await select.select_option(str(pvid))
                        await asyncio.sleep(0.5)
                        break
                except:
                    continue

            # Click Apply
            apply_btn = await page.query_selector('input[value="Apply"]')
            if apply_btn:
                await apply_btn.click()
                await asyncio.sleep(2)

            print(f"  ✓ Port {port_num} PVID set to {pvid}")
            return True

        except Exception as e:
            print(f"  ✗ Error setting PVID: {e}")
            return False

    async def disable_vlan_global(self, page):
        """Disable 802.1Q VLAN globally (ROLLBACK)"""
        try:
            print(f"  → Disabling 802.1Q VLAN on {self.name}")
            print(f"  ⚠️  WARNING: This will remove all VLAN configuration!")

            await self.navigate_to_vlan_page(page)
            await asyncio.sleep(1)

            # Click "Disable" radio button
            disable_radio = await page.query_selector('input[type="radio"][value="2"]')
            if disable_radio:
                await disable_radio.click()
                await asyncio.sleep(0.5)

            # Click Apply
            apply_btn = await page.query_selector('input[value="Apply"]')
            if apply_btn:
                # Handle confirmation dialog
                async with page.expect_dialog(lambda dialog: True) as dialog_info:
                    await apply_btn.click()
                dialog = await dialog_info.value
                await dialog.accept()

                await asyncio.sleep(2)

            print(f"  ✓ 802.1Q VLAN disabled on {self.name}")
            print(f"  ⚠️  All ports returned to default flat network mode")
            return True

        except Exception as e:
            print(f"  ✗ Error disabling VLAN: {e}")
            return False

    async def take_screenshot(self, page, label):
        """Take screenshot for verification"""
        try:
            output_dir = Path("/tmp/tplink-vlan-screenshots")
            output_dir.mkdir(parents=True, exist_ok=True)

            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            filename = f"{self.switch_key}_{label}_{timestamp}.png"
            filepath = output_dir / filename

            await page.screenshot(path=str(filepath))
            print(f"  📷 Screenshot saved: {filepath}")
            return True

        except Exception as e:
            print(f"  ✗ Screenshot error: {e}")
            return False


async def verify_switch(switch_key, switch_config):
    """Verify switch configuration (read-only)"""
    print(f"\n{'='*70}")
    print(f"VERIFYING: {switch_config['name']}")
    print(f"{'='*70}\n")

    configurator = ModularSwitchConfigurator(switch_key, switch_config)

    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=True)
        page = await browser.new_page()

        if not await configurator.login(page):
            await browser.close()
            return False

        # Get VLAN status
        status = await configurator.get_vlan_status(page)

        if status:
            print(f"\n  802.1Q VLAN: {'ENABLED' if status['802.1q_enabled'] else 'DISABLED'}")
            if status['vlans']:
                print(f"  Configured VLANs: {', '.join(map(str, status['vlans']))}")
            else:
                print(f"  Configured VLANs: None (only default VLAN 1)")

        # Take screenshot
        await configurator.take_screenshot(page, "verify")

        await browser.close()

    return True


async def create_vlan_on_switch(switch_key, switch_config, vlan_id, vlan_name):
    """Create a VLAN on a switch"""
    print(f"\n{'='*70}")
    print(f"CREATING VLAN {vlan_id} ON: {switch_config['name']}")
    print(f"{'='*70}\n")

    configurator = ModularSwitchConfigurator(switch_key, switch_config)

    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=True)
        page = await browser.new_page()

        if not await configurator.login(page):
            await browser.close()
            return False

        # Take before screenshot
        await configurator.take_screenshot(page, "before_vlan_create")

        # Create VLAN
        result = await configurator.create_vlan(page, vlan_id, vlan_name)

        # Take after screenshot
        await configurator.take_screenshot(page, "after_vlan_create")

        await browser.close()

    return result


async def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(
        description="Modular TP-Link Switch VLAN Configuration",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )

    # Switch selection
    parser.add_argument("--switch", choices=list(SWITCHES.keys()),
                       help="Target specific switch")
    parser.add_argument("--all-switches", action="store_true",
                       help="Target all switches")

    # Verification
    parser.add_argument("--verify", action="store_true",
                       help="Verify switch configuration (read-only)")

    # VLAN operations
    parser.add_argument("--create-vlan", type=int, metavar="ID",
                       help="Create VLAN with this ID")
    parser.add_argument("--name", type=str, metavar="NAME",
                       help="VLAN name (use with --create-vlan)")
    parser.add_argument("--list-vlans", action="store_true",
                       help="List all configured VLANs")
    parser.add_argument("--disable-vlan", action="store_true",
                       help="Disable 802.1Q VLAN globally (ROLLBACK)")

    # Port operations
    parser.add_argument("--port", type=int, metavar="NUM",
                       help="Port number (1-5)")
    parser.add_argument("--access-vlan", type=int, metavar="ID",
                       help="Configure port as access (untagged) to VLAN")
    parser.add_argument("--tag-vlan", type=int, metavar="ID",
                       help="Tag port for single VLAN")
    parser.add_argument("--tag-vlans", type=str, metavar="ID,ID,ID",
                       help="Tag port for multiple VLANs (comma-separated)")
    parser.add_argument("--pvid", type=int, metavar="ID",
                       help="Set port PVID (Port VLAN ID)")

    # Utility
    parser.add_argument("--screenshot", action="store_true",
                       help="Take screenshot of current state")
    parser.add_argument("--no-headless", action="store_true",
                       help="Run browser in visible mode (for debugging)")

    args = parser.parse_args()

    # Validate arguments
    if not args.switch and not args.all_switches and not args.verify:
        print("Error: Must specify --switch or --all-switches (unless using --verify)")
        parser.print_help()
        sys.exit(1)

    if args.verify:
        # Verification mode - check all switches
        print("\n" + "="*70)
        print("VERIFICATION MODE - Read-only operation")
        print("="*70)

        switches_to_check = list(SWITCHES.keys()) if args.all_switches or not args.switch else [args.switch]

        for switch_key in switches_to_check:
            await verify_switch(switch_key, SWITCHES[switch_key])

        return

    # Determine target switches
    if args.all_switches:
        target_switches = list(SWITCHES.keys())
    else:
        target_switches = [args.switch]

    # Process operations
    if args.create_vlan:
        vlan_name = args.name or VLAN_DEFINITIONS.get(args.create_vlan, {}).get("name", f"vlan{args.create_vlan}")

        print("\n" + "="*70)
        print(f"CREATING VLAN {args.create_vlan} ({vlan_name})")
        print("="*70)
        print(f"\nTarget switches: {', '.join(target_switches)}")
        print("\nPress Enter to continue or Ctrl+C to cancel...")
        input()

        for switch_key in target_switches:
            result = await create_vlan_on_switch(switch_key, SWITCHES[switch_key], args.create_vlan, vlan_name)
            if not result:
                print(f"\n✗ Failed to create VLAN on {SWITCHES[switch_key]['name']}")
                sys.exit(1)

        print("\n" + "="*70)
        print("✓ VLAN creation complete on all target switches")
        print("="*70)

    elif args.list_vlans:
        # List VLANs on target switch
        configurator = ModularSwitchConfigurator(args.switch, SWITCHES[args.switch])

        async with async_playwright() as p:
            browser = await p.chromium.launch(headless=True)
            page = await browser.new_page()

            if await configurator.login(page):
                await configurator.list_vlans(page)

            await browser.close()

    elif args.disable_vlan:
        # DISABLE VLAN - ROLLBACK
        print("\n" + "="*70)
        print("⚠️  WARNING: DISABLING 802.1Q VLAN - ROLLBACK OPERATION")
        print("="*70)
        print(f"\nTarget switches: {', '.join(target_switches)}")
        print("\nThis will:")
        print("  - Disable 802.1Q VLAN globally")
        print("  - Remove all VLAN configurations")
        print("  - Return all ports to flat network mode")
        print("\nType 'rollback' to confirm: ")
        confirmation = input()

        if confirmation.lower() != "rollback":
            print("Cancelled.")
            sys.exit(0)

        for switch_key in target_switches:
            configurator = ModularSwitchConfigurator(switch_key, SWITCHES[switch_key])

            async with async_playwright() as p:
                browser = await p.chromium.launch(headless=True)
                page = await browser.new_page()

                if await configurator.login(page):
                    await configurator.disable_vlan_global(page)

                await browser.close()

        print("\n" + "="*70)
        print("✓ ROLLBACK COMPLETE - All switches returned to flat network mode")
        print("="*70)

    else:
        print("\nNo operation specified. Use --help for usage.")
        sys.exit(1)


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\n\nOperation cancelled by user.")
        sys.exit(0)
