#!/usr/bin/env bash
# nexus-dispatch.sh — dispatch the canonical deployment from Nexus
#
# Architecture:
#   Zephyr remains the authoring/source-of-truth host.
#   Nexus is the exclusive build and deployment executor.
#
# Usage from Zephyr (the only approved source checkout):
#   nexus-dispatch.sh --sync  --target all|zephyr|nexus|forge|sentry
#   nexus-dispatch.sh --async --target all|zephyr|nexus|forge|sentry
#
# Usage on Nexus:
#   nexus-dispatch.sh --executor --target all|zephyr|nexus|forge|sentry
#
# The executor always fetches and hard-resets Nexus' checkout to origin/main
# before evaluating the flake. This intentionally refuses to deploy an
# unpushed local worktree or a drifted Nexus checkout.

set -euo pipefail

FLAKE="${FLAKE:-/etc/nixos}"
TARGET="all"
MODE="sync"

usage() {
  cat <<'EOF'
Usage: nexus-dispatch.sh [MODE] [--target HOST]

MODE:
  --sync       Run the deployment on Nexus and stream its output (default).
  --async      Start a detached tmux deployment on Nexus and return its log.
  --executor   Internal: execute the deployment locally on Nexus.

HOST:
  all, zephyr, nexus, forge, sentry
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sync|--async|--executor)
      MODE="${1#--}"
      shift
      ;;
    --target)
      [[ $# -ge 2 ]] || { echo "--target requires a host" >&2; exit 2; }
      TARGET="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

case "$TARGET" in
  all|zephyr|nexus|forge|sentry) ;;
  *) echo "Invalid deployment target: $TARGET" >&2; exit 2 ;;
esac

HOSTNAME_SHORT="$(hostname -s)"

run_preflight() {
  "$FLAKE/scripts/preflight-check.sh"
}

executor() {
  [[ "$HOSTNAME_SHORT" == "nexus" ]] || {
    echo "--executor must run on nexus, got $HOSTNAME_SHORT" >&2
    exit 1
  }

  cd "$FLAKE"
  # colmena apply-local --sudo evaluates the flake as root and can create
  # root-owned objects in .git, which then breaks the NEXT deploy's fetch
  # (git unpack-objects: insufficient permission). Normalize before fetching.
  # colmena apply-local --sudo evaluates the flake as root and can create
  # root-owned files in the flake dir (e.g. .git objects, flake.lock), which
  # breaks the NEXT deploy's fetch/eval (insufficient permission). Normalize
  # the whole flake dir before fetching.
  REPO_OWNER="$(stat -c %U "$FLAKE")"
  REPO_GROUP="$(stat -c %G "$FLAKE")"
  if [[ -n "$REPO_OWNER" ]] && [[ "$(find "$FLAKE" -not -user "$REPO_OWNER" 2>/dev/null | head -1)" ]]; then
    sudo chown -R "$REPO_OWNER":"$REPO_GROUP" "$FLAKE" 2>/dev/null || true
  fi
  git fetch origin main
  git reset --hard origin/main

  CANONICAL="$(git rev-parse --short HEAD)"
  echo "Nexus deployment executor at origin/main: $CANONICAL"

  NIX_CMD=(
    nix --option pure-eval false run
    .#apps.x86_64-linux.colmena
    --
  )

  if [[ "$TARGET" == "nexus" ]]; then
    # nexus is the local executor host (deployment.targetHost = null). colmena
    # `apply` only targets SSH hosts — select_nodes() drops nodes with no
    # targetHost when the goal requires a target host — so the local node must
    # be deployed with `apply-local` (gated by deployment.allowLocalDeployment).
    echo "Deploying local node: nexus (apply-local)"
    exec "${NIX_CMD[@]}" apply-local --sudo --node nexus
  fi

  CMD=(
    "${NIX_CMD[@]}"
    apply
    --eval-node-limit 100
  )
  if [[ "$TARGET" != "all" ]]; then
    CMD+=(--on "$TARGET")
  fi

  echo "Deploying remote target: $TARGET"
  "${CMD[@]}"

  # `apply` skips the local node (targetHost = null); deploy it last so the
  # executor host converges with the rest of the fleet.
  if [[ "$TARGET" == "all" ]]; then
    echo "Deploying local node: nexus (apply-local)"
    exec "${NIX_CMD[@]}" apply-local --sudo --node nexus
  fi
}

if [[ "$MODE" == "executor" ]]; then
  executor
  # executor() runs the deployment and returns (only the local-nexus branch
  # uses exec). Do NOT fall through to the zephyr-only dispatch guard below —
  # on nexus it would wrongly exit 1 after a successful deploy.
  exit 0
fi

# All non-executor modes are initiated from Zephyr. This prevents a stale
# checkout on another node from becoming an accidental deployment authority.
if [[ "$HOSTNAME_SHORT" != "zephyr" ]]; then
  echo "dispatch must be initiated from zephyr, got $HOSTNAME_SHORT" >&2
  exit 1
fi

cd "$FLAKE"
run_preflight

if [[ "$MODE" == "sync" ]]; then
  exec ssh nexus \
    "bash --norc --noprofile -c 'cd /etc/nixos && ./scripts/deploy/nexus-dispatch.sh --executor --target $TARGET'"
fi

SESSION="nixos-deploy-${TARGET}"
LOG="/tmp/${SESSION}.log"

if ssh nexus "tmux has-session -t '$SESSION'" 2>/dev/null; then
  echo "deployment already running on Nexus"
  echo "  tmux session: $SESSION"
  echo "  log: $LOG"
  exit 1
fi

ssh nexus \
  "tmux new-session -d -s '$SESSION' \"cd /etc/nixos && ./scripts/deploy/nexus-dispatch.sh --executor --target '$TARGET' 2>&1 | tee '$LOG'\""

echo "Nexus deployment started"
echo "  target:  $TARGET"
echo "  session: $SESSION"
echo "  log:     nexus:$LOG"
