#!/usr/bin/env python3
"""Helper script to rekey all agenix secrets."""

import subprocess
import os
import sys


def rekey_all_secrets(owner_key_path=None):
    """Re-encrypt all secrets with the given key."""
    print("Rekeying all agenix secrets...")

    env = {**os.environ}
    env["RULES"] = "/etc/nixos/secrets.nix"

    if owner_key_path:
        env["AGE_RECIPIENTS"] = f"@{owner_key_path}"

    result = subprocess.run(["agenix", "-r"], env=env, cwd="/etc/nixos")

    if result.returncode != 0:
        print(f"Error: {result.stderr}")
        sys.exit(1)

    print("✓ Rekeying complete")


if __name__ == "__main__":
    key_path = sys.argv[1] if len(sys.argv) > 1 else "/home/j_kro/.age/key.txt"
    rekey_all_secrets(key_path)
