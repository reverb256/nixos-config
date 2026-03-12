# NixOS Cluster Deployment — Colmena-based single-source-of-truth

export NIX_SHOW_STATS := "0"
FLAKE_PATH := "/etc/nixos"
JUST_HELPERS := "./.just-helpers.sh"

_default:
    @just --list

# ──────────────────────────────────────────────────────────────────────────────
#  DEPLOYMENT
# ──────────────────────────────────────────────────────────────────────────────

# Deploy to all hosts
deploy:
    #!/usr/bin/env bash
    set -e
    source {{JUST_HELPERS}}
    _time; _header "deploy → all hosts"
    _step "pre-deploy checks..."
    ./scripts/pre-deploy-check.sh all

    # Deploy sequentially - colmena output goes directly to terminal
    for host in zephyr nexus forge sentry; do
        echo ""
        _step "building + deploying → $host"
        cd {{FLAKE_PATH}} && nix run .#apps.x86_64-linux.colmena -- apply --on $host
        _done "$host deployed"
    done

    _time; _header "all deployments complete"
    echo ""

# Deploy to zephyr only
zephyr:
    #!/usr/bin/env bash
    set -e
    source {{JUST_HELPERS}}
    _time; _header "deploy → zephyr"
    _step "pre-deploy checks..."
    ./scripts/pre-deploy-check.sh zephyr
    _step "building + deploying..."
    if cd {{FLAKE_PATH}} && nix run .#apps.x86_64-linux.colmena -- apply --on zephyr 2>&1; then
        _done "zephyr deployed successfully"
    else
        exit_code=$?
        echo "✗ deployment failed with exit code: $exit_code" >&2
        exit $exit_code
    fi
    _time; echo ""

# Deploy to nexus only
nexus:
    #!/usr/bin/env bash
    set -e
    source {{JUST_HELPERS}}
    _time; _header "deploy → nexus"
    _step "pre-deploy checks..."
    ./scripts/pre-deploy-check.sh nexus
    _step "building + deploying"
    cd {{FLAKE_PATH}} && nix run .#apps.x86_64-linux.colmena -- apply --on nexus
    _done "nexus deployed"
    _time; echo ""

# Deploy to forge only
forge:
    #!/usr/bin/env bash
    set -e
    source {{JUST_HELPERS}}
    _time; _header "deploy → forge"
    _step "pre-deploy checks..."
    ./scripts/pre-deploy-check.sh forge
    _step "building + deploying"
    cd {{FLAKE_PATH}} && nix run .#apps.x86_64-linux.colmena -- apply --on forge
    _done "forge deployed"
    _time; echo ""

# Deploy to sentry only
sentry:
    #!/usr/bin/env bash
    set -e
    source {{JUST_HELPERS}}
    _time; _header "deploy → sentry"
    _step "pre-deploy checks..."
    ./scripts/pre-deploy-check.sh sentry
    _step "building + deploying"
    cd {{FLAKE_PATH}} && nix run .#apps.x86_64-linux.colmena -- apply --on sentry
    _done "sentry deployed"
    _time; echo ""

# Deploy v3 optimizations with K8s-aware rolling update
deploy-v3-rolling:
    #!/usr/bin/env bash
    set -e  # Stop on any error
    source {{JUST_HELPERS}}

    _header "v3 Rolling Update → All Nodes (K8s-Aware Order)"

    # Step 1: Pre-flight validation - build all closures
    _step "building closures for all nodes..."
    cd {{FLAKE_PATH}} && nix run .#apps.x86_64-linux.colmena -- build
    _done "all closures built successfully"

    # Step 2: Deploy to Zephyr (K8s control plane, local)
    _step "deploying → zephyr (k8s-master)"
    cd {{FLAKE_PATH}} && nix run .#apps.x86_64-linux.colmena -- apply-local --on zephyr
    _step "validating K8s control plane..."
    ssh zephyr "kubectl get nodes" || echo "⚠️  K8s not yet installed, skipping validation"
    ssh zephyr "systemctl status apiserver etcd kubelet" || true
    _done "zephyr updated to v3"

    # Step 3: Deploy to remote workers sequentially (K8s order)
    _step "deploying → k8s workers"
    for host in sentry nexus forge; do
        cd {{FLAKE_PATH}} && nix run .#apps.x86_64-linux.colmena -- apply --on $host
        _step "validating $host..."
        ssh $host "kubectl get nodes | grep $host" || echo "⚠️  K8s not yet installed on $host"
        ssh $host "systemctl status kubelet" || true
        _done "$host updated to v3"
    done

    _time; _header "all nodes updated to v3 successfully"

# Deploy by tag (parallel deployment to tagged nodes)
deploy-tag ARG:
    #!/usr/bin/env bash
    set -e
    source {{JUST_HELPERS}}
    _header "deploy → @{{ARG}} (parallel)"
    cd {{FLAKE_PATH}} && nix run .#apps.x86_64-linux.colmena -- apply --on @{{ARG}}
    _done "nodes with tag @{{ARG}} updated"

# Emergency rollback to previous generation on remote node
rollback-remote ARG:
    #!/usr/bin/env bash
    source {{JUST_HELPERS}}
    _time; _header "rollback → {{ARG}}"
    ssh {{ARG}} "sudo nixos-rebuild rollback"
    _done "{{ARG}} rolled back to previous generation"
    _time; echo ""

# ──────────────────────────────────────────────────────────────────────────────
#  LOCAL OPERATIONS
# ──────────────────────────────────────────────────────────────────────────────

# Local switch (mining auto-pauses via wrapper)
switch:
    #!/usr/bin/env bash
    set -e
    source {{JUST_HELPERS}}
    _time; _header "local switch → $(hostname -s)"
    _info "mining will auto-pause during rebuild (CPU only, GPU continues)"

    cd {{FLAKE_PATH}}
    _info "building and applying new configuration..."

    # Use colmena apply-local to switch (bypasses nixos-rebuild wrapper)
    if output=$(colmena apply-local --sudo switch 2>&1); then
        echo "$output"
        _info "✓ configuration activated"
        _info "new generation: $(readlink /nix/var/nix/profiles/system | xargs basename)"
    else
        exit_code=$?
        echo "$output"
        echo "✗ rebuild failed with exit code: $exit_code" >&2
        exit $exit_code
    fi

    _done "switch complete"
    _time; echo ""

# Test configuration (dry run)
test:
    #!/usr/bin/env bash
    source {{JUST_HELPERS}}
    _time; _header "test → configuration validation"
    _step "flake check..."
    cd {{FLAKE_PATH}} && nix flake check
    _done "flake check"
    _step "build all hosts (dry run)..."
    cd {{FLAKE_PATH}} && nix run .#apps.x86_64-linux.colmena -- build
    _done "all tests passed"
    _time; echo ""

# Pre-deployment validation
validate:
    #!/usr/bin/env bash
    source {{JUST_HELPERS}}
    _time; _header "validate → pre-deployment checks"
    ./scripts/pre-deploy-check.sh all
    _done "validation complete"
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

# Sync all nodes to current branch (DEPRECATED - colmena handles this)
sync:
    #!/usr/bin/env bash
    source {{JUST_HELPERS}}
    branch=$(git branch --show-current)
    _time; _header "sync → $branch (deprecated)"
    _info "colmena handles distribution automatically"
    for host in nexus forge sentry; do
        _step "$host..."
        if ssh "$host" "cd /etc/nixos && git fetch origin && git reset --hard origin/$branch" 2>/dev/null; then
            _done "$host synced"
        else
            printf "  \033[2;31m✗\033[0m %s unreachable\n" "$host"
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

# Dry-run model update (no changes)
models-dry-run:
    #!/usr/bin/env bash
    set -e
    source {{JUST_HELPERS}}
    _time; _header "models → dry-run"
    nix-shell -p 'with pkgs; pkgs.python3.withPackages (ps: [ps.httpx])' --run 'python3 {{FLAKE_PATH}}/scripts/auto-update-models.py --dry-run'
    echo ""

# Download missing models (requires huggingface-cli)
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

# Update OpenCode configuration from gateway models
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
# CI/CD
# ──────────────────────────────────────────────────────────────────────────────

# Run CI locally (simulate GitHub Actions)
ci-local:
    #!/usr/bin/env bash
    source {{JUST_HELPERS}}
    _time; _header "ci → local pipeline"
    _step "flake check..."
    nix flake check
    _step "statix lint..."
    statix check . || true
    _step "deadnix check..."
    deadnix -f . || true
    _step "build all hosts..."
    nix run .#apps.x86_64-linux.colmena -- build
    _done "ci passed"
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
    _done "updated (run 'just ci-local' to verify)"
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

# ──────────────────────────────────────────────────────────────────────────────
#  CONTAINER SCANNING
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
