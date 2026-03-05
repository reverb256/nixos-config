#!/usr/bin/env python3
"""
List all secrets and show which hosts can access them.
Useful for auditing secret distribution across your infrastructure.
"""

import sys
import os
import re
from pathlib import Path
from collections import defaultdict
from typing import Dict, List, Tuple


def parse_secrets_nix(secrets_nix_path="/etc/nixos/secrets.nix"):
    """Parse secrets.nix and extract all secret entries with their recipients."""
    if not os.path.exists(secrets_nix_path):
        print(f"✗ secrets.nix not found: {secrets_nix_path}")
        return None

    with open(secrets_nix_path, "r") as f:
        content = f.read()

    secrets = {}

    # Find all secret entries
    for match in re.finditer(r'"([^"]+\.age)"\.publicKeys\s*=\s*\[([^\]]+)\];', content):
        secret_name = match.group(1)
        keys_content = match.group(2)

        # Parse the keys (users.xxx or hosts.xxx)
        keys = []
        for key_match in re.finditer(r'(users\.|hosts\.)(\w+)', keys_content):
            key_type, key_name = key_match.groups()
            keys.append((key_type, key_name))

        # Remove duplicates while preserving order
        seen = set()
        unique_keys = []
        for key in keys:
            if key not in seen:
                seen.add(key)
                unique_keys.append(key)

        secrets[secret_name] = unique_keys

    return secrets


def parse_host_configurations():
    """Parse all host configuration.nix files and extract age.secrets declarations."""
    hosts_dir = Path("/etc/nixos/hosts")
    host_secrets = defaultdict(dict)

    if not hosts_dir.exists():
        return host_secrets

    for host_dir in hosts_dir.iterdir():
        if not host_dir.is_dir():
            continue

        config_file = host_dir / "configuration.nix"
        if not config_file.exists():
            continue

        hostname = host_dir.name

        with open(config_file, "r") as f:
            content = f.read()

        # Find all age.secrets.* declarations
        # Match from secret name to the closing }; (handles nested ${} in file paths)
        for match in re.finditer(r'^\s*age\.secrets\.([\w-]+)\s*=\s*\{(.*?)^  \};', content, re.DOTALL | re.MULTILINE):
            # Skip commented lines (check if line starts with # before age.secrets)
            start_pos = match.start()
            # Get the line containing the match start
            line_start = content.rfind('\n', 0, start_pos) + 1
            line_before = content[line_start:start_pos].strip()
            if line_before.startswith('#'):
                continue  # Skip commented secrets

            secret_name = match.group(1)
            secret_config = match.group(2)

            # Extract file path
            file_match = re.search(r'file\s*=\s*"([^"]+)"', secret_config)
            if file_match:
                file_path = file_match.group(1)
                # Extract just the filename
                file_name = os.path.basename(file_path)

                # Extract owner and group
                owner_match = re.search(r'owner\s*=\s*"([^"]+)"', secret_config)
                group_match = re.search(r'group\s*=\s*"([^"]+)"', secret_config)
                mode_match = re.search(r'mode\s*=\s*"([^"]+)"', secret_config)

                host_secrets[hostname][secret_name] = {
                    "file": file_name,
                    "owner": owner_match.group(1) if owner_match else None,
                    "group": group_match.group(1) if group_match else None,
                    "mode": mode_match.group(1) if mode_match else None,
                }

    return host_secrets


def list_by_secret(secrets_data, host_secrets):
    """List secrets grouped by secret name."""
    print("\n" + "=" * 80)
    print("SECRETS GROUPED BY NAME")
    print("=" * 80)

    for secret_name in sorted(secrets_data.keys()):
        base_name = secret_name.replace("secrets/", "").replace(".age", "")

        print(f"\n{base_name}")
        print("-" * 80)

        # Show who can decrypt
        keys = secrets_data[secret_name]
        users = [name for type, name in keys if type == "users"]
        hosts_with_access = [name for type, name in keys if type == "hosts"]

        print(f"  Can be decrypted by:")
        if users:
            print(f"    Users: {', '.join(users)}")
        if hosts_with_access:
            print(f"    Hosts: {', '.join(hosts_with_access)}")

        # Show where it's deployed
        deployed_on = []
        for hostname, secrets_dict in host_secrets.items():
            for secret_info in secrets_dict.values():
                if secret_info["file"] == secret_name:
                    deployed_on.append(hostname)
                    break

        if deployed_on:
            print(f"  Deployed on: {', '.join(sorted(deployed_on))}")
        else:
            print(f"  ⚠ Not deployed on any host!")


def list_by_host(secrets_data, host_secrets):
    """List secrets grouped by host."""
    print("\n" + "=" * 80)
    print("SECRETS GROUPED BY HOST")
    print("=" * 80)

    for hostname in sorted(host_secrets.keys()):
        print(f"\n{hostname}")
        print("-" * 80)

        secrets_dict = host_secrets[hostname]

        if not secrets_dict:
            print("  No secrets configured")
            continue

        for secret_name, secret_info in sorted(secrets_dict.items()):
            file_name = secret_info["file"]
            print(f"  {secret_name}")
            print(f"    File: {file_name}")

            # Show who can decrypt
            if file_name in secrets_data:
                keys = secrets_data[file_name]
                users = [name for type, name in keys if type == "users"]
                hosts = [name for type, name in keys if type == "hosts"]

                if users:
                    print(f"    Users with access: {', '.join(users)}")
                if hosts:
                    print(f"    Hosts with access: {', '.join(hosts)}")

            # Show owner/group
            if secret_info["owner"]:
                print(f"    Owner: {secret_info['owner']}")
            if secret_info["group"]:
                print(f"    Group: {secret_info['group']}")
            if secret_info["mode"]:
                print(f"    Mode: {secret_info['mode']}")


def show_summary(secrets_data, host_secrets):
    """Show summary statistics."""
    print("\n" + "=" * 80)
    print("SUMMARY")
    print("=" * 80)

    total_secrets = len(secrets_data)
    unique_secrets = len(set(name.replace("secrets/", "").replace(".age", "") for name in secrets_data.keys()))
    total_hosts = len(host_secrets)

    print(f"\nTotal unique secrets: {unique_secrets}")
    print(f"Total entries in secrets.nix: {total_secrets}")
    print(f"Total hosts configured: {total_hosts}")

    # Count per-host
    print(f"\nSecrets per host:")
    for hostname in sorted(host_secrets.keys()):
        count = len(host_secrets[hostname])
        print(f"  {hostname}: {count}")

    # Count recipients
    print(f"\nRecipient summary:")
    all_users = set()
    all_hosts = set()
    for keys in secrets_data.values():
        for type, name in keys:
            if type == "users":
                all_users.add(name)
            elif type == "hosts":
                all_hosts.add(name)

    if all_users:
        print(f"  Users: {', '.join(sorted(all_users))}")
    if all_hosts:
        print(f"  Hosts: {', '.join(sorted(all_hosts))}")


def show_matrix(secrets_data, host_secrets):
    """Show a matrix of which secrets are on which hosts."""
    print("\n" + "=" * 80)
    print("SECRET DEPLOYMENT MATRIX")
    print("=" * 80)

    # Get list of unique secret names
    secret_names = sorted(set(
        name.replace("secrets/", "").replace(".age", "")
        for name in secrets_data.keys()
    ))
    hostnames = sorted(host_secrets.keys())

    if not secret_names or not hostnames:
        print("No data to display")
        return

    # Print header row
    print(f"{'Secret':<30}", end="")
    for hostname in hostnames:
        print(f"  {hostname[:10]:<10}", end="")
    print()
    print("-" * 80)

    # Print each secret
    for secret_name in secret_names:
        print(f"{secret_name:<30}", end="")

        for hostname in hostnames:
            # Check if this secret is on this host
            is_deployed = False
            for secret_info in host_secrets[hostname].values():
                if secret_name in secret_info["file"]:
                    is_deployed = True
                    break

            if is_deployed:
                print(f"  {'✓':<10}", end="")
            else:
                print(f"  {'-':<10}", end="")

        print()


def main():
    import argparse

    parser = argparse.ArgumentParser(
        description="List all secrets and show which hosts can access them"
    )
    parser.add_argument(
        "--by-host",
        action="store_true",
        help="Group secrets by host",
    )
    parser.add_argument(
        "--matrix",
        action="store_true",
        help="Show deployment matrix",
    )
    parser.add_argument(
        "--summary-only",
        action="store_true",
        help="Show only summary statistics",
    )
    parser.add_argument(
        "--secrets-nix",
        default="/etc/nixos/secrets.nix",
        help="Path to secrets.nix",
    )

    args = parser.parse_args()

    # Parse data
    secrets_data = parse_secrets_nix(args.secrets_nix)
    if secrets_data is None:
        sys.exit(1)

    host_secrets = parse_host_configurations()

    # Display
    if args.summary_only:
        show_summary(secrets_data, host_secrets)
    elif args.by_host:
        list_by_host(secrets_data, host_secrets)
        show_summary(secrets_data, host_secrets)
    elif args.matrix:
        show_matrix(secrets_data, host_secrets)
        show_summary(secrets_data, host_secrets)
    else:
        list_by_secret(secrets_data, host_secrets)
        show_summary(secrets_data, host_secrets)


if __name__ == "__main__":
    main()
