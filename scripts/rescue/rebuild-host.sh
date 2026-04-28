#!/usr/bin/env bash
# rebuild-host.sh - Rebuild a NixOS host from USB rescue
# Usage: rebuild-host.sh <hostname> [root_device]

set -e

HOSTNAME="$1"
ROOT_DEV="${2:-}"
NFS_MOUNT="/mnt/nixos-shared"
TARGET_ROOT="/mnt/target-root"

# Known hosts and their root devices
declare -A HOST_ROOTS=(
  ["nexus"]="/dev/nvme1n1p2"
  ["zephyr"]="/dev/nvme0n1p2"
  ["forge"]="/dev/nvme0n1p2"
  ["sentry"]="/dev/nvme0n1p2"
)

if [ -z "$HOSTNAME" ]; then
  echo "Usage: $0 <hostname> [root_device]"
  echo ""
  echo "Examples:"
  echo "  $0 nexus"
  echo "  $0 nexus /dev/nvme1n1p2"
  echo ""
  echo "Known hosts:"
  for host in "${!HOST_ROOTS[@]}"; do
    echo "  - $host (${HOST_ROOTS[$host]})"
  done
  exit 1
fi

# Auto-detect root device if not provided
if [ -z "$ROOT_DEV" ]; then
  if [ -n "${HOST_ROOTS[$HOSTNAME]}" ]; then
    ROOT_DEV="${HOST_ROOTS[$HOSTNAME]}"
    echo "Auto-detected root device: $ROOT_DEV"
  else
    echo "ERROR: Unknown host '$HOSTNAME' and no root device specified"
    exit 1
  fi
fi

# Verify NFS is mounted
if [ ! -d "$NFS_MOUNT" ] || ! mountpoint -q "$NFS_MOUNT"; then
  echo "ERROR: NFS not mounted at $NFS_MOUNT"
  echo "Run: sudo ./mount-cluster.sh"
  exit 1
fi

# Verify root device exists
if [ ! -e "$ROOT_DEV" ]; then
  echo "ERROR: Root device not found: $ROOT_DEV"
  echo "Available btrfs devices:"
  for dev in /dev/nvme*n* /dev/sd*; do
    if [ -e "$dev" ]; then
      echo "  $dev"
    fi
  done
  exit 1
fi

# Verify host config exists
if [ ! -d "$NFS_MOUNT/hosts/$HOSTNAME" ]; then
  echo "ERROR: Host configuration not found: $HOSTNAME"
  echo "Available hosts:"
  ls -1 "$NFS_MOUNT/hosts/" | sed 's/^/  - /'
  exit 1
fi

echo "=== Rebuilding $HOSTNAME ==="
echo "Root device: $ROOT_DEV"
echo "Config source: $NFS_MOUNT"
echo ""

# Mount target root
echo "==> Mounting target root filesystem"
mkdir -p "$TARGET_ROOT"
if ! mountpoint -q "$TARGET_ROOT"; then
  mount -o subvol=@ "$ROOT_DEV" "$TARGET_ROOT" || {
    echo "ERROR: Failed to mount $ROOT_DEV"
    echo "Try: sudo mount -o subvol=@ $ROOT_DEV $TARGET_ROOT"
    exit 1
  }
fi
echo "✓ Mounted at $TARGET_ROOT"

# Mount boot partition if it exists
BOOT_DEV="${ROOT_DEV%p*}1"
if [ -e "$BOOT_DEV" ]; then
  echo "==> Mounting boot partition ($BOOT_DEV)"
  mkdir -p "$TARGET_ROOT/boot"
  mount "$BOOT_DEV" "$TARGET_ROOT/boot" 2>/dev/null && echo "✓ Boot mounted" || echo "Note: Boot mount failed (may be OK)"
fi

# Verify mounts
echo ""
echo "==> Verifying mounts"
echo "NFS flake:"
ls -la "$NFS_MOUNT/flake.nix" || { echo "ERROR: flake.nix not found"; exit 1; }
echo "Target root:"
ls -la "$TARGET_ROOT/etc/" || { echo "ERROR: Target root looks empty"; exit 1; }
echo "✓ All mounts verified"

# Run rebuild
echo ""
echo "==> Starting rebuild (this will take several minutes)..."
echo ""

cd "$NFS_MOUNT"

# Use nixos-enter for clean chroot environment
NIXOS_CONFIG="$NFS_MOUNT" nixos-enter --root "$TARGET_ROOT" -- bash -c "
  set -e
  echo 'Inside chroot, running nixos-rebuild...'
  cd /mnt/nixos-shared
  nixos-rebuild switch --flake .#$HOSTNAME \
    --option cores 4 \
    --show-trace
"

echo ""
echo "=== Rebuild complete! ==="
echo ""
echo "Next steps:"
echo "  1. Unmount: sudo umount $TARGET_ROOT/boot $TARGET_ROOT"
echo "  2. Reboot target host to test"
echo "  3. Verify boot from NVMe (not USB)"
