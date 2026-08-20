#!/usr/bin/env bash
# lix-upstream-track.sh — detect drift between the homelab Lix fork and
# upstream lix-project/lix main. READ-ONLY: fetches upstream, never modifies
# the local checkout or flake.
#
# Why: the homelab fork (reverb256/lix, homelab/2.96) carries 24 commits on
# top of upstream's 2.96.0-dev base (gitlawb:// scheme, parallel-eval Stage
# 1-3, attrset linear-scan, Boehm GC heap cap, -O3 stack-depth fixes). Upstream
# commits at ~daily cadence and is actively rewriting libfetchers to be async —
# exactly the subsystem our gitlawb:// patch touches. Without tracking we drift
# silently until a rebase conflict bites.
#
# Behavior:
#   - Reads the pinned lix rev from flake.nix (the `lix` input `rev=`).
#   - Fetches lix-project/lix main (shallow, blobless) into a temp clone.
#   - Computes merge-base(fork_rev, upstream_main).
#   - If merge-base != upstream_main tip -> upstream has advanced past our fork
#     point: print a drift report (new commits + any touching libfetchers/) and
#     exit 1.
#   - Else -> clean, exit 0.
#
# Intended use: run from the Sunday flake-update workflow (or manually) so a
# drifted fork becomes a visible CI failure + kanban task, not a silent gap.

set -uo pipefail

UPSTREAM_URL="https://github.com/lix-project/lix"
FLAKE="${FLAKE:-/etc/nixos}/flake.nix"

# --- extract the pinned lix rev from flake.nix -------------------------------
# Matches: lix = { url = "git+https://...reverb256/lix?ref=homelab%2F2.96&rev=<REV>";
FORK_REV=$(grep -oE 'reverb256/lix\?ref=[^&]*&rev=[0-9a-f]{7,40}' "$FLAKE" 2>/dev/null \
  | grep -oE 'rev=[0-9a-f]{7,40}' | head -1 | cut -d= -f2)

if [[ -z "${FORK_REV:-}" ]]; then
  echo "ERROR: could not parse pinned lix rev from $FLAKE" >&2
  exit 2
fi

echo "Pinned homelab fork rev: ${FORK_REV}"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "Fetching upstream lix-project/lix main (shallow, blobless)..."
git clone --filter=blob:none --depth 200 --branch main "$UPSTREAM_URL" "$TMP/upstream" >/dev/null 2>&1 \
  || { echo "ERROR: failed to fetch upstream $UPSTREAM_URL" >&2; exit 3; }

UPSTREAM_TIP=$(git -C "$TMP/upstream" rev-parse HEAD)
echo "Upstream main tip:       ${UPSTREAM_TIP}"

# Resolve the fork rev inside the upstream clone (it is an ancestor of our fork
# tip, which itself is based on upstream main). If the pinned rev is unknown to
# upstream's history we cannot compute a merge-base — treat as drift/unknown.
if ! git -C "$TMP/upstream" cat-file -e "${FORK_REV}^{commit}" 2>/dev/null; then
  echo "WARN: pinned fork rev ${FORK_REV} not found in upstream history;" >&2
  echo "      fork may have rebased off a different upstream point." >&2
  MB=""
else
  MB=$(git -C "$TMP/upstream" merge-base "${FORK_REV}" HEAD)
fi

if [[ -z "${MB:-}" || "$MB" != "$UPSTREAM_TIP" ]]; then
  echo
  echo "=== DRIFT DETECTED: upstream main has advanced past the fork point ==="
  if [[ -n "${MB:-}" ]]; then
    echo "Merge-base: ${MB}"
    echo "Commits on upstream main since fork point:"
    git -C "$TMP/upstream" log --oneline "${MB}..HEAD" | head -40
    echo
    echo "--- upstream commits touching libfetchers/ (gitlawb:// collision surface) ---"
    git -C "$TMP/upstream" log --oneline "${MB}..HEAD" -- libfetchers/ | head -20 \
      || echo "(none)"
  else
    echo "Merge-base unavailable — fork lineage unknown vs current upstream."
  fi
  echo
  echo "ACTION: rebase homelab/2.96 onto upstream main; resolve libfetchers conflicts;"
  echo "        bump the rev in flake.nix; open a kanban task if not already tracked."
  exit 1
fi

echo
echo "OK: homelab fork is up to date with upstream main (merge-base == tip)."
exit 0
