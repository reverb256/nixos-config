#!/usr/bin/env bash
set -euo pipefail

SOURCE="/run/nixos-shared/flake.lock"
TARGET="/etc/nixos/flake.lock"
STATE_FILE="/var/lib/flake-lock-sync/last-sync"

# Only proceed if source exists (NFS might be unavailable)
if [ ! -f "$SOURCE" ]; then
  echo "flake-lock-sync: Source not available ($SOURCE)"
  exit 0
fi

# Calculate checksums
SOURCE_SUM=$(md5sum "$SOURCE" | cut -d' ' -f1)
TARGET_SUM=$(md5sum "$TARGET" 2>/dev/null | cut -d' ' -f1 || echo "none")

# Skip if identical
if [ "$SOURCE_SUM" = "$TARGET_SUM" ]; then
  exit 0
fi

# Create backup before overwriting
if [ -f "$TARGET" ]; then
  cp "$TARGET" "${TARGET}.backup"
fi

# Sync the file
cp "$SOURCE" "$TARGET"

# Record state
mkdir -p "$(dirname "$STATE_FILE")"
echo "$SOURCE_SUM" > "$STATE_FILE"

logger -t flake-lock-sync "Synced flake.lock from NFS (checksum: $SOURCE_SUM)"
echo "flake-lock-sync: Synced flake.lock from NFS"
