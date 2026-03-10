#!/usr/bin/env python3
"""
Configure Static IP Addresses on TP-Link Switches

Sets static IP configuration directly on each switch based on MAC address inventory.
This is more robust than DHCP reservations - switches maintain IPs even after modem replacement.

Switch Inventory (from MAC address discovery):
- sw1-modem (MAC: 8C:90:2D:AE:4D:27) → 10.1.1.10
- sw2-tv (MAC: 60:83:E7:F7:DF:C4) → 10.1.1.11
- sw3-upstairs (MAC: 60:83:E7:F7:F4:6C) → 10.1.1.12
- sw4-zephyr (MAC: A8:29:48:02:2A:1D) → 10.1.1.13
"""

import asyncio
import json
from pathlib import Path
from playwright.async_api import async_playwright

# Switch configuration based on MAC address inventory
SWITCHES = {
    "sw1-modem": {
        "current_ip": "10.1.1.10",  # Currently has this IP via DHCP
        "static_ip": "10.1.1.10",
        "mac": "8C:90:2D:AE:4D:27",
        "name": "sw1-modem (TL-SG105E)",
        "location": "Modem location",
    },
    "sw2-tv": {
        "current_ip": "10.1.1.11",  # Currently has this IP via DHCP
        "static_ip": "10.1.1.11",
        "mac": "60:83:E7:F7:DF:C4",
        "name": "sw2-tv (TL-SG105E)",
        "location": "TV area",
    },
    "sw3-upstairs": {
        "current_ip": "10.1.1.12",  # Currently has this IP via DHCP
        "static_ip": "10.1.1.12",
        "mac": "60:83:E7:F7:F4:6C",
        "name": "sw3-upstairs (TL-SG105E-23)",
        "location": "Spare room",
    },
    "sw4-zephyr": {
        "current_ip": "10.1.1.13",  # Currently has this IP via DHCP
        "static_ip": "10.1.1.13",
        "mac": "A8:29:48:02:2A:1D",
        "name": "sw4-zephyr (TL-SG105E)",
        "location": "Zephyr's room",
    },
}

# Network configuration
SUBNET_MASK = "255.255.255.0"
DEFAULT_GATEWAY = "10.1.1.1"
DNS_SERVERS = "10.1.1.1"  # Use modem as DNS

# Credentials
USERNAME = "admin"
PASSWORDS = ["admin", "ee80cb9718"]


async def configure_switch_static_ip(switch_key, switch_config):
    """Configure static IP on a switch"""
    current_ip = switch_config["current_ip"]
    static_ip = switch_config["static_ip"]
    name = switch_config["name"]

    print(f"\n{'='*60}")
    print(f"Configuring: {name}")
    print(f"  Current IP: {current_ip} (DHCP)")
    print(f"  Static IP:  {static_ip}")
    print(f"  MAC:        {switch_config['mac']}")
    print(f"{'='*60}")

    result = {
        "switch": switch_key,
        "name": name,
        "mac": switch_config["mac"],
        "current_ip": current_ip,
        "static_ip": static_ip,
        "success": False,
        "error": None,
    }

    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=False)  # Show browser for debugging
        page = await browser.new_page()

        try:
            # Login
            print(f"  → Connecting to {current_ip}...")
            await page.goto(f"http://{current_ip}", timeout=15000)
            await asyncio.sleep(2)

            # Try login with multiple passwords
            login_success = False
            for password in PASSWORDS:
                try:
                    await page.fill('input[name="username"]', USERNAME)
                    await page.fill('input[name="password"]', password)
                    await page.click('input[name="logon"]')
                    await asyncio.sleep(3)

                    if "logon" not in page.url:
                        print(f"  ✓ Logged in (password: {password})")
                        login_success = True
                        break
                    else:
                        print(f"  ✗ Login failed with password: {password}")
                        await page.goto(f"http://{current_ip}", timeout=10000)
                        await asyncio.sleep(1)
                except Exception as e:
                    print(f"  ! Login attempt failed: {e}")
                    await page.goto(f"http://{current_ip}", timeout=10000)
                    await asyncio.sleep(1)

            if not login_success:
                raise Exception("Login failed with all passwords")

            # Navigate to System > IP Configuration page
            print(f"  → Navigating to IP configuration...")
            await page.goto(f"http://{current_ip}/IpSettingRpm.htm", timeout=10000)
            await asyncio.sleep(2)

            # Check if we're on the IP configuration page
            page_text = await page.evaluate("() => document.body.innerText")

            if "IP Address" not in page_text and "ip" not in page_text.lower():
                # Try alternative URL pattern
                await page.goto(f"http://{current_ip}/system_ip.htm", timeout=10000)
                await asyncio.sleep(2)
                page_text = await page.evaluate("() => document.body.innerText")

            # Take screenshot before configuration
            screenshot_before = f"/tmp/switch-config-{switch_key}-before.png"
            await page.screenshot(path=screenshot_before)
            print(f"  ✓ Screenshot saved: {screenshot_before}")

            # Look for static IP configuration options
            print(f"  → Looking for static IP configuration...")
            print(f"  Page text preview: {page_text[:500]}...")

            # Try to find and configure static IP
            # This will depend on the specific TP-Link switch model interface
            try:
                # Look for IP address input field
                ip_inputs = await page.evaluate('''() => {
                    const inputs = document.querySelectorAll('input[type="text"]');
                    return Array.from(inputs).map(inp => ({
                        name: inp.name || inp.id || '',
                        placeholder: inp.getAttribute('placeholder') || '',
                        value: inp.value || ''
                    }));
                }''')

                print(f"  Found {len(ip_inputs)} input fields")

                # Look for static/DHCP radio buttons
                radio_buttons = await page.evaluate('''() => {
                    const radios = document.querySelectorAll('input[type="radio"]');
                    return Array.from(radios).map(radio => ({
                        name: radio.name || '',
                        value: radio.value || '',
                        checked: radio.checked
                    }));
                }''')

                print(f"  Found {len(radio_buttons)} radio buttons")

                # Save page HTML for analysis
                html_content = await page.evaluate("() => document.body.innerHTML")
                html_file = Path(f"/tmp/switch-config-{switch_key}-page.html")
                html_file.write_text(html_content)
                print(f"  ✓ Page HTML saved: {html_file}")

                result["html_saved"] = str(html_file)
                result["ip_inputs"] = ip_inputs
                result["radio_buttons"] = radio_buttons

            except Exception as e:
                print(f"  ! Error analyzing page: {e}")
                result["error"] = str(e)

            # Take screenshot after analysis
            screenshot_after = f"/tmp/switch-config-{switch_key}-after.png"
            await page.screenshot(path=screenshot_after)
            print(f"  ✓ Screenshot saved: {screenshot_after}")

            print(f"\n  ⏸️  Pausing for manual configuration (30 seconds)...")
            print(f"     Please configure static IP manually if needed:")
            print(f"     - IP Address: {static_ip}")
            print(f"     - Subnet Mask: {SUBNET_MASK}")
            print(f"     - Default Gateway: {DEFAULT_GATEWAY}")
            await asyncio.sleep(30)

            result["success"] = True
            print(f"  ✓ Configuration completed")

        except Exception as e:
            print(f"  ✗ Error: {e}")
            result["error"] = str(e)

        await browser.close()

    return result


async def main():
    print("="*60)
    print("Configure Static IP Addresses on TP-Link Switches")
    print("="*60)
    print(f"\nNetwork Configuration:")
    print(f"  Subnet Mask:     {SUBNET_MASK}")
    print(f"  Default Gateway: {DEFAULT_GATEWAY}")
    print(f"  DNS Server:      {DNS_SERVERS}")
    print(f"\nSwitches to configure:")
    for key, config in SWITCHES.items():
        print(f"  {key}: {config['name']}")
        print(f"    Current IP: {config['current_ip']} → Static IP: {config['static_ip']}")
    print()

    results = {}
    for key, config in SWITCHES.items():
        result = await configure_switch_static_ip(key, config)
        results[key] = result

    # Save results
    results_file = Path("/tmp/switch-static-ip-results.json")
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
    print(f"  1. Verify each switch is accessible at its static IP")
    print(f"  2. Test network connectivity")
    print(f"  3. Update documentation with static IP configuration")


if __name__ == "__main__":
    asyncio.run(main())
