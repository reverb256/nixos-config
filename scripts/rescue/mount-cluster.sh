#!/usr/bin/env bash
# mount-cluster.sh - Mount NFS share from Zephyr and detect local volumes
# Usage: mount-cluster.sh

set -e

ZEPHYR_IP="10.1.1.110"
NFS_MOUNT="/mnt/nixos-shared"
LOCAL_MOUNT="/mnt/local-btrfs"

echo "=== Mounting cluster resources ==="
echo ""

# Step 1: Mount NFS from Zephyr
echo "==> Mounting NFS from Zephyr ($ZEPHYR_IP:/etc/nixos)"
mkdir -p "$NFS_MOUNT"

if timeout 10 mount -t nfs -o ro,soft,timeo=5 "$ZEPHYR_IP:/etc/nixos" "$NFS_MOUNT" 2>/dev/null; then
  echo "✓ NFS mounted at $NFS_MOUNT"

  # Verify flake.nix exists
  if [ -f "$NFS_MOUNT/flake.nix" ]; then
    echo "✓ Found flake.nix"
  else
    echo "✗ WARNING: flake.nix not found on NFS share"
  fi

  # List available host configs
  echo ""
  echo "Available host configurations:"
  ls -1 "$NFS_MOUNT/hosts/" 2>/dev/null | sed 's/^/  - /'
else
  echo "✗ Failed to mount NFS from Zephyr"
  echo "  Make sure:"
  echo "    - Network is up (ping $ZEPHYR_IP)"
  echo "    - Zephyr is running and NFS server is enabled"
  echo "    - No firewall is blocking NFS (ports 111, 2049, 20048)"
  exit 1
fi

# Step 2: Detect btrfs volumes
echo ""
echo "==> Detecting local btrfs volumes"
BTRFS_DEVS=()

for dev in /dev/nvme*n* /dev/sd*; do
  if [ -e "$dev" ] && blkid "$dev" 2>/dev/null | grep -q 'TYPE="btrfs"'; then
    echo "Found btrfs device: $dev"
    BTRFS_DEVS+=("$dev")

    # Show filesystem info
    echo "  Label: $(btrfs filesystem show "$dev" | grep 'Label\|devid' | head -1)"
    echo "  UUID: $(blkid -s UUID -o value "$dev")"

    # List subvolumes
    echo "  Subvolumes:"
    btrfs subvolume list "$dev" 2>/dev/null | head -5 | sed 's/^/    /'
  fi
done

if [ ${#BTRFS_DEVS[@]} -eq 0 ]; then
  echo "✗ No btrfs devices found"
else
  echo ""
  echo "Found ${#BTRFS_DEVS[@]} btrfs device(s)"
  export RESCUE_BTRFS_DEVICES="${BTRFS_DEVS[*]}"
fi

echo ""
echo "=== Mount complete ==="
echo "NFS config available at: $NFS_MOUNT"
