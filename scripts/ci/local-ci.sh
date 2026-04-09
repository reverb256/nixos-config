#!/usr/bin/env bash
set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()    { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*"; }
die()         { log_error "$*"; exit 1; }

echo "=== Local CI Pipeline ==="
echo ""

cd /etc/nixos

# Step 1: Quick check
log_info "Step 1: Quick flake check..."
nix flake check || die "Flake check failed"

# Step 2: Linting
log_info "Step 2: Linting Nix files..."
if command -v statix &>/dev/null; then
    statix check . || log_warn "Statix found issues"
else
    log_warn "statix not installed, skipping..."
fi

if command -v deadnix &>/dev/null; then
    deadnix -f . || log_warn "Deadnix found issues"
else
    log_warn "deadnix not installed, skipping..."
fi

# Step 3: Security scan
log_info "Step 3: Security scan..."
if command -v osv-scanner &>/dev/null; then
    osv-scanner --skip-git --recursive || log_warn "Security scan found issues"
else
    log_warn "osv-scanner not installed, skipping..."
fi

# Step 4: Build
log_info "Step 4: Building all hosts..."
nix run .#apps.x86_64-linux.colmena -- build || die "Build failed"

# Step 5: Service tests
log_info "Step 5: Checking services..."
if systemctl is-active --quiet ai-inference-gateway 2>/dev/null; then
    curl -f http://127.0.0.1:8080/health >/dev/null 2>&1 && log_info "AI Gateway: OK" || log_warn "AI Gateway: DOWN"
else
    log_warn "AI Gateway: not running"
fi

echo ""
log_info "✅ Local CI passed!"
