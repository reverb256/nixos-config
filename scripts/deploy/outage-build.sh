#!/usr/bin/env bash
# outage-build.sh — build + copy a host closure WITHOUT nexus.
#
# Normal operation routes every build through nexus (see justfile `deploy`
# and scripts/deploy/nexus-dispatch.sh). When nexus is down, zephyr has
# max-jobs=0 (modules/system/distributed-builds.nix:61) and there is no
# builder left. This script supplies bounded build capacity as INVOCATION
# FLAGS only — it writes no persistent state and does not modify
# distributed-builds.nix, so the documented OOM guard stays intact.
#
#   ./scripts/deploy/outage-build.sh <host> [--copy-to <ssh-target>]
#
# Sizing (measured 2026-08-06, nexus down, sentry in usb-rescue):
#   zephyr : 32c / 16.4G avail  -> jobs=4 cores=8   (primary)
#   forge  :  6c / 10.9G avail  -> jobs=2 cores=2   (fallback; 4 cores stay
#                                  with peakminer, and TMPDIR is forced off
#                                  the 2G tmpfs at /tmp -- a large source
#                                  unpack there dies ENOSPC, not OOM)
#
# Cache-first: substituters are unchanged, so a closure that is already
# cached lands as a pure substitution and no local build runs at all.

set -euo pipefail

FLAKE="${FLAKE:-/etc/nixos}"
HOST="${1:-}"
COPY_TO=""

usage() {
  cat <<'EOF'
Usage: outage-build.sh <host> [--copy-to <ssh-target>]

  <host>              zephyr | nexus | forge | sentry
  --copy-to TARGET    nix-copy-closure the result to TARGET after building
                      (e.g. --copy-to root@10.1.1.140 for a rescue shell)

Prints the built store path on stdout.
EOF
}

case "$HOST" in
  zephyr | nexus | forge | sentry) ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "outage-build: invalid or missing host: '${HOST}'" >&2
    usage >&2
    exit 2
    ;;
esac
shift

while [[ $# -gt 0 ]]; do
  case "$1" in
    --copy-to)
      [[ $# -ge 2 ]] || {
        echo "--copy-to requires a target" >&2
        exit 2
      }
      COPY_TO="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

BUILDER="$(hostname -s)"

case "$BUILDER" in
  zephyr)
    JOBS=4
    CORES=8
    ;;
  forge)
    JOBS=2
    CORES=2
    # /tmp on forge is a 2G tmpfs; keep build scratch on disk.
    export TMPDIR=/nix/tmp
    mkdir -p "$TMPDIR"
    ;;
  *)
    echo "outage-build: refusing to run on '$BUILDER'." >&2
    echo "Approved outage builders are zephyr (primary) and forge (fallback)." >&2
    exit 1
    ;;
esac

# Guard the desktop session / the miners: bail rather than start a build that
# will push the host into swap-thrash or OOM.
AVAIL_MB="$(awk '/^MemAvailable:/ {print int($2/1024)}' /proc/meminfo)"
MIN_MB=6000
if [[ "$AVAIL_MB" -lt "$MIN_MB" ]]; then
  echo "outage-build: only ${AVAIL_MB}MB available on ${BUILDER} (need ${MIN_MB}MB)." >&2
  echo "Free memory or build on the other approved host." >&2
  exit 1
fi

echo "outage-build: building '${HOST}' on ${BUILDER} (jobs=${JOBS} cores=${CORES}, ${AVAIL_MB}MB avail)" >&2

# --builders '' disables /etc/nix/machines entirely. Without this, nix tries
# nexus first (speedFactor 10) and stalls on an unreachable host.
OUT="$(
  nix build \
    --builders '' \
    --max-jobs "$JOBS" \
    --cores "$CORES" \
    --no-link \
    --print-out-paths \
    "${FLAKE}#nixosConfigurations.${HOST}.config.system.build.toplevel"
)"

[[ -n "$OUT" ]] || {
  echo "outage-build: build produced no output path" >&2
  exit 1
}

# Cross-host footgun guard (same class as the 2026-07-28 nexus incident):
# refuse to hand over a closure whose name does not match the target host.
case "$(basename "$OUT")" in
  *"nixos-system-${HOST}-"*) ;;
  *)
    echo "outage-build: REFUSING — '$OUT' does not look like a '${HOST}' system." >&2
    exit 1
    ;;
esac

echo "outage-build: built ${OUT}" >&2

if [[ -n "$COPY_TO" ]]; then
  echo "outage-build: copying to ${COPY_TO}" >&2
  nix-copy-closure --to "$COPY_TO" "$OUT"
  echo "outage-build: copied. Activate on the target with:" >&2
  echo "  nix-env -p /nix/var/nix/profiles/system --set ${OUT}" >&2
  echo "  ${OUT}/bin/switch-to-configuration switch" >&2
fi

echo "$OUT"
