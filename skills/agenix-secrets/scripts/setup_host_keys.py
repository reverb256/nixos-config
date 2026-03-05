#!/usr/bin/env python3
"""
Setup host keys for agenix multi-host deployment.
This script helps you add host SSH keys to secrets.nix for automatic secret decryption.
"""

import subprocess
import sys
import os
import re
from pathlib import Path


def get_host_age_key(hostname=None, ssh_key_path="/etc/ssh/ssh_host_ed25519_key.pub"):
    """
    Get the age public key from a host's SSH host key.

    Args:
        hostname: Hostname or IP (for SSH remote access). None for localhost.
        ssh_key_path: Path to SSH host public key on the host.

    Returns:
        Age public key string.
    """
    if hostname:
        # Remote host - SSH and get the key
        cmd = ["ssh", hostname, f"sudo cat {ssh_key_path} | ssh-to-age"]
        print(f"Connecting to {hostname}...")
    else:
        # Local host
        cmd = ["sh", "-c", f"cat {ssh_key_path} | ssh-to-age"]
        print("Reading local host key...")

    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            check=True
        )
        age_key = result.stdout.strip()
        if age_key.startswith("age1"):
            return age_key
        else:
            print(f"Error: Unexpected output format: {age_key}")
            return None
    except subprocess.CalledProcessError as e:
        print(f"Error getting host key: {e.stderr}")
        return None
    except FileNotFoundError:
        print("Error: ssh-to-age not found. Install with: nix-shell -p ssh-to-age")
        return None


def parse_secrets_nix(secrets_nix_path="/etc/nixos/secrets.nix"):
    """
    Parse secrets.nix to extract users and hosts sections.

    Returns:
        dict with 'users' and 'hosts' sections.
    """
    if not os.path.exists(secrets_nix_path):
        return {"users": {}, "hosts": {}}

    with open(secrets_nix_path, "r") as f:
        content = f.read()

    result = {"users": {}, "hosts": {}}

    # Parse users section
    users_match = re.search(r'users\s*=\s*{([^}]+)};', content, re.DOTALL)
    if users_match:
        users_section = users_match.group(1)
        for match in re.finditer(r'(\w+)\s*=\s*"([^"]+)"', users_section):
            name, key = match.groups()
            result["users"][name] = key

    # Parse hosts section
    hosts_match = re.search(r'hosts\s*=\s*{([^}]+)};', content, re.DOTALL)
    if hosts_match:
        hosts_section = hosts_match.group(1)
        for match in re.finditer(r'(\w+)\s*=\s*"([^"]+)"', hosts_section):
            name, key = match.groups()
            result["hosts"][name] = key

    return result


def update_secrets_nix_hosts(hosts_dict, secrets_nix_path="/etc/nixos/secrets.nix"):
    """
    Add or update hosts section in secrets.nix.

    Args:
        hosts_dict: dict of hostname -> age_key
        secrets_nix_path: Path to secrets.nix

    Returns:
        True if successful, False otherwise.
    """
    with open(secrets_nix_path, "r") as f:
        content = f.read()

    # Check if hosts section exists
    if "hosts = {" in content:
        # Update existing hosts section
        def replace_hosts(match):
            existing = match.group(1)
            # Parse existing hosts
            existing_hosts = {}
            for m in re.finditer(r'(\w+)\s*=\s*"([^"]+)"', existing):
                name, key = m.groups()
                existing_hosts[name] = key

            # Merge with new hosts
            existing_hosts.update(hosts_dict)

            # Build new hosts section
            hosts_lines = ["  hosts = {"]
            for name, key in sorted(existing_hosts.items()):
                hosts_lines.append(f'    {name} = "{key}";')
            hosts_lines.append("  };")

            return "\n".join(hosts_lines)

        content = re.sub(
            r'hosts\s*=\s*\{([^}]+)\};',
            replace_hosts,
            content,
            flags=re.DOTALL
        )
    else:
        # Add new hosts section after users section
        hosts_lines = ["\n  # Host keys for automatic decryption"]
        for name, key in sorted(hosts_dict.items()):
            hosts_lines.append(f'  hosts = {{')
            hosts_lines.append(f'    {name} = "{key}";')
            hosts_lines.append(f'  }};')

        # Insert after users section
        users_end = content.find("};", content.find("users = {"))
        if users_end != -1:
            content = content[:users_end + 2] + "\n".join(hosts_lines) + content[users_end + 2:]
        else:
            print("Error: Could not find users section in secrets.nix")
            return False

    # Write back
    with open(secrets_nix_path, "w") as f:
        f.write(content)

    return True


def main():
    import argparse

    parser = argparse.ArgumentParser(
        description="Setup host keys for agenix multi-host deployment"
    )
    parser.add_argument(
        "--host",
        action="append",
        help="Host to setup (can be specified multiple times). Format: hostname or hostname=age_key",
    )
    parser.add_argument(
        "--local",
        action="store_true",
        help="Setup local host key",
    )
    parser.add_argument(
        "--all-known-hosts",
        action="store_true",
        help="Auto-discover and setup all hosts from cluster",
    )
    parser.add_argument(
        "--secrets-nix",
        default="/etc/nixos/secrets.nix",
        help="Path to secrets.nix",
    )

    args = parser.parse_args()

    hosts_to_setup = {}

    # Auto-discover hosts from cluster
    if args.all_known_hosts:
        # Get hosts from /etc/nixos/hosts directory
        hosts_dir = Path("/etc/nixos/hosts")
        if hosts_dir.exists():
            for host_path in hosts_dir.iterdir():
                if host_path.is_dir() and not host_path.name.startswith("."):
                    hostname = host_path.name
                    print(f"\nSetting up {hostname}...")
                    age_key = get_host_age_key(hostname)
                    if age_key:
                        hosts_to_setup[hostname] = age_key
                        print(f"✓ {hostname}: {age_key}")
                    else:
                        print(f"✗ Failed to get key for {hostname}")

    # Local host
    if args.local:
        print("\nSetting up local host...")
        age_key = get_host_age_key()
        if age_key:
            import socket
            hostname = socket.gethostname()
            hosts_to_setup[hostname] = age_key
            print(f"✓ {hostname}: {age_key}")

    # Manually specified hosts
    if args.host:
        for host_spec in args.host:
            if "=" in host_spec:
                # hostname=age_key format
                hostname, age_key = host_spec.split("=", 1)
                hosts_to_setup[hostname] = age_key
                print(f"✓ {hostname}: {age_key}")
            else:
                # Just hostname - fetch the key
                hostname = host_spec
                print(f"\nSetting up {hostname}...")
                age_key = get_host_age_key(hostname)
                if age_key:
                    hosts_to_setup[hostname] = age_key
                    print(f"✓ {hostname}: {age_key}")
                else:
                    print(f"✗ Failed to get key for {hostname}")

    if not hosts_to_setup:
        parser.print_help()
        print("\nError: No hosts specified. Use --local, --host, or --all-known-hosts")
        sys.exit(1)

    # Show current state
    print("\n" + "=" * 60)
    print("Current hosts in secrets.nix:")
    current = parse_secrets_nix(args.secrets_nix)
    for name, key in sorted(current["hosts"].items()):
        print(f"  {name}: {key[:20]}...{key[-8:]}")

    # Show what will be added/updated
    print("\n" + "=" * 60)
    print("Hosts to be added/updated:")
    for name, key in sorted(hosts_to_setup.items()):
        status = "UPDATE" if name in current["hosts"] else "ADD"
        print(f"  [{status}] {name}: {key[:20]}...{key[-8:]}")

    # Confirm
    print("\n" + "=" * 60)
    response = input("Update secrets.nix with these host keys? (y/N): ")
    if response.lower() != "y":
        print("Aborted.")
        sys.exit(0)

    # Update secrets.nix
    if update_secrets_nix_hosts(hosts_to_setup, args.secrets_nix):
        print(f"\n✓ Updated {args.secrets_nix}")

        # Next steps
        print("\n" + "=" * 60)
        print("Next steps:")
        print("1. Re-encrypt secrets with new host keys:")
        print("   cd /etc/nixos")
        print("   RULES=/etc/nixos/secrets.nix agenix -r -i ~/.age/key.txt")
        print("\n2. Update secret entries in secrets.nix to include host keys:")
        print('   "secret.age".publicKeys = [users.j_kro hosts.zephyr hosts.forge];')
        print("\n3. Add age.secrets.* to each host's configuration.nix")
        print("\n4. Rebuild each host:")
        print("   sudo nixos-rebuild switch --flake .#hostname")
    else:
        print("\n✗ Failed to update secrets.nix")
        sys.exit(1)


if __name__ == "__main__":
    main()
