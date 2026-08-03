#!/usr/bin/env bash
# Cluster-wide rescue CLI. This is dispatch only; phases remain independently rerunnable.
set -euo pipefail
TOOL_DIR="$(cd "$(dirname "$0")" && pwd)"
usage() {
  cat <<'EOF'
NixOS cluster rescue toolkit

Usage:
  rescue-cli.sh <phase> [phase options]

Phases:
  discover       Read-only hardware/filesystem discovery
  mount          Mount an existing target (dry-run unless --apply --confirm-target)
  diagnose       Read-only installed-target diagnosis
  build          Build/verify a host toplevel on the builder
  transfer       Import a verified closure into a mounted target store
  prepare-boot   Set target profile and generate boot entry from nixos-enter
  verify         Verify pre-reboot target or post-reboot running host
  unmount        Ordered normal unmount (dry-run unless --apply --confirm-target)

This toolkit never formats disks, runs disko, deletes generations, runs GC, or
accepts changed SSH keys. See docs/runbooks/nixos-usb-rescue.md.
EOF
}
[ "$#" -gt 0 ] || { usage; exit 1; }
phase="$1"; shift
case "$phase" in
  discover) exec "$TOOL_DIR/rescue-discover.sh" "$@" ;;
  mount) exec "$TOOL_DIR/rescue-mount-target.sh" "$@" ;;
  diagnose) exec "$TOOL_DIR/rescue-diagnose.sh" "$@" ;;
  build) exec "$TOOL_DIR/rescue-build-closure.sh" "$@" ;;
  transfer) exec "$TOOL_DIR/rescue-transfer-closure.sh" "$@" ;;
  prepare-boot) exec "$TOOL_DIR/rescue-prepare-boot.sh" "$@" ;;
  verify) exec "$TOOL_DIR/rescue-verify.sh" "$@" ;;
  unmount) exec "$TOOL_DIR/rescue-unmount-target.sh" "$@" ;;
  help|-h|--help) usage ;;
  *) printf 'unknown phase: %s\n\n' "$phase" >&2; usage >&2; exit 2 ;;
esac
