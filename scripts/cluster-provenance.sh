#!/usr/bin/env bash
# Deploy provenance + drift detection — issue #342
#
# Reports per host: current generation, active closure, git commit on
# /etc/nixos, whether the closure is a `.dirty` build, and whether the host
# matches origin/main HEAD (drift).
#
# Usage:
#   scripts/cluster-provenance.sh            # all hosts
#   scripts/cluster-provenance.sh nexus      # one host
#
# Exit code: 0 = no drift/.dirty; 1 = drift or .dirty closure detected.
set -euo pipefail

FLAKE="${FLAKE:-/etc/nixos}"
if [ $# -gt 0 ]; then
  HOSTS=("$@")
else
  HOSTS=(zephyr nexus forge sentry)
fi

cd "$FLAKE"
MAIN_COMMIT=$(git rev-parse origin/main 2>/dev/null || echo "unknown")
LOCAL_HOST=$(hostname -s)

printf '%-8s %-8s %-62s %-8s %s\n' HOST GEN CLOSURE DIRTY MATCHES_MAIN
drift=0

for host in "${HOSTS[@]}"; do
  if [ "$host" = "$LOCAL_HOST" ]; then
    closure=$(readlink /nix/var/nix/profiles/system 2>/dev/null || echo "-")
    gen=$(nix-env --list-generations --profile /nix/var/nix/profiles/system 2>/dev/null | awk 'END{print $1}' || echo "-")
    commit=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
  else
    closure=$(ssh -o BatchMode=yes -o ConnectTimeout=5 "$host" \
      "readlink /nix/var/nix/profiles/system 2>/dev/null || echo -" 2>/dev/null || echo "unreachable")
    gen=$(ssh -o BatchMode=yes -o ConnectTimeout=5 "$host" \
      "nix-env --list-generations --profile /nix/var/nix/profiles/system 2>/dev/null | awk 'END{print \$1}' || echo -" 2>/dev/null || echo "unreachable")
    commit=$(ssh -o BatchMode=yes -o ConnectTimeout=5 "$host" \
      "cd /etc/nixos 2>/dev/null && git rev-parse HEAD 2>/dev/null || echo unknown" 2>/dev/null || echo "unreachable")
  fi

  dirty="no"
  case "$closure" in
    *.dirty) dirty="YES" ;;
  esac
  if [ "$dirty" = "YES" ]; then drift=1; fi

  matches="no"
  if [ "$commit" = "$MAIN_COMMIT" ]; then
    matches="yes"
  else
    [ "$commit" != "unknown" ] && [ "$commit" != "unreachable" ] && drift=1
  fi

  # A down host is more urgent than drift — flag it.
  if [ "$closure" = "unreachable" ] || [ "$commit" = "unreachable" ]; then
    drift=1
    printf '%-8s %-8s %-62s %-8s %s  ⚠ UNREACHABLE\n' "$host" "$gen" "$closure" "$dirty" "$matches"
  else
    printf '%-8s %-8s %-62s %-8s %s\n' "$host" "$gen" "$closure" "$dirty" "$matches"
  fi
done

echo ""
echo "origin/main: $MAIN_COMMIT"
if [ "$drift" -eq 1 ]; then
  echo "⚠  Drift or .dirty closure detected (see above)."
  exit 1
fi
echo "✓ No drift, no .dirty closures."
