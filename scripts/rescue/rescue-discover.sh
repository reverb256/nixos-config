#!/usr/bin/env bash
# Read-only discovery. Never mounts, formats, changes profiles, or modifies disks.
set -euo pipefail
TOOL_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=rescue-common.sh
. "$TOOL_DIR/rescue-common.sh"

HOST=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --host) HOST="${2:?--host requires a value}"; shift 2 ;;
    --help|-h) cat <<'EOF'
Usage: rescue-discover.sh [--host HOST]
Read-only hardware and filesystem discovery. HOST is advisory and validates a
known profile; device selection always remains an explicit operator decision.
EOF
      exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

for cmd in lsblk blkid findmnt btrfs; do require_cmd "$cmd"; done
[ -n "$HOST" ] && host_profile "$HOST"

printf '%s\n' '=== RESCUE DISCOVERY (READ ONLY) ==='
printf 'time=%s\n' "$(date -Is)"
printf 'kernel=%s\n' "$(uname -a)"
if [ -d /sys/firmware/efi ]; then echo 'boot_mode=uefi'; else echo 'boot_mode=bios'; fi
printf '%s\n' '--- lsblk ---'; lsblk -e7 -o NAME,PATH,SIZE,TYPE,FSTYPE,LABEL,PARTLABEL,MOUNTPOINTS
printf '%s\n' '--- blkid ---'; blkid || true
printf '%s\n' '--- mounts ---'; findmnt --real || true
printf '%s\n' '--- btrfs devices/subvolumes ---'
while read -r dev; do
  [ -n "$dev" ] || continue
  echo "device=$dev"
  btrfs filesystem show "$dev" 2>/dev/null || true
  btrfs subvolume list -p "$dev" 2>/dev/null || true
done < <(blkid -t TYPE=btrfs -o device 2>/dev/null | sort -u)
if [ -n "$HOST" ]; then
  printf '%s\n' '--- profile hints (verify against discovery) ---'
  printf 'host=%s ip=%s root_label=%s root_subvol=%s nix_label=%s nix_subvol=%s persistent_label=%s persistent_subvol=%s efi_label=%s\n' \
    "$RESCUE_HOST" "$RESCUE_IP" "$RESCUE_ROOT_LABEL" "$RESCUE_ROOT_SUBVOL" \
    "$RESCUE_NIX_LABEL" "$RESCUE_NIX_SUBVOL" "$RESCUE_PERSISTENT_LABEL" \
    "$RESCUE_PERSISTENT_SUBVOL" "$RESCUE_EFI_LABEL"
fi
