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

HOSTS := "zephyr nexus forge sentry"

# Local secretspec fork paths — overridable so CI runners / other users can
# point at their own clones without forking the recipe per-env. Defaults
# resolve to ~/. The cachix fork (`secretspec-core`) supplies the CLI binary
# + sops Provider module. The provider fork (`secretspec`) supplies the
# NDJSON dispatcher binary spawned by cachix's SopsProvider at runtime.
LOCAL_SECRETSPEC_CORE := env_var_or_default('SECRETSPEC_LOCAL_CORE', env_var('HOME') + '/Projects/secretspec-core')
LOCAL_SECRETSPEC_PROVIDER := env_var_or_default('SECRETSPEC_LOCAL_PROVIDER', env_var('HOME') + '/Projects/secretspec')
LOCAL_SECRETSPEC_PROVIDER_DIR := LOCAL_SECRETSPEC_PROVIDER + '/provider-rust'

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
    set -euo pipefail
    # G4 gate: confirm source-of-truth + nexus builder agree on canonical before building.
    {{FLAKE}}/scripts/preflight-check.sh 2>&1 | sed 's/^/  [preflight] /' || {
        echo "Preflight BLOCKED deploy (nexus/local drift or in-flight build). Fix and retry." >&2
        exit 1
    }
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
            if [ "$host" = "zephyr" ]; then
                # Zephyr never builds locally (31GB OOM) — build on nexus, copy back, activate.
                OUT=$({{FLAKE}}/scripts/remote-build.sh zephyr zephyr-deploy | tail -1)
                echo "  copying closure..."
                ssh nexus "nix-copy-closure --to j_kro@zephyr $OUT" 2>&1 | grep -v "copying path\|already exists" || true
                echo "  activating..."
                sudo nix-env -p /nix/var/nix/profiles/system --set "$OUT"
                sudo "$OUT/bin/switch-to-configuration" switch 2>&1 | tail -10
            else
                sudo nixos-rebuild switch --flake {{FLAKE}}#$host 2>&1
            fi
            echo "done"
        else
            # Building for a REMOTE host (nexus/forge/sentry) from local (zephyr)
            # Offload build to nexus to avoid OOM on zephyr.
            # PIPELINE INTEGRITY: nexus is a build executor only — force its
            # /etc/nixos to the canonical ref BEFORE building so the produced
            # toplevel reflects origin/main, never nexus's drifted local checkout.
            ssh nexus "bash --norc --noprofile -c 'set -e; cd /etc/nixos; git fetch origin main 2>&1 | tail -1; git reset --hard origin/main 2>&1 | tail -1'" 2>&1 | tail -1
            # `--option pure-eval false` is REQUIRED for hosts with a cachix
            # fork present at ~/Projects/secretspec-core. Without it, the
            # secretspec derivation silently falls back to the upstream
            # tarball (no sops://) on the cluster-side rebuild. CI runners
            # (no fork) still work via the fall-through branch.
            OUT=$(ssh nexus "cd /etc/nixos && nix build --option pure-eval false --no-link --print-out-paths '.#nixosConfigurations.$host.config.system.build.toplevel'" 2>/dev/null) || {
                echo "Build failed for $host"; exit 1
            }
            nix-copy-closure --to j_kro@$host "$OUT" 2>&1 | grep -v "copying path\|already exists" || true
            ssh j_kro@$host "sudo nix-env -p /nix/var/nix/profiles/system --set $OUT && sudo $OUT/bin/switch-to-configuration switch" 2>&1 | tail -5
            echo "done"
        fi
    done
    echo ""
    echo "Deploy complete. Verify with 'just health'"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Syncing cluster nodes to central repo..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    cd {{FLAKE}}
    git push central main 2>/dev/null || echo "central push failed"
    for host in nexus forge sentry; do
        echo -n "  $host ... "
        if ssh "$host" "cd /etc/nixos && git stash 2>/dev/null; git pull --ff-only central main" >/dev/null 2>&1; then
            echo "OK"
        else
            echo "FAILED"
        fi
    done
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "All nodes synced"

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
    # FOOTGUN GUARD (G3): zephyr's colmena node has targetHost=null, which
    # colmena interprets as "deploy to localhost (wherever colmena runs)".
    # Since this runs ON nexus, 'just deploy-nexus zephyr' would apply
    # ZEPHYR'S CONFIG TO NEXUS. Hard-refuse zephyr and the all-aggregate.
    if [ "$HOST" = "zephyr" ] || [ "$HOST" = "all" ]; then
        echo "ERROR: 'just deploy-nexus $HOST' would apply config to nexus (zephyr node has targetHost=null)." >&2
        echo "       Use 'just deploy zephyr' (builds on nexus, activates on zephyr) instead." >&2
        exit 1
    fi
    SESSION="deploy-nexus-${HOST}"
    LOG="/var/log/colmena-deploy-${HOST}.log"
    # PIPELINE INTEGRITY (G2): nexus evaluates the colmena hive from its LOCAL
    # /etc/nixos. Force it to the canonical ref so the hive matches origin/main.
    ssh nexus "bash --norc --noprofile -c 'set -e; cd /etc/nixos; git fetch origin main 2>&1 | tail -1; git reset --hard origin/main 2>&1 | tail -1'" 2>&1 | tail -1
    # Use the flake's OWN colmena app (.#colmena = 0.5.0-pre built from
    # flake.nix colmena input). Using 'nixpkgs#colmena' drifts to the
    # channel-pinned 0.4.0 binary, which cannot evaluate a 0.5.0-style
    # 'colmenaHive' flake attribute ('cannot update unlocked flake
    # input hive in pure mode'). .#colmena is version-correct by
    # construction and survives future colmena bumps.
    # --option pure-eval false MUST come BEFORE the `run` subcommand (it's
    # argument-position-sensitive in Nix CLI). Same rationale as elsewhere in
    # this justfile: flake pure-eval disallows probing absolute paths to
    # ~/Projects/secretspec-core and ~/Projects/secretspec/provider-rust,
    # so without this option each host's colmena-applied toplevel silently
    # falls through to the upstream cachix tarball (no sops://).
    CMD="cd /etc/nixos && nix --option pure-eval false run .#apps.x86_64-linux.colmena -- apply --on ${HOST} --eval-node-limit 100 | tee ${LOG}"
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
    # zephyr must NOT use colmena-on-nexus (targetHost=null footgun) — route to correct path.
    just deploy zephyr
deploy-nexus-forge:
    just deploy-nexus forge
deploy-nexus-sentry:
    just deploy-nexus sentry
deploy-nexus-all:
    # 'all' includes zephyr, which is unsafe via colmena-on-nexus (G3). Deploy each host by its correct path.
    just deploy nexus
    just deploy forge
    just deploy sentry
    just deploy zephyr

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
    set -euo pipefail
    cd {{FLAKE}}
    HOST=$(hostname -s)
    if [ "$HOST" = "zephyr" ]; then
        # Zephyr never builds locally (31GB OOM). Use remote-build.sh which
        # runs nix build directly ON nexus via systemd-run -- avoiding the
        # ssh-ng remote-build pipe-draining wedge (NixOS/nix#5701).
        exec {{FLAKE}}/scripts/remote-build.sh zephyr zephyr-build
    else
        NIX_SSHOPTS="-o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ConnectTimeout=30" \
        # --option pure-eval false is required on hosts with a cachix fork
        # checkout at ~/Projects/secretspec-core so flake eval probes the
        # absolute local-fork path and selects the buildRustPackage branch
        # (with sops://) instead of falling back to the upstream tarball.
        # See pkgs/secretspec/default.nix header comment for full rationale.
        nix build --option pure-eval false --builders 'ssh-ng://j_kro@nexus' --no-link --print-out-paths .#$HOST
    fi

switch:
    #!/usr/bin/env bash
    set -euo pipefail
    cd {{FLAKE}}
    {{FLAKE}}/scripts/preflight-check.sh 2>/dev/null || true
    HOST=$(hostname -s)
    if [ "$HOST" = "zephyr" ]; then
        echo "Building on nexus for $HOST..."
        OUT=$({{FLAKE}}/scripts/remote-build.sh zephyr zephyr-switch | tail -1)
        echo "  copying closure to $HOST..."
        ssh nexus "nix-copy-closure --to j_kro@${HOST} $OUT" 2>&1 | grep -v "copying path\|already exists" || true
        echo "  activating..."
        sudo nix-env -p /nix/var/nix/profiles/system --set "$OUT"
        sudo "$OUT/bin/switch-to-configuration" switch 2>&1 | tail -10
    else
        sudo nixos-rebuild switch --flake .#$HOST
    fi

test-apply:
    #!/usr/bin/env bash
    set -euo pipefail
    cd {{FLAKE}}
    HOST=$(hostname -s)
    if [ "$HOST" = "zephyr" ]; then
        echo "Building on nexus for $HOST (test)..."
        OUT=$({{FLAKE}}/scripts/remote-build.sh zephyr zephyr-test)
        echo "  copying closure to $HOST..."
        ssh nexus "nix-copy-closure --to j_kro@${HOST} '$OUT'" 2>&1 | grep -v "copying path\|already exists" || true
        echo "  testing..."
        sudo "$OUT/bin/switch-to-configuration" test 2>&1 | tail -10
    else
        sudo nixos-rebuild test --flake .#$HOST
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

# ── NODE SYNC ─────────────────────────────────────────────────────────────────

# Pull central repo on all cluster nodes (keeps them in sync after deploy)
sync-nodes:
    #!/usr/bin/env bash
    set -e
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Syncing all cluster nodes to central repo..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    for host in {{HOSTS}}; do
        if [ "$host" = "$(hostname -s)" ]; then
            echo "Skipping local ($host)"
            continue
        fi
        echo -n "  $host ... "
        if ssh "$host" "cd /etc/nixos && git stash 2>/dev/null; git pull --ff-only central main" >/dev/null 2>&1; then
            echo "OK"
        else
            echo "FAILED"
        fi
    done
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "All nodes synced"

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
    # --option pure-eval false is required to trigger the cachix-fork
    # buildRustPackage branch (which carries the sops:// subprocess
    # Dispatcher module) for transitively-included pkgs.secretspec.
    nix build --option pure-eval false --no-link --print-out-paths \
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
    # --option pure-eval false required for the same reason as hermes-update
    # above: pkgs.secretspec inside zephyr's toplevel needs the cachix-fork
    # branch selected to ship sops:// provider registration at runtime.
    nix build --option pure-eval false --no-link --print-out-paths \
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
    # No --option pure-eval false: k8s manifests don't transitively depend on
    # pkgs.secretspec (they're YAML/Kustomize), so flake pure-eval restrictions
    # don't apply. Other recipes in this justfile still need the flag for the
    # cachix-fork buildRustPackage path (validate-local, build, hermes-update*,
    # deploy-nexus) — those reach `builtins.pathExists` on the local fork.
    nix build .#kubernetesManifests 2>/dev/null && echo "K8s manifests built" || nix run .#k8s-validate 2>/dev/null || echo "k8s-validate not available"

# Validate all *.yaml/*.yml files in the repo. Lenient of Nix toJSON, SOPS, and
# Helm output (tab indentation, JSON-as-YAML). Surfaces real syntax errors.
validate-yaml *paths:
    #!/usr/bin/env bash
    set -e
    cd {{FLAKE}}
    if [ "$#" -eq 0 ]; then
        exec python3 scripts/yaml-validate.py
    fi
    exec python3 scripts/yaml-validate.py "$@"

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

# ── STATUS REGEN ─────────────────────────────────────────────────────────────
# Regenerate STATUS.md manually. The hourly status-update.timer (declared
# in modules/system/status-auto-update.nix) runs the same script. Use this
# recipe after editing cluster-state.nix to preview the diff before the
# next scheduled regen. The script aborts BEFORE clobbering STATUS.md if
# nix/jq/kubectl are missing or if cluster-state.nix is missing — so this
# is safe to run from a fresh shell with incomplete toolchain.
status-regen:
    sudo /etc/nixos/scripts/update-status.sh

# ── SECRETSPEC ──────────────────────────────────────────────────────────────────
# Validate secretspec.toml against the cluster's declared schema. Wraps
# `secretspec check` with the cluster's prod manifest path. The
# modules/system/secretspec-validator systemd unit invokes this on every
# activation; run manually for pre-deploy validation.

# Validate every required secret in secretspec.toml resolves under the
# production profile. Exits non-zero on any unresolved required secret.
secretspec-check:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -v secretspec >/dev/null 2>&1; then
        echo "secretspec not on PATH - built via /etc/nixos/pkgs/secretspec + overlay wiring" >&2
        exit 127
    fi
    secretspec check \
        --manifest /etc/nixos/secretspec.toml \
        --profile production

# List every declared secret grouped by category. Useful for audit + new-member
# onboarding ("what does the cluster expect, in human terms?").
secretspec-list:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -v secretspec >/dev/null 2>&1; then
        echo "secretspec not on PATH - built via /etc/nixos/pkgs/secretspec + overlay wiring" >&2
        exit 127
    fi
    secretspec list --manifest /etc/nixos/secretspec.toml

# Phase-2 manual bridge: proves that the local `secretspec-provider-sops`
# CLI can decrypt a real sops:// route (the cluster's #1 missing piece
# until cachix/secretspec#98 lands the Provider-trait exposure).
#
# Flow: provider-sops get <file> <key> --format dotenv > /tmp/.env.bridge
#       secretspec check -f secretspec-bridge.toml   (uses /tmp/.env.bridge)
#
# Override SECRET_FILE / SECRET_KEY to demo other routes. The bridge CLI
# is built via `pkgs/secretspec-provider-sops` — `nix shell .#secretspec-provider-sops`
# puts it on PATH without a permanent install. Once upstream lands, this
# recipe becomes obsolete (the same route works natively with
# `providers = ["sops"]`).
secretspec-bridge-demo:
    #!/usr/bin/env bash
    set -euo pipefail
    PROVIDER_SOPS=$(command -v secretspec-provider-sops || true)
    if [ -z "$PROVIDER_SOPS" ]; then
        echo "secretspec-provider-sops not on PATH" >&2
        echo "  Hint: nix shell .#secretspec-provider-sops" >&2
        exit 127
    fi
    SECRET_FILE="${SECRET_FILE:-/etc/nixos/secrets/ci/github-token.yaml}"
    SECRET_KEY="${SECRET_KEY:-github_token}"
    BRIDGE_OUT="${BRIDGE_OUT:-/tmp/.env.bridge}"
    trap "rm -f $BRIDGE_OUT" EXIT INT TERM
    if [ ! -f "$SECRET_FILE" ]; then
        echo "missing: $SECRET_FILE" >&2
        exit 2
    fi
    echo "[bridge] decrypting $SECRET_FILE#${SECRET_KEY} via secretspec-provider-sops..."
    if ! "$PROVIDER_SOPS" get "$SECRET_FILE" "$SECRET_KEY" --format dotenv > "$BRIDGE_OUT" 2>/dev/null; then
        echo "[bridge] decrypt failed (check \$HOME/.config/sops/age/keys.txt)" >&2
        exit 3
    fi
    echo "[bridge] verifying via secretspec check (manifest: secretspec-bridge.toml)..."
    secretspec check -f /etc/nixos/secretspec-bridge.toml
    echo "[bridge] OK: secretspec-provider-sops decrypted $SECRET_FILE and secretspec check passed"

# Audit table: each script in scripts/ + its first comment line as
# description, plus every just recipe at the bottom. Surfaces the
# ~118 vs ~30 split so "what does X do" never gets the wrong-name answer.
catalog:
    #!/usr/bin/env bash
    cd /etc/nixos
    printf '=== scripts/ (top-level dispatchers) ===\n'
    for s in scripts/*.sh scripts/*.py; do
        [ -f "$s" ] || continue
        # First non-blank comment line of the file, normalized as description
        desc=$(grep -m1 -E '^[[:space:]]*(#|""")' "$s" 2>/dev/null | sed -E 's/^[[:space:]]*(#|""")[[:space:]]*//' | head -c 80)
        printf '  %-40s %s\n' "$(basename "$s")" "$desc"
    done
    printf '\n=== just recipes ===\n'
    just --list --unsorted 2>/dev/null || just --list

# Show every hermes-agent MCP server this cluster exports plus the
# secretspec provider chain. Greps the nixos-cluster-mcp package for
# `name = "..."` rows (the schema source-of-truth).
mcp-list:
    #!/usr/bin/env bash
    cd /etc/nixos
    printf '=== Cluster MCP servers (nixos-cluster-mcp) ===\n'
    grep -rnE '^[[:space:]]*name[[:space:]]*=[[:space:]]*"[a-z][-a-z0-9_/.]+"' packages/nixos-cluster-mcp/ 2>/dev/null \
        | sed -E 's/.*name = "([^"]+)".*/  \1/' \
        | sort -u || true
    printf '\n=== secretspec providers ===\n'
    grep -E '^[a-z_]+\s*=\s*"[a-z]+://' /etc/nixos/secretspec.toml 2>/dev/null \
        | sed -E 's/^[[:space:]]*([a-z_]+).*=.*/  \1/' \
        | sort -u

# ── DUAL-FORK SECRETSPEC CI/CD ───────────────────────────────────────────────
# The cluster builds secretspec from TWO local forks:
#   ~/$Projects/secretspec-core/   — cachix/secretspec fork + sops Provider
#   ~/$Projects/secretspec/        — provider-rust fork + NDJSON dispatcher
# These recipes keep them in sync with upstream and rebuild the closure.

# Show ahead/behind commit counts + working-tree state for both forks.
secretspec-fork-status:
    #!/usr/bin/env bash
    set -e
    printf '=== cachix fork (%s) ===\n' '{{LOCAL_SECRETSPEC_CORE}}'
    if [ -d '{{LOCAL_SECRETSPEC_CORE}}' ]; then
        (cd '{{LOCAL_SECRETSPEC_CORE}}' && \
            BR=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) && \
            UPSTREAM=$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null || echo "no upstream") && \
            echo "branch: $BR  upstream: $UPSTREAM" && \
            AHEAD=$(git rev-list --count @{u}..HEAD 2>/dev/null || echo "?") && \
            BEHIND=$(git rev-list --count HEAD..@{u} 2>/dev/null || echo "?") && \
            echo "ahead: $AHEAD  behind: $BEHIND (rebase target if non-zero)" && \
            git status --short | head -5)
    else
        echo 'NOT CLONED. Run: just secretspec-fork-bootstrap'
    fi
    printf '\n=== provider fork (%s) ===\n' '{{LOCAL_SECRETSPEC_PROVIDER}}'
    if [ -d '{{LOCAL_SECRETSPEC_PROVIDER}}' ]; then
        (cd '{{LOCAL_SECRETSPEC_PROVIDER}}' && \
            BR=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) && \
            UPSTREAM=$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null || echo "no upstream") && \
            echo "branch: $BR  upstream: $UPSTREAM" && \
            AHEAD=$(git rev-list --count @{u}..HEAD 2>/dev/null || echo "?") && \
            BEHIND=$(git rev-list --count HEAD..@{u} 2>/dev/null || echo "?") && \
            echo "ahead: $AHEAD  behind: $BEHIND" && \
            git status --short | head -5)
    else
        echo 'NOT CLONED. Run: just secretspec-fork-bootstrap'
    fi

# Sync cachix fork (~/Projects/secretspec-core) with upstream — rebase, no
# merge. Fails loud if merge-tree would conflict (the user resolves manually).
secretspec-core-sync:
    #!/usr/bin/env bash
    set -euo pipefail
    cd '{{LOCAL_SECRETSPEC_CORE}}'
    git fetch upstream main 2>&1 | tail -1
    # merge-tree dry-run detects changed-in-both conflicts before the actual
    # rebase; exit 1 → dump exit so the operator knows to rebase manually.
    if git merge-tree $(git merge-base HEAD @{u}) HEAD @{u} | grep -q '^changed in both'; then
        echo 'CONFLICT detected in merge-tree dry-run. Run manual rebase:' >&2
        echo '  cd ~/Projects/secretspec-core && git rebase -i upstream/main' >&2
        exit 1
    fi
    git rebase upstream/main
    echo 'cachix fork rebased onto upstream/main. NEXT: just secretspec-rebuild'

# Sync provider fork (~/Projects/secretspec) with upstream — rebase, no merge.
secretspec-provider-sync:
    #!/usr/bin/env bash
    set -euo pipefail
    cd '{{LOCAL_SECRETSPEC_PROVIDER}}'
    git fetch upstream main 2>&1 | tail -1
    if git merge-tree $(git merge-base HEAD @{u}) HEAD @{u} | grep -q '^changed in both'; then
        echo 'CONFLICT detected. Manual rebase:' >&2
        echo '  cd ~/Projects/secretspec && git rebase -i upstream/main' >&2
        exit 1
    fi
    git rebase upstream/main
    echo 'provider fork rebased onto upstream/main. NEXT: just secretspec-rebuild'

# Rebuild the cluster's Nix closure for BOTH secretspec packages. Uses local
# forks when present (~/Projects/*), falls back to upstream GH fetches when
# absent. Runs `pkgs.secretspec` and `pkgs.secretspec-provider-sops` build
# in parallel to halve wall-clock time.
secretspec-rebuild:
    #!/usr/bin/env bash
    set -euo pipefail
    cd /etc/nixos
    ./scripts/validate-secretspec-stack.sh --env --binary --schema || true
    # Two builds run as parallel subprocesses — `&` + `wait` halves wall-clock
    # vs running serially. Cachix-push is best-effort (`|| echo`) so a flaky
    # cache upload doesn't fail the rebuild.
    # `--option pure-eval false` is REQUIRED for both builds: the cachix
    # fork path lives outside the flake's directory tree (at
    # /home/j_kro/Projects/secretspec-core) and flake pure-eval (the
    # default on Lix 2.95.2+ and Nix 2.20+) prevents `builtins.pathExists`
    # from probing external paths. Without the option, pure mode silently
    # evaluates the `else` branch (upstream cachix tarball, no sops://)
    # and the cluster either has no sops feature at all or the build Rust
    # step fails because the local-fork derivation never evaluates.
    echo "[rebuild] Building pkgs/secretspec + pkgs/secretspec-provider-sops in parallel..."
    ( nix build --option pure-eval false --no-link --print-out-paths .#secretspec > /tmp/secretspec-rebuild-out 2>&1 ) &
    PID_A=$!
    ( nix build --option pure-eval false --no-link --print-out-paths .#secretspec-provider-sops > /tmp/secretspec-provider-rebuild-out 2>&1 ) &
    PID_B=$!
    wait "$PID_A" "$PID_B" || { echo "[rebuild] at least one nix build failed:"; sed 's/^/  /' /tmp/secretspec-rebuild-out /tmp/secretspec-provider-rebuild-out; exit 1; }
    OUT_SECRETSPEC=$(tail -1 /tmp/secretspec-rebuild-out)
    OUT_PROVIDER=$(tail -1 /tmp/secretspec-provider-rebuild-out)
    rm -f /tmp/secretspec-rebuild-out /tmp/secretspec-provider-rebuild-out
    echo "[rebuild] secretspec → $OUT_SECRETSPEC"
    echo "[rebuild] secretspec-provider-sops → $OUT_PROVIDER"
    if [ -n "${CACHIX_AUTH_TOKEN:-}" ]; then
        echo "[rebuild] pushing to cachix (best-effort)..."
        cachix push nixos-cluster-mcp "$OUT_SECRETSPEC" "$OUT_PROVIDER" || echo "  cachix push failed (cache best-effort)"
    fi
    echo "[rebuild] OK"

# End-to-end local validation — ephemeral age keypair, never touches real
# secrets. Mirrors the provider fork's CI bridge fixture (commit 43eadc6).
# Used by: pre-commit, GitHub Actions secretspec-build job, manual sanity
# checks before deploying cluster changes.
secretspec-validate-local:
    #!/usr/bin/env bash
    set -euo pipefail
    cd /etc/nixos
    BDIR=$(mktemp -d -t secretspec-bridge-XXXXXX)
    trap 'rm -rf "$BDIR"' EXIT INT TERM
    cd "$BDIR"
    echo '[ci] Generating ephemeral AGE keypair...'
    age-keygen -o test-age.key >/dev/null 2>&1 || { echo 'age-keygen not found; install nixpkgs#age'; exit 1; }
    AGE_PUB=$(grep '^# public key:' test-age.key | awk '{print $NF}')
    echo '[ci] Encrypting dummy payload with sops...'
    printf 'ci_dummy_secret: "ci-dummy-value"\n' > test-fixture.yaml
    SOPS_AGE_KEY_FILE=test-age.key sops --encrypt --age "$AGE_PUB" --in-place test-fixture.yaml
    # Manifest content lives in a separate template under scripts/ (not inline
    # heredoc) so this recipe body stays pure 4-space-indented. just's parser
    # rejects ANY tab/space mix inside a single recipe body — a heredoc with
    # tab-indented content lines was previously interpreted as a new recipe
    # header `[profiles.default]`, breaking the parse (line 907 of the
    # previously-broken state). Template substitutes @BDIR@ via sed after cp.
    cp /etc/nixos/scripts/test-bridge-manifest.toml "$BDIR/test-manifest.toml"
    sed -i "s|@BDIR@|$BDIR|g" "$BDIR/test-manifest.toml"
    # Cluster-path alignment: build BOTH binaries via `nix build
    # --no-link --print-out-paths` against /etc/nixos flake outputs so this
    # recipe exercises the same closure the cluster side rebuild produces
    # (via `just secretspec-rebuild`). Earlier iterations used `cargo build`
    # directly which produced a feature-correct binary but bypassed the
    # Nix-store path entirely — useful during the buildFeatures debugging
    # phase, but it diverged from the cluster rebuild path and would have
    # silently passed validate-local while the cluster rebuild was still
    # broken. The cachix fork (pkgs/secretspec, via $LOCAL_SECRETSPEC_CORE)
    # AND the provider fork (pkgs/secretspec-provider-sops, via
    # $LOCAL_SECRETSPEC_PROVIDER) are independent Nix derivations, so we
    # invoke each separately and capture its own store path. Build logs are
    # tee'd to /tmp so a nix-build failure leaves the diagnostic context
    # behind regardless of pass/fail.
    #
    # Pre-build fork-existence guard: a fresh-clone host (CI runner, new
    # operator) without ~/Projects/secretspec-core checked out would
    # otherwise hit a cryptic "path /nix/store/...-secretspec-0.16.0...
    # does not exist" from nix build (the derivation evaluates but the
    # buildRustPackage branch with src=localForkPath fails the
    # builtins.pathExists short-circuit and falls back to the upstream
    # tarball mkDerivation branch — which has NO sops feature). Fail-fast
    # with the bootstrap hint instead.
    SECRETSPEC_LOG=/tmp/secretspec-validate-build-cachix-fork.log
    SOPS_LOG=/tmp/secretspec-validate-build-provider-rust.log
    CACHIX_FORK='{{LOCAL_SECRETSPEC_CORE}}'
    PROVIDER_FORK='{{LOCAL_SECRETSPEC_PROVIDER_DIR}}'
    [ -d "$CACHIX_FORK" ] || { echo "missing fork dir: $CACHIX_FORK (run: just secretspec-fork-bootstrap)"; exit 1; }
    [ -d "$PROVIDER_FORK" ] || { echo "missing fork dir: $PROVIDER_FORK (provider-rust subdir of cachix fork rev)"; exit 1; }
    echo '[ci] Building pkgs/secretspec via nix build (cluster-path)...'
    # `--option pure-eval false` is REQUIRED here (Lix 2.95.2 + Nix flake
    # default = `pure-eval = true`): without it, `builtins.pathExists
    # /home/j_kro/Projects/secretspec-core` in pkgs/secretspec/default.nix
    # silently evaluates to `false` (paths outside the flake tree are
    # unreadable in pure mode), the `else mkDerivation` upstream-tarball
    # branch fires, and the resulting binary has no `SopsProvider`
    # registration (the upstream cachix tarball doesn't ship with the
    # sops:// provider module — it's an out-of-tree fork addition).
    # With `--option pure-eval false`, flake eval relaxes the absolute-path
    # restriction, the local-fork branch evaluates, buildRustPackage +
    # buildAndTestSubdir + cargoBuildFlags all fire correctly, and the
    # output store path includes `local-fork.1` (e.g.
    # `/nix/store/...-secretspec-0.16.0-local-fork.1`) instead of plain
    # `0.16.0` (upstream tarball).
    SECRETSPEC_OUT=$(nix --extra-experimental-features 'nix-command flakes' \
        build --option pure-eval false --no-link --print-out-paths /etc/nixos#secretspec 2>"$SECRETSPEC_LOG") \
        || { echo "nix build /etc/nixos#secretspec failed; full build log: $SECRETSPEC_LOG" >&2; tail -20 "$SECRETSPEC_LOG" >&2; exit 1; }
    echo '[ci] Building pkgs/secretspec-provider-sops via nix build (cluster-path)...'
    SOPS_OUT=$(nix --extra-experimental-features 'nix-command flakes' \
        build --option pure-eval false --no-link --print-out-paths /etc/nixos#secretspec-provider-sops 2>"$SOPS_LOG") \
        || { echo "nix build /etc/nixos#secretspec-provider-sops failed; full build log: $SOPS_LOG" >&2; tail -20 "$SOPS_LOG" >&2; exit 1; }
    # Sanity: confirm the freshly-built binary actually came from the
    # buildRustPackage branch (local-fork compile with sops feature) and
    # not the upstream-tarball fallback (which lacks sops://). Missing
    # `local-fork.1` in the store path means pure-eval re-fell-through to
    # the else branch on a host where the local fork path doesn't exist.
    case "$SECRETSPEC_OUT" in
        *local-fork.1*) echo "[ci] OK: secretspec built from local fork (sops feature enabled)" ;;
        *) echo "[ci] WARN: secretspec binary is the upstream tarball (no sops:// support). Local fork at $CACHIX_FORK missing? Run: just secretspec-fork-bootstrap" >&2 ;;
    esac
    SECRETSPEC_BIN="$SECRETSPEC_OUT/bin/secretspec"
    SOPS_DISPATCHER="$SOPS_OUT/bin/secretspec-provider-sops-protocol"
    [ -x "$SECRETSPEC_BIN" ] || { printf 'secretspec bin missing: %s\n' "$SECRETSPEC_BIN" >&2; exit 1; }
    [ -x "$SOPS_DISPATCHER" ] || { printf 'provider dispatcher missing: %s\n' "$SOPS_DISPATCHER" >&2; exit 1; }
    echo '[ci] Binaries ready:' && ls -la "$SECRETSPEC_BIN" "$SOPS_DISPATCHER"
    echo '[ci] Running secretspec check against ephemeral sops:// route...'
    # `SECRETSPEC_SOPS_PROVIDER_BIN` is read by cachix fork's
    # `SopsProvider::dispatcher_binary()` (env override before `which`
    # fallback). Pointing it at the freshly-built provider-rust-protocol
    # binary lets the cachix fork dispatch in-process keystore resolution to
    # NDJSON over stdio, which then shells out to `sops --decrypt` with the
    # ephemeral age keyfile we generated above.
    SOPS_AGE_KEY_FILE=test-age.key \
    SECRETSPEC_SOPS_PROVIDER_BIN="$SOPS_DISPATCHER" \
        "$SECRETSPEC_BIN" check -f test-manifest.toml
    echo '[ci] End-to-end provider chain validated successfully.'

# One-shot bootstrapper: clones cachix/secretspec to ~/Projects/secretspec-core
# on a feature/sops-provider-subprocess-dispatch branch, then applies the
# local secretspec-fork-patches/0001-add-sops-provider.patch. Idempotent.
# Path defaults to $HOME/Projects/secretspec-core; override via
# SECRETSPEC_LOCAL_CORE env var.
secretspec-fork-bootstrap:
    #!/usr/bin/env bash
    set -euo pipefail
    LOCAL_CORE='{{LOCAL_SECRETSPEC_CORE}}'
    PATCH=/etc/nixos/secretspec-fork-patches/0001-add-sops-provider.patch
    if [ -d "$LOCAL_CORE" ]; then
        echo "[bootstrap] $LOCAL_CORE already exists. To re-bootstrap: rm -rf $LOCAL_CORE"
        exit 0
    fi
    echo "[bootstrap] Cloning cachix/secretspec → $LOCAL_CORE (shallow)..."
    git clone --depth=200 https://github.com/cachix/secretspec.git "$LOCAL_CORE"
    (cd "$LOCAL_CORE" && \
        git remote rename origin upstream && \
        git remote add upstream https://github.com/cachix/secretspec.git && \
        git fetch upstream --unshallow 2>/dev/null || true)
    echo "[bootstrap] Creating feature branch..."
    (cd "$LOCAL_CORE" && git checkout -b feature/sops-provider-subprocess-dispatch)
    if [ -f "$PATCH" ]; then
        echo "[bootstrap] Applying $PATCH..."
        (cd "$LOCAL_CORE" && git apply --index "$PATCH")
        echo '[bootstrap] Patch applied. Review and commit with:'
        echo "  cd $LOCAL_CORE && git status"
        echo '  cd '"$LOCAL_CORE"' && git commit -m "feat: SOPS provider via subprocess NDJSON dispatcher"'
    else
        echo "[bootstrap] WARN: $PATCH not found — skipping apply step"
    fi
    echo '[bootstrap] Done. Run `just secretspec-fork-status` to verify.'

# Run all linters in check mode (no changes). Exits non-zero on any issue.
# Used by CI (ci.yml) and for pre-commit checks.
lint:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "=== alejandra --check ==="
    alejandra --check --exclude modules/system/agenix-secrets-registry.nix --exclude modules/home-manager/default.nix --exclude modules/services/spacebot/container.nix --exclude kubernetes/modules .
    echo "=== statix check ==="
    statix check
    echo "=== deadnix ==="
    deadnix --fail --no-lambda-arg --no-lambda-pattern-names

# Format all .nix files with alejandra (in-place).
fmt:
    alejandra --exclude modules/system/agenix-secrets-registry.nix --exclude modules/home-manager/default.nix --exclude modules/services/spacebot/container.nix --exclude kubernetes/modules .

# ── Mosaic Identity Service ──────────────────────────────────────────────────

# Build MIS Docker image and push to local registry
mosaic-build:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Building MIS on nexus..."
    ssh nexus "cd /home/j_kro/Projects/astral-key && \
        docker build -t nexus:5000/mosaic-identity:latest -f Dockerfile . && \
        docker push nexus:5000/mosaic-identity:latest"
    echo "MIS image pushed to nexus:5000/mosaic-identity:latest"

# Deploy MIS to cluster
mosaic-deploy:
    kubectl apply -f /etc/nixos/k8s/mosaic-identity/
    echo "MIS deployed. Check: kubectl -n orchestration get pods -l app=mosaic-identity"

# Deploy all bridge plugins
mosaic-bridges-deploy:
    kubectl apply -f /etc/nixos/k8s/mosaic-bridges/
    echo "Bridges deployed."

# Deploy MIS + all bridges
mosaic-up: mosaic-build mosaic-deploy mosaic-bridges-deploy

# Check MIS status
mosaic-status:
    kubectl -n orchestration get pods -l app=mosaic-identity
    kubectl -n orchestration get svc mosaic-identity
    echo "---"
    kubectl -n orchestration get pods -l 'app in (mosaic-bridge-atproto, mosaic-bridge-buzz, mosaic-bridge-matrix, mosaic-bridge-irc)' 2>/dev/null || echo "No bridge pods running"
    echo "---"
    # Quick health check via port-forward
    echo "MIS endpoint check:"
    kubectl -n orchestration run mis-test --image=curlimages/curl --restart=Never --rm -it -- \
        curl -s http://mosaic-identity:8081/health 2>/dev/null || echo "Port-forward not available"

# Tail MIS logs
mosaic-logs:
    kubectl -n orchestration logs -l app=mosaic-identity --tail=50 -f

# Destroy MIS + bridges
mosaic-down:
    kubectl delete -f /etc/nixos/k8s/mosaic-identity/ 2>/dev/null || true
    kubectl delete -f /etc/nixos/k8s/mosaic-bridges/ 2>/dev/null || true
    echo "MIS removed from cluster."
