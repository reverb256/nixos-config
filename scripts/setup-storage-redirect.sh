#!/usr/bin/env bash
# Pre-reboot storage migration script for cluster nodes
# Run BEFORE nixos-rebuild boot on each node
# Usage: ssh <host> 'sudo bash -s' < setup-storage-redirect.sh
#
set -euo pipefail

HOST=$(hostname)

echo "=========================================="
echo " Storage Redirect Setup: $HOST"
echo "=========================================="
echo ""

setup_nix_subvolume() {
  local device="$1"
  echo "  Device: $device"

  local tmp_mnt
  tmp_mnt=$(mktemp -d)
  mount -o subvol=/ "$device" "$tmp_mnt"

  if btrfs subvolume show "$tmp_mnt/@nix" &>/dev/null; then
    echo "  [OK] @nix already exists"
  else
    btrfs subvolume create "$tmp_mnt/@nix"
    mkdir -p "$tmp_mnt/@nix/store" "$tmp_mnt/@nix/var"
    echo "  [CREATE] @nix created"
  fi

  if [ -d "$tmp_mnt/@nix/store" ] && [ "$(ls -A "$tmp_mnt/@nix/store" 2>/dev/null)" ]; then
    echo "  [OK] /nix/store already populated"
  else
    echo "  [COPY] /nix/store... (this will take a while)"
    cp -a /nix/store/* "$tmp_mnt/@nix/store/"
    cp -a /nix/var/* "$tmp_mnt/@nix/var/"
    echo "  [OK] /nix copied"
  fi

  umount "$tmp_mnt"
  rmdir "$tmp_mnt"
  echo "  [DONE] @nix ready"
  echo ""
}

setup_subvolume() {
  local name="$1"     # e.g. @home, @var
  local device="$2"
  local src="$3"      # source path to copy from

  echo "  Setting up $name from $src"
  local tmp_mnt
  tmp_mnt=$(mktemp -d)
  mount -o subvol=/ "$device" "$tmp_mnt"

  if btrfs subvolume show "$tmp_mnt/$name" &>/dev/null; then
    echo "  [OK] $name already exists"
  else
    btrfs subvolume create "$tmp_mnt/$name"
    echo "  [CREATE] $name created"
  fi

  # Check if already populated (ignore lost+found)
  if [ -d "$tmp_mnt/$name" ] && [ "$(ls -A "$tmp_mnt/$name" 2>/dev/null | grep -v 'lost+found')" ]; then
    echo "  [OK] $name already populated"
  elif [ -d "$src" ] && [ "$(ls -A "$src" 2>/dev/null)" ]; then
    echo "  [COPY] $src -> $name... (may take a while)"
    cp -a "$src"/* "$tmp_mnt/$name/"
    echo "  [OK] $name copied"
  else
    echo "  [INFO] $src is empty, leaving $name empty"
  fi

  umount "$tmp_mnt"
  rmdir "$tmp_mnt"
  echo "  [DONE] $name ready"
  echo ""
}

# ─────────────────────────────────────────────────
# Per-node setup
# ─────────────────────────────────────────────────
case "$HOST" in
  sentry)
    HDD="/dev/disk/by-id/ata-ST1000DM010-2EP102_ZN1AMQLC"

    echo "[1/4] @nix — nix store (137G)"
    setup_nix_subvolume "$HDD"

    echo "[2/4] @home — user home (5.6G)"
    setup_subvolume "@home" "$HDD" "/home"

    echo "[3/4] @var — /var (1.3G: k3s, logs, etc.)"
    setup_subvolume "@var" "$HDD" "/var"

    echo "[4/4] Verify"
    echo "  /storage/k3s-storage exists: $(test -d /storage/k3s-storage && echo YES || echo NO)"
    echo "  Note: @var covers k3s data now (/var/lib/rancher/k3s)"
    ;;

  zephyr)
    NVME="/dev/disk/by-id/nvme-XPG_GAMMIX_S11_Pro_2J2520059477-part2"

    echo "[1/3] @nix — nix store (186G)"
    setup_nix_subvolume "$NVME"

    echo "[2/3] @var — /var (22G: flatpak, nix-csi, k3s)"
    setup_subvolume "@var" "$NVME" "/var"

    echo "[3/3] Verify"
    echo "  /data/projects unaffected (stays on @projects subvolume)"
    ;;

  forge)
    HDD="/dev/disk/by-id/ata-ADATA_SU635_2L40291DQ5CE-part2"

    echo "[1/3] @nix — nix store (86G)"
    setup_nix_subvolume "$HDD"

    echo "[2/3] @var — /var (29G: vllm-models, nix-csi, flatpak, k3s)"
    setup_subvolume "@var" "$HDD" "/var"

    echo "[3/3] Verify"
    echo "  /home stays on this drive (already there)"
    ;;

  nexus)
    echo "[SKIP] Nexus at 58% — not critical"
    ;;

  *)
    echo "Unknown host: $HOST"
    exit 1
    ;;
esac

echo ""
echo "=========================================="
echo " Setup complete for $HOST"
echo "=========================================="
echo ""
echo "Verify mounts will work:"
echo "  sudo mount -o subvol=@nix <device> /mnt && ls /mnt/store && umount /mnt"
echo "  sudo mount -o subvol=@var <device> /mnt && ls /mnt/lib && umount /mnt"
echo ""
echo "Next steps:"
echo "  1. sudo nixos-rebuild boot"
echo "  2. sudo reboot"
echo "  3. After reboot: df -h /nix /var"
echo "  4. sudo nixos-rebuild switch"
echo ""
