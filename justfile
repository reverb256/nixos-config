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
        tmux send-keys -t "$SESSION" "cd {{FLAKE}} && nix run .#apps.x86_64-linux.colmena -- apply --on nexus --verbose {{args}} && nix run .#apps.x86_64-linux.colmena -- apply --on forge --verbose {{args}} && nix run .#apps.x86_64-linux.colmena -- apply --on sentry --verbose {{args}} && sudo nixos-rebuild switch --flake .#zephyr {{args}}" Enter
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

# Pre-flight check (run before switch/deploy to prevent OOM)
preflight:
    #!/usr/bin/env bash
    set -e
    /etc/nixos/scripts/preflight-check.sh

# Apply to current host (uses nixos-rebuild switch — colmena apply-local has NixOS sudo PATH issue)
# Runs in tmux for visibility — runs non-blocking for agents
switch:
    #!/usr/bin/env bash
    set -e
    echo "▸ Running pre-flight check..."
    /etc/nixos/scripts/preflight-check.sh
    just switch-bg

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

# Full system upgrade: update flake → check → switch → gc
# Idempotent — safe to run from any directory
topgrade:
    #!/usr/bin/env bash
    set -e
    HOST=$(hostname -s)
    FLAKE="/etc/nixos"

    echo "▸ Topgrade: $HOST"
    echo ""

    echo "1/4 ▸ Updating flake.lock..."
    cd "$FLAKE" && nix flake update 2>&1 || echo "  ⚠ Update skipped (non-fatal, check flake inputs)"

    echo ""
    echo "2/4 ▸ Validating flake..."
    cd "$FLAKE" && nix flake check 2>&1 || echo "  ⚠ Check skipped (non-fatal, may OOM on Zephyr)"

    echo ""
    echo "3/4 ▸ Switching $HOST..."
    cd "$FLAKE"
    set +e
    sudo nixos-rebuild switch --flake .#$HOST; rc=$?
    set -e
    if [ $rc -eq 4 ]; then
        echo "  ⚠ Some units failed (non-fatal)"
    elif [ $rc -ne 0 ]; then
        echo "  ✗ Switch failed (exit $rc)"
        exit $rc
    fi

    echo ""
    echo "4/4 ▸ Cleaning old generations..."
    sudo nix-collect-garbage -d || echo "  ⚠ GC failed (non-fatal)"

    echo ""
    echo "✓ Topgrade complete ($HOST)"


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
#  GITHUB ISSUES WORKFLOW
# ──────────────────────────────────────────────────────────────────────────────

# Create a new GitHub issue interactively
issue-create title="" label="":
    #!/usr/bin/env bash
    set -euo pipefail
    TITLE="{{title}}"
    LABEL="{{label}}"
    if [ -z "$TITLE" ]; then
        read -r -p "Issue title: " TITLE
    fi
    if [ -z "$LABEL" ]; then
        read -r -p "Labels (comma-separated, e.g. p2,infra): " LABEL
    fi
    gh issue create \
      --title "$TITLE" \
      --label "$LABEL" \
      --body "## Context\n\n## Task\n\n## Priority\n\n## Estimate\n" \
      --assignee "@me"

# List open issues with labels
issue-list:
    #!/usr/bin/env bash
    set -euo pipefail
    gh issue list --limit 20 --json number,title,state,labels,assignees \
      | jq -r '.[] | "#\(.number | tostring | " " * (3 - (. | tostring | length)) + .) [" + .state + "] " + .title + " " + (.labels | map(.name) | join(" "))'

# Close an issue with a comment referencing the PR
issue-close number pr_url="":
    #!/usr/bin/env bash
    set -euo pipefail
    N="{{number}}"
    PR="{{pr_url}}"
    if [ -n "$PR" ]; then
        gh issue close "$N" --comment "Closed by $PR"
    else
        gh issue close "$N" --comment "Completed."
    fi

# Create a branch from an issue number
branch-from number:
    #!/usr/bin/env bash
    set -euo pipefail
    N="{{number}}"
    TITLE=$(gh issue view "$N" --json title --jq '.title' 2>/dev/null || echo "issue-$N")
    # Slugify the title
    SLUG=$(echo "$TITLE" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//' | cut -c1-60)
    BRANCH="issue-$N-$SLUG"
    git checkout -b "$BRANCH"
    echo "→ Switched to branch: $BRANCH"

# ──────────────────────────────────────────────────────────────────────────────
#  UTILITIES
# ──────────────────────────────────────────────────────────────────────────────

# Garbage collect (aggressive)
gc:
    #!/usr/bin/env bash
    set -e
    echo "▸ Garbage collecting..."
    sudo nix-collect-garbage -d || echo "  ⚠ GC failed (non-fatal)"

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

# ──────────────────────────────────────────────────────────────────────────────

# CA CERTIFICATE MANAGEMENT
# ──────────────────────────────────────────────────────────────────────────────

# Verify CA cert distribution across all hosts (declarative check)
ca-verify:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "▸ Verifying CA certificate distribution..."
    CA_CERT="/etc/ssl/cluster-ca/ca.crt"
    ALL_OK=true
    for host in zephyr nexus forge sentry; do
        echo "  $host:"
        if [ "$host" = "zephyr" ]; then
            # Local checks
            if [ -f "$CA_CERT" ]; then echo "    ✓ CA cert present"; else echo "    ✗ CA cert MISSING"; ALL_OK=false; fi
            if grep -q 'Cluster CA' /etc/ssl/certs/ca-bundle.crt 2>/dev/null; then echo "    ✓ CA trusted in system bundle"; else echo "    ✗ CA NOT trusted"; ALL_OK=false; fi
            if [ -f /etc/ssl/cluster-ca/leaf.crt ]; then echo "    ✓ Leaf cert present"; else echo "    ✗ Leaf cert MISSING"; ALL_OK=false; fi
            if [ -f /etc/ssl/cluster-ca/.san-hash ]; then echo "    ✓ SAN hash file present"; else echo "    ⚠ SAN hash file missing (will regen on next boot)"; fi
        else
            # Remote checks via SSH
            CA_EXISTS=$(ssh -o ConnectTimeout=5 "$host" "test -f $CA_CERT && echo yes || echo no" 2>/dev/null || echo "no")
            if [ "$CA_EXISTS" = "yes" ]; then echo "    ✓ CA cert present"; else echo "    ✗ CA cert MISSING"; ALL_OK=false; fi
            TRUSTED=$(ssh -o ConnectTimeout=5 "$host" "grep -c 'Cluster CA' /etc/ssl/certs/ca-bundle.crt 2>/dev/null || true" 2>/dev/null || echo "0")
            if [ "${TRUSTED:-0}" -gt 0 ] 2>/dev/null; then echo "    ✓ CA trusted in system bundle"; else echo "    ✗ CA NOT trusted"; ALL_OK=false; fi
            LEAF=$(ssh -o ConnectTimeout=5 "$host" "test -f /etc/ssl/cluster-ca/leaf.crt && echo yes || echo no" 2>/dev/null || echo "no")
            if [ "$LEAF" = "yes" ]; then echo "    ✓ Leaf cert present"; else echo "    ℹ No leaf cert (not a Caddy host)"; fi
        fi
    done
    if [ "$ALL_OK" = true ]; then echo "▸ All hosts OK"; else echo "▸ Some hosts need attention — deploy to fix"; fi

# Regenerate leaf certificates on all Caddy hosts (emergency use only)
# Normal flow: just deploy (cluster-ca-init auto-detects SAN changes)
ca-regen-leaf:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "▸ Regenerating leaf certificates on Caddy hosts..."
    for host in zephyr nexus; do
        echo "  $host:"
        if [ "$host" = "zephyr" ]; then
            sudo rm -f /etc/ssl/cluster-ca/leaf.crt /etc/ssl/cluster-ca/leaf.key /etc/ssl/cluster-ca/.san-hash
            sudo systemctl restart cluster-ca-init.service
            sleep 2
            sudo systemctl restart caddy.service
        else
            ssh -o ConnectTimeout=5 "$host" "sudo rm -f /etc/ssl/cluster-ca/leaf.crt /etc/ssl/cluster-ca/leaf.key /etc/ssl/cluster-ca/.san-hash && sudo systemctl restart cluster-ca-init.service && sleep 2 && sudo systemctl restart caddy.service"
        fi
        echo "    ✓ Leaf cert regenerated and Caddy restarted"
    done
    echo "▸ Done. Use 'just ca-verify' to check status."

# Export CA cert for installation on external devices (phones, laptops, etc.)
ca-export path="":
    #!/usr/bin/env bash
    set -euo pipefail
    DEST="${1:-$HOME/cluster-ca.crt}"
    cp /etc/nixos/certs/cluster-ca.crt "$DEST"
    echo "▸ CA certificate exported to $DEST"
    echo ""
    echo "Install on devices:"
    echo "  Linux:   sudo cp $DEST /usr/local/share/ca-certificates/ && sudo update-ca-certificates"
    echo "  macOS:   sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain $DEST"
    echo "  Windows: Import into 'Trusted Root Certification Authorities' store"
    echo "  Android: Settings → Security → Install from storage"
    echo "  iOS:     AirDrop file → Install profile → Settings → General → About → Cert Trust Settings"

# Show all .lan domains (from SSOT in cluster-dns.nix)


# Show all .lan domains (from SSOT in cluster-dns.nix)
ca-domains:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "All .lan domains (SSOT from cluster-dns.nix):"
    cd /etc/nixos
    nix eval '.#nixosConfigurations.zephyr.config.clusterNetworking.lanDomains' --json 2>/dev/null \
      | python3 -c "import json,sys;domains=json.loads(sys.stdin.read());[print(f'  {i:2d}. {d}') for i,d in enumerate(sorted(domains),1)];print(f'\n  Total: {len(domains)} domains');print('  + *.lan wildcard (covers everything else)')"

# ──────────────────────────────────────────────────────────────────────────────
#  DOCUMENTATION
# ──────────────────────────────────────────────────────────────────────────────

# Run full documentation verification suite (part of CI/CD)
docs-audit:
    #!/usr/bin/env bash
    set -e
    echo "▸ Running documentation verification suite..."
    docs/meta/VERIFICATION-SUITE/run.sh

# Refresh stale documentation sections
docs-freshen:
    #!/usr/bin/env bash
    set -e
    echo "▸ Refreshing documentation..."
    echo "→ Check LIVE/ documents for accuracy"
    echo "→ Run 'just docs-audit' after changes"
    echo "Documentation refresh complete."
