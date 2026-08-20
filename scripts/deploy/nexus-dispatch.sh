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

  # Preferred path: the flake-locked `nix run` — declarative, and colmena's
  # closure substitutes from the LAN cache (verified: signed zephyr-cache-1,
  # ~170MB) so no from-source GHC rebuild is needed. Use the prebuilt store
  # path only as a fast-path when present (it is NOT a GC root, so nix-gc can
  # remove it at any time — the nix run fallback is the durable path).
  #
  # NOTE on history: an earlier comment claimed `nix run` OOMs nexus (GHC
  # rebuild over MemoryMax=45GB, exit 137) and pinned the store path. That was
  # a cold-cache one-off; once the closure is in the LAN cache it substitutes.
  COLMENA_BIN="$(ls -d /nix/store/*colmena-0.5.0-pre/bin/colmena 2>/dev/null | head -1 || true)"
  if [[ -n "$COLMENA_BIN" ]]; then
    echo "using prebuilt colmena: $COLMENA_BIN"
    NIX_CMD=("$COLMENA_BIN")
  else
    echo "prebuilt colmena not in store; using nix run (substitutes from LAN cache)" >&2
    NIX_CMD=(nix run --option pure-eval false .#apps.x86_64-linux.colmena --)
  fi

  # ── SELF-HEALING BUILDER PROBE (2026-08-20) ────────────────────────────
  # colmena's meta.machinesFile points at /tmp/colmena-machines (a stable
  # path written HERE, not baked at eval). Probe each declared remote
  # builder's LIVE max-jobs; drop any builder whose daemon refuses remote
  # builds (max-jobs=0, e.g. zephyr's stale config before its deploy
  # lands). Without this, colmena dispatches to a dead builder and the
  # whole deploy fails with "unable to start any build; remote machines may
  # not have all required system features".
  #
  # Builders (from lib/build-machines.nix, nexus view): zephyr, sentry.
  # forge is never a builder (GPU miner). The probe reads the daemon's
  # EFFECTIVE max-jobs (nix show-config as the builder's j_kro, which
  # reports the daemon value for a daemon-restricted setting).
  write_colmena_machines() {
    local builders=("zephyr" "sentry")
    local out="/tmp/colmena-machines"
    : > "$out"
    local healthy=""
    for b in "${builders[@]}"; do
      local mj
      mj=$(ssh -o ConnectTimeout=5 -o BatchMode=yes "$b" 'nix show-config 2>/dev/null | awk "/^max-jobs/ {print \$3}"' 2>/dev/null || echo 0)
      if [[ "${mj:-0}" -gt 0 ]]; then
        healthy="$healthy $b(max-jobs=$mj)"
        # Machine line (8-col format with host key). Keep in sync with
        # lib/build-machines.nix formatMachine.
        case "$b" in
          zephyr)
            echo "ssh-ng://j_kro@zephyr x86_64-linux /home/j_kro/.ssh/id_ed25519 3 10 big-parallel,kvm - c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUEwL3BUWGEvSDdtdnkzK1lQSnE5VTJtRktPNCtZckxTT1lkOHNQVTQ0K3Egcm9vdEB6ZXBoeXIK" >> "$out"
            ;;
          sentry)
            echo "ssh-ng://j_kro@sentry x86_64-linux /home/j_kro/.ssh/id_ed25519 2 10 big-parallel,kvm - c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSU1wdmhXZkhxM0tWa3doZGxXOEdva1RMdzVQMFFtVUVaTUdhdWFqOG1hSlUgcm9vdEBzZW50cnkK" >> "$out"
            ;;
        esac
      else
        echo "  WARN: builder $b has max-jobs=$mj — excluded from colmena builders" >&2
      fi
    done
    echo "colmena builders (self-healed):$healthy"
    echo "  machines file: $out"
    cat "$out" >&2
  }
  write_colmena_machines

  if [[ "$TARGET" == "nexus" ]]; then
    # nexus is the local executor host (deployment.targetHost = null). colmena
    # `apply` only targets SSH hosts — select_nodes() drops nodes with no
    # targetHost when the goal requires a target host — so the local node must
    # be deployed with `apply-local` (gated by deployment.allowLocalDeployment).
    echo "Deploying local node: nexus (apply-local)"
    # NOTE: apply-local does NOT accept --evaluator (verified); only the
    # remote `apply` path below gets the streaming evaluator.
    # Close lock fds BEFORE exec: colmena's child `nix-store --realise`
    # inherits open fds and deadlocks waiting on its own parent's flock
    # (observed 2026-08-17: 54-min hang, empty nexus.lock, realise in
    # ep_poll). flock releases when the fd closes, so closing here is safe.
    for fd in "${LOCK_FDS[@]:-}"; do eval "exec ${fd}>&-"; done
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
  # Close lock fds BEFORE exec (same fd-leak deadlock as apply-local above).
  for fd in "${LOCK_FDS[@]:-}"; do eval "exec ${fd}>&-"; done
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
if ! run_preflight; then
    echo "Preflight BLOCKED deploy (drift or in-flight build). Fix and retry." >&2
    exit 1
fi

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
