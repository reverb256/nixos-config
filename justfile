# NixOS Cluster Deployment — NFS-Based Architecture
#
# Architecture:
#   • Zephyr: Local /etc/nixos (source of truth)
#   • Remote hosts: Read-only NFS mount at /run/nixos-shared
#   • No config sync needed - all hosts share same flake
#
# Quick start:
#   just check         # Validate flake (quick, no build)
#   just check-nfs     # Verify NFS mount health
#   just deploy        # Build + deploy to all hosts
#   just deploy <host> # Build + deploy single host
#   just switch        # Apply to current host (local)
#   just status        # Show cluster status

export FLAKE := "/etc/nixos"

_default:
    @just --list

# ──────────────────────────────────────────────────────────────────────────────
#  NFS MOUNT HEALTH
# ──────────────────────────────────────────────────────────────────────────────

# Check NFS mount health on all remote hosts
# Architecture: All remote hosts read from /run/nixos-shared (NFS from Zephyr)
check-nfs:
    #!/usr/bin/env bash
    set -e
    echo "▸ Checking NFS mount health..."
    for host in nexus forge sentry; do
        echo "  → $host"
        if ssh -o ConnectTimeout=5 $host "mountpoint -q /run/nixos-shared"; then
            # Check if flake.nix is readable
            if ssh -o ConnectTimeout=5 $host "test -f /run/nixos-shared/flake.nix"; then
                echo "    ✓ NFS mount healthy, flake.nix accessible"
            else
                echo "    ⚠ NFS mounted but flake.nix not accessible"
            fi
            # Check fallback cache status
            if ssh -o ConnectTimeout=5 $host "test -f /var/cache/nixos-config/.last-sync"; then
                LAST_SYNC=$(ssh -o ConnectTimeout=5 $host "cat /var/cache/nixos-config/.last-sync")
                echo "    ℹ Fallback cache last sync: $LAST_SYNC"
            fi
        else
            echo "    ✗ NFS mount not available"
            # Check if fallback cache exists
            if ssh -o ConnectTimeout=5 $host "test -f /var/cache/nixos-config/flake.nix"; then
                echo "    ℹ Fallback cache available"
            else
                echo "    ✗ No fallback cache either - host cannot rebuild!"
            fi
        fi
    done

# Show current NFS architecture status
nfs-status:
    #!/usr/bin/env bash
    echo "▸ NixOS Cluster NFS Architecture"
    echo ""
    echo "  Zephyr (10.1.1.110):"
    echo "    • Local /etc/nixos (source of truth)"
    echo "    • Exports via NFS to /run/nixos-shared"
    echo ""
    echo "  Remote hosts (nexus, forge, sentry):"
    echo "    • Read-only mount: /run/nixos-shared (from Zephyr)"
    echo "    • Fallback cache: /var/cache/nixos-config (hourly sync)"
    echo "    • No local config files"
    echo ""
    echo "  Commands:"
    echo "    just check-nfs    # Verify NFS mount health"
    echo "    just deploy       # Uses NFS, no sync needed"

# ──────────────────────────────────────────────────────────────────────────────
#  DEPLOYMENT
# ──────────────────────────────────────────────────────────────────────────────

# Deploy to all hosts or specific host via tmux session (non-blocking for agents)
# Use 'just attach' to view progress, Ctrl+B D to detach when attached
deploy target *args:
    @just deploy-bg {{target}} {{args}}

# Attach to running deploy session
attach:
    #!/usr/bin/env bash
    SESSION="deploy"
    if tmux has-session -t "$SESSION" 2>/dev/null; then
        exec tmux attach -t "$SESSION"
    else
        echo "No active deploy session. Use 'just deploy' to start one."
        exit 1
    fi

# Non-blocking deploy (for agents) - runs in tmux without attaching
deploy-bg target *args:
    #!/usr/bin/env bash
    set -e

    SESSION="deploy"
    if tmux has-session -t "$SESSION" 2>/dev/null; then
        echo "▸ Deploy session already running — use 'just attach' to view"
        exit 1
    fi

    tmux new-session -d -s "$SESSION" -c {{FLAKE}} -x 200 -y 50
    tmux set-option -t "$SESSION" status-style "bg=#1e1e2e fg=#cdd6f4"
    tmux set-option -t "$SESSION" status-left " #[fg=#89b4fa]⬢ NixOS #[fg=#a6adc8]│ #[fg=#f9e2af]#{session_name} "
    tmux set-option -t "$SESSION" status-right " #[fg=#a6adc8]#{pane_current_path} #[fg=#6c7086]│ #[fg=#a6e3a1]%H:%M "

    if [ "{{target}}" = "all" ] || [ -z "{{target}}" ]; then
        tmux send-keys -t "$SESSION" "echo '▸ Deploying all hosts...'" Enter
        tmux send-keys -t "$SESSION" "cd {{FLAKE}} && nix run .#apps.x86_64-linux.colmena -- apply --on nexus,forge,sentry --verbose {{args}} && sudo nixos-rebuild switch --flake .#zephyr {{args}}" Enter
    elif [ "{{target}}" = "zephyr" ]; then
        tmux send-keys -t "$SESSION" "echo '▸ Deploying zephyr...'" Enter
        tmux send-keys -t "$SESSION" "cd {{FLAKE}} && sudo nixos-rebuild switch --flake .#zephyr {{args}}" Enter
    else
        tmux send-keys -t "$SESSION" "echo '▸ Deploying {{target}}...'" Enter
        tmux send-keys -t "$SESSION" "cd {{FLAKE}} && nix run .#apps.x86_64-linux.colmena -- apply --on {{target}} --verbose {{args}}" Enter
    fi

    echo "▸ Deploy started in tmux session '$SESSION' (non-blocking)"
    echo "  → Use 'just attach' to view progress"
    echo "  → Use 'tmux kill-session -t deploy' to cancel"

# Non-blocking local switch (for agents) - runs in tmux without attaching
switch-bg:
    #!/usr/bin/env bash
    set -e

    SESSION="deploy"
    if tmux has-session -t "$SESSION" 2>/dev/null; then
        echo "▸ Deploy session already running — use 'just attach' to view"
        exit 1
    fi

    tmux new-session -d -s "$SESSION" -c {{FLAKE}} -x 200 -y 50
    tmux set-option -t "$SESSION" status-style "bg=#1e1e2e fg=#cdd6f4"
    tmux set-option -t "$SESSION" status-left " #[fg=#89b4fa]⬢ NixOS #[fg=#a6adc8]│ #[fg=#f9e2af]#{session_name} "
    tmux set-option -t "$SESSION" status-right " #[fg=#a6e3a1]%H:%M "
    tmux send-keys -t "$SESSION" "echo '▸ Switching $(hostname -s)...'" Enter
    tmux send-keys -t "$SESSION" "cd {{FLAKE}} && sudo nixos-rebuild switch --flake .#$(hostname -s)" Enter

    echo "▸ Switch started in tmux session '$SESSION' (non-blocking)"
    echo "  → Use 'just attach' to view progress"

# Convenience aliases
zephyr:
    just deploy zephyr
nexus:
    just deploy nexus
forge:
    just deploy forge
sentry:
    just deploy sentry
all:
    just deploy all

# ──────────────────────────────────────────────────────────────────────────────
#  VALIDATION
# ──────────────────────────────────────────────────────────────────────────────

# Check flake (quick validation, no build)
check:
    #!/usr/bin/env bash
    set -e
    echo "▸ Checking flake..."
    cd {{FLAKE}} && nix flake check

# ──────────────────────────────────────────────────────────────────────────────
#  LOCAL OPERATIONS
# ──────────────────────────────────────────────────────────────────────────────

# Apply to current host (uses nixos-rebuild switch — colmena apply-local has NixOS sudo PATH issue)
# Runs in tmux for visibility — runs non-blocking for agents
switch:
    @just switch-bg

# Build without applying (local host only)
build:
    #!/usr/bin/env bash
    set -e
    echo "▸ Building $(hostname -s)..."
    cd {{FLAKE}} && sudo nixos-rebuild build --flake .#$(hostname -s)

# Test rollback-safe switch
test-apply:
    #!/usr/bin/env bash
    set -e
    echo "▸ Testing $(hostname -s) (rollback on next boot)..."
    cd {{FLAKE}} && sudo nixos-rebuild test --flake .#$(hostname -s)

# ──────────────────────────────────────────────────────────────────────────────
#  FLAKE MANAGEMENT
# ──────────────────────────────────────────────────────────────────────────────

# Update flake.lock
update:
    #!/usr/bin/env bash
    set -e
    echo "▸ Updating flake.lock..."
    cd {{FLAKE}} && nix flake update

# Show flake metadata
info:
    #!/usr/bin/env bash
    set -e
    cd {{FLAKE}} && nix flake metadata

# ──────────────────────────────────────────────────────────────────────────────
#  CLUSTER STATUS
# ──────────────────────────────────────────────────────────────────────────────

# Git status across all nodes
# Note: Remote hosts use NFS mount, so we check Zephyr's git status
status:
    #!/usr/bin/env bash
    echo "▸ Git status (all hosts read from Zephyr via NFS):"
    commit=$(cd {{FLAKE}} && git log -1 --oneline)
    branch=$(cd {{FLAKE}} && git branch --show-current)
    echo "  ● Zephyr (source): $branch | $commit"
    echo "  ● Remote hosts: read from /run/nixos-shared (NFS)"
    echo ""
    echo "▸ Uncommitted changes:"
    if cd {{FLAKE}} && git status --short | grep -q .; then
        cd {{FLAKE}} && git status --short | sed 's/^/  /'
    else
        echo "  ✓ Working tree clean"
    fi

# Cluster health check
health:
    #!/usr/bin/env bash
    echo "▸ Cluster connectivity:"
    for host in zephyr nexus forge sentry; do
        if [ "$host" = "$(hostname -s)" ]; then
            echo "  ● $host: local"
        elif ssh -o ConnectTimeout=2 "$host" "true" >/dev/null 2>&1; then
            echo "  ● $host: up"
        else
            echo "  ● $host: down"
        fi
    done
    echo ""
    echo "▸ Kubernetes:"
    if [ "$(hostname -s)" = "zephyr" ] && command -v kubectl >/dev/null 2>&1; then
        kubectl get nodes 2>/dev/null | sed 's/^/  /' || echo "  ⚠ Kubernetes not responding"
    elif [ "$(hostname -s)" != "zephyr" ]; then
        ssh zephyr "kubectl get nodes" 2>/dev/null | sed 's/^/  /' || echo "  ⚠ Cannot query Kubernetes"
    else
        echo "  ⚠ kubectl not found"
    fi

# ──────────────────────────────────────────────────────────────────────────────
#  ROLLBACK
# ──────────────────────────────────────────────────────────────────────────────

# Rollback local host
rollback:
    #!/usr/bin/env bash
    set -e
    echo "▸ Rolling back $(hostname -s)..."
    sudo nixos-rebuild rollback

# Rollback remote host
rollback-remote host:
    #!/usr/bin/env bash
    set -e
    echo "▸ Rolling back {{host}}..."
    ssh {{host}} "sudo nixos-rebuild rollback"

# ──────────────────────────────────────────────────────────────────────────────
#  UTILITIES
# ──────────────────────────────────────────────────────────────────────────────

# Garbage collect (aggressive)
gc:
    #!/usr/bin/env bash
    set -e
    echo "▸ Garbage collecting..."
    sudo nix-collect-garbage -d

# Optimize nix store
optimize:
    #!/usr/bin/env bash
    set -e
    echo "▸ Optimizing store..."
    nix-store --optimize

# Show generations
generations:
    #!/usr/bin/env bash
    nix-env --list-generations --profile /nix/var/nix/profiles/system

# Prune stale nix-store/colmena processes (fixes lock contention)
prune-stale:
    #!/usr/bin/env bash
    set -e
    echo "▸ Pruning stale nix-store/colmena processes..."

    # Kill stale colmena processes (older than 30 minutes with 0% CPU)
    echo "  Checking for stale colmena..."
    pgrep -af colmena | while read pid cmdline; do
        cpu=$(ps -p "${pid%% *}" -o %cpu= 2>/dev/null || echo "0")
        if [ "${cpu%.*}" = "0" ]; then
            echo "    Killing stale colmena PID ${pid%% *}"
            kill -9 "${pid%% *}" 2>/dev/null || true
        fi
    done

    # Kill stale nix-store --realise processes (stuck waiting for locks)
    echo "  Checking for stale nix-store processes..."
    pgrep -af "nix-store.*--realise" | while read pid cmdline; do
        # Check if process has been running over 1 hour with 0% CPU
        cpu=$(ps -p "${pid%% *}" -o %cpu= 2>/dev/null || echo "0")
        if [ "${cpu%.*}" = "0" ]; then
            echo "    Killing stale nix-store PID ${pid%% *}"
            kill -9 "${pid%% *}" 2>/dev/null || true
        fi
    done

    echo "✓ Prune complete"

# ──────────────────────────────────────────────────────────────────────────────
#  MODEL MANAGEMENT
# ──────────────────────────────────────────────────────────────────────────────

# List available models
models-list:
    curl -s http://127.0.0.1:1234/v1/models 2>/dev/null | jq '.data[].id' 2>/dev/null || echo "LM Studio not responding"

# Gateway models
models-gateway:
    curl -s http://127.0.0.1:8080/v1/models 2>/dev/null | jq '.data[].id' 2>/dev/null || echo "Gateway not responding"

# ──────────────────────────────────────────────────────────────────────────────
#  UNIFIED DEPLOYMENT PIPELINE (Phase 5)
# ──────────────────────────────────────────────────────────────────────────────

# Unified deploy: validate + OS + copy closures + K8s (all hosts)
unified-deploy target="all" *args:
    #!/usr/bin/env bash
    set -e
    echo "▸ Running unified deployment pipeline..."
    cd {{FLAKE}} && sudo bash scripts/deploy.sh {{target}} {{args}}

# Unified rollback: OS + K8s
unified-rollback *args:
    #!/usr/bin/env bash
    set -e
    echo "▸ Running unified rollback..."
    cd {{FLAKE}} && sudo bash scripts/rollback.sh {{args}}

# Full validation suite (flake check + colmena build + K8s dry-run + connectivity)
full-check *args:
    #!/usr/bin/env bash
    set -e
    echo "▸ Running full validation suite..."
    cd {{FLAKE}} && sudo bash scripts/check.sh {{args}}

# Validate K8s manifests only (via k8s-validate app or nix build)
validate-k8s:
    #!/usr/bin/env bash
    set -e
    echo "▸ Validating Kubernetes manifests..."
    cd {{FLAKE}}
    if nix build .#kubernetesManifests 2>/dev/null; then
        if [ -d result ]; then
            echo "  ✓ Kubernetes manifests built successfully"
            if command -v kubectl >/dev/null 2>&1; then
                if kubectl apply --dry-run=client -f result/ --recursive; then
                    echo "  ✓ Kubectl dry-run passed"
                else
                    echo "  ✗ Kubectl dry-run failed"
                    exit 1
                fi
            else
                echo "  ⚠ kubectl not found, skipping dry-run"
            fi
        else
            echo "  ✓ K8s manifest built (single file)"
        fi
    else
        echo "  ⚠ kubernetesManifests not available, trying k8s-validate..."
        nix run .#k8s-validate
    fi
