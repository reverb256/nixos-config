#!/usr/bin/env python3
"""
TP-Link Easy Smart Switch - Python Management Library

Supports TL-SG105E, TL-SG108E, TL-SG1016DE, TL-SG1024DE and similar models.

Usage:
    from tplink_switch import TPLinkSwitch

    switch = TPLinkSwitch('10.1.1.10', 'admin', 'password')
    switch.login()
    info = switch.get_system_info()
    print(info)
"""

import requests
import urllib3
from typing import Optional, Dict, Any, List

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)


class TPLinkSwitch:
    """Python class for managing TP-Link Easy Smart Switches via HTTP"""

    def __init__(self, ip: str, username: str = "admin", password: str = "admin"):
        self.ip = ip
        self.username = username
        self.password = password
        self.session = requests.Session()
        self.session.headers.update(
            {
                "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) TPLink-Switch/1.0",
                "Referer": f"http://{self.ip}/",
            }
        )
        self.logged_in = False

    def _request(self, method: str, url: str, **kwargs) -> requests.Response:
        """Make HTTP request with error handling"""
        try:
            response = self.session.request(method, url, **kwargs)
            response.raise_for_status()
            return response
        except requests.exceptions.RequestException as e:
            raise TPLinkSwitchError(f"Request failed: {e}")

    def login(self) -> bool:
        """Login to switch web interface - returns True on success even if HTTP 401 (normal)"""
        login_url = f"http://{self.ip}/logon.cgi"

        data = {"username": self.username, "password": self.password, "logon": "Login"}

        try:
            response = self._request("POST", login_url, data=data, timeout=10)
            self.logged_in = True
            # TP-Link returns 401 even on successful login
            # Session is maintained via IP-based authentication
            return True
        except TPLinkSwitchError:
            return False

    def logout(self):
        """Logout from switch"""
        if self.logged_in:
            try:
                self._request("GET", f"http://{self.ip}/logout.cgi")
            except Exception:
                pass
            finally:
                self.logged_in = False

    def get_port_status(self) -> List[Dict[str, Any]]:
        """Get port statistics from switch"""
        if not self.logged_in:
            self.login()

        port_url = f"http://{self.ip}/PortStatisticsRpm.htm"

        try:
            response = self._request("GET", port_url, timeout=10)
            return self._parse_port_statistics(response.text)
        except TPLinkSwitchError:
            return []

    def get_vlan_config(self) -> Dict[str, Any]:
        """Get VLAN configuration"""
        if not self.logged_in:
            self.login()

        vlan_url = f"http://{self.ip}/VlanRpm.htm"

        try:
            response = self._request("GET", vlan_url, timeout=10)
            return self._parse_vlan_config(response.text)
        except TPLinkSwitchError:
            return {}

    def set_port_state(self, port: int, enabled: bool) -> bool:
        """Enable or disable a port via QoS settings"""
        if not self.logged_in:
            self.login()

        port_url = f"http://{self.ip}/QosBandWidthControlRpm.htm"

        # Select port: sel_1, sel_2, sel_3, sel_4, sel_5 for ports 1-5
        port_select = f"sel_{port}"
        data = {
            f"{port_select}": "1",  # Select the port
            "applay": "Apply",  # Apply settings
        }

        try:
            # First enable the port (set to unlimited bandwidth)
            data["igrRate"] = "1000000"  # 1000000 Kbps = unlimited
            data["egrRate"] = "1000000"

            response = self._request("POST", port_url, data=data, timeout=10)
            return response.status_code == 200
        except TPLinkSwitchError:
            return False

    def reboot(self) -> bool:
        """Reboot the switch"""
        if not self.logged_in:
            self.login()

        reboot_url = f"http://{self.ip}/SysRebootRpm.htm"

        try:
            response = self._request("GET", reboot_url + "?Reboot=Reboot", timeout=10)
            # TP-Link switches respond with 200 to reboot request
            # Response body may be minimal
            return response.status_code == 200
        except TPLinkSwitchError:
            return False

    def get_system_info(self) -> Dict[str, Any]:
        """Get system information"""
        if not self.logged_in:
            self.login()

        system_url = f"http://{self.ip}/SysInfoRpm.htm"

        try:
            response = self._request("GET", system_url, timeout=10)
            return self._parse_system_info(response.text)
        except TPLinkSwitchError:
            return {}

    def _parse_system_info(self, html: str) -> Dict[str, Any]:
        """Parse system info from HTML response"""
        info = {}

        import re

        # Extract from JavaScript variables
        patterns = {
            "model": r'var\s+g_model\s*=\s*"([^"]+)"',
            "hostname": r'var\s+g_devName\s*=\s*"([^"]+)"',
            "ip": r'var\s+ipAddr\s*=\s*"([^"]+)"',
            "mac": r'var\s+macAddr\s*=\s*"([^"]+)"',
            "firmware": r'var\s+g_softVer\s*=\s*"([^"]+)"',
            "portCount": r'var\s+portNum\s*=\s*([\d]+)"',
        }

        for key, pattern in patterns.items():
            match = re.search(pattern, html)
            if match:
                info[key] = match.group(1)

        return info

    def _parse_port_statistics(self, html: str) -> List[Dict[str, Any]]:
        """Parse port statistics from JavaScript data in HTML"""
        ports = []

        import re

        # Extract all_info JavaScript array
        m = re.search(r"var\s+all_info\s*=\s*{(.*?)};", html)
        if m:
            data_str = m.group(1)

            # Parse port states and link statuses
            states = re.search(r"state:\s*\[(.*?)\]", data_str)
            link_statuses = re.search(r"link_status:\s*\[(.*?)\]", data_str)
            packet_stats = re.search(r"pkts:\s*\[(.*?)\]", data_str)

            if states and link_statuses and packet_stats:
                state_list = [s.strip() for s in states.group(1).split(",")]
                link_status_list = [
                    s.strip() for s in link_statuses.group(1).split(",")
                ]
                packet_list = packet_stats.group(1).strip("[]").split(",")

                # Process each port
                for i in range(min(len(state_list), 5)):  # Max 5 ports
                    ports.append(
                        {
                            "port": i + 1,
                            "enabled": state_list[i] == "1",
                            "linkStatus": int(link_status_list[i])
                            if i < len(link_status_list)
                            else 0,
                            "txGood": int(packet_list[i * 4])
                            if i * 4 < len(packet_list)
                            else 0,
                            "txBad": int(packet_list[i * 4 + 1])
                            if i * 4 + 1 < len(packet_list)
                            else 0,
                            "rxGood": int(packet_list[i * 4 + 2])
                            if i * 4 + 2 < len(packet_list)
                            else 0,
                            "rxBad": int(packet_list[i * 4 + 3])
                            if i * 4 + 3 < len(packet_list)
                            else 0,
                        }
                    )

        return ports

    def _parse_vlan_config(self, html: str) -> Dict[str, Any]:
        """Parse VLAN configuration from HTML response"""
        vlans = {}

        import re

        # Extract VLAN data from JavaScript
        m = re.search(r"var\s+g_vlan\s*=\s*\[(.*?)\];", html)
        if m:
            vlan_data = m.group(1)

            # Parse individual VLAN entries
            vlan_pattern = r'\{vid:\s*(\d+),\s*vname:\s*"([^"]+)"'
            for match in re.finditer(vlan_pattern, vlan_data):
                vlans[match.group(1)] = {
                    "name": match.group(2),
                    "vid": int(match.group(1)),
                }

        return vlans

    def __enter__(self):
        self.login()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.logout()

    def __del__(self):
        try:
            self.logout()
        except Exception:
            pass


class TPLinkSwitchError(Exception):
    """Exception for TP-Link switch operations"""

    pass


def discover_switches(interface: Optional[str] = None) -> List[Dict[str, Any]]:
    """
    Discover TP-Link switches on the network using UDP broadcast.

    Note: This requires root privileges and uses the Realtek RRCP protocol.
    """
    import socket

    switches = []

    RRCP_DISCOVER = bytes([0x01, 0x09, 0x00, 0x00, 0x00, 0x00])
    RRCP_PORT = 29808

    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        if interface:
            sock.bind((interface, 0))
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        sock.settimeout(5)

        sock.sendto(RRCP_DISCOVER, ("255.255.255.255", RRCP_PORT))

        while True:
            try:
                data, addr = sock.recvfrom(1024)
                if len(data) >= 20:
                    switches.append(
                        {
                            "ip": addr[0],
                            "mac": ":".join(f"{b:02x}" for b in data[6:12]),
                            "type": "TL-SG???E",
                        }
                    )
            except socket.timeout:
                break

    except Exception:
        pass

    return switches


if __name__ == "__main__":
    import sys

    if len(sys.argv) < 2:
        print("Usage: python -m tplink_switch <switch-ip> [username] [password]")
        sys.exit(1)

    ip = sys.argv[1]
    username = sys.argv[2] if len(sys.argv) > 2 else "admin"
    password = sys.argv[3] if len(sys.argv) > 3 else "admin"

    switch = TPLinkSwitch(ip, username, password)

    with switch:
        print(f"Connected to {ip}")
        info = switch.get_system_info()
        print(f"System Info: {info}")

        ports = switch.get_port_status()
        print(f"Port Status: {ports}")
