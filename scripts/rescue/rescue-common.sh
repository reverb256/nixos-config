#!/usr/bin/env bash
# Shared helpers for the cluster-wide NixOS USB-rescue toolkit.
# shellcheck shell=bash

set -euo pipefail

RESCUE_TOOL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESCUE_REPO_ROOT="$(cd "$RESCUE_TOOL_DIR/../.." && pwd)"
RESCUE_STATE_DIR="${RESCUE_STATE_DIR:-/tmp/nixos-rescue-state}"
RESCUE_DRY_RUN=1
RESCUE_APPLY=0
RESCUE_CONFIRM=0
RESCUE_EXTRA_MOUNTS=()

info() { printf '[INFO] %s\n' "$*"; }
ok() { printf '[ OK ] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
die() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

require_root() {
  [ "$(id -u)" -eq 0 ] || die "run this phase as root (or use sudo)"
}

run() {
  if [ "$RESCUE_DRY_RUN" -eq 1 ]; then
    printf '[DRY-RUN]'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

begin_apply() {
  RESCUE_APPLY=1
  RESCUE_DRY_RUN=0
  [ "$RESCUE_CONFIRM" -eq 1 ] || die "mutating phase requires --confirm-target"
}

mkdir_state() {
  run mkdir -p "$RESCUE_STATE_DIR"
  if [ "$RESCUE_DRY_RUN" -eq 0 ]; then
    chmod 700 "$RESCUE_STATE_DIR"
  fi
}

state_file() { printf '%s/%s' "$RESCUE_STATE_DIR" "$1"; }

write_state() {
  [ "$RESCUE_DRY_RUN" -eq 1 ] && return 0
  mkdir -p "$RESCUE_STATE_DIR"
  printf '%b\n' "$2" > "$(state_file "$1")"
  chmod 600 "$(state_file "$1")"
}

read_state() {
  [ -f "$(state_file "$1")" ] && cat "$(state_file "$1")"
}

usage_common() {
  cat <<'EOF'
Common safety flags:
  --apply                 Execute mutations; without it, mutating phases dry-run.
  --confirm-target        Required with --apply for target/profile/boot changes.
  --state-dir DIR         Durable checkpoint/log directory (default: /tmp/nixos-rescue-state).

The toolkit never formats disks, runs disko, deletes generations, runs GC, or
accepts changed SSH host keys automatically.
EOF
}

host_profile() {
  local host="$1"
  RESCUE_HOST="$host"
  RESCUE_EXTRA_MOUNTS=()
  case "$host" in
    zephyr)
      RESCUE_IP=10.1.1.110
      RESCUE_ROOT_LABEL=disk-samsung-root
      RESCUE_ROOT_SUBVOL=@
      RESCUE_NIX_LABEL=disk-xpg-nix
      RESCUE_NIX_SUBVOL=@nix
      RESCUE_PERSISTENT_LABEL=""
      RESCUE_PERSISTENT_SUBVOL=""
      RESCUE_EFI_LABEL=disk-samsung-boot
      RESCUE_EXTRA_MOUNTS+=("/dev/disk/by-partlabel/disk-xpg-nix|@var|/var")
      ;;
    nexus)
      RESCUE_IP=10.1.1.120
      RESCUE_ROOT_LABEL=disk-nvme1n1-root
      RESCUE_ROOT_SUBVOL=@root
      RESCUE_NIX_LABEL=disk-nvme1n1-root
      RESCUE_NIX_SUBVOL=@nix
      RESCUE_PERSISTENT_LABEL=disk-nvme1n1-root
      RESCUE_PERSISTENT_SUBVOL=@persistent
      RESCUE_EFI_LABEL=disk-nvme1n1-ESP
      RESCUE_EXTRA_MOUNTS+=("/dev/disk/by-label/nexus-storage|home|/home")
      ;;
    forge)
      RESCUE_IP=10.1.1.130
      RESCUE_ROOT_LABEL=disk-sdb-root
      RESCUE_ROOT_SUBVOL=@root
      RESCUE_NIX_LABEL=disk-sdb-root
      RESCUE_NIX_SUBVOL=@nix
      RESCUE_PERSISTENT_LABEL=disk-sdb-root
      RESCUE_PERSISTENT_SUBVOL=@persistent
      RESCUE_EFI_LABEL=disk-sdb-boot
      RESCUE_EXTRA_MOUNTS+=("/dev/disk/by-partlabel/disk-sda-data|@var|/var")
      ;;
    sentry)
      RESCUE_IP=10.1.1.140
      RESCUE_ROOT_LABEL=disk-sdb-root
      RESCUE_ROOT_SUBVOL=@root
      RESCUE_NIX_LABEL=disk-sdb-root
      RESCUE_NIX_SUBVOL=@nix
      RESCUE_PERSISTENT_LABEL=disk-sdb-root
      RESCUE_PERSISTENT_SUBVOL=@persistent
      RESCUE_EFI_LABEL=disk-sdb-boot
      RESCUE_EXTRA_MOUNTS+=("/dev/disk/by-partlabel/disk-sdb-root|@srv|/srv" "/dev/disk/by-partlabel/disk-sdb-root|@var/tmp|/var/tmp")
      ;;
    *)
      die "unknown host '$host'; use zephyr, nexus, forge, or sentry"
      ;;
  esac
}

partlabel_path() { printf '/dev/disk/by-partlabel/%s' "$1"; }

# Nix's local store backend treats the mounted target as the store root.  The
# target therefore uses /nix/store and /nix/var/... internally while the rescue
# host addresses those paths through local?root=/mnt/<host>-root.
target_store_uri() {
  local root="$1"
  [[ "$root" =~ ^/mnt/[A-Za-z0-9._-]+$ ]] \
    || die "target root must match /mnt/<safe-name> (got $root)"
  printf 'local?root=%s' "$root"
}

validate_target_root() {
  local root="$1"
  [ -n "$root" ] || die "target root is empty"
  [ "$root" != "/" ] || die "refusing target root=/; this would address the rescue system"
  [[ "$root" =~ ^/mnt/[A-Za-z0-9._-]+$ ]] \
    || die "target root must match /mnt/<safe-name> (got $root)"
}

ssh_args() {
  local known_hosts="$1"
  [ -f "$known_hosts" ] || die "known-hosts file missing: $known_hosts; verify the rescue fingerprint first"
  SSH_ARGS=(
    -o BatchMode=yes
    -o ConnectTimeout=8
    -o StrictHostKeyChecking=yes
    -o UserKnownHostsFile="$known_hosts"
  )
}

remote_target() { printf '%s@%s' "${RESCUE_SSH_USER:-j_kro}" "$RESCUE_IP"; }

remote() {
  ssh "${SSH_ARGS[@]}" "$(remote_target)" "$@"
}

remote_script() {
  ssh "${SSH_ARGS[@]}" "$(remote_target)" bash -s -- "$@"
}

remote_root_script() {
  ssh "${SSH_ARGS[@]}" "$(remote_target)" sudo bash -s -- "$@"
}

parse_common_flags() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --apply) RESCUE_APPLY=1; RESCUE_DRY_RUN=0; shift ;;
      --confirm-target) RESCUE_CONFIRM=1; shift ;;
      --state-dir) [ "$#" -ge 2 ] || die "$1 requires a value"; RESCUE_STATE_DIR="$2"; shift 2 ;;
      *) printf '%s\n' "$1"; shift ;;
    esac
  done
}

log_command() {
  mkdir_state
  local log
  log="$(state_file "${RESCUE_HOST:-unknown}-$(date -u +%Y%m%dT%H%M%SZ).log")"
  printf '%s\n' "$log"
}
