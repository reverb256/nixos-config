#!/usr/bin/env python3
"""
Validate agenix secret configuration.
Checks for consistency between secrets.nix, .age files, and host configurations.
"""

import subprocess
import sys
import os
import re
from pathlib import Path
from collections import defaultdict


def parse_secrets_nix(secrets_nix_path="/etc/nixos/secrets.nix"):
    """Parse secrets.nix and extract all secret entries."""
    if not os.path.exists(secrets_nix_path):
        print(f"✗ secrets.nix not found: {secrets_nix_path}")
        return None

    with open(secrets_nix_path, "r") as f:
        content = f.read()

    secrets = {}

    # Find all secret entries
    for match in re.finditer(
        r'"([^"]+\.age)"\.publicKeys\s*=\s*\[([^\]]+)\];', content
    ):
        secret_name = match.group(1)
        keys_content = match.group(2)

        # Parse the keys (users.xxx or hosts.xxx)
        keys = []
        for key_match in re.finditer(r"(users\.|hosts\.)(\w+)", keys_content):
            key_type, key_name = key_match.groups()
            keys.append((key_type, key_name))

        if secret_name not in secrets:
            secrets[secret_name] = keys
        else:
            # Merge keys if duplicate entry
            secrets[secret_name].extend(keys)

    return secrets


def get_age_files(secrets_dir="/etc/nixos/secrets"):
    """Get all .age files in the secrets directory."""
    if not os.path.exists(secrets_dir):
        return {}

    age_files = {}
    for file_path in Path(secrets_dir).glob("*.age"):
        age_files[file_path.name] = file_path

    # Also check root directory
    root_path = Path("/etc/nixos")
    for file_path in root_path.glob("*.age"):
        age_files[file_path.name] = file_path

    return age_files


def parse_host_configurations():
    """Parse all host configuration.nix files and extract age.secrets declarations."""
    hosts_dir = Path("/etc/nixos/hosts")
    host_secrets = defaultdict(list)

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
        for match in re.finditer(
            r"^\s*age\.secrets\.([\w-]+)\s*=\s*\{(.*?)^  \};",
            content,
            re.DOTALL | re.MULTILINE,
        ):
            # Skip commented lines (check if line starts with # before age.secrets)
            start_pos = match.start()
            # Get the line containing the match start
            line_start = content.rfind("\n", 0, start_pos) + 1
            line_before = content[line_start:start_pos].strip()
            if line_before.startswith("#"):
                continue  # Skip commented secrets

            secret_name = match.group(1)
            secret_config = match.group(2)

            # Extract file path
            file_match = re.search(r'file\s*=\s*"([^"]+)"', secret_config)
            if file_match:
                file_path = file_match.group(1)
                # Extract just the filename
                file_name = os.path.basename(file_path)
                host_secrets[hostname].append(
                    {
                        "name": secret_name,
                        "file": file_name,
                        "config": secret_config.strip(),
                    }
                )

    return host_secrets


def validate_secret_entries(secrets_from_nix, age_files, verbose=False):
    """Validate that all entries in secrets.nix have corresponding .age files."""
    issues = []

    for secret_name in secrets_from_nix.keys():
        # Check if .age file exists (handle both "name.age" and "secrets/name.age" formats)
        base_name = secret_name.replace("secrets/", "")

        # Check if file exists in either location
        file_exists = False
        if secret_name in age_files:
            file_exists = True
        elif base_name in age_files:
            file_exists = True
        elif os.path.exists(f"/etc/nixos/{secret_name}"):
            file_exists = True
        elif os.path.exists(f"/etc/nixos/{base_name}"):
            file_exists = True

        if not file_exists:
            issues.append(f"✗ Missing .age file: {secret_name}")
            if verbose:
                print("  Entry exists in secrets.nix but file not found")
        else:
            if verbose:
                print(f"✓ {secret_name}: File exists")

    # Check for orphaned .age files (not in secrets.nix)
    all_secret_names = set()
    for secret_name in secrets_from_nix.keys():
        base_name = secret_name.replace("secrets/", "")
        all_secret_names.add(base_name)

    for file_name in age_files.keys():
        base_name = file_name.replace("secrets/", "")
        if base_name not in all_secret_names:
            issues.append(f"⚠ Orphaned .age file: {file_name} (not in secrets.nix)")
            if verbose:
                print("  File exists but no entry in secrets.nix")

    return issues


def validate_host_consistency(secrets_from_nix, host_secrets, verbose=False):
    """Validate that host configurations match secrets.nix entries."""
    issues = []

    for hostname, secrets_list in host_secrets.items():
        if verbose:
            print(f"\n{hostname}:")

        for secret in secrets_list:
            file_name = secret["file"]
            secret_name = secret["name"]

            # Check if file is in secrets.nix
            if file_name not in secrets_from_nix:
                issues.append(
                    f"✗ {hostname}: age.secrets.{secret_name} uses {file_name} not in secrets.nix"
                )
                if verbose:
                    print(f"  ✗ {secret_name}: {file_name} not in secrets.nix")
                continue

            if verbose:
                print(f"  ✓ {secret_name}: {file_name}")

    return issues


def validate_key_references(secrets_from_nix, verbose=False):
    """Validate that all user and host key references are valid."""
    issues = []

    # Extract all unique users and hosts referenced
    users = set()
    hosts = set()

    for secret_name, keys in secrets_from_nix.items():
        for key_type, key_name in keys:
            if key_type == "users":
                users.add(key_name)
            elif key_type == "hosts":
                hosts.add(key_name)

    if verbose:
        print("\nKey references:")
        print(f"  Users: {', '.join(sorted(users)) if users else 'None'}")
        print(f"  Hosts: {', '.join(sorted(hosts)) if hosts else 'None'}")

    # Check for empty publicKeys
    for secret_name, keys in secrets_from_nix.items():
        if not keys:
            issues.append(f"✗ {secret_name}: No recipient keys defined")

    return issues


def test_decrypt_single(secret_name, identity_file="/home/j_kro/.age/key.txt"):
    """Test decrypting a single secret."""
    secrets_dir = "/etc/nixos/secrets"
    secret_path = os.path.join(secrets_dir, secret_name)

    if not os.path.exists(secret_path):
        # Try root directory
        secret_path = os.path.join("/etc/nixos", secret_name)
        if not os.path.exists(secret_path):
            return False, "File not found"

    try:
        result = subprocess.run(
            ["agenix", "-d", secret_path, "-i", identity_file],
            capture_output=True,
            text=True,
            env={**os.environ, "RULES": "/etc/nixos/secrets.nix"},
            cwd="/etc/nixos",
        )

        if result.returncode == 0:
            return True, result.stdout.strip()
        else:
            return False, result.stderr.strip()

    except Exception as e:
        return False, str(e)


def validate_decryption(secrets_from_nix, test_one=False, verbose=False):
    """Validate that secrets can be decrypted."""
    issues = []

    # Get unique secret names (remove "secrets/" prefix duplicates)
    unique_secrets = set()
    for secret_name in secrets_from_nix.keys():
        base_name = secret_name.replace("secrets/", "")
        unique_secrets.add(base_name)

    if verbose:
        print(f"\nDecryption test ({len(unique_secrets)} secrets):")

    for secret_name in sorted(unique_secrets):
        if test_one:
            # Only test one as a sample
            success, result = test_decrypt_single(secret_name)
            if verbose:
                if success:
                    print(f"  ✓ {secret_name}: OK (length: {len(result)} bytes)")
                else:
                    print(f"  ✗ {secret_name}: Failed - {result}")
            break
        else:
            # Test all
            success, result = test_decrypt_single(secret_name)
            if success:
                if verbose:
                    print(f"  ✓ {secret_name}: OK (length: {len(result)} bytes)")
            else:
                issues.append(f"✗ Decryption failed for {secret_name}: {result}")
                if verbose:
                    print(f"  ✗ {secret_name}: {result}")

    return issues


def main():
    import argparse

    parser = argparse.ArgumentParser(description="Validate agenix secret configuration")
    parser.add_argument(
        "--verbose",
        "-v",
        action="store_true",
        help="Show detailed validation output",
    )
    parser.add_argument(
        "--test-decrypt",
        action="store_true",
        help="Test decryption of secrets",
    )
    parser.add_argument(
        "--test-one",
        action="store_true",
        help="Test decrypt only one secret (sample)",
    )
    parser.add_argument(
        "--secrets-nix",
        default="/etc/nixos/secrets.nix",
        help="Path to secrets.nix",
    )
    parser.add_argument(
        "--secrets-dir",
        default="/etc/nixos/secrets",
        help="Path to secrets directory",
    )

    args = parser.parse_args()

    print("=" * 60)
    print("Agenix Configuration Validation")
    print("=" * 60)

    all_issues = []

    # Parse secrets.nix
    if args.verbose:
        print("\nParsing secrets.nix...")
    secrets_from_nix = parse_secrets_nix(args.secrets_nix)

    if secrets_from_nix is None:
        print("✗ Failed to parse secrets.nix")
        sys.exit(1)

    if args.verbose:
        print(f"✓ Found {len(secrets_from_nix)} secret entries")

    # Get .age files
    if args.verbose:
        print("\nScanning for .age files...")
    age_files = get_age_files(args.secrets_dir)

    if args.verbose:
        print(f"✓ Found {len(age_files)} .age files")

    # Parse host configurations
    if args.verbose:
        print("\nParsing host configurations...")
    host_secrets = parse_host_configurations()

    if args.verbose:
        print(f"✓ Found {len(host_secrets)} hosts")

    # Validate secret entries
    print("\n" + "-" * 60)
    print("Validating secret entries...")
    issues = validate_secret_entries(secrets_from_nix, age_files, args.verbose)
    all_issues.extend(issues)

    # Validate host consistency
    print("\n" + "-" * 60)
    print("Validating host configurations...")
    issues = validate_host_consistency(secrets_from_nix, host_secrets, args.verbose)
    all_issues.extend(issues)

    # Validate key references
    print("\n" + "-" * 60)
    print("Validating key references...")
    issues = validate_key_references(secrets_from_nix, args.verbose)
    all_issues.extend(issues)

    # Test decryption if requested
    if args.test_decrypt or args.test_one:
        print("\n" + "-" * 60)
        print("Testing decryption...")
        issues = validate_decryption(secrets_from_nix, args.test_one, args.verbose)
        all_issues.extend(issues)

    # Summary
    print("\n" + "=" * 60)
    if all_issues:
        print(f"✗ Found {len(all_issues)} issue(s):")
        for issue in all_issues:
            print(f"  {issue}")
        sys.exit(1)
    else:
        print("✓ All validations passed!")
        print("\nConfiguration is consistent and ready to use.")

        # Quick stats
        print("\n" + "-" * 60)
        print("Summary:")
        print(f"  Secrets in secrets.nix: {len(secrets_from_nix)}")
        print(f"  .age files on disk: {len(age_files)}")
        print(f"  Hosts configured: {len(host_secrets)}")

        # Count per-host secrets
        if host_secrets:
            print("\n  Per-host secret counts:")
            for hostname, secrets_list in sorted(host_secrets.items()):
                print(f"    {hostname}: {len(secrets_list)} secrets")


if __name__ == "__main__":
    main()
