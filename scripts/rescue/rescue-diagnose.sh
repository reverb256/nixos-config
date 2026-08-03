#!/usr/bin/env bash
# Read-only target diagnosis. Never edits target files or profiles.
set -euo pipefail
TOOL_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=rescue-common.sh
. "$TOOL_DIR/rescue-common.sh"
HOST=""; TARGET_ROOT=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --host) HOST="${2:?}"; shift 2 ;;
    --target-root) TARGET_ROOT="${2:?}"; shift 2 ;;
    --help|-h) echo "Usage: rescue-diagnose.sh --host HOST [--target-root /mnt/HOST-root]"; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done
[ -n "$HOST" ] || die '--host is required'
host_profile "$HOST"
TARGET_ROOT="${TARGET_ROOT:-/mnt/$HOST-root}"
validate_target_root "$TARGET_ROOT"
require_root
for cmd in findmnt journalctl nix-env; do require_cmd "$cmd"; done
[ -d "$TARGET_ROOT" ] || die "target root missing: $TARGET_ROOT"

printf '%s\n' "=== DIAGNOSTICS: $HOST ==="
findmnt -R "$TARGET_ROOT" || true
printf '%s\n' '--- fstab ---'; cat "$TARGET_ROOT/etc/fstab" 2>&1 || true
printf '%s\n' '--- system profile ---'
readlink -f "$TARGET_ROOT/nix/var/nix/profiles/system" 2>&1 || true
TARGET_STORE="$(target_store_uri "$TARGET_ROOT")"
nix-env --store "$TARGET_STORE" -p /nix/var/nix/profiles/system --list-generations 2>&1 || true
printf '%s\n' '--- boot entries ---'
find "$TARGET_ROOT/boot/loader/entries" -maxdepth 1 -type f -printf '%f\n' 2>/dev/null | sort || true
printf '%s\n' '--- target journal boots ---'
journalctl --root="$TARGET_ROOT" --list-boots 2>&1 || true
printf '%s\n' '--- recent failure lines ---'
journalctl --root="$TARGET_ROOT" -b -1 --no-pager 2>/dev/null \
  | grep -iE 'failed|failure|emergency|dependency|mount|panic|initrd' | tail -100 || true
