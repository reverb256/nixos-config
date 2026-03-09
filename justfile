# NixOS Cluster Deployment — Colmena-based single-source-of-truth

export NIX_SHOW_STATS := "0"
FLAKE_PATH := "/etc/nixos"

# Visual helpers for elegant output
_header:
    #!/usr/bin/env bash
    printf "\033[1;36m▸\033[0m \033[1m%s\033[0m\n" "$1"

_step:
    #!/usr/bin/env bash
    printf "  \033[2;36m◦\033[0m %s\n" "$1"

_done:
    #!/usr/bin/env bash
    printf "  \033[2;32m✓\033[0m %s\n" "$1"

_info:
    #!/usr/bin/env bash
    printf "  \033[2;90m│\033[0m %s\n" "$1"

_time:
    #!/usr/bin/env bash
    printf "\033[2;90m[%s]\033[0m " "$(date +%H:%M:%S)"

_default:
    @just --list

# ──────────────────────────────────────────────────────────────────────────────
#  DEPLOYMENT
# ──────────────────────────────────────────────────────────────────────────────

# Deploy to all hosts
deploy:
    #!/usr/bin/env bash
    {{_time}}; {{_header}} "deploy → all hosts"
    {{_step}} "pre-deploy checks..."
    ./scripts/pre-deploy-check.sh all
    {{_step}} "deploying → zephyr..."
    cd {{FLAKE_PATH}} && nix run .#apps.x86_64-linux.colmena -- apply --on zephyr
    {{_done}} "zephyr"
    {{_step}} "deploying → nexus, forge, sentry..."
    cd {{FLAKE_PATH}} && nix run .#apps.x86_64-linux.colmena -- apply --on nexus,forge,sentry switch
    {{_done}} "all hosts"
    {{_time}}; echo ""

# Deploy to zephyr only
zephyr:
    #!/usr/bin/env bash
    {{_time}}; {{_header}} "deploy → zephyr"
    {{_step}} "pre-deploy checks..."
    ./scripts/pre-deploy-check.sh zephyr
    {{_step}} "deploying..."
    cd {{FLAKE_PATH}} && nix run .#apps.x86_64-linux.colmena -- apply --on zephyr
    {{_done}} "zephyr"
    {{_time}}; echo ""

# Deploy to nexus only
nexus:
    #!/usr/bin/env bash
    {{_time}}; {{_header}} "deploy → nexus"
    {{_step}} "pre-deploy checks..."
    ./scripts/pre-deploy-check.sh nexus
    {{_step}} "deploying..."
    cd {{FLAKE_PATH}} && nix run .#apps.x86_64-linux.colmena -- apply --on nexus switch
    {{_done}} "nexus"
    {{_time}}; echo ""

# Deploy to forge only
forge:
    #!/usr/bin/env bash
    {{_time}}; {{_header}} "deploy → forge"
    {{_step}} "pre-deploy checks..."
    ./scripts/pre-deploy-check.sh forge
    {{_step}} "deploying..."
    cd {{FLAKE_PATH}} && nix run .#apps.x86_64-linux.colmena -- apply --on forge switch
    {{_done}} "forge"
    {{_time}}; echo ""

# Deploy to sentry only
sentry:
    #!/usr/bin/env bash
    {{_time}}; {{_header}} "deploy → sentry"
    {{_step}} "pre-deploy checks..."
    ./scripts/pre-deploy-check.sh sentry
    {{_step}} "deploying..."
    cd {{FLAKE_PATH}} && nix run .#apps.x86_64-linux.colmena -- apply --on sentry switch
    {{_done}} "sentry"
    {{_time}}; echo ""

# ──────────────────────────────────────────────────────────────────────────────
#  LOCAL OPERATIONS
# ──────────────────────────────────────────────────────────────────────────────

# Local switch (mining auto-pauses)
switch:
    #!/usr/bin/env bash
    {{_time}}; {{_header}} "local switch → $(hostname -s)"
    {{_info}} "mining will auto-pause during rebuild"
    cd /etc/nixos && sudo ./scripts/nixos-rebuild-safe.sh switch --flake ".#$(hostname -s)"
    {{_done}} "switch complete"
    {{_time}}; echo ""

# Test configuration (dry run)
test:
    #!/usr/bin/env bash
    {{_time}}; {{_header}} "test → configuration validation"
    {{_step}} "flake check..."
    cd {{FLAKE_PATH}} && nix flake check
    {{_done}} "flake check"
    {{_step}} "build all hosts (dry run)..."
    cd {{FLAKE_PATH}} && nix run .#apps.x86_64-linux.colmena -- build
    {{_done}} "all tests passed"
    {{_time}}; echo ""

# Pre-deployment validation
validate:
    #!/usr/bin/env bash
    {{_time}}; {{_header}} "validate → pre-deployment checks"
    ./scripts/pre-deploy-check.sh all
    {{_done}} "validation complete"
    {{_time}}; echo ""

# ──────────────────────────────────────────────────────────────────────────────
#  UTILITIES
# ──────────────────────────────────────────────────────────────────────────────

# Git status on all nodes
status:
    #!/usr/bin/env bash
    {{_time}}; {{_header}} "git status → all nodes"
    for host in zephyr nexus forge sentry; do
        if [ "$host" = "$(hostname -s)" ]; then
            commit=$(cd {{FLAKE_PATH}} && git log -1 --oneline)
            printf "  \033[2;36m●\033[0m %-8s %s\n" "$host" "$commit"
        elif commit=$(ssh -o ConnectTimeout=2 "$host" "cd /etc/nixos && git log -1 --oneline" 2>/dev/null); then
            printf "  \033[2;32m●\033[0m %-8s %s\n" "$host" "$commit"
        else
            printf "  \033[2;31m●\033[0m %-8s unreachable\n" "$host"
        fi
    done
    echo ""

# Sync all nodes to current branch (DEPRECATED - colmena handles this)
sync:
    #!/usr/bin/env bash
    branch=$(git branch --show-current)
    {{_time}}; {{_header}} "sync → $branch (deprecated)"
    {{_info}} "colmena handles distribution automatically"
    for host in nexus forge sentry; do
        {{_step}} "$host..."
        if ssh "$host" "cd /etc/nixos && git fetch origin && git reset --hard origin/$branch" 2>/dev/null; then
            {{_done}} "$host synced"
        else
            printf "  \033[2;31m✗\033[0m %s unreachable\n" "$host"
        fi
    done
    echo ""

# Cluster connectivity status
cluster-status:
    #!/usr/bin/env bash
    {{_time}}; {{_header}} "cluster status"
    for host in zephyr nexus forge sentry; do
        if [ "$host" = "$(hostname -s)" ]; then
            printf "  \033[2;36m●\033[0m %-8s local\n" "$host"
        elif ssh -o ConnectTimeout=2 "$host" "true" >/dev/null 2>&1; then
            printf "  \033[2;32m●\033[0m %-8s up\n" "$host"
        else
            printf "  \033[2;31m●\033[0m %-8s down\n" "$host"
        fi
    done
    echo ""

# ──────────────────────────────────────────────────────────────────────────────
#  CI/CD
# ──────────────────────────────────────────────────────────────────────────────

# Run CI locally (simulate GitHub Actions)
ci-local:
    #!/usr/bin/env bash
    {{_time}}; {{_header}} "ci → local pipeline"
    {{_step}} "flake check..."
    nix flake check
    {{_step}} "statix lint..."
    statix check . || true
    {{_step}} "deadnix check..."
    deadnix -f . || true
    {{_step}} "build all hosts..."
    nix run .#apps.x86_64-linux.colmena -- build
    {{_done}} "ci passed"
    {{_time}}; echo ""

# Pre-commit on all files
pre-commit-all:
    #!/usr/bin/env bash
    {{_time}}; {{_header}} "pre-commit → all files"
    pre-commit run --all-files
    echo ""

# Update flake.lock
flake-update:
    #!/usr/bin/env bash
    {{_time}}; {{_header}} "flake → update"
    {{_step}} "updating flake.lock..."
    nix flake update
    {{_done}} "updated (run 'just ci-local' to verify)"
    echo ""

# Security scan
security-scan:
    #!/usr/bin/env bash
    {{_time}}; {{_header}} "security → osv scanner"
    {{_step}} "scanning..."
    nix-shell -p osv-scanner --run "osv-scanner --skip-git --recursive"
    echo ""

# CI/CD status info
ci-status:
    #!/usr/bin/env bash
    {{_time}}; {{_header}} "ci → status"
    printf "  pre-commit: %s\n" "$(pre-commit --version 2>/dev/null || echo 'not installed')"
    nix flake metadata 2>/dev/null | grep "Last modified" | sed 's/^/  /' || true
    echo "  recent flake updates:"
    git log --oneline --all --grep="flake" -5 2>/dev/null | sed 's/^/    /' || echo "    none"
    echo ""

# Health check
health-check:
    #!/usr/bin/env bash
    {{_time}}; {{_header}} "health → cluster check"
    scripts/ci/health-check.sh
    echo ""

# Rollback to previous generation
rollback:
    #!/usr/bin/env bash
    {{_time}}; {{_header}} "rollback → previous generation"
    {{_info}} "this will undo the last system switch"
    scripts/deploy/rollback.sh
    echo ""
