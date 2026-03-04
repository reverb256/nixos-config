#!/usr/bin/env python3
"""
TP-Link Switch Automation with Playwright
Automates configuration for TL-SG105E Easy Smart Switches
"""

import asyncio
import sys
from typing import Optional, Dict, Any

try:
    import playwright

    PlaywrightAvailable = True
except ImportError:
    PlaywrightAvailable = False
    print("ERROR: Playwright not installed. Install with:")
    print("  playwright install")
    print("  nix-shell -p playwright --run 'playwright install'")
    sys.exit(1)


class TPLinkSwitchAutomator:
    """Automate TP-Link Easy Smart Switch configuration with Playwright"""

    def __init__(self, ip: str, username: str = "admin", password: str = "admin"):
        self.ip = ip
        self.username = username
        self.password = password
        self.base_url = f"http://{ip}"

    async def login(self, page) -> bool:
        """Login to switch web interface"""
        try:
            await page.goto(self.base_url, timeout=15000)
            await page.wait_for_load_state("domcontentloaded", timeout=5000)

            # Wait for login form
            await page.wait_for_selector('input[name="username"]', timeout=5000)
            await page.fill('input[name="username"]', self.username)
            await page.fill('input[name="password"]', self.password)
            await page.click('input[name="logon"]')
            await page.wait_for_load_state("domcontentloaded", timeout=5000)

            # Check if login succeeded (page should redirect or change)
            current_url = page.url
            if "/logon.cgi" not in current_url:
                return True
            return False
        except Exception as e:
            print(f"Login failed: {e}")
            return False

    async def enable_snmp(self, page) -> bool:
        """Enable SNMP on switch"""
        try:
            # Navigate to SNMP page
            await page.goto(f"{self.base_url}/snmpRpm.htm", timeout=15000)
            await page.wait_for_load_state("domcontentloaded", timeout=5000)

            # Look for SNMP enable checkbox
            # Wait a moment for page to load
            await asyncio.sleep(1)

            # Try different selectors for SNMP enable
            enable_selectors = [
                'input[name="snmpEnable"]',
                'input[type="checkbox"][name*="snmp"]',
                "#snmpEnable",
            ]

            for selector in enable_selectors:
                try:
                    element = await page.query_selector(selector)
                    if element:
                        # Check if it's enabled
                        is_checked = await element.is_checked()
                        if not is_checked:
                            await element.check()
                            print(f"  [✓] SNMP enabled using selector: {selector}")
                            return True
                except Exception:
                    continue

            # Alternative: Try clicking SNMP link and filling form
            snmp_link = await page.query_selector('a:has-text("SNMP")')
            if snmp_link:
                await snmp_link.click()
                await page.wait_for_load_state("domcontentloaded", timeout=5000)

                # Now look for enable checkbox
                for selector in enable_selectors:
                    try:
                        element = await page.query_selector(selector)
                        if element:
                            is_checked = await element.is_checked()
                            if not is_checked:
                                await element.check()
                                print(
                                    f"  [✓] SNMP enabled via link + selector: {selector}"
                                )
                                return True
                    except Exception:
                        continue

            print(f"  [✗] Could not find SNMP enable option")
            return False

        except Exception as e:
            print(f"  [!] Error enabling SNMP: {e}")
            return False

    async def create_vlan(self, page, vlan_id: int, vlan_name: str) -> bool:
        """Create a VLAN on the switch"""
        try:
            # Navigate to VLAN page
            await page.goto(f"{self.base_url}/vlanRpm.htm", timeout=15000)
            await page.wait_for_load_state("domcontentloaded", timeout=5000)

            # Wait a moment for page to load
            await asyncio.sleep(1)

            # Try to find VLAN creation interface
            # Look for "Add" button or similar
            add_vlan_selectors = [
                'input:has-text("Add")',
                'button:has-text("Add")',
                'a:has-text("Add")',
                "#addVlan",
            ]

            for selector in add_vlan_selectors:
                try:
                    element = await page.query_selector(selector)
                    if element:
                        print(f"  [✓] Found VLAN add button: {selector}")
                        await element.click()
                        await asyncio.sleep(1)
                        break
                except Exception:
                    continue

            # Try to fill VLAN form
            vlan_id_input = await page.query_selector('input[name*="vid"]')
            vlan_name_input = await page.query_selector('input[name*="vname"]')

            if vlan_id_input:
                await vlan_id_input.fill(str(vlan_id))
                print(f"  [✓] Set VLAN ID: {vlan_id}")

            if vlan_name_input:
                await vlan_name_input.fill(vlan_name)
                print(f"  [✓] Set VLAN name: {vlan_name}")

            # Try to find and click save/apply button
            save_selectors = [
                'input:has-text("Apply")',
                'button:has-text("Apply")',
                'input[value="Apply"]',
                "#save",
            ]

            for selector in save_selectors:
                try:
                    element = await page.query_selector(selector)
                    if element:
                        await element.click()
                        print(f"  [✓] Clicked save using: {selector}")
                        await page.wait_for_load_state("domcontentloaded", timeout=5000)
                        return True
                except Exception:
                    continue

            print(f"  [✗] Could not find save button")
            return False

        except Exception as e:
            print(f"  [!] Error creating VLAN: {e}")
            return False

    async def configure_port(
        self, page, port: int, vlan_id: Optional[int] = None
    ) -> bool:
        """Configure a port with VLAN tagging"""
        try:
            # Navigate to port configuration page
            await page.goto(f"{self.base_url}/portRpm.htm", timeout=15000)
            await page.wait_for_load_state("domcontentloaded", timeout=5000)

            # Wait a moment for page to load
            await asyncio.sleep(1)

            # Try to select the port
            port_selectors = [
                f'input[name*="port"][value="{port}"]',
                f'select[name*="port"] option[value="{port}"]',
                f"#port{port}",
                f'a:has-text("Port {port}")',
            ]

            port_selected = False
            for selector in port_selectors:
                try:
                    element = await page.query_selector(selector)
                    if element:
                        await element.click()
                        print(f"  [✓] Selected port {port}")
                        port_selected = True
                        await asyncio.sleep(0.5)
                        break
                except Exception:
                    continue

            if not port_selected:
                print(f"  [✗] Could not select port {port}")
                return False

            # Try to set VLAN if provided
            if vlan_id:
                vlan_selectors = [
                    f'select[name*="pvid"][value="{vlan_id}"]',
                    f'input[name*="pvid"][value="{vlan_id}"]',
                ]

                for selector in vlan_selectors:
                    try:
                        element = await page.query_selector(selector)
                        if element:
                            await element.select_option(value=str(vlan_id))
                            print(f"  [✓] Set VLAN {vlan_id} for port {port}")
                            break
                    except Exception:
                        continue

            # Try to save
            save_selectors = [
                'input:has-text("Apply")',
                'button:has-text("Apply")',
                'input[value="Apply"]',
                "#save",
            ]

            for selector in save_selectors:
                try:
                    element = await page.query_selector(selector)
                    if element:
                        await element.click()
                        print(f"  [✓] Saved port configuration")
                        await page.wait_for_load_state("domcontentloaded", timeout=5000)
                        return True
                except Exception:
                    continue

            print(f"  [✗] Could not find save button")
            return False

        except Exception as e:
            print(f"  [!] Error configuring port: {e}")
            return False

    async def take_screenshot(self, page, filename: str):
        """Take a screenshot for debugging"""
        await page.screenshot(path=f"/tmp/{filename}.png", full_page=True)
        print(f"  [📷] Screenshot saved to /tmp/{filename}.png")


async def configure_switch(ip: str, username: str, password: str):
    """Configure a single switch with all settings"""
    print(f"\n{'=' * 60}")
    print(f"Configuring switch: {ip}")
    print(f"{'=' * 60}\n")

    automator = TPLinkSwitchAutomator(ip, username, password)

    async with async_playwright(headless=True) as p:
        browser = await p.chromium.launch(headless=True)
        page = await browser.new_page()

        # Login
        print("Step 1: Logging in...")
        if not await automator.login(page):
            print(f"  [✗] Login failed for {ip}")
            return

        print(f"  [✓] Logged in to {ip}")
        await asyncio.sleep(1)

        # Enable SNMP
        print("Step 2: Enabling SNMP...")
        if await automator.enable_snmp(page):
            print(f"  [✓] SNMP enabled on {ip}")
        else:
            print(f"  [✗] SNMP enablement may have failed for {ip}")
            await automator.take_screenshot(page, f"{ip.replace('.', '-')}-snmp-error")

        await asyncio.sleep(1)

        # Create VLANs
        print("Step 3: Creating VLANs...")
        vlans = [
            (10, "gaming"),
            (20, "ai"),
            (30, "storage"),
            (40, "mining"),
            (50, "monitoring"),
            (60, "backup"),
            (99, "management"),
        ]

        for vlan_id, vlan_name in vlans:
            print(f"  Creating VLAN {vlan_id} ({vlan_name})...")
            if await automator.create_vlan(page, vlan_id, vlan_name):
                print(f"    [✓] VLAN {vlan_id} created")
            else:
                print(f"    [✗] VLAN {vlan_id} creation may have failed")

        await asyncio.sleep(1)

        # Configure ports (port 1 with VLAN 10, port 2 with VLAN 20, etc.)
        print("Step 4: Configuring ports...")
        port_configs = [
            (1, 10),  # zephyr-gaming
            (2, 20),  # zephyr-ai
        ]

        for port, vlan_id in port_configs:
            print(f"  Configuring port {port} for VLAN {vlan_id}...")
            if await automator.configure_port(page, port, vlan_id):
                print(f"    [✓] Port {port} configured for VLAN {vlan_id}")
            else:
                print(f"    [✗] Port {port} configuration may have failed")

        # Take final screenshot
        await automator.take_screenshot(page, f"{ip.replace('.', '-')}-complete")

        print(f"\n{'=' * 60}")
        print(f"Configuration completed for {ip}")
        print(f"{'=' * 60}\n")

        await browser.close()


async def main():
    """Main automation function"""
    if len(sys.argv) < 4:
        print("Usage: python3 automate_switches.py <ip> <username> <password>")
        sys.exit(1)

    ip = sys.argv[1]
    username = sys.argv[2]
    password = sys.argv[3]

    print("=" * 60)
    print("TP-Link Switch Automation")
    print("=" * 60)
    print(f"\nTarget: {ip}")
    print(f"Credentials: {username}/{password}")
    print("\nThis will:")
    print("  1. Login to the switch")
    print("  2. Enable SNMP")
    print("  3. Create VLANs (10, 20, 30, 40, 50, 60, 99)")
    print("  4. Configure ports (port 1 -> VLAN 10, port 2 -> VLAN 20)")
    print("\nStarting...\n")

    await configure_switch(ip, username, password)


if __name__ == "__main__":
    if PlaywrightAvailable:
        asyncio.run(main())
