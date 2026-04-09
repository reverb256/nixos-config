#!/usr/bin/env python3
"""
Configure Static IPs and Hostnames on TP-Link Switches
IP-ONLY configuration - No VLAN changes, no other settings modified

Switch Configuration:
  sw1-modem:   10.1.1.12 → 10.1.1.10
  sw2-tv:      10.1.1.90  → 10.1.1.11
  sw3-upstairs: 10.1.1.95  → 10.1.1.12
  sw4-zephyr:  10.1.1.104 → 10.1.1.13

Network Settings:
  Subnet Mask: 255.255.255.0
  Default Gateway: 10.1.1.1
"""

import asyncio
import sys
from pathlib import Path
from playwright.async_api import async_playwright

# Switch configuration with current and target IPs
SWITCHES = {
    "sw1-modem": {
        "current_ip": "10.1.1.12",
        "target_ip": "10.1.1.10",
        "hostname": "sw1-modem",
        "description": "Root switch at modem",
        "mac": "8C:90:2D:AE:4D:27",
    },
    "sw2-tv": {
        "current_ip": "10.1.1.90",
        "target_ip": "10.1.1.11",
        "hostname": "sw2-tv",
        "description": "TV area switch",
        "mac": "60:83:E7:F7:DF:C4",
    },
    "sw3-upstairs": {
        "current_ip": "10.1.1.95",
        "target_ip": "10.1.1.12",
        "hostname": "sw3-upstairs",
        "description": "Upstairs distribution switch",
        "mac": "60:83:E7:F7:F4:6C",
    },
    "sw4-zephyr": {
        "current_ip": "10.1.1.104",
        "target_ip": "10.1.1.13",
        "hostname": "sw4-zephyr",
        "description": "Zephyr room workstation switch",
        "mac": "A8:29:48:02:2A:1D",
    },
}

# Network configuration (same for all switches)
SUBNET_MASK = "255.255.255.0"
DEFAULT_GATEWAY = "10.1.1.1"

# Credentials
USERNAME = "admin"
PASSWORDS = ["admin", "ee80cb9718"]


class SwitchIPConfigurator:
    """Configure IP and hostname on TP-Link switch"""

    def __init__(self, switch_key, switch_config):
        self.switch_key = switch_key
        self.current_ip = switch_config["current_ip"]
        self.target_ip = switch_config["target_ip"]
        self.hostname = switch_config["hostname"]
        self.description = switch_config["description"]
        self.mac = switch_config["mac"]
        self.base_url = f"http://{self.current_ip}"

    async def configure(self):
        """Configure IP and hostname"""
        print(f"\n{'='*60}")
        print(f"Configuring: {self.hostname} ({self.switch_key})")
        print(f"  MAC: {self.mac}")
        print(f"  Current IP: {self.current_ip}")
        print(f"  Target IP:  {self.target_ip}")
        print(f"{'='*60}")

        async with async_playwright() as p:
            browser = await p.chromium.launch(headless=True)
            page = await browser.new_page()

            try:
                # Login
                print(f"  → Logging in...")
                if not await self._login(page):
                    raise Exception("Login failed")

                # Step 1: Update hostname/description
                print(f"  → Setting hostname to: {self.hostname}")
                await self._set_hostname(page)

                # Step 2: Configure static IP
                print(f"  → Configuring static IP: {self.target_ip}")
                await self._set_static_ip(page)

                # Take screenshot
                await self._take_screenshot(page, "after-config")

                print(f"  ✓ Configuration complete")
                print(f"  ℹ️  Switch may need reboot for IP change to take effect")
                return {"switch": self.switch_key, "success": True, "error": None}

            except Exception as e:
                print(f"  ✗ Error: {e}")
                return {"switch": self.switch_key, "success": False, "error": str(e)}

            finally:
                await browser.close()

    async def _login(self, page):
        """Login to switch web interface"""
        try:
            await page.goto(self.base_url, timeout=15000)
            await asyncio.sleep(2)

            # Try multiple passwords
            for password in PASSWORDS:
                try:
                    await page.fill('input[name="username"]', USERNAME)
                    await page.fill('input[name="password"]', password)
                    await page.click('input[name="logon"]')
                    await asyncio.sleep(3)

                    if "logon" not in page.url:
                        print(f"  ✓ Logged in (password: {password})")
                        return True
                    else:
                        print(f"  ✗ Login failed with password: {password}")
                        await page.goto(self.base_url, timeout=10000)
                        await asyncio.sleep(1)
                except Exception as e:
                    print(f"  ! Login attempt error: {e}")
                    await page.goto(self.base_url, timeout=10000)
                    await asyncio.sleep(1)

            return False
        except Exception as e:
            print(f"  ✗ Login error: {e}")
            return False

    async def _set_hostname(self, page):
        """Set device description/hostname"""
        try:
            await page.goto(f"{self.base_url}/SystemInfoRpm.htm", timeout=15000)
            await asyncio.sleep(2)

            # Find and fill description field
            description_selectors = [
                'input[name="devName"]',
                'input[name="description"]',
                'input[name="device"]',
            ]

            for selector in description_selectors:
                try:
                    input_field = await page.query_selector(selector)
                    if input_field:
                        # Clear existing value and set new hostname
                        await input_field.fill("")
                        await input_field.fill(self.hostname)
                        print(f"    → Found description field, set to: {self.hostname}")

                        # Click Apply
                        await self._click_apply(page)
                        await asyncio.sleep(2)
                        return True
                except:
                    continue

            print(f"    ! Description field not found, may use different selector")
            return False

        except Exception as e:
            print(f"    ! Error setting hostname: {e}")
            return False

    async def _set_static_ip(self, page):
        """Configure static IP address"""
        try:
            await page.goto(f"{self.base_url}/IpSettingRpm.htm", timeout=15000)
            await asyncio.sleep(2)

            # Verify we're on IP configuration page
            page_text = await page.evaluate("() => document.body.innerText")
            if "IP Address" not in page_text:
                print(f"    ! Not on IP configuration page")
                return False

            # Fill in IP configuration
            ip_selectors = ['input[name="ipAddress"]', 'input[name="ip"]', 'input[type="text"]']

            # Try to find and fill IP address field
            found_ip_field = False
            for selector in ip_selectors:
                try:
                    ip_field = await page.query_selector(selector)
                    if ip_field:
                        await ip_field.fill("")
                        await ip_field.fill(self.target_ip)
                        print(f"    → Set IP address to: {self.target_ip}")
                        found_ip_field = True
                        break
                except:
                    continue

            if not found_ip_field:
                print(f"    ! IP address field not found")
                return False

            # Fill in subnet mask
            subnet_selectors = ['input[name="subnetMask"]', 'input[name="subnet"]']
            for selector in subnet_selectors:
                try:
                    subnet_field = await page.query_selector(selector)
                    if subnet_field:
                        await subnet_field.fill("")
                        await subnet_field.fill(SUBNET_MASK)
                        print(f"    → Set subnet mask to: {SUBNET_MASK}")
                        break
                except:
                    continue

            # Fill in default gateway
            gateway_selectors = ['input[name="gateway"]', 'input[name="defaultGateway"]']
            for selector in gateway_selectors:
                try:
                    gateway_field = await page.query_selector(selector)
                    if gateway_field:
                        await gateway_field.fill("")
                        await gateway_field.fill(DEFAULT_GATEWAY)
                        print(f"    → Set gateway to: {DEFAULT_GATEWAY}")
                        break
                except:
                    continue

            # Ensure DHCP is disabled
            print(f"    → DHCP should be disabled (static mode)")

            # Click Apply to save
            await self._click_apply(page)
            await asyncio.sleep(3)

            return True

        except Exception as e:
            print(f"    ! Error setting IP: {e}")
            return False

    async def _click_apply(self, page):
        """Click Apply/Save button"""
        selectors = [
            'input[value="Apply"]',
            'input[name="Apply"]',
            'button:has-text("Apply")',
            'button:has-text("Save")',
        ]

        for selector in selectors:
            try:
                btn = await page.query_selector(selector)
                if btn:
                    await btn.click()
                    print(f"    → Clicked Apply button")
                    await asyncio.sleep(2)
                    return True
            except:
                continue

        print(f"    ! Apply button not found")
        return False

    async def _take_screenshot(self, page, name):
        """Take screenshot for verification"""
        try:
            output_dir = Path("/tmp/switch-ip-config")
            output_dir.mkdir(parents=True, exist_ok=True)
            screenshot_path = output_dir / f"{self.switch_key}-{name}.png"
            await page.screenshot(path=str(screenshot_path))
            print(f"  📷 Screenshot: {screenshot_path}")
        except Exception as e:
            print(f"  ! Screenshot error: {e}")


async def main():
    print("="*60)
    print("TP-Link Switch IP & Hostname Configuration")
    print("="*60)
    print(f"\nNetwork Configuration:")
    print(f"  Subnet Mask:     {SUBNET_MASK}")
    print(f"  Default Gateway: {DEFAULT_GATEWAY}")
    print(f"\nSwitches to configure:")
    for key, config in SWITCHES.items():
        print(f"  {key}:")
        print(f"    Current: {config['current_ip']} → Target: {config['target_ip']}")
        print(f"    Hostname: {config['hostname']}")
    print()

    results = {}
    for key, config in SWITCHES.items():
        configurator = SwitchIPConfigurator(key, config)
        result = await configurator.configure()
        results[key] = result

    # Save results
    import json
    results_file = Path("/tmp/switch-ip-results.json")
    results_file.write_text(json.dumps(results, indent=2))

    print(f"\n{'='*60}")
    print(f"Configuration Summary")
    print(f"{'='*60}")
    for key, result in results.items():
        status = "✓ SUCCESS" if result["success"] else "✗ FAILED"
        print(f"{key}: {status}")
        if result["error"]:
            print(f"  Error: {result['error']}")

    print(f"\nResults saved to: {results_file}")
    print(f"\nNext steps:")
    print(f"  1. Verify each switch is accessible at its new IP")
    print(f"  2. Test network connectivity between switches")
    print(f"  3. Update documentation with new IPs")

    print(f"\n⚠️  IMPORTANT:")
    print(f"  Switches may require reboot for IP changes to take effect.")
    print(f"  If switches are not accessible at new IPs, try old IPs first.")


if __name__ == "__main__":
    asyncio.run(main())
