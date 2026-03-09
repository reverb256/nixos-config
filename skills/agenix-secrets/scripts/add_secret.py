#!/usr/bin/env python3
import subprocess
import sys
import os

sys.path.insert(0, os.path.dirname(__file__))
from common import (
    ensure_dependencies,
    get_age_identity_path,
    get_secrets_nix_path,
    get_nixos_dir,
    print_error,
    print_success,
    print_info,
    backup_file,
)


def add_secret(secret_name, secret_value, owner="j_kro", group=None):
    print(f"Creating encrypted secret: {secret_name}")

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
        env={**os.environ, "RULES": str(get_secrets_nix_path())},
    )

    if result.returncode != 0:
        print_error(
            f"Failed to create encrypted file",
            "Ensure agenix is installed: ./skills/agenix-secrets/bootstrap.sh",
        )
        return False

    print_success(f"Encrypted file created: secrets/{secret_name}.age")

    if os.path.exists(f"/etc/nixos/{secret_name}.age"):
        subprocess.run(
            [
                "mv",
                f"/etc/nixos/{secret_name}.age",
                f"/etc/nixos/secrets/{secret_name}.age",
            ]
        )

    return True


def add_to_secrets_nix(secret_name, owner="j_kro"):
    print_info(f"Adding to secrets.nix: {secret_name}")

    secrets_nix_path = get_secrets_nix_path()

    backup_file(secrets_nix_path)

    with open(secrets_nix_path, "r") as f:
        content = f.read()

    if f'"{secret_name}".publicKeys' in content:
        print_info("  Already exists")
        return True

    new_entry = f'  "{secret_name}".publicKeys = [users.{owner}];\n'
    new_entry_full = f'  "secrets/{secret_name}".publicKeys = [users.{owner}];\n'

    content = content.rstrip()
    content = content.rstrip("}\n") + "\n" + new_entry + new_entry_full + "}\n"

    with open("/etc/nixos/secrets.nix", "w") as f:
        f.write(content)

    print("✓ Added to secrets.nix")
    return True


def add_to_config_nix(secret_name, owner="j_kro", group=None, host="zephyr"):
    """Add age.secrets.* declaration to a host's configuration.nix."""
    print_info(f"Adding to {host}/configuration.nix: {secret_name}")

    nixos_dir = get_nixos_dir()
    config_path = nixos_dir / "hosts" / host / "configuration.nix"
    if not config_path.exists():
        print_error(
            f"Configuration file not found: {config_path}",
            "Ensure host '{host}' exists in hosts/ directory",
        )
        return False

    backup_file(config_path)

    with open(config_path, "r") as f:
        content = f.read()

    if f"age.secrets.{secret_name}" in content:
        print("  Already exists")
        return True

    # Find a good insertion point (after another age.secrets entry)
    import re

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
    mode = "440";
    owner = "{owner}";
{group_line}
  }};
"""
        content = content[:end_pos] + new_block + content[end_pos:]

        with open(config_path, "w") as f:
            f.write(content)

        print(f"✓ Added to {host}/configuration.nix")
        return True

        print_warning("Could not find age.secrets section")
        print_info(
            "  → Add 'age.secrets = {};' to hosts/{host}/configuration.nix first"
        )
        return False


def main():
    import argparse

    if not ensure_dependencies(auto_install=True):
        sys.exit(1)

    parser = argparse.ArgumentParser(
        description="Add a new secret to your NixOS configuration"
    )
    parser.add_argument("name", help="Secret name (without .age extension)")
    parser.add_argument("value", help="Secret value to encrypt")
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
        "--host",
        default="zephyr",
        help="Host to add secret to (default: zephyr)",
    )

    args = parser.parse_args()

    secret_name = args.name
    secret_value = args.value
    owner = args.owner
    group = args.group
    host = args.host

    if not add_secret(secret_name, secret_value, owner):
        sys.exit(1)

    if not add_to_secrets_nix(secret_name, owner):
        sys.exit(1)

    if not add_to_config_nix(secret_name, owner, group, host):
        sys.exit(1)

    print("\n✓ All steps completed!")
    print("\nNext steps:")
    print(
        f"1. Review the changes made to secrets.nix and hosts/{host}/configuration.nix"
    )
    print(f"2. Run: sudo nixos-rebuild build --flake .#{host}")
    print("3. Secret will be available at /run/agenix/" + secret_name)


if __name__ == "__main__":
    main()
