#!/usr/bin/env python3
import subprocess
import sys
import os


def add_secret(secret_name, secret_value, owner="j_kro", group=None):
    print(f"Creating encrypted secret: {secret_name}")

    result = subprocess.run(
        [
            "agenix",
            "-e",
            f"secrets/{secret_name}.age",
            "-i",
            "/home/j_kro/.age/key.txt",
        ],
        input=secret_value,
        text=True,
        cwd="/etc/nixos",
        env={**os.environ, "RULES": "/etc/nixos/secrets.nix"},
    )

    if result.returncode != 0:
        print(f"Error creating encrypted file: {result.stderr}")
        return False

    print(f"✓ Encrypted file created: secrets/{secret_name}.age")

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
    print(f"Adding to secrets.nix: {secret_name}")

    with open("/etc/nixos/secrets.nix", "r") as f:
        content = f.read()

    if f'"{secret_name}".publicKeys' in content:
        print("  Already exists")
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
    print(f"Adding to {host}/configuration.nix: {secret_name}")

    config_path = f"/etc/nixos/hosts/{host}/configuration.nix"
    if not os.path.exists(config_path):
        print(f"  ✗ Configuration file not found: {config_path}")
        return False

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

    print("  Warning: Could not find age.secrets section")
    return False


def main():
    import argparse

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
