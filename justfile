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
deploy:
    just verify-db
    @echo "Deploying to all hosts..."
    cd {{FLAKE_PATH}} && sudo -E nix run .#apps.x86_64-linux.colmena -- apply --on @all --keep-result

# Deploy to zephyr only
zephyr:
    @echo "Deploying to zephyr..."
    cd {{FLAKE_PATH}} && sudo -E nix run .#apps.x86_64-linux.colmena -- apply --on zephyr

# Deploy to nexus only
nexus:
    @echo "Deploying to nexus..."
    cd {{FLAKE_PATH}} && sudo -E nix run .#apps.x86_64-linux.colmena -- apply --on nexus

# Deploy to forge only
forge:
    @echo "Deploying to forge..."
    cd {{FLAKE_PATH}} && sudo -E nix run .#apps.x86_64-linux.colmena -- apply --on forge

# Deploy to sentry only
sentry:
    @echo "Deploying to sentry..."
    cd {{FLAKE_PATH}} && sudo -E nix run .#apps.x86_64-linux.colmena -- apply --on sentry

# ============================================================================
# LOCAL OPERATIONS (no colmena)
# ============================================================================
# Local switch (current host only)
switch:
    @echo "Switching local system..."
    cd /etc/nixos && sudo nixos-rebuild switch --flake ".#$(hostname -s)"

# Test configuration (dry run)
test:
    @echo "Testing configuration..."
    cd {{FLAKE_PATH}} && nix flake check
    @echo "Building all hosts (dry run)..."
    cd {{FLAKE_PATH}} && sudo -E nix run .#apps.x86_64-linux.colmena -- build

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
