#!/usr/bin/env python3
"""Test agenix secret configuration."""

import subprocess
import os
import sys


def test_decrypt(secret_name):
    """Test decrypting a secret."""
    print(f"Testing decryption of: {secret_name}")

    result = subprocess.run(
        [
            "agenix",
            "-d",
            f"secrets/{secret_name}.age",
            "-i",
            "/home/j_kro/.age/key.txt",
        ],
        capture_output=True,
        text=True,
        env={**os.environ, "RULES": "/etc/nixos/secrets.nix"},
        cwd="/etc/nixos",
    )

    if result.returncode != 0:
        print(f"  ✗ Decrypt failed: {result.stderr}")
        return False

    print(f"  ✓ Decrypted successfully (length: {len(result.stdout)} bytes)")
    return True


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 test_secrets.py <secret-name>")
        sys.exit(1)

    secret_name = sys.argv[1]
    if not test_decrypt(secret_name):
        sys.exit(1)


if __name__ == "__main__":
    main()
