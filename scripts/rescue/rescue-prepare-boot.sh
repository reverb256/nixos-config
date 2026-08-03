#!/usr/bin/env bash
# Mutating phase: profile update + boot entry generation. No service switch.
set -euo pipefail
TOOL_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=rescue-common.sh
. "$TOOL_DIR/rescue-common.sh"
HOST=""; CLOSURE=""; KNOWN_HOSTS=""; TARGET_ROOT=""; REFUSE_GENERATION=""; RESCUE_SSH_USER="j_kro"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --host) HOST="${2:?}"; shift 2 ;;
    --closure) CLOSURE="${2:?}"; shift 2 ;;
    --known-hosts) KNOWN_HOSTS="${2:?}"; shift 2 ;;
    --target-root) TARGET_ROOT="${2:?}"; shift 2 ;;
    --refuse-generation) REFUSE_GENERATION="${2:?}"; shift 2 ;;
    --ssh-user) RESCUE_SSH_USER="${2:?}"; shift 2 ;;
    --apply) RESCUE_APPLY=1; RESCUE_DRY_RUN=0; shift ;;
    --confirm-target) RESCUE_CONFIRM=1; shift ;;
    --help|-h) echo "Usage: rescue-prepare-boot.sh --host HOST --closure /nix/store/... --known-hosts FILE [--refuse-generation N] --apply --confirm-target"; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done
[ -n "$HOST" ] && [ -n "$CLOSURE" ] && [ -n "$KNOWN_HOSTS" ] || die 'required arguments missing'
host_profile "$HOST"; TARGET_ROOT="${TARGET_ROOT:-/mnt/$HOST-root}"; validate_target_root "$TARGET_ROOT"
[[ "$CLOSURE" =~ ^/nix/store/[a-z0-9]{32}-[A-Za-z0-9._+?=-]+$ ]] \
  || die 'closure contains unsafe characters or is not a NixOS store path'
[ "$RESCUE_DRY_RUN" -eq 0 ] || die 'boot preparation is mutating; use --apply --confirm-target'
begin_apply
require_root; ssh_args "$KNOWN_HOSTS"
remote_root_script "$TARGET_ROOT" "$CLOSURE" "$REFUSE_GENERATION" <<'REMOTE'
set -euo pipefail
TARGET_ROOT="$1"; CLOSURE="$2"; REFUSE_GENERATION="$3"
PROFILE=/nix/var/nix/profiles/system
TARGET_STORE="local?root=$TARGET_ROOT"
case "$CLOSURE" in /nix/store/*-nixos-system-*) ;; *) echo 'invalid NixOS toplevel' >&2; exit 2 ;; esac
[ -e "$TARGET_ROOT$CLOSURE" ] || { echo "closure is not in target store: $CLOSURE" >&2; exit 3; }
OLD=$(readlink -f "$TARGET_ROOT$PROFILE" || true)
printf 'old_profile=%s\n' "$OLD"
BLOCKED_PROFILE="$TARGET_ROOT/nix/var/nix/profiles/system-$REFUSE_GENERATION-link"
if [ -n "$REFUSE_GENERATION" ] && [ -e "$BLOCKED_PROFILE" ] \
  && [ "$(readlink -f "$BLOCKED_PROFILE")" = "$TARGET_ROOT$CLOSURE" ]; then
  echo "refusing to select blocked generation $REFUSE_GENERATION" >&2
  exit 5
fi
nix-env --store "$TARGET_STORE" -p "$PROFILE" --set "$CLOSURE"
NEW=$(readlink -f "$TARGET_ROOT$PROFILE")
[ "$NEW" = "$TARGET_ROOT$CLOSURE" ] || { echo "profile mismatch: $NEW != $TARGET_ROOT$CLOSURE" >&2; exit 4; }
NIXOS_INSTALL_BOOTLOADER=1 nixos-enter --root "$TARGET_ROOT" -- "$CLOSURE/bin/switch-to-configuration" boot
[ -d "$TARGET_ROOT/boot" ]
find "$TARGET_ROOT/boot" -maxdepth 3 -type f -name '*nixos*' -o -name '*.conf' | head -20
printf 'new_profile=%s\n' "$NEW"
REMOTE
write_state "$HOST.boot" "closure=$CLOSURE\ntarget_root=$TARGET_ROOT"
ok "profile and boot entries prepared; reboot remains a separate explicit step"
