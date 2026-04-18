#!/usr/bin/env bash
# Run all validations for the NixOS cluster configuration
set -euo pipefail

FLAKE="${FLAKE:-/etc/nixos}"
PASS=0
FAIL=0
WARN=0

log() { echo "[$(date +%H:%M:%S)] $*" >&2; }
pass() { log "  ✓ $*"; ((PASS++)); }
fail() { log "  ✗ $*"; ((FAIL++)); }
warn() { log "  ⚠ $*"; ((WARN++)); }

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Run all validations on the NixOS cluster configuration.

OPTIONS:
  --quick     Skip slow checks (colmena build, k8s dry-run)
  -h, --help  Show this help
EOF
}

QUICK=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --quick) QUICK=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1"; usage; exit 1 ;;
  esac
done

cd "$FLAKE"
log "=== Running All Validations ==="

# ── 1. Git status ─────────────────────────────────────────────────────────────
log "Checking git status..."
if git diff --quiet 2>/dev/null && git diff --cached --quiet 2>/dev/null; then
  pass "Git working tree clean"
else
  warn "Git has uncommitted changes"
  git status --short | head -20 | while read line; do log "    $line"; done
fi

# ── 2. Flake check ───────────────────────────────────────────────────────────
log "Running nix flake check..."
if nix flake check 2>&1; then
  pass "nix flake check passed"
else
  fail "nix flake check FAILED"
fi

# ── 3. Colmena eval ──────────────────────────────────────────────────────────
if [[ "$QUICK" -eq 0 ]]; then
  log "Validating colmena configuration (remote hosts)..."
  if nix run .#apps.x86_64-linux.colmena -- build --on nexus,forge,sentry 2>&1; then
    pass "Colmena build (remote hosts) succeeded"
  else
    fail "Colmena build FAILED"
  fi
fi

# ── 4. K8s validation ────────────────────────────────────────────────────────
log "Validating Kubernetes manifests..."
if nix build .#kubernetesManifests 2>/dev/null; then
  if [[ -d result ]]; then
    pass "Kubernetes manifests built successfully"
    if [[ "$QUICK" -eq 0 ]] && command -v kubectl &>/dev/null; then
      if kubectl apply --dry-run=client -f result/ --recursive 2>&1; then
        pass "Kubectl dry-run validation passed"
      else
        fail "Kubectl dry-run validation FAILED"
      fi
    else
      warn "kubectl not found or --quick, skipping dry-run"
    fi
  else
    pass "Kubernetes manifest built (single file)"
  fi
else
  if nix run .#k8s-validate 2>&1; then
    pass "K8s validation (via k8s-validate app) passed"
  else
    warn "Kubernetes manifest build/validation had issues"
  fi
fi

# ── 5. Host connectivity ─────────────────────────────────────────────────────
log "Checking host connectivity..."
for host in nexus forge sentry; do
  if ssh -o ConnectTimeout=5 "$host" "true" 2>/dev/null; then
    pass "$host: reachable"
  else
    warn "$host: unreachable"
  fi
done

# ── 6. K8s cluster health ────────────────────────────────────────────────────
log "Checking Kubernetes cluster health..."
if command -v kubectl &>/dev/null; then
  if kubectl get nodes &>/dev/null; then
    NOT_READY=$(kubectl get nodes --no-headers 2>/dev/null | grep -cv " Ready" || echo "0")
    if [[ "$NOT_READY" -eq 0 ]]; then
      pass "All K8s nodes Ready"
    else
      fail "$NOT_READY K8s node(s) not Ready"
      kubectl get nodes | grep -v " Ready" | while read line; do log "    $line"; done
    fi
  else
    warn "Cannot query K8s API"
  fi
else
  warn "kubectl not found, skipping K8s health check"
fi

# ── Summary ──────────────────────────────────────────────────────────────────
log ""
log "=== Validation Summary ==="
log "  Passed: $PASS"
log "  Failed: $FAIL"
log "  Warnings: $WARN"

if [[ "$FAIL" -gt 0 ]]; then
  log "RESULT: FAIL - fix errors before deploying"
  exit 1
elif [[ "$WARN" -gt 0 ]]; then
  log "RESULT: PASS (with warnings)"
  exit 0
else
  log "RESULT: ALL PASS"
  exit 0
fi
