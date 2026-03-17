# NixOS Cluster Deployment — Streamlined
#
# Quick start:
#   just check         # Validate flake (quick, no build)
#   just deploy        # Build + deploy to all hosts
#   just deploy <host> # Build + deploy single host
#   just switch        # Apply to current host (local)
#   just status        # Show cluster status

export FLAKE := "/etc/nixos"

_default:
    @just --list

# ──────────────────────────────────────────────────────────────────────────────
#  FLAKE LOCK SYNC
# ──────────────────────────────────────────────────────────────────────────────

# Sync flake.lock to remote hosts (before deployment)
# Note: Sentry is excluded - it reads from NFS mount /run/nixos-shared (no local copy)
sync-lock:
    #!/usr/bin/env bash
    set -e
    echo "▸ Syncing flake.lock to remote hosts..."
    for host in nexus forge; do
        echo "  → $host"
        if scp -o ConnectTimeout=5 {{FLAKE}}/flake.lock $host:/tmp/flake.lock.tmp; then
            ssh $host "sudo mv /tmp/flake.lock.tmp /etc/nixos/flake.lock && sudo chmod 644 /etc/nixos/flake.lock"
        else
            echo "    ⚠ $host unreachable, skipping"
        fi
    done
    echo "✓ Synced flake.lock to nexus and forge (sentry uses NFS mount)"

# Check flake.lock drift across hosts
check-drift:
    #!/usr/bin/env bash
    set -e
    echo "▸ Checking flake.lock drift..."
    ZEPHYR_SUM=$(md5sum {{FLAKE}}/flake.lock | cut -d' ' -f1)
    echo "  Zephyr: $ZEPHYR_SUM"

    for host in nexus forge; do
        REMOTE_SUM=$(ssh -o ConnectTimeout=5 $host "md5sum /etc/nixos/flake.lock 2>/dev/null | cut -d' ' -f1" || echo "unreachable")
        if [ "$REMOTE_SUM" = "$ZEPHYR_SUM" ]; then
            echo "  $host: ✓ in sync"
        else
            echo "  $host: ✗ DRIFT (got: $REMOTE_SUM)"
        fi
    done

# Trigger immediate sync on all remote hosts
sync-trigger:
    #!/usr/bin/env bash
    set -e
    echo "▸ Triggering flake.lock sync on remote hosts..."
    for host in nexus forge sentry; do
        echo "  → $host"
        ssh $host "systemctl start flake-lock-sync.service" || echo "    ⚠ Failed (host may be down)"
    done
    echo "✓ Sync triggered on all hosts"

# ──────────────────────────────────────────────────────────────────────────────
#  DEPLOYMENT
# ──────────────────────────────────────────────────────────────────────────────

# Deploy to all hosts or specific host
deploy target *args:
    #!/usr/bin/env bash
    set -e
    # Prevent concurrent colmena runs (lock timeout 5 seconds)
    exec {LOCK_FD}>/tmp/colmena-deploy.lock || exit 1
    flock -x -w 5 $LOCK_FD || { echo "⚠ Another deploy is already running"; exit 1; }
    trap "flock -u $LOCK_FD" EXIT

    # Sync flake.lock before deploying to remote hosts
    if [ "{{target}}" = "all" ] || [ -z "{{target}}" ]; then
        echo "▸ Syncing flake.lock to remote hosts..."
        just sync-lock
        echo "▸ Deploying to all hosts..."
        cd {{FLAKE}} && nix run .#apps.x86_64-linux.colmena -- apply
    else
        # Sync to specific host if it's remote (sentry uses NFS, no sync needed)
        case "{{target}}" in
            nexus|forge)
                echo "▸ Syncing flake.lock to {{target}}..."
                scp -o ConnectTimeout=5 {{FLAKE}}/flake.lock {{target}}:/tmp/flake.lock.tmp
                ssh {{target}} "sudo mv /tmp/flake.lock.tmp /etc/nixos/flake.lock && sudo chmod 644 /etc/nixos/flake.lock"
                ;;
            sentry)
                echo "▸ Note: sentry uses NFS mount /run/nixos-shared, no local sync needed"
                ;;
        esac
        echo "▸ Deploying to {{target}}..."
        cd {{FLAKE}} && nix run .#apps.x86_64-linux.colmena -- apply --on {{target}}
    fi

# Convenience aliases
zephyr:
    just deploy zephyr
nexus:
    just deploy nexus
forge:
    just deploy forge
sentry:
    just deploy sentry

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

# Apply to current host
switch:
    #!/usr/bin/env bash
    set -e
    echo "▸ Switching $(hostname -s)..."
    cd {{FLAKE}} && sudo nixos-rebuild switch --flake .#$(hostname -s)

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
status:
    #!/usr/bin/env bash
    echo "▸ Git status on all nodes:"
    for host in zephyr nexus forge sentry; do
        if [ "$host" = "$(hostname -s)" ]; then
            commit=$(cd {{FLAKE}} && git log -1 --oneline)
            echo "  ● $host: $commit"
        elif commit=$(ssh -o ConnectTimeout=2 "$host" "cd {{FLAKE}} && git log -1 --oneline" 2>/dev/null); then
            echo "  ● $host: $commit"
        else
            echo "  ● $host: unreachable"
        fi
    done

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
