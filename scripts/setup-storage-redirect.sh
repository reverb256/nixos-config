#!/usr/bin/env bash
# Pre-reboot storage migration script for cluster nodes
# Run BEFORE nixos-rebuild boot on each node
# Usage: ssh <host> 'bash -s' < setup-storage-redirect.sh
#
set -euo pipefail

HOST=$(hostname)

echo "=== Storage Redirect Setup: $HOST ==="

setup_nix_subvolume() {
  local device="$1"   # by-id path
  local mount_opts="$2"

  echo "  Device: $device"
  echo "  Mount opts: $mount_opts"

  # Extract the subvol name from options
  local subvol
  subvol=$(echo "$mount_opts" | grep -oP 'subvol=\K[^, ]+')

  # Check if subvolume already exists
  local tmp_mnt
  tmp_mnt=$(mktemp -d)
  mount -o subvol=/ "$device" "$tmp_mnt"

  if btrfs subvolume show "$tmp_mnt/$subvol" &>/dev/null; then
    echo "  [OK] Subvolume @$subvol already exists on $device"
  else
    echo "  [CREATE] Creating subvolume @$subvol on $device..."
    btrfs subvolume create "$tmp_mnt/$subvol"
    mkdir -p "$tmp_mnt/$subvol/store" "$tmp_mnt/$subvol/var"
  fi

  # Check if store has data
  if [ -d "$tmp_mnt/$subvol/store" ] && [ "$(ls -A "$tmp_mnt/$subvol/store" 2>/dev/null)" ]; then
    echo "  [OK] /nix/store already populated on $device"
  else
    echo "  [COPY] Copying /nix/store to $device... (this may take a while)"
    cp -a /nix/store/* "$tmp_mnt/$subvol/store/"

    echo "  [COPY] Copying /nix/var to $device..."
    cp -a /nix/var/* "$tmp_mnt/$subvol/var/"
    echo "  [OK] Copy complete"
  fi

  umount "$tmp_mnt"
  rmdir "$tmp_mnt"
}

setup_home_subvolume() {
  local device="$1"
  local mount_opts="$2"

  local subvol
  subvol=$(echo "$mount_opts" | grep -oP 'subvol=\K[^, ]+')

  local tmp_mnt
  tmp_mnt=$(mktemp -d)
  mount -o subvol=/ "$device" "$tmp_mnt"

  if btrfs subvolume show "$tmp_mnt/$subvol" &>/dev/null; then
    echo "  [OK] Subvolume @$subvol already exists on $device"
  else
    echo "  [CREATE] Creating subvolume @$subvol on $device..."
    btrfs subvolume create "$tmp_mnt/$subvol"
  fi

  # Only copy if the subvolume is empty
  if [ -d "$tmp_mnt/$subvol" ] && [ "$(ls -A "$tmp_mnt/$subvol" 2>/dev/null | grep -v 'lost+found')" ]; then
    echo "  [OK] /home already populated on $device"
  else
    echo "  [COPY] Copying /home to $device... (may take a while)"
    cp -a /home/* "$tmp_mnt/$subvol/"
    echo "  [OK] Copy complete"
  fi

  umount "$tmp_mnt"
  rmdir "$tmp_mnt"
}

# Per-node setup
case "$HOST" in
  sentry)
    echo ""
    echo "--- Setting up /nix on HDD (sda /storage) ---"
    setup_nix_subvolume "/dev/disk/by-id/ata-ST1000DM010-2EP102_ZN1AMQLC" "subvol=@nix"

    echo ""
    echo "--- Setting up /home on HDD (sda /storage) ---"
    setup_home_subvolume "/dev/disk/by-id/ata-ST1000DM010-2EP102_ZN1AMQLC" "subvol=@home"

    echo ""
    echo "--- Checking k3s data dir ---"
    if [ -d "/storage/k3s-storage" ]; then
      echo "  [OK] /storage/k3s-storage exists"
    else
      echo "  [CREATE] Creating /storage/k3s-storage..."
      mkdir -p /storage/k3s-storage
    fi
    ;;

  zephyr)
    echo ""
    echo "--- Setting up /nix on secondary NVMe (nvme1n1) ---"
    setup_nix_subvolume "/dev/disk/by-id/nvme-XPG_GAMMIX_S11_Pro_2J2520059477-part2" "subvol=@nix"
    ;;

  forge)
    echo ""
    echo "--- Setting up /nix on secondary HDD (sda) ---"
    setup_nix_subvolume "/dev/disk/by-id/ata-ADATA_SU635_2L40291DQ5CE-part2" "subvol=@nix"
    ;;

  nexus)
    echo "  [SKIP] Nexus usage at 58% — not critical, skipping"
    ;;

  *)
    echo "Unknown host: $HOST"
    exit 1
    ;;
esac

echo ""
echo "=== Setup complete for $HOST ==="
echo "Next steps:"
echo "  1. sudo nixos-rebuild boot"
echo "  2. sudo reboot"
echo "  3. After reboot, verify: df -h /nix"
echo "  4. sudo nixos-rebuild switch (to rebuild nix store on new location)"
