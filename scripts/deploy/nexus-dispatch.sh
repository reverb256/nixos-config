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
if [[ -n "${CANARY_TOKEN_B64:-}" ]]; then
  CANARY_TOKEN="$(printf '%s' "$CANARY_TOKEN_B64" | base64 -d)"
fi
if [[ -n "${DEPLOY_CANARY_LOCK_DIR_B64:-}" ]]; then
  DEPLOY_CANARY_LOCK_DIR="$(printf '%s' "$DEPLOY_CANARY_LOCK_DIR_B64" | base64 -d)"
fi

usage() {
  cat <<'EOF'
Usage: nexus-dispatch.sh [MODE] [--target HOST]

MODE:
  --sync       Run the deployment on Nexus and stream its output (default).
  --async      Start a detached tmux deployment on Nexus and return its log.
  --executor   Internal: execute the deployment locally on Nexus.

HOST:
  all, zephyr, nexus, forge, sentry

Environment:
  DEPLOY_LOCK_FILE   Override the single-flight lock path.
  DEPLOY_RESULT_DIR  Override the persistent JSON result directory.
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

  local lock_file result_dir run_id result_file start_time end_time
  local deploy_status="failed" deploy_rc=1 canonical="UNKNOWN"
  local evidence_json="{}" evidence_status="complete"
  local error_code="not-started"

  lock_file="${DEPLOY_LOCK_FILE:-/tmp/nixos-cluster-deploy.lock}"
  result_dir="${DEPLOY_RESULT_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/nixos-deploy}"
  start_time="$(date --iso-8601=seconds)"
  run_id="$(date +%Y%m%dT%H%M%S)-${TARGET}-${BASHPID:-$$}"
  result_file="$result_dir/$run_id.json"

  exec 9>"$lock_file" || {
    echo "cannot open deployment lock: $lock_file" >&2
    exit 1
  }
  if ! flock -n 9; then
    echo "deployment already running on Nexus (lock: $lock_file)" >&2
    exit 75
  fi
  echo "Nexus deployment lock acquired: $lock_file"
  canary_lock_dir="${DEPLOY_CANARY_LOCK_DIR:-/tmp/nixos-canary-rollout.lock.d}"
  if [[ -d "$canary_lock_dir" ]]; then
    canary_owner="$(cat "$canary_lock_dir/owner" 2>/dev/null || true)"
    if [[ -z "${CANARY_TOKEN:-}" || "$canary_owner" != "$CANARY_TOKEN" ]]; then
      error_code="canary-rollout-active"
      echo "another canary rollout owns Nexus (lock: $canary_lock_dir)" >&2
      return 75
    fi
    echo "Nexus canary rollout lock validated"
  fi
  if ! command -v jq >/dev/null 2>&1; then
    error_code="jq-missing"
    echo "jq is required for durable deployment result evidence" >&2
    return 1
  fi

  json_generation_evidence() {
    local host="$1" generation host_commit commit_matches_canonical
    if [[ "$host" == "nexus" ]]; then
      generation="$(readlink -f /run/current-system 2>/dev/null || true)"
      host_commit="$(git rev-parse --short HEAD 2>/dev/null || true)"
    else
      generation="$(ssh -o BatchMode=yes -o ConnectTimeout=10 "$host" \
        "readlink -f /run/current-system" 2>/dev/null || true)"
      host_commit="$(ssh -o BatchMode=yes -o ConnectTimeout=10 "$host" \
        "git -C /etc/nixos rev-parse --short HEAD 2>/dev/null" 2>/dev/null || true)"
    fi
    if [[ -z "$generation" || "$generation" != /nix/store/* || -z "$host_commit" ]]; then
      echo "unable to capture active generation and checkout commit for $host" >&2
      return 1
    fi
    commit_matches_canonical=false
    if [[ "$host_commit" == "$canonical" ]]; then
      commit_matches_canonical=true
    else
      evidence_status="incomplete"
      error_code="commit-provenance-mismatch"
      echo "WARNING: $host checkout commit $host_commit differs from canonical $canonical" >&2
    fi
    evidence_json="$(jq -cn --argjson current "$evidence_json" --arg host "$host" --arg generation "$generation" --arg commit "$host_commit" --argjson matches "$commit_matches_canonical" '$current + {($host): {generation: $generation, commit: $commit, commit_matches_canonical: $matches}}')"
  }

  capture_generation_evidence() {
    local host
    if [[ "$TARGET" == "all" ]]; then
      for host in zephyr forge sentry nexus; do
        json_generation_evidence "$host" || return 1
      done
    else
      json_generation_evidence "$TARGET" || return 1
    fi
  }

  write_result() {
    local status="$1" rc="$2" message="$3"
    end_time="$(date --iso-8601=seconds)"
    mkdir -p "$result_dir" || {
      echo "cannot create deployment result directory: $result_dir" >&2
      return 1
    }
    local tmp="$result_file.tmp"
    jq -n \
      --arg run_id "$run_id" \
      --arg target "$TARGET" \
      --arg canonical_commit "$canonical" \
      --arg status "$status" \
      --arg evidence_status "$evidence_status" \
      --arg started_at "$start_time" \
      --arg finished_at "$end_time" \
      --arg message "$message" \
      --argjson exit_code "$rc" \
      --argjson active_generations "$evidence_json" \
      '{schema: 1, run_id: $run_id, target: $target, canonical_commit: $canonical_commit, status: $status, evidence_status: $evidence_status, exit_code: $exit_code, started_at: $started_at, finished_at: $finished_at, message: $message, active_generations: $active_generations}' >"$tmp" || {
        echo "cannot encode deployment result JSON: $result_file" >&2
        rm -f "$tmp"
        return 1
      }
    mv -f "$tmp" "$result_file" || {
      echo "cannot persist deployment result: $result_file" >&2
      rm -f "$tmp"
      return 1
    }
    echo "Deployment result: $result_file"
  }

  finish() {
    local rc="$?"
    set +e
    if [[ "$deploy_status" == "success" && "$rc" -eq 0 ]]; then
      deploy_rc=0
    else
      # Preserve lock contention and the exact deployment failure code.
      deploy_rc="$rc"
    fi
    if ! write_result "$deploy_status" "$deploy_rc" "$error_code"; then
      echo "ERROR: deployment result persistence failed; inspect the deployment log" >&2
      if [[ "$deploy_rc" -eq 0 ]]; then
        deploy_rc=74
      fi
    fi
    trap - EXIT
    exit "$deploy_rc"
  }
  trap finish EXIT

  cd "$FLAKE"
  git fetch origin main || {
    error_code="git-fetch-failed"
    return 1
  }
  git reset --hard origin/main || {
    error_code="git-reset-failed"
    return 1
  }

  canonical="$(git rev-parse --short HEAD)"
  echo "Nexus deployment executor at origin/main: $canonical"

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
    if ! "${NIX_CMD[@]}" apply-local --sudo --node nexus; then
      error_code="colmena-apply-local-failed"
      return 1
    fi
  else
    CMD=(
      "${NIX_CMD[@]}"
      apply
      --eval-node-limit 100
    )
    if [[ "$TARGET" != "all" ]]; then
      CMD+=(--on "$TARGET")
    fi

    echo "Deploying remote target: $TARGET"
    if ! "${CMD[@]}"; then
      error_code="colmena-apply-failed"
      return 1
    fi

    # `apply` skips the local node (targetHost = null); deploy it last so the
    # executor host converges with the rest of the fleet.
    if [[ "$TARGET" == "all" ]]; then
      echo "Deploying local node: nexus (apply-local)"
      if ! "${NIX_CMD[@]}" apply-local --sudo --node nexus; then
        error_code="colmena-apply-local-failed"
        return 1
      fi
    fi
  fi

  deploy_status="success"
  error_code="ok"
  if ! capture_generation_evidence; then
    evidence_status="incomplete"
    error_code="generation-evidence-incomplete"
    echo "WARNING: deployment completed, but active-generation evidence is incomplete" >&2
  fi
  return 0
}

if [[ "$MODE" == "executor" ]]; then
  if executor; then
    exit 0
  else
    rc=$?
    exit "$rc"
  fi
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
  if [[ -n "${CANARY_TOKEN:-}" ]]; then
    token_b64="$(printf '%s' "$CANARY_TOKEN" | base64 -w0)"
    lock_dir_b64="$(printf '%s' "${DEPLOY_CANARY_LOCK_DIR:-/tmp/nixos-canary-rollout.lock.d}" | base64 -w0)"
    exec ssh nexus \
      env "CANARY_TOKEN_B64=$token_b64" \
      "DEPLOY_CANARY_LOCK_DIR_B64=$lock_dir_b64" \
      "DEPLOY_TARGET=$TARGET" \
      bash --norc --noprofile -s <<'REMOTE_EXECUTOR'
set -euo pipefail
cd /etc/nixos
exec ./scripts/deploy/nexus-dispatch.sh --executor --target "$DEPLOY_TARGET"
REMOTE_EXECUTOR
  fi
  exec ssh nexus \
    bash --norc --noprofile -s <<REMOTE_EXECUTOR
set -euo pipefail
cd /etc/nixos
exec ./scripts/deploy/nexus-dispatch.sh --executor --target "$TARGET"
REMOTE_EXECUTOR
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
  env "DEPLOY_TARGET=$TARGET" "DEPLOY_SESSION=$SESSION" "DEPLOY_LOG=$LOG" \
  bash --norc --noprofile -s <<'REMOTE_ASYNC'
set -euo pipefail
tmux new-session -d -s "$DEPLOY_SESSION" "cd /etc/nixos && ./scripts/deploy/nexus-dispatch.sh --executor --target '$DEPLOY_TARGET' 2>&1 | tee '$DEPLOY_LOG'"
REMOTE_ASYNC

echo "Nexus deployment started"
echo "  target:  $TARGET"
echo "  session: $SESSION"
echo "  log:     nexus:$LOG"
