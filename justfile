# NixOS Cluster Deployment — GitOps-Based Architecture
#
# Architecture:
#   • /etc/nixos on all hosts tracks main (deployed state = main HEAD after `just deploy`)
#   • All development in worktrees under /data/projects/own/nixos-config-NNN
#   • PR → main (CI validates) → cluster via `just deploy` (no separate prod branch)
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

# ── GIT MANAGEMENT ────────────────────────────────────────────────────────────────
# Sync all hosts to central/main

HOSTS := "zephyr nexus forge sentry krash3"

# Show git status on all hosts
git-status:
    #!/usr/bin/env bash
    set -e
    for host in {{HOSTS}}; do
        echo "=== $host ==="
        if [ "$host" = "$(hostname -s)" ]; then
            cd {{FLAKE}} && git log -1 --oneline && git status --short | head -5 || echo "  clean"
        else
            ssh "$host" "cd /etc/nixos && echo \"Commit: \\$(git log -1 --oneline)\" && git status --short | head -5 || echo \"  clean\""
        fi
        echo ""
    done

# Pull latest on all hosts (stashes local changes first)
git-pull:
    #!/usr/bin/env bash
    set -e
    for host in {{HOSTS}}; do
        echo "=== $host ==="
        if [ "$host" = "$(hostname -s)" ]; then
            cd {{FLAKE}} && git stash 2>/dev/null; git pull --rebase origin main; git stash pop 2>/dev/null || true
        else
            ssh "$host" "cd /etc/nixos && git stash 2>/dev/null; git pull --rebase central main 2>&1 | tail -2; git stash pop 2>/dev/null || true"
        fi
        echo ""
    done
    echo "All hosts synced"

# Show last 5 commits on each host
git-log:
    #!/usr/bin/env bash
    set -e
    for host in {{HOSTS}}; do
        echo "=== $host ==="
        if [ "$host" = "$(hostname -s)" ]; then
            cd {{FLAKE}} && git log --oneline -5
        else
            ssh "$host" "cd /etc/nixos && git log --oneline -5"
        fi
        echo ""
    done

# Push local commits to origin + central, then pull on all hosts
git-push:
    #!/usr/bin/env bash
    set -e
    cd {{FLAKE}}
    echo "=== Pushing ==="
    git push origin main 2>&1 | tail -2 || echo "push to origin failed"
    git push central main 2>&1 | tail -2 || echo "push to central failed"
    echo ""
    echo "=== Pulling to remotes ==="
    for host in nexus forge sentry; do
        echo -n "$host: "
        ssh "$host" "cd /etc/nixos && git stash 2>/dev/null; git pull --rebase central main 2>&1 | tail -1; git stash pop 2>/dev/null || true"
    done
    echo "All hosts synced"

# ── DEPLOYMENT ────────────────────────────────────────────────────────────────
# Nexus is the workhorse: build/apply from there to keep zephyr light.
# Local deploy still works for the host you're running on.

# Local deploy to all hosts or a specific host
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
        LOCAL=$(hostname -s)
        if [ "$host" = "$LOCAL" ]; then
            # Zephyr never builds locally (31GB OOM). Offload its system build
            # to nexus via colmena; other hosts build locally as before.
            if [ "$host" = "zephyr" ]; then
                ssh nexus "cd /etc/nixos && colmena apply --on zephyr --eval-node-limit 100" 2>&1
            else
                sudo nixos-rebuild switch --flake {{FLAKE}}#$host 2>&1
            fi
            echo "done"
        else
            OUT=$(nix build --no-link --print-out-paths {{FLAKE}}#nixosConfigurations.$host.config.system.build.toplevel 2>&1) || {
                echo "Build failed for $host"; echo "$OUT"; exit 1
            }
            nix-copy-closure --to j_kro@$host "$OUT" 2>&1 | grep -v "copying path" | grep -v "already exists"
            ssh j_kro@$host "sudo nix-env -p /nix/var/nix/profiles/system --set $OUT && sudo $OUT/bin/switch-to-configuration switch" 2>&1 | tail -5
            echo "done"
        fi
    done
    echo ""
    echo "Deploy complete. Verify with 'just health'"

# Host shortcuts: local deploy
zephyr:
    just deploy zephyr
nexus:
    just deploy nexus
forge:
    just deploy forge
sentry:
    just deploy sentry

# Async deploy from nexus using colmena, tmux session + log file.
# Idempotent: re-running attaches to the existing session instead of creating a duplicate.
NEXUS_DEPLOY_SESSION := "deploy-nexus-{{host}}"
NEXUS_DEPLOY_LOG := "/var/log/colmena-deploy-{{host}}.log"

deploy-nexus host:
    #!/usr/bin/env bash
    set -euo pipefail
    HOST="{{host}}"
    SESSION="deploy-nexus-${HOST}"
    LOG="/var/log/colmena-deploy-${HOST}.log"
    CMD="cd /etc/nixos && colmena apply --on ${HOST} --eval-node-limit 100 | tee ${LOG}"
    if tmux has-session -t "$SESSION" 2>/dev/null; then
        echo "attaching to existing deploy session: $SESSION"
        exec tmux attach -t "$SESSION"
    fi
    tmux new-session -d -s "$SESSION"
    tmux send-keys -t "$SESSION" "ssh nexus '${CMD}'" Enter
    echo "deploy started on nexus -> ${HOST}"
    echo "tmux: $SESSION"
    echo "log:  $LOG"

# Attach to an in-progress nexus deploy, or start it if missing.
deploy-nexus-attach host:
    #!/usr/bin/env bash
    set -euo pipefail
    HOST="{{host}}"
    SESSION="deploy-nexus-${HOST}"
    if tmux has-session -t "$SESSION" 2>/dev/null; then
        exec tmux attach -t "$SESSION"
    fi
    just deploy-nexus "$HOST"

# Tail the deploy log without attaching.
deploy-nexus-logs host:
    #!/usr/bin/env bash
    set -euo pipefail
    HOST="{{host}}"
    LOG="/var/log/colmena-deploy-${HOST}.log"
    if [ -f "$LOG" ]; then
        tail -f "$LOG"
    else
        echo "no log yet: $LOG"
        exit 1
    fi

# Stop an in-progress nexus deploy.
deploy-nexus-stop host:
    #!/usr/bin/env bash
    set -euo pipefail
    HOST="{{host}}"
    SESSION="deploy-nexus-${HOST}"
    if tmux has-session -t "$SESSION" 2>/dev/null; then
        tmux send-keys -t "$SESSION" C-c
        sleep 1
        tmux kill-session -t "$SESSION"
        echo "stopped deploy session: $SESSION"
    else
        echo "no deploy session: $SESSION"
    fi

# Convenience shortcuts: deploy from nexus
deploy-nexus-zephyr:
    just deploy-nexus zephyr
deploy-nexus-forge:
    just deploy-nexus forge
deploy-nexus-sentry:
    just deploy-nexus sentry
deploy-nexus-all:
    just deploy-nexus all

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
    cd {{FLAKE}}
    # Offload compilation to nexus so zephyr never builds locally (31GB OOM).
    nix build --builders 'ssh-ng://j_kro@nexus' --no-link --print-out-paths .#$(hostname -s)

switch:
    #!/usr/bin/env bash
    set -e
    cd {{FLAKE}}
    {{FLAKE}}/scripts/preflight-check.sh 2>/dev/null || true
    # Zephyr never builds locally (31GB OOM) — offload the system build to
    # nexus via colmena. Other hosts build locally.
    if [ "$(hostname -s)" = "zephyr" ]; then
        ssh nexus "cd /etc/nixos && colmena apply --on zephyr --eval-node-limit 100" 2>&1
    else
        sudo nixos-rebuild switch --flake .#$(hostname -s)
    fi

test-apply:
    #!/usr/bin/env bash
    set -e
    cd {{FLAKE}}
    # Zephyr never builds locally (31GB OOM) — use test via nexus.
    if [ "$(hostname -s)" = "zephyr" ]; then
        ssh nexus "cd /etc/nixos && colmena apply --on zephyr --eval-node-limit 100" 2>&1
    else
        sudo nixos-rebuild test --flake .#$(hostname -s)
    fi

preflight:
    #!/usr/bin/env bash
    set -e
    {{FLAKE}}/scripts/preflight-check.sh

# ── TOPGRADE (super-upgrade) ──────────────────────────────────────
# Comprehensive flake upgrade: unpins stale inputs, updates ALL flake
# inputs to latest, collapses redundant nixpkgs variants, validates,
# switches, GCs, and commits the result.
#
# Usage:
#   just topgrade        # dry-run: show what would change
#   just topgrade apply  # execute: unpin, update, commit, switch, gc
topgrade mode="dry":
    #!/usr/bin/env bash
    set -euo pipefail
    cd {{FLAKE}}
    exec ./scripts/topgrade.sh {{mode}}

# ── CLUSTER STATUS ────────────────────────────────────────────────────────────

status:
    #!/usr/bin/env bash
    cd {{FLAKE}}
    echo "Branch: $(git rev-parse --abbrev-ref HEAD)"
    echo "Commit: $(git log -1 --oneline)"
    echo ""
    echo "Origin alignment (local HEAD vs origin/main):"
    LOCAL=$(git rev-parse HEAD 2>/dev/null || echo "")
    MAIN=$(git rev-parse origin/main 2>/dev/null || echo "")
    if [ "$LOCAL" = "$MAIN" ]; then
        echo "  local = origin/main"
    elif [ -n "$LOCAL" ] && [ -n "$MAIN" ]; then
        AHEAD=$(git rev-list --count $MAIN..$LOCAL)
        BEHIND=$(git rev-list --count $LOCAL..$MAIN)
        echo "  local is $AHEAD commit(s) ahead, $BEHIND behind origin/main"
    else
        echo "  unable to determine (missing origin/main ref)"
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

# ── HERMES AGENT ──────────────────────────────────────────────────────────
# "Full" update: bump EVERY flake input to latest upstream (nix flake update),
# commit + push the lock, verify the NixOS patches in modules/services/hermes-cli.nix
# still apply on a full toplevel build (fail fast before touching the cluster),
# then deploy the whole system (patched hermes package included) to all 5 hosts.
#
# IMPORTANT: a full `nix flake update` also moves nixpkgs to its newest commit,
# which can be a large rebuild and can surface breaking changes elsewhere. The
# step-3 build is the guard: if anything fails to evaluate/build, the script
# aborts BEFORE deploying, so the cluster stays on the last good generation.
#
# Note: a full deploy triggers nixos-rebuild switch on every host. Services whose
# units change will restart — miners included. If you need a maintenance window,
# run `just hermes-update-check` first, then deploy in a window.
hermes-update:
    #!/usr/bin/env bash
    set -euo pipefail
    cd {{FLAKE}}

    echo "1/6 Bumping ALL flake inputs to latest upstream..."
    nix flake update 2>&1 | tail -5

    echo "2/6 Committing + pushing flake.lock..."
    git add flake.lock
    if git diff --cached --quiet; then
        echo "  (lock unchanged — already at latest)"
    else
        git commit -m "chore: bump all flake inputs to latest upstream" 2>&1 | tail -2
        git push origin main 2>&1 | tail -2 || echo "  (push skipped)"
    fi

    echo "3/6 Building zephyr toplevel (full build — verifies hermes-cli.nix patches + all inputs)..."
    nix build --no-link --print-out-paths \
        .#nixosConfigurations.zephyr.config.system.build.toplevel 2>&1 | tail -20

    echo "4/6 Deploying to all hosts (full system switch)..."
    just deploy all 2>&1 | tail -50

    echo "5/6 Verifying hermes version on all hosts..."
    for host in {{HOSTS}}; do
        if [ "$host" = "$(hostname -s)" ]; then
            V=$(hermes --version 2>/dev/null || echo "unknown")
        else
            V=$(ssh "$host" "hermes --version 2>/dev/null || echo unknown" 2>/dev/null)
        fi
        echo "  $host: $V"
    done

    echo "6/6 Done. Hermes Agent + all flake inputs updated and deployed."

# Dry-run variant: full flake update + build only, NO deploy. Use to catch
# breaking changes (nixpkgs moves, hermes-cli.nix patch mismatches) before
# committing the cluster to a full switch in a maintenance window.
hermes-update-check:
    #!/usr/bin/env bash
    set -euo pipefail
    cd {{FLAKE}}
    echo "Bumping ALL flake inputs to latest upstream..."
    nix flake update 2>&1 | tail -5
    echo "Building zephyr toplevel to verify hermes-cli.nix patches + all inputs apply..."
    nix build --no-link --print-out-paths \
        .#nixosConfigurations.zephyr.config.system.build.toplevel 2>&1 | tail -20 \
        && echo "OK: everything builds. Run 'just hermes-update' to deploy."

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