#!/usr/bin/env bash
# Read-only by default; --apply performs ordered normal unmounts only.
set -euo pipefail
TOOL_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=rescue-common.sh
. "$TOOL_DIR/rescue-common.sh"
HOST=""; TARGET_ROOT=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --host) HOST="${2:?}"; shift 2 ;;
    --target-root) TARGET_ROOT="${2:?}"; shift 2 ;;
    --apply) RESCUE_APPLY=1; RESCUE_DRY_RUN=0; shift ;;
    --confirm-target) RESCUE_CONFIRM=1; shift ;;
    --help|-h) echo "Usage: rescue-unmount-target.sh --host HOST [--target-root /mnt/HOST-root] [--apply --confirm-target]"; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done
[ -n "$HOST" ] || die '--host is required'
if [ "$RESCUE_APPLY" -eq 1 ]; then begin_apply; fi
host_profile "$HOST"; TARGET_ROOT="${TARGET_ROOT:-/mnt/$HOST-root}"; validate_target_root "$TARGET_ROOT"
if [ "$RESCUE_DRY_RUN" -eq 0 ]; then require_root; fi
findmnt -R "$TARGET_ROOT" 2>/dev/null || true
UNMOUNTS=("$TARGET_ROOT/boot")
for extra in "${RESCUE_EXTRA_MOUNTS[@]}"; do
  IFS='|' read -r _extra_dev _extra_subvol extra_mountpoint <<< "$extra"
  UNMOUNTS+=("$TARGET_ROOT$extra_mountpoint")
done
[ -z "$RESCUE_PERSISTENT_LABEL" ] || UNMOUNTS+=("$TARGET_ROOT/persistent")
UNMOUNTS+=("$TARGET_ROOT/nix" "$TARGET_ROOT")
for p in "${UNMOUNTS[@]}"; do
  if mountpoint -q "$p"; then
    if [ "$RESCUE_DRY_RUN" -eq 1 ]; then
      printf '[DRY-RUN] umount %q\n' "$p"
    else
      umount "$p"
    fi
  fi
done
if [ "$RESCUE_DRY_RUN" -eq 0 ]; then
  findmnt -R "$TARGET_ROOT" 2>/dev/null && die 'mounts remain; inspect before retrying'
  ok "unmounted $TARGET_ROOT"
fi
