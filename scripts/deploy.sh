#!/usr/bin/env bash
# Unified deployment pipeline for NixOS cluster
# Validates, deploys OS via colmena, copies closures, applies K8s manifests
set -euo pipefail

FLAKE="${FLAKE:-/etc/nixos}"
REMOTE_NODES="nexus sentry forge"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

log() { echo "[$(date +%H:%M:%S)] $*" >&2; }
die() { log "ERROR: $*"; exit 1; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] [TARGET]

Unified deployment pipeline for the NixOS cluster.

TARGET:
  all       Deploy to all hosts (default)
  zephyr    Deploy only to zephyr (local)
  nexus     Deploy only to nexus
  forge     Deploy only to forge
  sentry    Deploy only to sentry

OPTIONS:
  --skip-check      Skip nix flake check
  --skip-os         Skip colmena OS deployment
  --skip-copy       Skip nix copy to remote nodes
  --skip-k8s        Skip Kubernetes manifest deployment
  --no-rollback     Do not create rollback snapshot
  -h, --help        Show this help

Examples:
  $(basename "$0")                    # Full deploy to all hosts
  $(basename "$0") nexus              # Deploy only to nexus
  $(basename "$0") --skip-k8s all     # OS deploy only, skip K8s
EOF
}

# ── Parse args ────────────────────────────────────────────────────────────────
SKIP_CHECK=0
SKIP_OS=0
SKIP_COPY=0
SKIP_K8S=0
SKIP_CA=0
NO_ROLLBACK=0
TARGET="all"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-check)   SKIP_CHECK=1; shift ;;
    --skip-os)      SKIP_OS=1; shift ;;
    --skip-copy)    SKIP_COPY=1; shift ;;
    --skip-k8s)     SKIP_K8S=1; shift ;;
    --no-rollback)  NO_ROLLBACK=1; shift ;;
    -h|--help)      usage; exit 0 ;;
    all|zephyr|nexus|forge|sentry) TARGET="$1"; shift ;;
    *) die "Unknown argument: $1. Use --help for usage." ;;
  esac
done

cd "$FLAKE"

# ── Phase 0: Pre-flight ──────────────────────────────────────────────────────
log "=== Unified Deployment Pipeline ==="
log "Target: $TARGET"
log "Timestamp: $TIMESTAMP"

# Save current generation for rollback
if [[ "$NO_ROLLBACK" -eq 0 ]]; then
  ROLLBACK_DIR="/var/lib/nixos-deploy/rollbacks"
  sudo -S -p '' mkdir -p "$ROLLBACK_DIR"
  CURRENT_GEN=$(readlink /nix/var/nix/profiles/system || echo "unknown")
  CURRENT_COMMIT=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
  ROLLBACK_FILE="$ROLLBACK_DIR/rollback-$TIMESTAMP.env"
  sudo -S -p '' tee "$ROLLBACK_FILE" >/dev/null <<EOF
DEPLOY_TIMESTAMP=$TIMESTAMP
DEPLOY_TARGET=$TARGET
NIXOS_SYSTEM_LINK=$CURRENT_GEN
GIT_COMMIT=$CURRENT_COMMIT
EOF
  log "Rollback snapshot saved: $ROLLBACK_FILE"
fi

# ── Phase 1: Validate ────────────────────────────────────────────────────────
if [[ "$SKIP_CHECK" -eq 0 ]]; then
  log "Phase 1/4: Validating flake..."
  if ! nix flake check; then
    die "Flake check failed. Fix errors before deploying."
  fi
  log "Flake check passed."
else
  log "Phase 1/4: Skipping validation (--skip-check)"
fi

# ── Phase 2: Deploy OS via colmena ───────────────────────────────────────────
if [[ "$SKIP_OS" -eq 0 ]]; then
  log "Phase 2/4: Deploying OS configuration..."
  case "$TARGET" in
    all)
      nix run .#apps.x86_64-linux.colmena -- apply --on nexus,forge,sentry --verbose
      nix run .#apps.x86_64-linux.colmena -- apply-local --sudo --verbose
      ;;
    zephyr)
      nix run .#apps.x86_64-linux.colmena -- apply-local --sudo --verbose
      ;;
    *)
      nix run .#apps.x86_64-linux.colmena -- apply --on "$TARGET" --verbose
      ;;
  esac
  log "OS deployment complete."
else
  log "Phase 2/4: Skipping OS deployment (--skip-os)"
fi

# ── Phase 3: Copy closures to remote nodes ───────────────────────────────────
if [[ "$SKIP_COPY" -eq 0 ]]; then
  log "Phase 3/4: Copying closures to remote nodes..."
  NODES_TO_COPY=()
  case "$TARGET" in
    all) NODES_TO_COPY=(nexus sentry forge) ;;
    zephyr) NODES_TO_COPY=() ;;  # No remote copy needed for local
    *) NODES_TO_COPY=("$TARGET") ;;
  esac

  if [[ ${#NODES_TO_COPY[@]} -gt 0 ]]; then
    for node in "${NODES_TO_COPY[@]}"; do
      log "  Copying closure to $node..."
      nix copy --to "ssh://$node" \
        "$(nix eval --raw ".#nixosConfigurations.$node.config.system.build.toplevel" 2>/dev/null || true)" \
        2>/dev/null || log "  Warning: Could not copy closure to $node (may already exist)"
    done
  else
    log "  No remote nodes to copy to."
  fi
  log "Closure copy complete."
else
  log "Phase 3/4: Skipping closure copy (--skip-copy)"
fi

# ── Phase 4: Deploy K8s manifests ────────────────────────────────────────────
if [[ "$SKIP_K8S" -eq 0 ]]; then
  log "Phase 4/4: Deploying Kubernetes manifests..."

  # Save current K8s state for rollback
  if [[ "$NO_ROLLBACK" -eq 0 ]] && command -v kubectl &>/dev/null; then
    K8S_ROLLBACK_DIR="$ROLLBACK_DIR/k8s-$TIMESTAMP"
    sudo -S -p '' mkdir -p "$K8S_ROLLBACK_DIR"
    for ns in $(kubectl get ns -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true); do
      kubectl get all -n "$ns" -o yaml 2>/dev/null | sudo -S -p '' tee "$K8S_ROLLBACK_DIR/$ns.yaml" >/dev/null || true
    done
    log "  K8s state snapshot saved to $K8S_ROLLBACK_DIR"
  fi

  # Build and apply manifests via easykubenix
  if nix build .#kubernetesManifests 2>/dev/null; then
    if [[ -d result ]]; then
      kubectl apply -f result/ --recursive
      log "  K8s manifests applied from nix build."
    else
      if [[ -f result ]]; then
        kubectl apply -f result
        log "  K8s manifest applied."
      fi
    fi
  else
    # Fallback: use the k8s-deploy app from the flake
    log "  kubernetesManifests package not found, using k8s-deploy app..."
    nix run .#k8s-deploy
  fi

  log "K8s deployment complete."
else
  log "Phase 4/4: Skipping K8s deployment (--skip-k8s)"
fi


if [[ "$SKIP_CA" -eq 0 ]]; then
# ── Phase 5: CA certificate verification ─────────────────────────────────────
CA_CERT="/etc/ssl/cluster-ca/ca.crt"
REPO_CERT="$FLAKE/certs/cluster-ca.crt"

log "Phase 5/5: Verifying CA certificate distribution..."

# Determine which hosts to check
case "$TARGET" in
  all) CA_HOSTS="zephyr nexus forge sentry" ;;
  zephyr) CA_HOSTS="zephyr" ;;
  *) CA_HOSTS="$TARGET" ;;
esac

for host in $CA_HOSTS; do
  log "  Checking $host..."

  if [ "$host" = "zephyr" ]; then
    # Local host
    if [ ! -f "$CA_CERT" ]; then
      log "    ⚠ CA cert missing — triggering cluster-ca-init"
      sudo systemctl restart cluster-ca-init.service
    fi
    # Check leaf cert SAN hash (auto-regen mechanism)
    SAN_HASH_FILE="/etc/ssl/cluster-ca/.san-hash"
    if [ -f "$SAN_HASH_FILE" ]; then
      log "    ✓ CA + leaf cert present (SAN hash tracked)"
    else
      log "    ⚠ SAN hash missing — leaf cert will regenerate on next boot"
    fi
    # Check system trust
    if grep -q 'Cluster CA' /etc/ssl/certs/ca-bundle.crt 2>/dev/null; then
      log "    ✓ CA trusted in system bundle"
    else
      log "    ⚠ CA NOT trusted — deploy should fix this"
    fi
  else
    # Remote host
    CA_EXISTS=$(ssh -o ConnectTimeout=5 "$host" "test -f $CA_CERT && echo yes || echo no" 2>/dev/null || echo "no")
    if [ "$CA_EXISTS" = "no" ]; then
      log "    ⚠ CA cert missing — triggering cluster-ca-init"
      ssh -o ConnectTimeout=5 "$host" "sudo systemctl restart cluster-ca-init.service" 2>/dev/null || true
    else
      log "    ✓ CA cert present"
    fi

    # Check if CA is in system trust store
    TRUSTED=$(ssh -o ConnectTimeout=5 "$host" "grep -c 'Cluster CA' /etc/ssl/certs/ca-bundle.crt 2>/dev/null || true" 2>/dev/null || echo "0")
    if [ "${TRUSTED:-0}" -gt 0 ] 2>/dev/null; then
      log "    ✓ CA trusted in system bundle"
    else
      log "    ⚠ CA NOT trusted — deploy should fix this"
    fi

    # Check leaf cert (Caddy hosts only)
    HAS_LEAF=$(ssh -o ConnectTimeout=5 "$host" "test -f /etc/ssl/cluster-ca/leaf.crt && echo yes || echo no" 2>/dev/null || echo "no")
    if [ "$HAS_LEAF" = "yes" ]; then
      log "    ✓ Leaf cert present"
    else
      log "    ℹ No leaf cert (expected if not a Caddy host)"
    fi
  fi
done

# ── Final Summary ────────────────────────────────────────────────────────────

else
  log "Phase 5/5: Skipping CA verification (--skip-ca)"
fi
log "=== Deployment Complete ==="
