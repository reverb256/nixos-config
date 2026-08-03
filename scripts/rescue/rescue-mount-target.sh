#!/usr/bin/env bash
# Mount an existing target. Never creates subvolumes or formats anything.
set -euo pipefail
TOOL_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=rescue-common.sh
. "$TOOL_DIR/rescue-common.sh"

HOST=""; TARGET_ROOT=""; ROOT_DEV=""; ROOT_SUBVOL=""; NIX_DEV=""; NIX_SUBVOL=""; PERSIST_DEV=""; PERSIST_SUBVOL=""; EFI_DEV=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --host) HOST="${2:?}"; shift 2 ;;
    --target-root) TARGET_ROOT="${2:?}"; shift 2 ;;
    --root-device) ROOT_DEV="${2:?}"; shift 2 ;;
    --root-subvol) ROOT_SUBVOL="${2:?}"; shift 2 ;;
    --nix-device) NIX_DEV="${2:?}"; shift 2 ;;
    --nix-subvol) NIX_SUBVOL="${2:?}"; shift 2 ;;
    --persistent-device) PERSIST_DEV="${2:?}"; shift 2 ;;
    --persistent-subvol) PERSIST_SUBVOL="${2:?}"; shift 2 ;;
    --efi-device) EFI_DEV="${2:?}"; shift 2 ;;
    --apply) RESCUE_APPLY=1; RESCUE_DRY_RUN=0; shift ;;
    --confirm-target) RESCUE_CONFIRM=1; shift ;;
    --state-dir) RESCUE_STATE_DIR="${2:?}"; shift 2 ;;
    --help|-h) cat <<'EOF'
Usage: rescue-mount-target.sh --host HOST [options]
Default is dry-run. Use --apply --confirm-target to mount.
Override generated profile data with --root-device/--root-subvol,
--nix-device/--nix-subvol, --persistent-device/--persistent-subvol, and
--efi-device. TARGET_ROOT must be below /mnt.
EOF
      exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done
[ -n "$HOST" ] || die '--host is required'
if [ "$RESCUE_APPLY" -eq 1 ]; then begin_apply; fi
host_profile "$HOST"
TARGET_ROOT="${TARGET_ROOT:-/mnt/$HOST-root}"
validate_target_root "$TARGET_ROOT"
ROOT_SUBVOL="${ROOT_SUBVOL:-$RESCUE_ROOT_SUBVOL}"
NIX_SUBVOL="${NIX_SUBVOL:-$RESCUE_NIX_SUBVOL}"
PERSIST_SUBVOL="${PERSIST_SUBVOL:-$RESCUE_PERSISTENT_SUBVOL}"
ROOT_DEV="${ROOT_DEV:-$(partlabel_path "$RESCUE_ROOT_LABEL")}"
NIX_DEV="${NIX_DEV:-$(partlabel_path "$RESCUE_NIX_LABEL")}"
[ -n "$RESCUE_PERSISTENT_LABEL" ] && PERSIST_DEV="${PERSIST_DEV:-$(partlabel_path "$RESCUE_PERSISTENT_LABEL")}"
EFI_DEV="${EFI_DEV:-$(partlabel_path "$RESCUE_EFI_LABEL")}"

if [ "$RESCUE_DRY_RUN" -eq 0 ]; then
  require_root
  for p in "$ROOT_DEV" "$NIX_DEV" "$EFI_DEV"; do [ -e "$p" ] || die "device path missing: $p; run rescue-discover.sh and override explicitly"; done
  [ -z "$PERSIST_DEV" ] || [ -e "$PERSIST_DEV" ] || die "persistent device path missing: $PERSIST_DEV"
  for extra in "${RESCUE_EXTRA_MOUNTS[@]}"; do
    IFS='|' read -r extra_dev extra_subvol extra_mountpoint <<< "$extra"
    [ -e "$extra_dev" ] || die "extra device path missing: $extra_dev"
  done
fi
[ -n "$ROOT_SUBVOL" ] || die "root subvolume is required"
[ -n "$NIX_SUBVOL" ] || die "Nix subvolume is required"
mkdir_state

mount_one() {
  local dev="$1" subvol="$2" mountpoint="$3"
  run mkdir -p "$mountpoint"
  if mountpoint -q "$mountpoint"; then
    local details mounted_source requested_source
    details="$(findmnt -n -o SOURCE,OPTIONS --target "$mountpoint")"
    mounted_source="$(findmnt -n -o SOURCE --target "$mountpoint")"
    requested_source="$dev"
    # findmnt renders Btrfs subvolume sources as /dev/...[/subvol]. Compare
    # the underlying filesystem device, not the display suffix.
    mounted_source="${mounted_source%%\[*}"
    if [ -e "$mounted_source" ] && [ -e "$requested_source" ]; then
      [ "$(readlink -f "$mounted_source")" = "$(readlink -f "$requested_source")" ] \
        || die "existing mount source differs at $mountpoint: $mounted_source != $requested_source"
    else
      [ "$mounted_source" = "$requested_source" ] \
        || die "existing mount source differs at $mountpoint: $mounted_source != $requested_source"
    fi
    printf '%s\n' "$details" | grep -Eq "subvol=/?${subvol}(,|$)" \
      || die "existing mount does not match subvolume $subvol at $mountpoint: $details"
    info "verified existing mount: $mountpoint ($details)"
  else
    run mount -o "subvol=$subvol" "$dev" "$mountpoint"
  fi
}

info "host=$HOST target_root=$TARGET_ROOT"
info "root=$ROOT_DEV subvol=$ROOT_SUBVOL"
info "nix=$NIX_DEV subvol=$NIX_SUBVOL"
[ -n "$PERSIST_DEV" ] && info "persistent=$PERSIST_DEV subvol=$PERSIST_SUBVOL"
info "efi=$EFI_DEV"
mount_one "$ROOT_DEV" "$ROOT_SUBVOL" "$TARGET_ROOT"
mount_one "$NIX_DEV" "$NIX_SUBVOL" "$TARGET_ROOT/nix"
if [ -n "$PERSIST_DEV" ]; then mount_one "$PERSIST_DEV" "$PERSIST_SUBVOL" "$TARGET_ROOT/persistent"; fi
for extra in "${RESCUE_EXTRA_MOUNTS[@]}"; do
  IFS='|' read -r extra_dev extra_subvol extra_mountpoint <<< "$extra"
  mount_one "$extra_dev" "$extra_subvol" "$TARGET_ROOT$extra_mountpoint"
done
run mkdir -p "$TARGET_ROOT/boot"
if mountpoint -q "$TARGET_ROOT/boot"; then
  details="$(findmnt -n -o SOURCE --target "$TARGET_ROOT/boot")"
  [ "$(readlink -f "$details")" = "$(readlink -f "$EFI_DEV")" ] \
    || die "existing EFI mount does not match $EFI_DEV: $details"
  info "verified existing mount: $TARGET_ROOT/boot ($details)"
else
  run mount "$EFI_DEV" "$TARGET_ROOT/boot"
fi
if [ "$RESCUE_DRY_RUN" -eq 0 ]; then
  mountpoint -q "$TARGET_ROOT" || die 'root mount did not complete'
  mountpoint -q "$TARGET_ROOT/nix" || die 'Nix mount did not complete'
  mountpoint -q "$TARGET_ROOT/boot" || die 'EFI mount did not complete'
  [ -d "$TARGET_ROOT/nix/store" ] || die 'target Nix store is missing'
  write_state "$HOST.mounts" "target_root=$TARGET_ROOT"
  ok "mounted and verified target: $TARGET_ROOT"
fi
