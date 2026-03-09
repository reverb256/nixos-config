#!/usr/bin/env python3
"""
Add secrets to multiple hosts with proper key management.
Supports both shared secrets (same value across hosts) and per-host secrets.
"""

import subprocess
import sys
import os
import re

sys.path.insert(0, os.path.dirname(__file__))
from common import (
    ensure_dependencies,
    get_age_identity_path,
    get_secrets_nix_path,
    print_error,
    print_success,
    print_info,
)


def parse_secrets_nix(secrets_nix_path=None):
    """Parse secrets.nix to extract users and hosts."""
    if secrets_nix_path is None:
        secrets_nix_path = str(get_secrets_nix_path())

    if not os.path.exists(secrets_nix_path):
        return {"users": {}, "hosts": {}}

    with open(secrets_nix_path, "r") as f:
        content = f.read()

    result = {"users": {}, "hosts": {}}

    users_match = re.search(r"users\s*=\s*{([^}]+)};", content, re.DOTALL)
    if users_match:
        for match in re.finditer(r'(\w+)\s*=\s*"([^"]+)"', users_match.group(1)):
            result["users"][match.group(1)] = match.group(2)

    hosts_match = re.search(r"hosts\s*=\s*{([^}]+)};", content, re.DOTALL)
    if hosts_match:
        for match in re.finditer(r'(\w+)\s*=\s*"([^"]+)"', hosts_match.group(1)):
            result["hosts"][match.group(1)] = match.group(2)

    return result


def get_recipients_for_hosts(hosts_list, secrets_nix_path=None):
    """
    Get age public keys for specified hosts.

    Args:
        hosts_list: List of hostnames
        secrets_nix_path: Path to secrets.nix

    Returns:
        dict of hostname -> age_key
    """
    keys_data = parse_secrets_nix(secrets_nix_path)
    recipients = {}

    for hostname in hosts_list:
        if hostname in keys_data["hosts"]:
            recipients[hostname] = keys_data["hosts"][hostname]
        else:
            print(f"Warning: Host '{hostname}' not found in secrets.nix")
            print("  Run: python3 scripts/setup_host_keys.py --host {hostname}")
            return None

    return recipients


def create_encrypted_file(secret_name, secret_value, recipients, owner="j_kro"):
    """
    Create an encrypted .age file for multiple recipients.

    Args:
        secret_name: Name of the secret (without .age extension)
        secret_value: The secret value to encrypt
        recipients: dict of hostname -> age_key
        owner: Owner username (defaults to j_kro)

    Returns:
        True if successful, False otherwise.
    """
    print(f"Creating encrypted file: {secret_name}")

    secrets_nix_path = str(get_secrets_nix_path())
    keys_data = parse_secrets_nix(secrets_nix_path)

    if owner not in keys_data["users"]:
        print_error(f"Owner '{owner}' not found in secrets.nix")
        return False

    recipient_keys = [keys_data["users"][owner]]
    recipient_keys.extend(recipients.values())
    age_recipients = ":".join(recipient_keys)

    env = {**os.environ, "RULES": secrets_nix_path, "AGE_RECIPIENTS": age_recipients}

    identity_path = get_age_identity_path(owner)

    result = subprocess.run(
        [
            "agenix",
            "-e",
            f"secrets/{secret_name}.age",
            "-i",
            str(identity_path),
        ],
        input=secret_value,
        text=True,
        cwd="/etc/nixos",
        env=env,
    )

    if result.returncode != 0:
        print(f"Error creating encrypted file: {result.stderr}")
        return False

    # Move to secrets/ directory if created in wrong location
    if os.path.exists(f"/etc/nixos/{secret_name}.age"):
        subprocess.run(
            [
                "mv",
                f"/etc/nixos/{secret_name}.age",
                f"/etc/nixos/secrets/{secret_name}.age",
            ]
        )

    print(f"✓ Created: secrets/{secret_name}.age")
    print(f"  Recipients: {owner}, {', '.join(recipients.keys())}")
    return True


def update_secrets_nix(secret_name, recipients, owner="j_kro", secrets_nix_path=None):
    """
    Add secret to secrets.nix with proper recipient keys.

    Args:
        secret_name: Name of the secret
        recipients: dict of hostname -> age_key
        owner: Owner username
        secrets_nix_path: Path to secrets.nix

    Returns:
        True if successful, False otherwise.
    """
    print(f"Updating secrets.nix: {secret_name}")

    if secrets_nix_path is None:
        secrets_nix_path = str(get_secrets_nix_path())

    with open(secrets_nix_path, "r") as f:
        content = f.read()

    # Check if already exists
    if f'"{secret_name}".publicKeys' in content:
        print("  Already exists in secrets.nix")
        return True

    # Build the publicKeys list
    _keys_data = parse_secrets_nix(secrets_nix_path)  # noqa: F841
    public_keys_list = [f"users.{owner}"]
    public_keys_list.extend([f"hosts.{host}" for host in recipients.keys()])
    public_keys = " ".join(public_keys_list)

    # Add both entries (for path compatibility)
    new_entry = f'  "{secret_name}".publicKeys = [{public_keys}];\n'
    new_entry_full = f'  "secrets/{secret_name}".publicKeys = [{public_keys}];\n'

    # Insert before the closing brace
    content = content.rstrip()
    content = content.rstrip("}\n") + "\n" + new_entry + new_entry_full + "}\n"

    with open(secrets_nix_path, "w") as f:
        f.write(content)

    print("✓ Added to secrets.nix")
    return True


def update_host_configuration(
    secret_name, hosts_list, owner="j_kro", group=None, mode="440"
):
    """
    Add age.secrets.* declaration to each host's configuration.nix.

    Args:
        secret_name: Name of the secret
        hosts_list: List of hostnames to update
        owner: Owner username
        group: Optional group name
        mode: File permissions (default: 440)

    Returns:
        True if all successful, False otherwise.
    """
    print(f"Updating host configurations: {secret_name}")

    success = True
    for hostname in hosts_list:
        config_path = f"/etc/nixos/hosts/{hostname}/configuration.nix"

        if not os.path.exists(config_path):
            print(f"  ✗ {hostname}: Configuration file not found: {config_path}")
            success = False
            continue

        with open(config_path, "r") as f:
            content = f.read()

        # Check if already exists
        if f"age.secrets.{secret_name}" in content:
            print(f"  ✓ {hostname}: Already exists")
            continue

        # Find a good insertion point (after another age.secrets entry)
        pattern = r"age\.secrets\.\w+\s*=\s*\{"
        matches = list(re.finditer(pattern, content))

        if matches:
            # Insert after the last age.secrets entry
            last_match = matches[-1]
            insert_pos = last_match.end()

            # Find the end of that block
            brace_count = 1
            end_pos = insert_pos
            while end_pos < len(content) and brace_count > 0:
                if content[end_pos] == "{":
                    brace_count += 1
                elif content[end_pos] == "}":
                    brace_count -= 1
                end_pos += 1

            # Insert the new block
            group_line = f'    group = "{group}";' if group else ""
            new_block = f"""
  age.secrets.{secret_name} = {{
    file = "${{inputs.self}}/secrets/{secret_name}.age";
    mode = "{mode}";
    owner = "{owner}";
{group_line}
  }};
"""
            content = content[:end_pos] + new_block + content[end_pos:]

            with open(config_path, "w") as f:
                f.write(content)

            print(f"  ✓ {hostname}: Added age.secrets.{secret_name}")
        else:
            print(f"  ✗ {hostname}: Could not find age.secrets section")
            print(f"    Manually add to {config_path}:")
            print(
                f"""    age.secrets.{secret_name} = {{
      file = "${{inputs.self}}/secrets/{secret_name}.age";
      mode = "{mode}";
      owner = "{owner}";
    }};"""
            )
            success = False

    return success


def main():
    import argparse

    if not ensure_dependencies(auto_install=True):
        sys.exit(1)

    parser = argparse.ArgumentParser(
        description="Add secrets to multiple hosts with proper key management"
    )
    parser.add_argument("name", help="Secret name (without .age extension)")
    parser.add_argument("value", help="Secret value to encrypt")
    parser.add_argument(
        "--hosts",
        required=True,
        help="Comma-separated list of hostnames (e.g., zephyr,forge,nexus)",
    )
    parser.add_argument(
        "--owner",
        default="j_kro",
        help="Owner username (default: j_kro)",
    )
    parser.add_argument(
        "--group",
        help="Group for file permissions (optional)",
    )
    parser.add_argument(
        "--mode",
        default="440",
        help="File permissions mode (default: 440)",
    )
    parser.add_argument(
        "--per-host",
        action="store_true",
        help="Create unique secret per host (value will be used as template)",
    )
    parser.add_argument(
        "--no-rebuild",
        action="store_true",
        help="Skip rebuild step",
    )

    args = parser.parse_args()

    hosts_list = [h.strip() for h in args.hosts.split(",")]

    # Validate hosts exist in secrets.nix
    recipients = get_recipients_for_hosts(hosts_list)
    if recipients is None:
        print("\nError: Some hosts are not configured in secrets.nix")
        print("Run: python3 scripts/setup_host_keys.py --help")
        sys.exit(1)

    if args.per_host:
        # Create unique secret per host
        print(f"\nCreating per-host secrets for: {', '.join(hosts_list)}")

        for hostname in hosts_list:
            host_recipients = {hostname: recipients[hostname]}
            secret_name = f"{args.name}-{hostname}"

            # Interpolate hostname in value
            secret_value = args.value.replace("{hostname}", hostname)

            if not create_encrypted_file(
                secret_name, secret_value, host_recipients, args.owner
            ):
                sys.exit(1)

            if not update_secrets_nix(secret_name, host_recipients, args.owner):
                sys.exit(1)

            if not update_host_configuration(
                secret_name, [hostname], args.owner, args.group, args.mode
            ):
                sys.exit(1)

        print(f"\n✓ Created {len(hosts_list)} per-host secrets")
    else:
        # Single shared secret across all hosts
        print(f"\nCreating shared secret for: {', '.join(hosts_list)}")

        if not create_encrypted_file(args.name, args.value, recipients, args.owner):
            sys.exit(1)

        if not update_secrets_nix(args.name, recipients, args.owner):
            sys.exit(1)

        if not update_host_configuration(
            args.name, hosts_list, args.owner, args.group, args.mode
        ):
            sys.exit(1)

        print("\n✓ Created shared secret")

    # Summary
    print("\n" + "=" * 60)
    print("Summary of changes:")
    print(f"  ✓ Created: secrets/{args.name}.age")
    print("  ✓ Updated: secrets.nix")
    print(
        f"  ✓ Updated: {', '.join([f'hosts/{h}/configuration.nix' for h in hosts_list])}"
    )

    if not args.no_rebuild:
        print("\n" + "=" * 60)
        print("Next steps:")
        print("1. Review the changes:")
        print("   git diff secrets.nix")
        for host in hosts_list:
            print(f"   git diff hosts/{host}/configuration.nix")
        print("\n2. Rebuild each host:")
        for host in hosts_list:
            print(f"   sudo nixos-rebuild switch --flake .#{host}")
    else:
        print("\n" + "=" * 60)
        print("Secret created. Remember to:")
        print("  1. Review changes with git diff")
        print("  2. Rebuild affected hosts")


if __name__ == "__main__":
    main()
