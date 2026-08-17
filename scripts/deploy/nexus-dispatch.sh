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

  # ── Per-host flock: different targets deploy in PARALLEL; same-target and
  #    --target all serialize. colmena handles multi-host parallelism itself
  #    (--eval-node-limit/--parallel); this lock only prevents two dispatches
  #    racing the same host's switch-to-configuration or the shared checkout.
  #    flock auto-releases on process exit (no stale locks).
  #    Executor runs as j_kro (non-root): /run is root-only, so use the
  #    user-runtime dir (systemd) with /tmp fallback.
  LOCK_DIR="${XDG_RUNTIME_DIR:-/tmp}/nexus-dispatch"
  mkdir -p "$LOCK_DIR" 2>/dev/null || { echo "cannot create lock dir $LOCK_DIR" >&2; exit 1; }
  LOCK_HOSTS=()
  if [[ "$TARGET" == "all" ]]; then
    LOCK_HOSTS=(zephyr nexus forge sentry)
  else
    LOCK_HOSTS=("$TARGET")
  fi
  LOCK_FDS=()
  for h in $(printf '%s\n' "${LOCK_HOSTS[@]}" | sort); do
    exec {fd}>"$LOCK_DIR/$h.lock" || { echo "lock open failed: $h" >&2; exit 1; }
    flock -n "$fd" || {
      echo "Another dispatch to '$h' is running (or --target all). Try again later." >&2
      exit 1
    }
    LOCK_FDS+=("$fd")
  done

  cd "$FLAKE"
  # colmena apply-local --sudo evaluates the flake as root and can create
  # root-owned objects in .git, which then breaks the NEXT deploy's fetch
  # (git unpack-objects: insufficient permission). Normalize before fetching.
  # (The shared checkout is only fetched here; the actual build/deploy runs
  # from a per-dispatch worktree below, so root-owned objects can't poison it.)
  REPO_OWNER="$(stat -c %U "$FLAKE")"
  REPO_GROUP="$(stat -c %G "$FLAKE")"
  if [[ -n "$REPO_OWNER" ]] && [[ "$(find "$FLAKE" -not -user "$REPO_OWNER" 2>/dev/null | head -1)" ]]; then
    sudo chown -R "$REPO_OWNER":"$REPO_GROUP" "$FLAKE" 2>/dev/null || true
  fi
  git fetch origin main

  # ── Per-dispatch worktree: immutable snapshot at origin/main. Two
  #    concurrent executors each build from their OWN tree — no shared
  #    checkout to reset under each other (the old `git reset --hard`
  #    raced: a second dispatch could yank the first's build mid-eval).
  WORKTREE="/tmp/nexus-dispatch-$$"
  git worktree add --detach "$WORKTREE" origin/main
  cd "$WORKTREE"
  CANONICAL="$(git rev-parse --short HEAD)"
  echo "Nexus deployment executor at origin/main: $CANONICAL (worktree $WORKTREE)"
  # Cleanup the worktree on exit (plain return, not exec, so the trap fires).
  trap 'cd /; git -C "$FLAKE" worktree remove --force "$WORKTREE" 2>/dev/null || true' EXIT

  # Use the prebuilt colmena from the store directly. `nix run .#apps...colmena`
  # re-evaluates the flake, which hits the `path:/home/j_kro` permission error
  # on nexus (podman overlay in j_kro's home) and forces a from-source GHC
  # rebuild of colmena's Haskell closure — that build exceeds MemoryMax=45GB
  # and gets OOM-killed (exit 137). The store path below is already built and
  # verified (Colmena 0.5.0-pre). Pin it to avoid the rebuild.
  COLMENA_BIN="$(ls -d /nix/store/*colmena-0.5.0-pre/bin/colmena 2>/dev/null | head -1)"
  if [[ -z "$COLMENA_BIN" ]]; then
    echo "prebuilt colmena not found in store; falling back to nix run" >&2
    NIX_CMD=(nix run --option pure-eval false .#apps.x86_64-linux.colmena --)
  else
    echo "using prebuilt colmena: $COLMENA_BIN"
    NIX_CMD=("$COLMENA_BIN")
  fi

  if [[ "$TARGET" == "nexus" ]]; then
    # nexus is the local executor host (deployment.targetHost = null). colmena
    # `apply` only targets SSH hosts — select_nodes() drops nodes with no
    # targetHost when the goal requires a target host — so the local node must
    # be deployed with `apply-local` (gated by deployment.allowLocalDeployment).
    echo "Deploying local node: nexus (apply-local)"
    # NOTE: apply-local does NOT accept --evaluator (verified); only the
    # remote `apply` path below gets the streaming evaluator.
    "${NIX_CMD[@]}" apply-local --sudo --node nexus
    return
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
    # NOTE: apply-local does NOT accept --evaluator (verified); only the
    # remote `apply` path below gets the streaming evaluator.
    "${NIX_CMD[@]}" apply-local --sudo --node nexus
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
