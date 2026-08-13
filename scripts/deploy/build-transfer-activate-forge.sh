#!/usr/bin/env bash
# build-transfer-activate-forge.sh — build and activate Forge on Forge
#
# The build deliberately runs on Forge itself to keep Zephyr completely out of
# the build. The closure is activated locally on Forge, so no copy step is
# required.
#
# Usage from Zephyr after pushing main:
#   ./scripts/deploy/build-transfer-activate-forge.sh
#   ./scripts/deploy/build-transfer-activate-forge.sh --yes
set -euo pipefail

FLAKE="${FLAKE:-/etc/nixos}"
HOST="forge"
REMOTE_USER="${REMOTE_USER:-j_kro}"
SSH_TARGET="${REMOTE_USER}@${HOST}"
AUTO_APPROVE=false

info() { printf '[INFO] %s\n' "$*"; }
pass() { printf '[ OK ] %s\n' "$*"; }
fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }

if [[ "${1:-}" == "--yes" ]]; then
  AUTO_APPROVE=true
elif [[ $# -gt 0 ]]; then
  fail "unknown argument '$1'; use --yes or no argument"
fi

cd "$FLAKE"
[[ "$(hostname -s)" == "zephyr" ]] || \
  fail "run this helper from Zephyr; coordinator host is $(hostname -s)"
[[ -d .git && -f flake.nix ]] || fail "invalid NixOS checkout: $FLAKE"

EXPECTED_REF="$(git rev-parse origin/main 2>/dev/null || true)"
CURRENT_REF="$(git rev-parse HEAD 2>/dev/null || true)"
[[ -n "$EXPECTED_REF" && "$CURRENT_REF" == "$EXPECTED_REF" ]] || \
  fail "checkout is not aligned with origin/main"
[[ -z "$(git status --porcelain)" ]] || \
  fail "working tree is dirty; commit/stash changes before deployment"

info "Repository: $CURRENT_REF"
info "Target: $SSH_TARGET"
info "Build policy: host=Forge, max-jobs=3, cores=3, builders=none"

if [[ "$AUTO_APPROVE" != true ]]; then
  printf 'This will update, build, and activate Forge. Type yes to continue: '
  read -r confirmation
  [[ "$confirmation" == yes ]] || fail "cancelled"
fi

info "Checking Forge identity, checkout, and sudo-rs wrapper..."
ssh -o BatchMode=yes -o ConnectTimeout=5 "$SSH_TARGET" bash -s <<'REMOTE_PREFLIGHT'
set -euo pipefail
[[ "$(hostname -s)" == "forge" ]]
cd /etc/nixos
[[ -d .git && -f flake.nix ]]
[[ -z "$(git status --porcelain)" ]] || {
  echo "Forge checkout is dirty; refusing to overwrite it" >&2
  exit 1
}
GIT_SSH_COMMAND='ssh -F /dev/null -o BatchMode=yes -o ConnectTimeout=5' \
  git pull --ff-only origin main
[[ -x /run/wrappers/bin/sudo ]]
printf 'forge checkout=%s\n' "$(git rev-parse HEAD)"
REMOTE_PREFLIGHT
pass "Forge checkout is clean, synchronized, and sudo-rs is available"

info "Building and activating on Forge; Zephyr performs no build work..."
ssh -t -o ConnectTimeout=5 "$SSH_TARGET" bash -s <<'REMOTE_DEPLOY'
set -euo pipefail
cd /etc/nixos
output_file=/tmp/nixos-forge-output.path
rm -f "$output_file"
nix build -L \
  --max-jobs 3 \
  --cores 3 \
  --builders "" \
  --no-link \
  --print-out-paths \
  '.#nixosConfigurations.forge.config.system.build.toplevel' \
  | tee "$output_file"
build_out=$(tail -n 1 "$output_file")
[[ "$build_out" == /nix/store/*nixos-system-forge-* ]]
[[ -x "$build_out/bin/switch-to-configuration" ]]
printf 'Forge closure=%s\n' "$build_out"
/run/wrappers/bin/sudo nix-env -p /nix/var/nix/profiles/system --set "$build_out"
/run/wrappers/bin/sudo "$build_out/bin/switch-to-configuration" switch
active=$(readlink -f /nix/var/nix/profiles/system)
[[ "$active" == "$build_out" ]]
printf 'Forge active=%s\n' "$active"
state=$(timeout 30 systemctl is-system-running --wait 2>/dev/null || true)
case "$state" in
  running) echo 'Forge systemd=running' ;;
  degraded) echo 'Forge systemd=degraded' >&2 ;;
  *) echo "Forge systemd=$state" >&2; exit 1 ;;
esac
REMOTE_DEPLOY

pass "Forge built and activated locally with 3 jobs and 3 cores"
