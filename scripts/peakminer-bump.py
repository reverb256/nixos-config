#!/usr/bin/env python3
"""Bump pkgs/peakminer.nix to a new version + hash.

Usage: peakminer-bump.py <package-file> <version> <sri-hash>
Idempotent: rewrites version/url/hash in place, leaves everything else.
"""
import re
import sys


def main() -> int:
    if len(sys.argv) != 4:
        print("usage: peakminer-bump.py <package-file> <version> <sri-hash>", file=sys.stderr)
        return 2

    path, version, hash_sri = sys.argv[1], sys.argv[2], sys.argv[3]

    with open(path) as f:
        text = f.read()

    new_text = re.sub(
        r'version = "[0-9.]+";',
        f'version = "{version}";',
        text,
        count=1,
    )
    new_text = re.sub(
        r'v\d+\.\d+\.\d+/peakminer-\d+\.\d+\.\d+\.tar\.gz',
        f'v{version}/peakminer-{version}.tar.gz',
        new_text,
        count=1,
    )
    new_text = re.sub(
        r'hash = "sha256-[^"]+";',
        f'hash = "{hash_sri}";',
        new_text,
        count=1,
    )

    if new_text == text:
        print(f"no change (already {version}?)", file=sys.stderr)
        return 1

    with open(path, "w") as f:
        f.write(new_text)

    print(f"bumped {path} -> {version} ({hash_sri})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
