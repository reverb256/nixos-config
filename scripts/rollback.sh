#!/usr/bin/env bash
# Unified rollback for OS and K8s
set -euo pipefail

FLAKE="${FLAKE:-/etc/nixos}"
ROLLBACK_DIR="/var/lib/nixos-deploy/rollbacks"

log() { echo "[$(date +%H:%M:%S)] $*" >&2; }
die() { log "ERROR: $*"; exit 1; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] [TIMESTAMP]

Rollback NixOS and/or Kubernetes to a previous deployment state.

TIMESTAMP:
  Specific rollback timestamp (e.g., 20260418-045600)
  If omitted, uses the latest rollback snapshot.

OPTIONS:
  --os-only        Only rollback OS configuration
  --k8s-only       Only rollback Kubernetes manifests
  --list           List available rollback snapshots
  -h, --help       Show this help

Examples:
  $(basename "$0")                        # Rollback latest (OS + K8s)
  $(basename "$0") --os-only              # Rollback OS only
  $(basename "$0") --list                 # Show available rollbacks
  $(basename "$0") 20260418-045600        # Rollback to specific snapshot
EOF
}

# ── Parse args ────────────────────────────────────────────────────────────────
OS_ONLY=0
K8S_ONLY=0
LIST_ONLY=0
TIMESTAMP=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --os-only)   OS_ONLY=1; shift ;;
    --k8s-only)  K8S_ONLY=1; shift ;;
    --list)      LIST_ONLY=1; shift ;;
    -h|--help)   usage; exit 0 ;;
    *)           TIMESTAMP="$1"; shift ;;
  esac
done

# ── List mode ─────────────────────────────────────────────────────────────────
if [[ "$LIST_ONLY" -eq 1 ]]; then
  log "Available rollback snapshots:"
  if [[ ! -d "$ROLLBACK_DIR" ]]; then
    log "  No rollback snapshots found."
    exit 0
  fi
  for env_file in $(ls -t "$ROLLBACK_DIR"/rollback-*.env 2>/dev/null || true); do
    ts=$(basename "$env_file" | sed 's/rollback-\(.*\)\.env/\1/')
    source "$env_file"
    has_k8s=""
    [[ -d "$ROLLBACK_DIR/k8s-$ts" ]] && has_k8s=" [+K8s]"
    log "  $ts | target=$DEPLOY_TARGET | commit=${GIT_COMMIT:0:8}$has_k8s"
  done
  exit 0
fi

# ── Find rollback snapshot ───────────────────────────────────────────────────
if [[ -z "$TIMESTAMP" ]]; then
  latest=$(ls -t "$ROLLBACK_DIR"/rollback-*.env 2>/dev/null | head -1)
  if [[ -z "$latest" ]]; then
    die "No rollback snapshots found in $ROLLBACK_DIR"
  fi
  TIMESTAMP=$(basename "$latest" | sed 's/rollback-\(.*\)\.env/\1/')
  log "Using latest rollback: $TIMESTAMP"
fi

ROLLBACK_FILE="$ROLLBACK_DIR/rollback-$TIMESTAMP.env"
if [[ ! -f "$ROLLBACK_FILE" ]]; then
  die "Rollback snapshot not found: $ROLLBACK_FILE"
fi

source "$ROLLBACK_FILE"
log "=== Rolling Back ==="
log "Snapshot: $TIMESTAMP | Target: $DEPLOY_TARGET | Commit: ${GIT_COMMIT:0:8}"

DO_OS=1
DO_K8S=1
[[ "$K8S_ONLY" -eq 1 ]] && DO_OS=0
[[ "$OS_ONLY" -eq 1 ]] && DO_K8S=0

# ── Rollback OS ──────────────────────────────────────────────────────────────
if [[ "$DO_OS" -eq 1 ]]; then
  log "Rolling back OS configuration..."

  # Checkout the git commit if available
  if [[ "$GIT_COMMIT" != "unknown" ]] && [[ -d "$FLAKE/.git" ]]; then
    log "  Checking out git commit $GIT_COMMIT..."
    cd "$FLAKE"
    sudo -S -p '' git checkout "$GIT_COMMIT" -- . 2>/dev/null || log "  Warning: Could not checkout git state (may have uncommitted changes)"
  fi

  # Rollback local host
  log "  Rolling back local host..."
  sudo -S -p '' nixos-rebuild rollback || log "  Warning: Local rollback failed or no previous generation"

  # Rollback remote hosts
  case "$DEPLOY_TARGET" in
    all)
      for host in nexus forge sentry; do
        log "  Rolling back $host..."
        ssh -o ConnectTimeout=10 "$host" "sudo nixos-rebuild rollback" 2>/dev/null || log "  Warning: Rollback failed on $host"
      done
      ;;
    zephyr)
      # Already done above
      ;;
    *)
      log "  Rolling back $DEPLOY_TARGET..."
      ssh -o ConnectTimeout=10 "$DEPLOY_TARGET" "sudo nixos-rebuild rollback" 2>/dev/null || log "  Warning: Rollback failed on $DEPLOY_TARGET"
      ;;
  esac

  log "OS rollback complete."
fi

# ── Rollback K8s ─────────────────────────────────────────────────────────────
if [[ "$DO_K8S" -eq 1 ]]; then
  K8S_ROLLBACK_DIR="$ROLLBACK_DIR/k8s-$TIMESTAMP"

  if [[ -d "$K8S_ROLLBACK_DIR" ]]; then
    log "Rolling back Kubernetes manifests..."
    if command -v kubectl &>/dev/null; then
      for manifest in "$K8S_ROLLBACK_DIR"/*.yaml; do
        if [[ -f "$manifest" ]]; then
          ns=$(basename "$manifest" .yaml)
          log "  Restoring namespace: $ns"
          kubectl apply -f "$manifest" 2>/dev/null || log "  Warning: Could not restore $ns"
        fi
      done
      log "K8s rollback complete."
    else
      log "  kubectl not found, skipping K8s rollback."
    fi
  else
    log "No K8s snapshot found for $TIMESTAMP. Attempting generic K8s rollback..."
    if command -v kubectl &>/dev/null; then
      cd "$FLAKE"
      if nix build .#kubernetesManifests 2>/dev/null && [[ -d result ]]; then
        log "  Re-applying current manifests from rolled-back OS config..."
        kubectl apply -f result/ --recursive
      else
        nix run .#k8s-deploy
      fi
    fi
  fi
fi

log "=== Rollback Complete ==="
log "Snapshot: $TIMESTAMP | Target: $DEPLOY_TARGET"
