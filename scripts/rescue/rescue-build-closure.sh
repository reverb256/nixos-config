#!/usr/bin/env bash
# Run on the builder/dispatcher, not in USB rescue.
set -euo pipefail
TOOL_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=rescue-common.sh
. "$TOOL_DIR/rescue-common.sh"
HOST=""; FLAKE="${RESCUE_FLAKE:-$RESCUE_REPO_ROOT}"; CACHE="${RESCUE_SUBSTITUTERS:-http://10.1.1.110:50000 https://cache.nixos.org https://nix-community.cachix.org}"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --host) HOST="${2:?}"; shift 2 ;;
    --flake) FLAKE="${2:?}"; shift 2 ;;
    --substituters) CACHE="${2:?}"; shift 2 ;;
    --help|-h) cat <<'EOF'
Usage: rescue-build-closure.sh --host HOST [--flake PATH] [--substituters 'URL ...']
Builds locally on the invoking builder. Does not activate or contact a target.
EOF
      exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done
[ -n "$HOST" ] || die '--host is required'
require_cmd nix; require_cmd git; require_cmd tee
[ -f "$FLAKE/flake.nix" ] || die "flake not found: $FLAKE"
cd "$FLAKE"
OUT_DIR="${RESCUE_BUILD_DIR:-$RESCUE_STATE_DIR/builds}"
mkdir -p "$OUT_DIR"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
LOG="$OUT_DIR/$HOST-$STAMP.log"
PATH_FILE="$OUT_DIR/$HOST-$STAMP.path"
info "evaluating $HOST"
nix eval --show-trace --raw ".#nixosConfigurations.$HOST.config.system.build.toplevel.drvPath" >/dev/null
info "building $HOST; log=$LOG"
set +e
nix build --no-link --fallback --print-out-paths \
  --option http2 false \
  --option http-connections 16 \
  --option connect-timeout 10 \
  --option download-attempts 10 \
  --option substituters "$CACHE" \
  --option builders '' \
  --option max-jobs "${RESCUE_MAX_JOBS:-16}" \
  --option cores "${RESCUE_CORES:-16}" \
  ".#nixosConfigurations.$HOST.config.system.build.toplevel" 2>&1 | tee "$LOG"
rc=${PIPESTATUS[0]}
set -e
[ "$rc" -eq 0 ] || { warn "build failed; log=$LOG"; exit "$rc"; }
CLOSURE="$(grep -E '^/nix/store/[a-z0-9]+-nixos-system-' "$LOG" | tail -1)"
[ -n "$CLOSURE" ] || die "build succeeded but no toplevel path found in $LOG"
[ -e "$CLOSURE" ] || die "toplevel path missing: $CLOSURE"
printf '%s\n' "$CLOSURE" > "$PATH_FILE"
nix path-info --json "$CLOSURE" > "$PATH_FILE.json"
nix-store -qR "$CLOSURE" > "$PATH_FILE.closure"
nix-store --verify-path "$CLOSURE"
printf 'closure=%s\ncount=%s\nlog=%s\n' "$CLOSURE" "$(wc -l < "$PATH_FILE.closure")" "$LOG"
ok "verified toplevel: $CLOSURE"
