# NixOS Cluster Deployment — Streamlined CI/CD
#
# Quick start:
#   just test          # Validate config (fastest)
#   just quick-test    # Test current host only
#   just deploy        # Deploy to all hosts
#   just deploy zephyr # Deploy single host
#   just ci            # Run local CI pipeline
#   just switch        # Apply to current host

# Force real-time output - disable all buffering
export NIX_SHOW_STATS := "0"
export PYTHONUNBUFFERED := "1"
export FLAKE_PATH := "/etc/nixos"
export JUST_HELPERS := "./.just-helpers.sh"
export ZEPHYR_HOST := "zephyr"

_default:
    @just --list

# ──────────────────────────────────────────────────────────────────────────────
#  DEPLOYMENT (Consolidated)
# ──────────────────────────────────────────────────────────────────────────────

# Unified deploy command - handles all deployment scenarios
# Usage: just deploy [target] [--rolling] [--parallel TAG]
deploy target *args:
    #!/usr/bin/env bash
    set -e
    source {{JUST_HELPERS}}
    _time; _header "deploy → {{target}}"

    # IDEMPOTENT: Kill any conflicting builds first
    _kill_conflicting_builds

    # Proxy to zephyr if not already there
    if [ "$(hostname -s)" != "zephyr" ]; then
      _info "proxying to zephyr..."
      ssh {{ZEPHYR_HOST}} "cd {{FLAKE_PATH}} && just deploy {{target}} {{args}}"
      exit $?
    fi

    # Parse flags
    rolling=""
    parallel=""
    for arg in {{args}}; do
        case "$arg" in
            --rolling) rolling="yes" ;;
            --parallel) parallel="yes" ;;
        esac
    done

    # Pre-deploy checks
    _step "pre-deploy checks..."
    ./scripts/pre-deploy-check.sh "{{target}}"

    # Build phase (for rolling or if requested)
    if [ -n "$rolling" ]; then
        _step "building closures for all nodes..."
        cd {{FLAKE_PATH}} && stdbuf -oL -eL nix run .#apps.x86_64-linux.colmena -- build
        _done "all closures built"
    fi

    # Deploy based on target and flags
    if [ "{{target}}" = "all" ] || [ "{{target}}" = "" ]; then
        # Determine deployment order
        if [ -n "$rolling" ]; then
            # K8s-aware rolling order: zephyr (control plane) first
            hosts="zephyr sentry nexus forge"
        else
            hosts="zephyr nexus forge sentry"
        fi

        for host in $hosts; do
            echo ""
            _step "deploying → $host"
            if [ "$host" != "$(hostname -s)" ]; then
                _kill_remote_builds $host
            fi
            cd {{FLAKE_PATH}} && stdbuf -oL -eL nix run .#apps.x86_64-linux.colmena -- apply --on $host
            _done "$host deployed"
        done
    elif [ -n "$parallel" ]; then
        # Parallel deployment by tag
        _header "parallel deploy → {{target}}"
        cd {{FLAKE_PATH}} && stdbuf -oL -eL nix run .#apps.x86_64-linux.colmena -- apply --on @{{target}}
        _done "nodes with tag @{{target}} updated"
    else
        # Single host
        _step "building + deploying → {{target}}"
        if [ "{{target}}" != "$(hostname -s)" ]; then
            _kill_remote_builds {{target}}
        fi
        cd {{FLAKE_PATH}} && stdbuf -oL -eL nix run .#apps.x86_64-linux.colmena -- apply --on {{target}}
        _done "{{target}} deployed"
    fi

    _time; _header "deployment complete"
    echo ""

# Convenience aliases for single-host deployment
# Note: 'just deploy <host>' is preferred for consistency
zephyr:
    @just deploy zephyr

nexus:
    @just deploy nexus

forge:
    @just deploy forge

sentry:
    @just deploy sentry

# ──────────────────────────────────────────────────────────────────────────────
#  TESTING & VALIDATION
# ──────────────────────────────────────────────────────────────────────────────

# Quick test: build current host only (fastest feedback)
quick-test:
    #!/usr/bin/env bash
    source {{JUST_HELPERS}}
    _time; _header "quick-test → $(hostname -s)"

    # IDEMPOTENT: Kill any conflicting builds first
    _kill_conflicting_builds

    host=$(hostname -s)
    _step "evaluating $host configuration..."
    cd {{FLAKE_PATH}}
    if nix eval ".#nixosConfigurations.${host}.config.system.build.toplevel" >/dev/null 2>&1; then
        _done "$host configuration valid"
    else
        _error "$host configuration evaluation failed"
        exit 1
    fi
    _time; echo ""

# Test: build all hosts (full validation)
test:
    #!/usr/bin/env bash
    source {{JUST_HELPERS}}
    _time; _header "test → all hosts"

    # IDEMPOTENT: Kill any conflicting builds first
    _kill_conflicting_builds

    if [ "$(hostname -s)" != "zephyr" ]; then
      _info "proxying to zephyr..."
      ssh {{ZEPHYR_HOST}} "cd {{FLAKE_PATH}} && just test"
      exit $?
    fi
    _step "build all hosts..."
    cd {{FLAKE_PATH}} && stdbuf -oL -eL nix run .#apps.x86_64-linux.colmena -- build
    _done "all tests passed"
    _time; echo ""

# Pre-deployment validation only
validate:
    #!/usr/bin/env bash
    source {{JUST_HELPERS}}
    _time; _header "validate → pre-deployment checks"
    ./scripts/pre-deploy-check.sh all
    _done "validation complete"
    _time; echo ""

# ──────────────────────────────────────────────────────────────────────────────
#  LOCAL OPERATIONS
# ──────────────────────────────────────────────────────────────────────────────

# Local switch (mining auto-pauses via wrapper)
switch:
    #!/usr/bin/env bash
    set -e
    source {{JUST_HELPERS}}
    _time; _header "switch → $(hostname -s)"
    _info "mining will auto-pause during rebuild (CPU only, GPU continues)"

    # IDEMPOTENT: Kill any conflicting builds first
    _kill_conflicting_builds

    # Acquire lock
    if ! _acquire_build_lock; then
      exit 1
    fi

    # Ensure lock is released on exit
    trap '_release_build_lock' EXIT INT TERM

    cd {{FLAKE_PATH}}
    _info "building and applying new configuration..."

    # Use colmena apply-local for switch
    stdbuf -oL -eL colmena apply-local --sudo switch 2>&1
    exit_code=$?
    if [ $exit_code -eq 0 ]; then
        _info "✓ configuration activated"
        _info "new generation: $(readlink /nix/var/nix/profiles/system | xargs basename)"
    else
        echo "✗ rebuild failed with exit code: $exit_code" >&2
        exit $exit_code
    fi

    _done "switch complete"
    _time; echo ""

# ──────────────────────────────────────────────────────────────────────────────
#  CI/CD (Consolidated)
# ──────────────────────────────────────────────────────────────────────────────

# Run local CI pipeline (uses scripts/ci/ci.sh for consistency)
ci:
    #!/usr/bin/env bash
    source {{JUST_HELPERS}}
    _time; _header "ci → local pipeline"

    # IDEMPOTENT: Kill any conflicting builds first
    _kill_conflicting_builds

    if [ "$(hostname -s)" != "zephyr" ]; then
      _info "proxying to zephyr..."
      ssh {{ZEPHYR_HOST}} "cd {{FLAKE_PATH}} && just ci"
      exit $?
    fi

    ./scripts/ci/ci.sh
    _time; echo ""

# Pre-commit on all files
pre-commit-all:
    #!/usr/bin/env bash
    source {{JUST_HELPERS}}
    _time; _header "pre-commit → all files"
    pre-commit run --all-files
    echo ""

# Update flake.lock
flake-update:
    #!/usr/bin/env bash
    source {{JUST_HELPERS}}
    _time; _header "flake → update"
    _step "updating flake.lock..."
    nix flake update
    _done "updated (run 'just ci' to verify)"
    echo ""

# Security scan
security-scan:
    #!/usr/bin/env bash
    source {{JUST_HELPERS}}
    _time; _header "security → osv scanner"
    _step "scanning..."
    nix-shell -p osv-scanner --run "osv-scanner --skip-git --recursive"
    echo ""

# CI/CD status info
ci-status:
    #!/usr/bin/env bash
    source {{JUST_HELPERS}}
    _time; _header "ci → status"
    printf "  pre-commit: %s\n" "$(pre-commit --version 2>/dev/null || echo 'not installed')"
    nix flake metadata 2>/dev/null | grep "Last modified" | sed 's/^/  /' || true
    echo "  recent flake updates:"
    git log --oneline --all --grep="flake" -5 2>/dev/null | sed 's/^/    /' || echo "    none"
    echo ""

# Health check
health-check:
    #!/usr/bin/env bash
    source {{JUST_HELPERS}}
    _time; _header "health → cluster check"
    scripts/ci/health-check.sh
    echo ""

# Rollback to previous generation
rollback:
    #!/usr/bin/env bash
    source {{JUST_HELPERS}}
    _time; _header "rollback → previous generation"
    _info "this will undo the last system switch"
    scripts/deploy/rollback.sh
    echo ""

# Emergency rollback on remote node
rollback-remote host:
    #!/usr/bin/env bash
    source {{JUST_HELPERS}}
    _time; _header "rollback → {{host}}"
    ssh {{host}} "sudo nixos-rebuild rollback"
    _done "{{host}} rolled back to previous generation"
    _time; echo ""

# ──────────────────────────────────────────────────────────────────────────────
#  UTILITIES
# ──────────────────────────────────────────────────────────────────────────────

# Git status on all nodes
status:
    #!/usr/bin/env bash
    source {{JUST_HELPERS}}
    _time; _header "git status → all nodes"
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

# Cluster connectivity status
cluster-status:
    #!/usr/bin/env bash
    source {{JUST_HELPERS}}
    _time; _header "cluster status"
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
# AI INFERENCE
# ──────────────────────────────────────────────────────────────────────────────

# Auto-update LM Studio models
models:
    #!/usr/bin/env bash
    set -e
    source {{JUST_HELPERS}}
    _time; _header "models → auto-update"
    _info "checking for new models and updating gateway..."
    nix-shell -p 'with pkgs; pkgs.python3.withPackages (ps: [ps.httpx])' --run 'python3 {{FLAKE_PATH}}/scripts/auto-update-models.py'
    _done "auto-update complete"
    _time; echo ""

# List available models
models-list:
    #!/usr/bin/env bash
    set -e
    source {{JUST_HELPERS}}
    nix-shell -p 'with pkgs; pkgs.python3.withPackages (ps: [ps.httpx])' --run 'python3 {{FLAKE_PATH}}/scripts/auto-update-models.py --list'
    echo ""

# Dry-run model update
models-dry-run:
    #!/usr/bin/env bash
    set -e
    source {{JUST_HELPERS}}
    _time; _header "models → dry-run"
    nix-shell -p 'with pkgs; pkgs.python3.withPackages (ps: [ps.httpx])' --run 'python3 {{FLAKE_PATH}}/scripts/auto-update-models.py --dry-run'
    echo ""

# Download missing models
models-download:
    #!/usr/bin/env bash
    set -e
    source {{JUST_HELPERS}}
    _time; _header "models → download missing"
    _info "downloading missing models from HuggingFace..."
    nix-shell -p 'with pkgs; pkgs.python3.withPackages (ps: [ps.httpx])' --run 'python3 {{FLAKE_PATH}}/scripts/auto-update-models.py --download'
    _done "download complete"
    _time; echo ""

# Check LM Studio status
models-status:
    #!/usr/bin/env bash
    set -e
    source {{JUST_HELPERS}}
    _time; _header "models → status"
    echo "Checking LM Studio status..."
    curl -s http://127.0.0.1:1234/v1/models -H "Authorization: Bearer $(cat /run/agenix/lm-studio-api-key 2>/dev/null)" | jq -r '.data | length' | xargs -I {} echo "Loaded models: {}"
    echo "Gateway models:"
    curl -s http://127.0.0.1:8080/v1/models 2>/dev/null | jq -r '.data | length' | xargs -I {} echo "Available via gateway: {}"
    _time; echo ""

# Optimize GPU allocation for models
models-optimize:
    #!/usr/bin/env bash
    set -e
    source {{JUST_HELPERS}}
    _time; _header "models → optimize GPU allocation"
    nix-shell -p 'with pkgs; pkgs.python3.withPackages (ps: [ps.httpx])' --run 'python3 {{FLAKE_PATH}}/scripts/manage-models.py'

# Update OpenCode configuration
opencode-update:
    #!/usr/bin/env bash
    set -e
    source {{JUST_HELPERS}}
    _time; _header "opencode → update models"
    _info "fetching models from gateway and updating OpenCode configuration..."
    python3 {{FLAKE_PATH}}/scripts/update-opencode-models.py
    _done "OpenCode configuration updated"
    _time; echo ""

# List OpenCode gateway models
opencode-list:
    #!/usr/bin/env bash
    set -e
    source {{JUST_HELPERS}}
    python3 {{FLAKE_PATH}}/scripts/update-opencode-models.py --list
    echo ""

# Dry-run OpenCode configuration update
opencode-dry-run:
    #!/usr/bin/env bash
    set -e
    source {{JUST_HELPERS}}
    _time; _header "opencode → dry-run"
    python3 {{FLAKE_PATH}}/scripts/update-opencode-models.py --dry-run
    echo ""

# Update models and OpenCode together
models-and-opencode:
    #!/usr/bin/env bash
    set -e
    source {{JUST_HELPERS}}
    _time; _header "models → auto-update + opencode config"
    _info "updating LM Studio models and OpenCode configuration..."
    nix-shell -p 'with pkgs; pkgs.python3.withPackages (ps: [ps.httpx])' --run 'python3 {{FLAKE_PATH}}/scripts/auto-update-models.py --update-opencode'
    _done "models and OpenCode updated"
    _time; echo ""
    _done "optimization complete"
    _time; echo ""

# ──────────────────────────────────────────────────────────────────────────────
# CONTAINER SCANNING
# ──────────────────────────────────────────────────────────────────────────────

# Scan all running containers
scan-containers:
    trivy image --severity HIGH,CRITICAL $(docker ps --format '{{{{.Image}}}}')

# Scan a specific image
scan-image IMAGE:
    trivy image --severity HIGH,CRITICAL {{IMAGE}}

# Scan all Kubernetes pod images
scan-k8s:
    kubectl get pods -A -o jsonpath='{range .items[*]}{.spec.nodeName}{"\t"}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.spec.containers[*].image}{"\n"}{end}' | while read node namespace name images; do for img in $images; do echo "Scanning $namespace/$name: $img"; trivy image --severity HIGH,CRITICAL "$img" || true; done; done
