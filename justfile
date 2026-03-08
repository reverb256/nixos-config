# NixOS Cluster Deployment - Single-Source-of-Truth Colmena
# All deployment managed centrally from zephyr

export NIX_SHOW_STATS := "0"
FLAKE_PATH := "/etc/nixos"

_default:
    @just --list

# ============================================================================
# CRITICAL: Pre-deployment verification
# ============================================================================
verify-db:
    @echo "Checking distributed builds..."
    @sudo nix-show-config 2>/dev/null | grep -A 10 "builders" || echo "No builders configured"

# ============================================================================
# DEPLOYMENT COMMANDS
# ============================================================================
# Deploy to all hosts via colmena
# Note: Remote hosts use 'boot' goal to avoid switch inhibitors (e.g., dbus changes)
deploy:
    just verify-db
    @echo "Deploying to all hosts..."
    @echo "Deploying to zephyr (local)..."
    cd {{FLAKE_PATH}} && nix run .#apps.x86_64-linux.colmena -- apply --on zephyr
    @echo "Deploying to remote hosts (nexus, forge, sentry)..."
    cd {{FLAKE_PATH}} && nix run .#apps.x86_64-linux.colmena -- apply --on nexus,forge,sentry boot

# Deploy to zephyr only
zephyr:
    @echo "Deploying to zephyr..."
    cd {{FLAKE_PATH}} && nix run .#apps.x86_64-linux.colmena -- apply --on zephyr

# Deploy to nexus only
nexus:
    @echo "Deploying to nexus..."
    cd {{FLAKE_PATH}} && nix run .#apps.x86_64-linux.colmena -- apply --on nexus boot

# Deploy to forge only
forge:
    @echo "Deploying to forge..."
    cd {{FLAKE_PATH}} && nix run .#apps.x86_64-linux.colmena -- apply --on forge boot

# Deploy to sentry only
sentry:
    @echo "Deploying to sentry..."
    cd {{FLAKE_PATH}} && nix run .#apps.x86_64-linux.colmena -- apply --on sentry boot

# ============================================================================
# LOCAL OPERATIONS (no colmena)
# ============================================================================
# Local switch (current host only) - pauses mining automatically
switch:
    @echo "Switching local system (mining will auto-pause)..."
    cd /etc/nixos && sudo ./scripts/nixos-rebuild-safe.sh switch --flake ".#$(hostname -s)"

# Test configuration (dry run)
test:
    @echo "Testing configuration..."
    cd {{FLAKE_PATH}} && nix flake check
    @echo "Building all hosts (dry run)..."
    cd {{FLAKE_PATH}} && nix run .#apps.x86_64-linux.colmena -- build

# ============================================================================
# UTILITIES
# ============================================================================
# Show git status on all nodes
status:
    @echo "Git status on all nodes..."
    @echo "=== ZEPHYR (local) ==="
    @cd {{FLAKE_PATH}} && git log -1 --oneline
    @for host in nexus forge sentry; do \
        echo "=== $$host ==="; \
        ssh $$host "cd /etc/nixos && git log -1 --oneline" 2>/dev/null || echo "  unreachable"; \
    done

# Sync all repos to current branch
sync:
    @echo "Syncing all nodes to $(git branch --show-current)..."
    @for host in nexus forge sentry; do \
        echo "Syncing $$host..."; \
        ssh $$host "cd /etc/nixos && git fetch origin && git reset --hard origin/$(git branch --show-current)" 2>/dev/null || true; \
    done

# Show cluster status
cluster-status:
    #!/usr/bin/env bash
    # Show connectivity status of all cluster nodes
    set -euo pipefail
    echo "Cluster Status:"
    for host in zephyr nexus forge sentry; do
        printf "%s: " "$host"
        if [ "$host" = "$(hostname -s)" ]; then
            echo "local"
        else
            if ssh -o ConnectTimeout=2 "$host" "true" >/dev/null 2>&1; then
                echo "up"
            else
                echo "down"
            fi
        fi
    done

# ============================================================================
# CI/CD - Local & Remote
# ============================================================================
# Run CI locally (simulate GitHub Actions)
ci-local:
    @echo "Running local CI..."
    @echo "→ Quick check..."
    nix flake check
    @echo "→ Linting..."
    statix check . || true
    deadnix -f . || true
    @echo "→ Building all hosts..."
    nix run .#apps.x86_64-linux.colmena -- build
    @echo "✅ Local CI passed!"

# Run pre-commit checks on all files
pre-commit-all:
    @echo "Running pre-commit on all files..."
    pre-commit run --all-files

# Update flake.lock
flake-update:
    @echo "Updating flake.lock..."
    nix flake update
    @echo "✓ Flake updated. Run 'just ci-local' to verify."

# Security scan locally
security-scan:
    @echo "Running security scan..."
    nix-shell -p osv-scanner --run "osv-scanner --skip-git --recursive"

# ============================================================================
# CI/CD Status
# ============================================================================
# Show CI/CD status
ci-status:
    @echo "=== CI/CD Status ==="
    @echo ""
    @echo "Pre-commit:"
    @pre-commit --version 2>/dev/null || echo "  Not installed"
    @echo ""
    @echo "Flake inputs age:"
    @nix flake metadata | grep "Last modified" || true
    @echo ""
    @echo "Recent flake updates:"
    @git log --oneline --all --grep="flake" -5 || echo "  None found"

# ============================================================================
# CI/CD Utilities
# ============================================================================
# Cluster health check
health-check:
    scripts/ci/health-check.sh

# Rollback to previous generation
rollback:
    scripts/deploy/rollback.sh
