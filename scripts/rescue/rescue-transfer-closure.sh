#!/usr/bin/env bash
# Transfer only; does not change the target profile or bootloader.
set -euo pipefail
TOOL_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=rescue-common.sh
. "$TOOL_DIR/rescue-common.sh"
HOST=""; CLOSURE=""; KNOWN_HOSTS=""; TARGET_ROOT=""; RESCUE_SSH_USER="j_kro"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --host) HOST="${2:?}"; shift 2 ;;
    --closure) CLOSURE="${2:?}"; shift 2 ;;
    --known-hosts) KNOWN_HOSTS="${2:?}"; shift 2 ;;
    --target-root) TARGET_ROOT="${2:?}"; shift 2 ;;
    --ssh-user) RESCUE_SSH_USER="${2:?}"; shift 2 ;;
    --apply) RESCUE_APPLY=1; RESCUE_DRY_RUN=0; shift ;;
    --confirm-target) RESCUE_CONFIRM=1; shift ;;
    --help|-h) echo "Usage: rescue-transfer-closure.sh --host HOST --closure /nix/store/... --known-hosts FILE [--target-root /mnt/HOST-root] --apply --confirm-target"; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done
[ -n "$HOST" ] && [ -n "$CLOSURE" ] && [ -n "$KNOWN_HOSTS" ] || die '--host, --closure, and --known-hosts are required'
host_profile "$HOST"
TARGET_ROOT="${TARGET_ROOT:-/mnt/$HOST-root}"
validate_target_root "$TARGET_ROOT"
[[ "$CLOSURE" == /nix/store/* ]] || die 'closure must be an absolute /nix/store path'
[ -e "$CLOSURE" ] || die "closure missing locally: $CLOSURE"
[[ "$CLOSURE" =~ ^/nix/store/[a-z0-9]{32}-[A-Za-z0-9._+?=-]+$ ]] \
  || die 'closure contains unsafe characters or is not a store path'
[ "$RESCUE_DRY_RUN" -eq 0 ] || die 'transfer is mutating; use --apply --confirm-target'
begin_apply
require_root
require_cmd nix-store; require_cmd sha256sum; require_cmd tee
mkdir_state
ssh_args "$KNOWN_HOSTS"
mapfile -t PATHS < <(nix-store -qR "$CLOSURE")
[ "${#PATHS[@]}" -gt 0 ] || die 'closure query returned no paths'
info "transferring ${#PATHS[@]} paths to $HOST target store $TARGET_ROOT"
printf '%s\n' "${PATHS[@]}" | sha256sum | tee "$(state_file "$HOST.transfer.paths.sha256")"
TARGET_STORE="$(target_store_uri "$TARGET_ROOT")"
nix-store --export "${PATHS[@]}" \
  | ssh "${SSH_ARGS[@]}" "$(remote_target)" sudo nix-store --store "$TARGET_STORE" --import
remote_root_script "$TARGET_STORE" "$CLOSURE" "$TARGET_ROOT" <<'REMOTE'
set -euo pipefail
TARGET_STORE="$1"; CLOSURE="$2"; TARGET_ROOT="$3"
nix-store --store "$TARGET_STORE" --verify-path "$CLOSURE"
test -e "$TARGET_ROOT$CLOSURE"
REMOTE
write_state "$HOST.transfer" "closure=$CLOSURE\ncount=${#PATHS[@]}\ntarget_root=$TARGET_ROOT"
ok "closure imported and verified in installed target store"
