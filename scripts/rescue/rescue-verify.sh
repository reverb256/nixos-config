#!/usr/bin/env bash
# Read-only verification phase.
set -euo pipefail
TOOL_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=rescue-common.sh
. "$TOOL_DIR/rescue-common.sh"
HOST=""; TARGET_ROOT=""; CLOSURE=""; KNOWN_HOSTS=""; MODE=pre; RESCUE_SSH_USER=j_kro
while [ "$#" -gt 0 ]; do
  case "$1" in
    --host) HOST="${2:?}"; shift 2 ;;
    --target-root) TARGET_ROOT="${2:?}"; shift 2 ;;
    --closure) CLOSURE="${2:?}"; shift 2 ;;
    --known-hosts) KNOWN_HOSTS="${2:?}"; shift 2 ;;
    --mode) MODE="${2:?}"; shift 2 ;;
    --ssh-user) RESCUE_SSH_USER="${2:?}"; shift 2 ;;
    --help|-h) echo "Usage: rescue-verify.sh --host HOST --mode pre|post [--closure PATH --known-hosts FILE]"; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done
[ -n "$HOST" ] || die '--host is required'
host_profile "$HOST"
if [ "$MODE" = post ]; then
  [ -n "$KNOWN_HOSTS" ] || die '--known-hosts is required for post verification'
  ssh_args "$KNOWN_HOSTS"
  remote 'hostname; uptime; readlink -f /run/booted-system; readlink -f /nix/var/nix/profiles/system; systemctl is-system-running || true; systemctl --failed --no-legend || true; findmnt / /nix /persistent 2>/dev/null || true'
  exit 0
fi
TARGET_ROOT="${TARGET_ROOT:-/mnt/$HOST-root}"; validate_target_root "$TARGET_ROOT"; require_root
[ -n "$CLOSURE" ] || die '--closure is required for pre verification'
[[ "$CLOSURE" =~ ^/nix/store/[a-z0-9]{32}-[A-Za-z0-9._+?=-]+$ ]] \
  || die 'closure contains unsafe characters or is not a NixOS store path'
[ -e "$TARGET_ROOT$CLOSURE" ] || die "closure absent from target store: $CLOSURE"
for p in "$TARGET_ROOT" "$TARGET_ROOT/nix" "$TARGET_ROOT/boot"; do mountpoint -q "$p" || die "required target mount absent: $p"; done
TARGET_STORE="$(target_store_uri "$TARGET_ROOT")"
nix-env --store "$TARGET_STORE" -p /nix/var/nix/profiles/system --list-generations
PROFILE_TARGET="$TARGET_ROOT/nix/var/nix/profiles/system"
PROFILE_PATH="$(readlink -f "$PROFILE_TARGET")"
[ "$PROFILE_PATH" = "$TARGET_ROOT$CLOSURE" ] || die "target profile does not point to requested closure: $PROFILE_PATH"
nix-store --store "$TARGET_STORE" --verify-path "$CLOSURE"
find "$TARGET_ROOT/boot/loader/entries" -maxdepth 1 -type f -printf '%f\n' 2>/dev/null | sort
ok "pre-reboot verification passed for $HOST"
