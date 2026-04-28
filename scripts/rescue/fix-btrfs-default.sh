#!/usr/bin/env bash
# fix-btrfs-default.sh - Reset btrfs default subvolume
# Usage: fix-btrfs-default.sh <device> [subvol_id]
#
# Examples:
#   fix-btrfs-default.sh /dev/nvme1n1p2           # Reset to 256 (@)
#   fix-btrfs-default.sh /dev/nvme1n1p2 256       # Reset to specific ID
#   fix-btrfs-default.sh /dev/nvme1n1p2 257       # Reset to @home

set -e

DEVICE="$1"
SUBVOL_ID="${2:-256}"  # Default to 256 (usually @)

if [ -z "$DEVICE" ]; then
  echo "Usage: $0 <device> [subvol_id]"
  echo ""
  echo "Reset the default subvolume for a btrfs filesystem."
  echo ""
  echo "Common subvolume IDs:"
  echo "  256 - @ (root)"
  echo "  257 - @home"
  echo "  258 - @nix"
  echo "  259 - @swap"
  echo ""
  echo "Examples:"
  echo "  $0 /dev/nvme1n1p2"
  echo "  $0 /dev/nvme1n1p2 256"
  exit 1
fi

# Verify device exists
if [ ! -e "$DEVICE" ]; then
  echo "ERROR: Device not found: $DEVICE"
  exit 1
fi

# Verify it's btrfs
if ! blkid "$DEVICE" | grep -q 'TYPE="btrfs"'; then
  echo "ERROR: $DEVICE is not a btrfs filesystem"
  echo "  Type: $(blkid -s TYPE -o value "$DEVICE")"
  exit 1
fi

echo "=== Btrfs Default Subvolume Fix ==="
echo "Device: $DEVICE"
echo "Target subvolume ID: $SUBVOL_ID"
echo ""

# Show current state
echo "==> Current default subvolume:"
btrfs subvolume get-default "$DEVICE"
echo ""

# List all subvolumes for reference
echo "==> Available subvolumes:"
btrfs subvolume list "$DEVICE" | head -20
if [ $(btrfs subvolume list "$DEVICE" | wc -l) -gt 20 ]; then
  echo "  ... (showing first 20 of $(btrfs subvolume list "$DEVICE" | wc -l) total)"
fi
echo ""

# Confirm
read -p "Set default subvolume to $SUBVOL_ID? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Aborted"
  exit 0
fi

# Set new default
echo ""
echo "==> Setting default subvolume to $SUBVOL_ID..."
sudo btrfs subvolume set-default "$SUBVOL_ID" "$DEVICE"

# Verify
echo ""
echo "==> New default subvolume:"
btrfs subvolume get-default "$DEVICE"

echo ""
echo "✓ Default subvolume updated"
echo ""
echo "Next steps:"
echo "  1. Unmount: sudo umount $DEVICE"
echo "  2. Reboot and test boot from this device"
