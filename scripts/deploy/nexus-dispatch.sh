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
#   nexus-dispatch.sh --executor --ref <rev> --target all|zephyr|nexus|forge|sentry
#
# The executor always fetches and hard-resets Nexus' checkout to origin/main
# before evaluating the flake (unless --ref overrides the rev — CI passes the
# exact prod SHA it validated). This intentionally refuses to deploy an
# unpushed local worktree or a drifted Nexus checkout.

set -euo pipefail

FLAKE="${FLAKE:-/etc/nixos}"
TARGET="all"
MODE="sync"
REF="origin/main"

usage() {
  cat <<'EOF'
Usage: nexus-dispatch.sh [MODE] [--target HOST] [--ref REV]

MODE:
  --sync       Run the deployment on Nexus and stream its output (default).
  --async      Start a detached tmux deployment on Nexus and return its log.
  --executor   Internal: execute the deployment locally on Nexus.

HOST:
  all, zephyr, nexus, forge, sentry

REF:
  Rev to deploy (default origin/main). CI passes the prod SHA it validated
  so the executor ships exactly what CI checked, never a newer main.
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
    --ref)
      [[ $# -ge 2 ]] || { echo "--ref requires a rev" >&2; exit 2; }
      REF="$2"
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

  # If CI passed an explicit --ref (prod SHA), ensure it's present locally
  # (GitHub runners check out the full history, so the SHA is already there;
  # a manual --ref on a drifted checkout would fail the verify below).
  if [[ "$REF" != "origin/main" ]]; then
    git rev-parse --verify --quiet "$REF^{commit}" >/dev/null || {
      echo "ERROR: --ref '$REF' is not present in $FLAKE (fetch it first)" >&2
      exit 1
    }
  fi

  # ── Per-dispatch worktree: immutable snapshot at the target rev
  #    (origin/main by default; --ref from CI pins the validated prod SHA).
  #    Two concurrent executors each build from their OWN tree — no shared
  #    checkout to reset under each other (the old `git reset --hard`
  #    raced: a second dispatch could yank the first's build mid-eval).
  WORKTREE="/tmp/nexus-dispatch-$$"
  git worktree add --detach "$WORKTREE" "$REF"
  cd "$WORKTREE"
  CANONICAL="$(git rev-parse --short HEAD)"
  echo "Nexus deployment executor at origin/main: $CANONICAL (worktree $WORKTREE)"
  # Cleanup the worktree on exit (plain return, not exec, so the trap fires).
  trap 'cd /; git -C "$FLAKE" worktree remove --force "$WORKTREE" 2>/dev/null || true' EXIT

  # Preferred path: the flake-locked `nix run` for deploy-rs — declarative,
  # and deploy-rs's closure substitutes from the LAN cache. Use the prebuilt
  # store path only as a fast-path when present (it is NOT a GC root, so
  # nix-gc can remove it at any time — the nix run fallback is the durable
  # path).
  DEPLOY_RS_BIN="$(ls -d /nix/store/*deploy-rs-*/bin/deploy 2>/dev/null | head -1 || true)"
  if [[ -n "$DEPLOY_RS_BIN" ]]; then
    echo "using prebuilt deploy-rs: $DEPLOY_RS_BIN"
    NIX_CMD=("$DEPLOY_RS_BIN")
  else
    echo "prebuilt deploy-rs not in store; using nix run (substitutes from LAN cache)" >&2
    NIX_CMD=(nix run --option pure-eval false .#apps.x86_64-linux.deploy-rs --)
  fi

  # ── COLMENA MACHINES (source of truth, 2026-08-20) ───────────────────
  # colmena's meta.machinesFile points at /tmp/colmena-machines (a stable
  # path written HERE, not baked at eval). This MUST come from
  # lib/build-machines.nix — the single source of truth for the cluster's
  # builder topology (nexus 10, zephyr 10, sentry 9; forge never a builder).
  #
  # Prior bug (2026-08-20, fixed): the old hardcoded probe re-wrote machine
  # lines by hand, (a) including nexus as a SELF-ENTRY — colmena running on
  # nexus dispatched builds back to itself over SSH and deadlocked on store
  # locks (documented at modules/system/distributed-builds.nix:310-319), and
  # (b) dropped zephyr whenever its live max-jobs read 0 (stale deployed
  # config), silently reducing the fleet to a single local builder.
  #
  # Fix: evaluate machinesTextFor "nexus" [] from the flake. That function
  # already excludes the CURRENT host (never self) and uses the declarative
  # topology + pinned host keys. No SSH probing of live max-jobs — the
  # declarative max-jobs/speedFactor in build-machines.nix is authoritative;
  # a builder whose daemon is down will simply not accept work and nix will
  # fall back to the remaining builders, not deadlock.
  write_colmena_machines() {
    local out="/tmp/colmena-machines"
    local machines_text
    # Derive the machines file from lib/build-machines.nix (single source of
    # truth) via the flake package output. machinesTextFor "nexus" [] excludes
    # the current host (never self-entry) and lists zephyr + sentry with
    # declarative max-jobs / speedFactor / pinned host keys.
    machines_text="$(
      nix build --print-out-paths .#packages.x86_64-linux.buildMachinesText 2>&1 \
        | tail -1 \
        | xargs -I{} cat {}
    )"
    if [[ -z "$machines_text" ]]; then
      echo "ERROR: could not generate colmena machines from lib/build-machines.nix" >&2
      exit 1
    fi
    printf '%s\n' "$machines_text" > "$out"
    echo "colmena builders (from lib/build-machines.nix, nexus view):"
    echo "  machines file: $out"
    cat "$out" >&2
  }
  write_colmena_machines

  if [[ "$TARGET" == "nexus" ]]; then
    # nexus is the local executor host. deploy-rs targets nexus by its
    # hostname (10.1.1.120 / null for local); deploy-rs handles the local
    # profile path. Close lock fds BEFORE exec: deploy-rs's child
    # `nix-store --realise` inherits open fds and could deadlock waiting on
    # its own parent's flock (same class as the colmena fd-leak observed
    # 2026-08-17). flock releases when the fd closes, so closing is safe.
    for fd in "${LOCK_FDS[@]:-}"; do eval "exec ${fd}>&-"; done
    "${NIX_CMD[@]}" .#nexus
    return
  fi

  # deploy-rs: deploy each target (or all hosts for --target all).
  # deploy-rs's magicRollback + autoRollback handle per-host safety.
  if [[ "$TARGET" == "all" ]]; then
    echo "Deploying all targets via deploy-rs"
    # Close lock fds BEFORE exec (same fd-leak class as above).
    for fd in "${LOCK_FDS[@]:-}"; do eval "exec ${fd}>&-"; done
    for h in zephyr nexus forge sentry; do
      "${NIX_CMD[@]}" .#"$h" || { echo "deploy-rs failed for $h"; exit 1; }
    done
  else
    echo "Deploying target: $TARGET via deploy-rs"
    # Close lock fds BEFORE exec (same fd-leak class as above).
    for fd in "${LOCK_FDS[@]:-}"; do eval "exec ${fd}>&-"; done
    "${NIX_CMD[@]}" .#"$TARGET"
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
