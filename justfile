# NixOS Cluster Deployment — GitOps-Based Architecture
#
# Architecture:
#   • /etc/nixos on all hosts tracks prod (deployed state)
#   • All development in worktrees under /data/projects/own/nixos-config-NNN
#   • PR → main (CI validates) → prod (deploy gate) → cluster
#   • Config deployed via nix-copy-closure + SSH switch-to-configuration
#
# Quick start:
#   just check             # Validate flake (quick, no build)
#   just build             # Build for this host
#   just switch            # Apply to local host
#   just deploy            # Build + deploy to all 4 hosts
#   just status            # Show git + cluster overview
#   just new-worktree NNN  # Create worktree for issue NNN

export FLAKE := "/etc/nixos"

_default:
    @just --list

# ── DEVELOPMENT WORKFLOW ──────────────────────────────────────────────────────

# Create a worktree for a new issue
new-worktree number:
    #!/usr/bin/env bash
    set -euo pipefail
    N="{{number}}"
    TITLE=$(gh issue view "$N" --json title --jq .title 2>/dev/null || echo "issue-$N")
    SLUG=$(echo "$TITLE" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//' | cut -c1-60)
    BRANCH="issue-$N-$SLUG"
    WT_PATH="/data/projects/own/nixos-config-$N"
    if [ -d "$WT_PATH" ]; then
        echo "Worktree already exists at $WT_PATH"
        exit 1
    fi
    cd {{FLAKE}}
    git worktree add -b "$BRANCH" "$WT_PATH" main
    echo "Worktree: $WT_PATH"
    echo "Branch:   $BRANCH"

# Remove a completed worktree
rm-worktree number:
    #!/usr/bin/env bash
    set -euo pipefail
    N="{{number}}"
    WT_PATH="/data/projects/own/nixos-config-$N"
    cd {{FLAKE}}
    if [ -d "$WT_PATH" ]; then
        BRANCH=$(cd "$WT_PATH" && git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
        git worktree remove "$WT_PATH" 2>/dev/null || git worktree remove --force "$WT_PATH"
        echo "Worktree removed: $WT_PATH"
    else
        BRANCH=$(git branch -l "issue-$N-*" 2>/dev/null | head -1 | tr -d ' ')
        echo "No worktree at $WT_PATH"
    fi
    if [ -n "$BRANCH" ] && git branch -l "$BRANCH" | grep -q .; then
        git branch -D "$BRANCH" 2>/dev/null || true
        git push origin --delete "$BRANCH" 2>/dev/null || echo "(remote branch gone)"
        echo "Branch deleted: $BRANCH"
    fi

# ── DEPLOYMENT ────────────────────────────────────────────────────────────────

HOSTS := "zephyr nexus forge sentry"

# Deploy to all hosts or a specific host
deploy host="all":
    #!/usr/bin/env bash
    set -e
    echo "Deploying from $(cd {{FLAKE}} && git rev-parse --abbrev-ref HEAD) ($(cd {{FLAKE}} && git rev-parse --short HEAD))"
    echo ""
    if [ "{{host}}" = "all" ]; then
        TARGETS="{{HOSTS}}"
    else
        TARGETS="{{host}}"
    fi
    for host in $TARGETS; do
        echo "=== $host ==="
        if [ "$host" = "zephyr" ]; then
            sudo nixos-rebuild switch --flake {{FLAKE}}#$host 2>&1
            echo "done"
        else
            OUT=$(nix build --no-link --print-out-paths {{FLAKE}}#nixosConfigurations.$host.config.system.build.toplevel 2>&1) || {
                echo "Build failed for $host"; echo "$OUT"; exit 1
            }
            nix-copy-closure --to root@$host "$OUT" 2>&1 | grep -v "copying path" | grep -v "already exists"
            ssh root@$host "nix-env -p /nix/var/nix/profiles/system --set $OUT && sudo $OUT/bin/switch-to-configuration switch" 2>&1 | tail -5
            echo "done"
        fi
    done
    echo ""
    echo "Deploy complete. Verify with 'just health'"

zephyr:
    just deploy zephyr
nexus:
    just deploy nexus
forge:
    just deploy forge
sentry:
    just deploy sentry

deploy-bg target="all":
    #!/usr/bin/env bash
    set -e
    SESSION="deploy"
    if tmux has-session -t "$SESSION" 2>/dev/null; then
        echo "Deploy session already running - use 'just attach'"
        exit 1
    fi
    tmux new-session -d -s "$SESSION" -c {{FLAKE}} -x 200 -y 50
    tmux send-keys -t "$SESSION" "just deploy {{target}}" Enter
    echo "Deploy started (tmux: $SESSION)"
    echo "use 'just attach' to view"

attach:
    #!/usr/bin/env bash
    SESSION="deploy"
    if tmux has-session -t "$SESSION" 2>/dev/null; then
        exec tmux attach -t "$SESSION"
    else
        echo "No active deploy session"
        exit 1
    fi

# ── VALIDATION & LOCAL OPS ────────────────────────────────────────────────────

check:
    #!/usr/bin/env bash
    set -e
    cd {{FLAKE}} && nix flake check

build:
    #!/usr/bin/env bash
    set -e
    cd {{FLAKE}} && sudo nixos-rebuild build --flake .#$(hostname -s)

switch:
    #!/usr/bin/env bash
    set -e
    {{FLAKE}}/scripts/preflight-check.sh 2>/dev/null || true
    cd {{FLAKE}} && sudo nixos-rebuild switch --flake .#$(hostname -s)

test-apply:
    #!/usr/bin/env bash
    set -e
    cd {{FLAKE}} && sudo nixos-rebuild test --flake .#$(hostname -s)

preflight:
    #!/usr/bin/env bash
    set -e
    {{FLAKE}}/scripts/preflight-check.sh

topgrade:
    #!/usr/bin/env bash
    set -e
    HOST=$(hostname -s)
    echo "Topgrade: $HOST"
    echo "1/4 Updating flake.lock..."
    cd {{FLAKE}} && nix flake update 2>&1 || echo "skip (non-fatal)"
    echo "2/4 Validating..."
    cd {{FLAKE}} && nix flake check 2>&1 || echo "skip (non-fatal)"
    echo "3/4 Switching..."
    cd {{FLAKE}} && sudo nixos-rebuild switch --flake .#$HOST; rc=$?
    if [ $rc -ne 0 ] && [ $rc -ne 4 ]; then exit $rc; fi
    echo "4/4 GC..."
    sudo nix-collect-garbage -d || true
    echo "done"

# ── CLUSTER STATUS ────────────────────────────────────────────────────────────

status:
    #!/usr/bin/env bash
    cd {{FLAKE}}
    echo "Branch: $(git rev-parse --abbrev-ref HEAD)"
    echo "Commit: $(git log -1 --oneline)"
    echo ""
    echo "Prod alignment:"
    PROD=$(git rev-parse origin/prod 2>/dev/null || echo "")
    MAIN=$(git rev-parse origin/main 2>/dev/null || echo "")
    if [ "$PROD" = "$MAIN" ]; then
        echo "  prod = main"
    elif [ -n "$PROD" ]; then
        echo "  prod is $(git rev-list --count $PROD..$MAIN) commit(s) behind main"
    else
        echo "  no prod branch"
    fi
    echo ""
    echo "Worktrees:"
    git worktree list | sed 's/^/  /'
    echo ""
    echo "Uncommitted:"
    git status --short | sed 's/^/  /' || echo "  clean"

health:
    #!/usr/bin/env bash
    echo "Connectivity:"
    for host in {{HOSTS}}; do
        if [ "$host" = "$(hostname -s)" ]; then
            echo "  $host: local"
        elif ssh -o ConnectTimeout=2 "$host" "true" >/dev/null 2>&1; then
            echo "  $host: up"
        else
            echo "  $host: down"
        fi
    done
    echo ""
    echo "Kubernetes:"
    kubectl get nodes 2>/dev/null | sed 's/^/  /' || echo "  not responding"

# ── ROLLBACK ──────────────────────────────────────────────────────────────────

rollback:
    #!/usr/bin/env bash
    set -e
    sudo nixos-rebuild rollback

rollback-remote host:
    #!/usr/bin/env bash
    set -e
    ssh {{host}} "sudo nixos-rebuild rollback"

# ── FLAKE MANAGEMENT ──────────────────────────────────────────────────────────

update:
    #!/usr/bin/env bash
    set -e
    cd {{FLAKE}} && nix flake update

info:
    #!/usr/bin/env bash
    set -e
    cd {{FLAKE}} && nix flake metadata

# ── GITHUB ISSUES ─────────────────────────────────────────────────────────────

issue-create title="" label="":
    #!/usr/bin/env bash
    set -euo pipefail
    TITLE="{{title}}"; LABEL="{{label}}"
    [ -z "$TITLE" ] && read -r -p "Title: " TITLE
    [ -z "$LABEL" ] && read -r -p "Labels: " LABEL
    gh issue create --title "$TITLE" --label "$LABEL" \
      --body "## Context\n## Task\n## Priority\n" --assignee @me

issue-list:
    #!/usr/bin/env bash
    set -euo pipefail
    gh issue list --limit 20 --json number,title,state,labels \
      | jq -r '.[] | "#\(.number) [\(.state)] \(.title)"'

branch-from number:
    #!/usr/bin/env bash
    set -euo pipefail
    N={{number}}
    TITLE=$(gh issue view "$N" --json title --jq .title 2>/dev/null || echo "issue-$N")
    SLUG=$(echo "$TITLE" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g;s/^-//;s/-$//' | cut -c1-60)
    git checkout -b "issue-$N-$SLUG"

# ── UTILITIES ─────────────────────────────────────────────────────────────────

gc:
    #!/usr/bin/env bash
    set -e
    sudo nix-collect-garbage -d || true

optimise:
    #!/usr/bin/env bash
    set -e
    nix-store --optimise

generations:
    #!/usr/bin/env bash
    nix-env --list-generations --profile /nix/var/nix/profiles/system

prune-stale:
    #!/usr/bin/env bash
    set -e
    pgrep -af colmena | while read p c; do cpu=$(ps -p ${p%% *} -o %cpu= 2>/dev/null || echo 0); [ "${cpu%.*}" = 0 ] && kill -9 ${p%% *} 2>/dev/null; done
    pgrep -af "nix-store.*--realise" | while read p c; do cpu=$(ps -p ${p%% *} -o %cpu= 2>/dev/null || echo 0); [ "${cpu%.*}" = 0 ] && kill -9 ${p%% *} 2>/dev/null; done

# ── VALIDATION / K8s ──────────────────────────────────────────────────────────

validate-k8s:
    #!/usr/bin/env bash
    set -e
    cd {{FLAKE}}
    nix build .#kubernetesManifests 2>/dev/null && echo "K8s manifests built" || nix run .#k8s-validate 2>/dev/null || echo "k8s-validate not available"

full-check *args:
    #!/usr/bin/env bash
    set -e
    cd {{FLAKE}} && sudo bash scripts/check.sh {{args}}

# ── CA MANAGEMENT ─────────────────────────────────────────────────────────────

ca-verify:
    #!/usr/bin/env bash
    set -euo pipefail
    ALL_OK=true
    for host in {{HOSTS}}; do
        if [ "$host" = "$(hostname -s)" ]; then
            [ -f /etc/ssl/cluster-ca/ca.crt ] && echo "  $host: OK" || { echo "  $host: MISSING"; ALL_OK=false; }
        else
            ssh "$host" "test -f /etc/ssl/cluster-ca/ca.crt" 2>/dev/null && echo "  $host: OK" || { echo "  $host: MISSING"; ALL_OK=false; }
        fi
    done
    $ALL_OK && echo "All OK" || echo "Some hosts need deploy"

ca-regen-leaf:
    #!/usr/bin/env bash
    set -euo pipefail
    for host in zephyr nexus; do
        [ "$host" = "$(hostname -s)" ] && local=1 || local=0
        [ $local -eq 1 ] && sudo rm -f /etc/ssl/cluster-ca/leaf.{crt,key} && sudo systemctl restart cluster-ca-init.service
        [ $local -eq 0 ] && ssh "$host" "sudo rm -f /etc/ssl/cluster-ca/leaf.{crt,key} && sudo systemctl restart cluster-ca-init.service"
        sleep 2
        [ $local -eq 1 ] && sudo systemctl restart caddy.service || ssh "$host" "sudo systemctl restart caddy.service"
        echo "$host done"
    done

ca-export path="":
    #!/usr/bin/env bash
    cp /etc/nixos/certs/cluster-ca.crt "{{path}}"

ca-domains:
    #!/usr/bin/env bash
    cd {{FLAKE}}
    nix eval '.#nixosConfigurations.zephyr.config.clusterNetworking.lanDomains' --json 2>/dev/null \
      | python3 -c "import json,sys;d=json.loads(sys.stdin.read());[print(f'  {i}. {x}') for i,x in enumerate(sorted(d),1)]"

# ── DOCUMENTATION ─────────────────────────────────────────────────────────────

docs-audit:
    #!/usr/bin/env bash
    set -e
    docs/meta/VERIFICATION-SUITE/run.sh

docs-freshen:
    #!/usr/bin/env bash
    set -e
    echo "Check LIVE/ docs for accuracy, run 'docs-audit' after"
