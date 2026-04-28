#!/usr/bin/env bash
# boot-diagnostics.sh - Boot troubleshooting diagnostics
# Usage: boot-diagnostics.sh [root_mount]

ROOT_MOUNT="${1:-/mnt/target-root}"

echo "=== Boot Diagnostics ==="
echo ""

echo "==> Boot mode"
if [ -d /sys/firmware/efi ]; then
  echo "UEFI mode detected"
  if command -v efibootmgr &>/dev/null; then
    echo "EFI boot manager:"
    efibootmgr -v
  fi
else
  echo "Legacy BIOS mode"
fi
echo ""

echo "==> Kernel command line"
cat /proc/cmdline
echo ""

echo "==> Initramfs messages"
dmesg | grep -E "btrfs|subvol|root|mount" | tail -20
echo ""

echo "==> Btrfs subvolumes"
for mount_point in $(mount | grep btrfs | awk '{print $3}'); do
  echo "Subvolumes under $mount_point:"
  btrfs subvolume list "$mount_point" 2>/dev/null | sed 's/^/  /' || echo "  (cannot list)"
done
echo ""

echo "==> Default subvolumes"
for dev in $(lsblk -no NAME -l | grep -E 'nvme|sd'); do
  dev_path="/dev/$dev"
  if blkid "$dev_path" 2>/dev/null | grep -q 'TYPE="btrfs"'; then
    echo "$dev_path:"
    btrfs subvolume get-default "$dev_path" 2>/dev/null || echo "  (cannot get default)"
  fi
done
echo ""

# Check mounted root if provided
if [ -n "$ROOT_MOUNT" ] && [ -d "$ROOT_MOUNT" ]; then
  echo "==> Checking root filesystem at $ROOT_MOUNT"

  # Check fstab
  if [ -f "$ROOT_MOUNT/etc/fstab" ]; then
    echo "Contents of /etc/fstab:"
    cat "$ROOT_MOUNT/etc/fstab"
  else
    echo "WARNING: No /etc/fstab found"
  fi
  echo ""

  # Check NixOS system link
  if [ -L "$ROOT_MOUNT/run/current-system" ]; then
    echo "✓ Current system link exists"
    echo "  Points to: $(readlink $ROOT_MOUNT/run/current-system)"
  else
    echo "✗ Current system link missing or broken"
  fi
  echo ""

  # Check bootloader
  if [ -d "$ROOT_MOUNT/boot" ]; then
    echo "Boot contents:"
    ls -la "$ROOT_MOUNT/boot" | head -20
  fi
fi

echo ""
echo "==> Recent boot messages"
dmesg | tail -30
