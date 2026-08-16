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
# Nexus is the exclusive build/deployment dispatcher: build/apply from there
# to keep Zephyr light while Zephyr remains the authoring source of truth.

# Dispatch deployment through Nexus. Zephyr remains the authoring/source-of-truth host;
# Nexus performs the canonical build and Colmena activation.
deploy host="all":
    #!/usr/bin/env bash
    set -euo pipefail
    # MANDATORY preflight — never bypass
    {{FLAKE}}/scripts/preflight-check.sh 2>&1 | sed 's/^/  [preflight] /' || {
        echo "Preflight BLOCKED deploy (drift or in-flight build). Fix and retry." >&2
        exit 1
    }
    exec {{FLAKE}}/scripts/deploy/nexus-dispatch.sh --sync --target "{{host}}"

# Submit a disconnect-safe deployment to Nexus. The command returns after
# creating the Nexus-side tmux job; inspect the reported log/session.
deploy-async host="all":
    #!/usr/bin/env bash
    set -euo pipefail
    # MANDATORY preflight — never bypass
    {{FLAKE}}/scripts/preflight-check.sh 2>&1 | sed 's/^/  [preflight] /' || {
        echo "Preflight BLOCKED deploy (drift or in-flight build). Fix and retry." >&2
        exit 1
    }
    exec {{FLAKE}}/scripts/deploy/nexus-dispatch.sh --async --target "{{host}}"

# Legacy direct dispatcher retained as an emergency fallback only. It bypasses
# the Nexus dispatcher and must not be used for normal operations.
deploy-direct-legacy host="all":
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
            # PIPELINE INTEGRITY: nexus is the build/deployment executor — force its
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
            # G5 hostname guard (build side): refuse to deploy if the
            # built toplevel's hostname doesn't match the deploy target.
            # Catches the cross-host footgun that bricked nexus on 2026-07-28:
            # system-365-link pointed at nixos-system-forge-* while nexus's
            # fstab referenced forge's disk-sdb/sda partlabels and the boot
            # cascade-failed local-fs.target. Hard-refuse rather than recover.
            # Trailing '-' makes the substring safe against prefix collisions
            # (e.g. 'nexus' won't match 'nexus2' because '2' ≠ '-').
            if [[ "$OUT" != *"nixos-system-${host}-"* ]]; then
                echo "ERROR: build output '$OUT' does not match target host '$host' (expected 'nixos-system-${host}-*'). Aborting to prevent cross-host application." >&2
                exit 1
            fi
            # G5 hostname guard (target side): confirm the SSH'd host
            # actually reports the expected short hostname BEFORE we
            # push the closure. Catches DNS-alias / wrong-IP mistakes
            # and short-circuits wasted bandwidth. Use exact match on
            # the first label of the FQDN (Nexus reports 'nexus.lan',
            # forge 'forge.lan', etc.) — substring 'for' would otherwise
            # falsely match 'forge'.
            ACTUAL_HOSTNAME=$(ssh j_kro@$host "hostname" 2>/dev/null)
            ACTUAL_SHORT="${ACTUAL_HOSTNAME%%.*}"
            if [[ "$ACTUAL_SHORT" != "$host" ]]; then
                echo "ERROR: target '$host' reports hostname '$ACTUAL_HOSTNAME' (short '$ACTUAL_SHORT' ≠ expected '$host'). Aborting to prevent cross-host application." >&2
                exit 1
            fi
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

# ── CANARY DEPLOY (issue #341) ─────────────────────────────────────────────────
# Rolling deploy: one host at a time (nexus → forge → sentry → zephyr), with a
# post-switch health probe (sshd + load + per-host key services) after each
# activation, auto-rollback on failure, and fail-stop abort of remaining hosts.
deploy-canary *hosts:
    #!/usr/bin/env bash
    set -euo pipefail
    # Script defaults to the safe order (nexus forge sentry zephyr) with no args.
    exec {{FLAKE}}/scripts/deploy-canary.sh "$@"

# ── DEPLOY PROVENANCE / DRIFT (issue #342) ────────────────────────────────────
# Per-host: generation, active closure, git commit, .dirty flag, and whether it
# matches origin/main HEAD. Exits 1 on drift or .dirty closure.
provenance *hosts:
    #!/usr/bin/env bash
    set -euo pipefail
    # Script checks all hosts by default; pass hosts to narrow the report.
    exec {{FLAKE}}/scripts/cluster-provenance.sh "$@"

# Compatibility alias for the old recipe name. Both synchronous and
# asynchronous deployment now use the single Nexus dispatcher, which validates
# the canonical ref before starting and handles Zephyr's remote target safely.
deploy-nexus host:
    #!/usr/bin/env bash
    set -euo pipefail
    exec {{FLAKE}}/scripts/deploy/nexus-dispatch.sh --async --target "{{host}}"

# Attach to an in-progress Nexus deploy, or start it if missing.
deploy-nexus-attach host:
    #!/usr/bin/env bash
    set -euo pipefail
    HOST="{{host}}"
    SESSION="nixos-deploy-${HOST}"
    if ssh nexus "tmux has-session -t '$SESSION'" 2>/dev/null; then
        exec ssh -t nexus "tmux attach -t '$SESSION'"
    fi
    just deploy-nexus "$HOST"

# Tail the deploy log on Nexus without attaching.
deploy-nexus-logs host:
    #!/usr/bin/env bash
    set -euo pipefail
    HOST="{{host}}"
    LOG="/tmp/nixos-deploy-${HOST}.log"
    exec ssh nexus "tail -f '$LOG'"

# Stop an in-progress Nexus deploy.
deploy-nexus-stop host:
    #!/usr/bin/env bash
    set -euo pipefail
    HOST="{{host}}"
    SESSION="nixos-deploy-${HOST}"
    if ssh nexus "tmux has-session -t '$SESSION'" 2>/dev/null; then
        ssh nexus "tmux send-keys -t '$SESSION' C-c"
        sleep 1
        ssh nexus "tmux kill-session -t '$SESSION'"
        echo "stopped deploy session on nexus: $SESSION"
    else
        echo "no deploy session on nexus: $SESSION"
    fi

# Convenience shortcuts: all routes use the Nexus dispatcher.
deploy-nexus-zephyr:
    just deploy-async zephyr
deploy-nexus-forge:
    just deploy-async forge
deploy-nexus-sentry:
    just deploy-async sentry
deploy-nexus-all:
    just deploy-async all

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

# Standalone preflight check — run before any deploy
preflight:
    #!/usr/bin/env bash
    set -euo pipefail
    exec {{FLAKE}}/scripts/preflight-check.sh

check:
    #!/usr/bin/env bash
    set -e
    cd {{FLAKE}} && nix flake check --option pure-eval false

# Network-dependent cache provenance audit. This does not build; it evaluates
# host toplevel derivations and probes configured upstream/community/custom
# caches via narinfo. Expected custom misses are reported, not hidden.
cache-audit:
    #!/usr/bin/env bash
    set -euo pipefail
    cd {{FLAKE}} && exec ./scripts/cache-audit.sh

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
        sudo nixos-rebuild switch --flake .#$HOST --option pure-eval false
    fi

# ── HOME MANAGER (Layer 2) — independent cadence from NixOS (Layer 1) ──
# Activates j_kro's user env via `home-manager switch` WITHOUT a NixOS rebuild.
# NOTE: flake homeConfigurations keys are PLAIN host names (`zephyr`, not
# `j_kro@zephyr`) — the old `.#j_kro@${HOST}` refs could not resolve (and the
# zephyr branch would have activated zephyr's config ON nexus). Heavy builds
# offload via the ssh-ng remote builder on nexus (distributed-builds.nix).
# See issue #338 (3-layer separation).
hm-switch:
    #!/usr/bin/env bash
    set -euo pipefail
    
    HOST=$(hostname -s)
    echo ">> home-manager switch -b backup --flake github:reverb256/home-manager-config#${HOST}"
    # nexus is the sole healthy builder (forge excluded = GPU miner; sentry
    # known_hosts stale vs ssh.nix source). Use nexus-only so hm-switch does
    # not abort on the broken sentry/forge remote builders (see issue #389).
    # `-b backup` is the STANDALONE collision handler (home.backupFileExtension
    # is a NixOS-module-only option): HM moves any differing plain file to
    # <file>.backup and links the store version instead of aborting. Remove
    # stale <file>.backup files if a switch reports "would be clobbered".
    NIX_CONFIG='pure-eval = false; builders = ssh-ng://j_kro@nexus x86_64-linux,i686-linux ~/.ssh/id_ed25519 12 10 big-parallel,kvm' \
      home-manager switch -b backup --flake github:reverb256/home-manager-config#${HOST}

# Build (dry) the HM config for a host without activating — CI/verification.
hm-build host="zephyr":
    #!/usr/bin/env bash
    set -euo pipefail
    
    echo ">> home-manager build --flake github:reverb256/home-manager-config#{{host}}"
    NIX_CONFIG='pure-eval = false' \
      home-manager build --flake github:reverb256/home-manager-config#{{host}} 2>&1 | tail -20

# Audit HM state across all hosts: compare each host's LIVE home-manager
# generation against a fresh build of the CURRENT upstream commit
# (github:reverb256/home-manager-config). Store-path equality ⇒ the host runs
# exactly the committed config; anything else ⇒ STALE (drifted, or built from
# uncommitted local state — the failure mode that put zephyr's config on
# sentry). Exits 1 if any host is STALE.
hm-audit:
    #!/usr/bin/env bash
    set -euo pipefail

    FLAKE="github:reverb256/home-manager-config"
    # nexus-only builder, same constraint as hm-switch (issue #389).
    export NIX_CONFIG='pure-eval = false; builders = ssh-ng://j_kro@nexus x86_64-linux,i686-linux ~/.ssh/id_ed25519 12 10 big-parallel,kvm'

    # Resolve the CURRENT upstream rev with --refresh and pin builds to it.
    # An unpinned `github:` ref is served from nix's branch-resolution cache
    # and goes stale — observed reporting the previous rev right after a push.
    META=$(nix flake metadata --refresh "$FLAKE" --json 2>/dev/null || echo "")
    REV=$(echo "$META" | jq -r '.locked.rev' 2>/dev/null || echo "")
    if [ -z "$REV" ]; then
        echo "ERROR: could not resolve $FLAKE (network/GitHub API down?)" >&2
        exit 1
    fi
    MOD=$(echo "$META" | jq -r '.locked.lastModified' 2>/dev/null || echo "")
    echo "== upstream $FLAKE @ ${REV:0:8} ($(date -u -d "@$MOD" '+%Y-%m-%d %H:%M UTC' 2>/dev/null || echo "?")) =="

    RC=0
    for host in {{HOSTS}}; do
        echo
        echo "== $host =="
        if [ "$host" = "$(hostname -s)" ]; then
            # readlink -f resolves the generation symlink to its store path.
            LIVE=$(readlink -f "$HOME/.local/state/nix/profiles/home-manager" 2>/dev/null || echo NONE)
            GEN=$(home-manager generations 2>/dev/null | head -1 || true)
        else
            # Disambiguate unreachable (ssh fails) from reachable-but-no-HM
            # profile (ssh OK, readlink found nothing).
            set +e
            LIVE=$(ssh -o ConnectTimeout=8 "$host" 'readlink -f "$HOME/.local/state/nix/profiles/home-manager"' 2>/dev/null)
            SSH_RC=$?
            set -e
            if [ "$SSH_RC" -ne 0 ]; then
                if ssh -o ConnectTimeout=5 "$host" true 2>/dev/null; then
                    LIVE="NONE"
                else
                    LIVE="UNREACHABLE"
                fi
            fi
            GEN=$(ssh -o ConnectTimeout=8 "$host" 'home-manager generations 2>/dev/null | head -1' 2>/dev/null || true)
        fi
        CANON=$(nix build --no-link --print-out-paths \
          "$FLAKE/$REV#homeConfigurations.$host.activationPackage" 2>/dev/null || echo BUILD-FAILED)

        if [ "$LIVE" = "UNREACHABLE" ]; then
            echo "  live:  UNREACHABLE"
            echo "  status: UNREACHABLE — check connectivity, then re-run"
            RC=1
            continue
        fi
        echo "  live:  $LIVE"
        [ -n "$GEN" ] && echo "  gen:   $GEN"
        echo "  canon: $CANON"
        if [ "$LIVE" = "$CANON" ]; then
            echo "  status: CURRENT"
        else
            echo "  status: STALE — fix with: just hm-deploy $host"
            RC=1
        fi
    done
    exit $RC

# Redeploy one host's HM config from the current upstream commit (the fix for
# `just hm-audit` STALE results). Builds the canonical activationPackage on
# zephyr (nexus builder), copies the closure to the host, registers it as the
# newest generation, and activates. Managed-file conflicts are backed up to
# <file>.pre-hm-backup and activation retried (same semantics as hm-switch -b backup).
hm-deploy host="zephyr":
    #!/usr/bin/env bash
    set -euo pipefail

    FLAKE="github:reverb256/home-manager-config"
    export NIX_CONFIG='pure-eval = false; builders = ssh-ng://j_kro@nexus x86_64-linux,i686-linux ~/.ssh/id_ed25519 12 10 big-parallel,kvm'
    HOST="{{host}}"

    # Resolve the CURRENT upstream rev fresh (same rationale as hm-audit) and
    # pin the build so a stale branch-resolution cache can't deploy old config.
    REV=$(nix flake metadata --refresh "$FLAKE" --json 2>/dev/null | jq -r '.locked.rev')
    echo ">> building $FLAKE/${REV:0:8}#homeConfigurations.$HOST.activationPackage"
    GEN=$(nix build --no-link --print-out-paths "$FLAKE/$REV#homeConfigurations.$HOST.activationPackage")
    echo ">> closure: $GEN"

    if [ "$HOST" = "$(hostname -s)" ]; then
        # Same helper as the remote path, so local deploys get identical
        # conflict-backup handling (no unguarded exec of activate).
        echo ">> activating locally"
        GEN="$GEN" bash {{FLAKE}}/scripts/hm-remote-deploy.sh
        exit $?
    fi

    echo ">> copying closure to $HOST"
    nix-copy-closure --to "$HOST" "$GEN"

    # Remote default shell is fish, so run the helper under bash via stdin
    # (no heredoc in the recipe body — just's parser rejects `set -e`-style
    # lines inside heredocs). The helper sets the profile + activates with
    # -b-backup-style conflict handling.
    echo ">> activating on $HOST"
    ssh -o ConnectTimeout=15 "$HOST" "GEN=$GEN bash -s" \
        < {{FLAKE}}/scripts/hm-remote-deploy.sh

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
    # sandbox=false only for this command: Lix's sandboxed curl hits
    # error 42 (CURLE_ABORTED_BY_CALLBACK) on GitHub API calls during
    # `nix flake update`. Builds themselves run sandboxed (sandbox=true).
    cd {{FLAKE}} && nix flake update --option sandbox false

# Verify the locked nixpkgs rev is close to the nixos-unstable channel tip
# (Hydra builds channel tips; random master commits often lack binaries for
# heavy packages like chromium/qtwebengine -> multi-hour source builds).
# Exits 1 with a warning when drift exceeds CHANNEL_MAX_DRIFT (default 100
# commits) so it can gate deploys. Use after `just update` or before `just deploy`.
channel-pin-check:
    #!/usr/bin/env bash
    set -euo pipefail
    cd {{FLAKE}}
    MAX_DRIFT="${CHANNEL_MAX_DRIFT:-100}"
    CHANNEL="${CHANNEL_URL:-https://channels.nixos.org/nixos-unstable/git-revision}"
    PINNED=$(python3 -c "import json; print(json.load(open('flake.lock'))['nodes']['nixpkgs']['locked']['rev'])")
    echo "pinned nixpkgs rev: $PINNED"
    TIP=$(curl -fsSL -m 20 "$CHANNEL" 2>/dev/null | head -1 | tr -d ' \n' || echo "")
    if [ -z "$TIP" ]; then
        echo "WARN: could not fetch channel tip ($CHANNEL) — skipping check"
        exit 0
    fi
    echo "channel tip rev:    $TIP"
    if [ "$PINNED" = "$TIP" ]; then
        echo "OK: pinned rev == channel tip (full Hydra binary coverage expected)"
        exit 0
    fi
    # Count drift via GitHub compare API (base=channel tip, head=pinned rev)
    DRIFT=$(curl -fsSL -m 20 "https://api.github.com/repos/NixOS/nixpkgs/compare/$TIP...$PINNED" 2>/dev/null \
      | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('behind_by', d.get('ahead_by', '?')))" 2>/dev/null || echo "?")
    echo "pinned rev is $DRIFT commit(s) BEHIND the nixos-unstable channel tip"
    echo "NOTE: cache.nixos.org only fully covers channel revisions — a stale pin"
    echo "      can force multi-hour source builds of chromium/qtwebengine."
    echo "      Fix:  just update && just channel-pin-check"
    echo "      or:   nix flake lock --option sandbox false --override-input nixpkgs github:NixOS/nixpkgs/$TIP"
    if [ "$DRIFT" != "?" ] && [ "$DRIFT" -gt "$MAX_DRIFT" ]; then
        echo "ERROR: drift ($DRIFT) exceeds MAX_DRIFT ($MAX_DRIFT) — deploy gated." >&2
        exit 1
    fi
    exit 0

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

# ── HERMES AGENT (nix profile) ──────────────────────────────────────────────
# Hermes is NOT built by nixos-config (issue #334): it lives in the USER NIX
# PROFILE via `nix profile install github:NousResearch/hermes-agent`, tracking
# upstream `main`. The recipes above (`hermes-update` / `hermes-update-check`)
# instead bump the OTHER flake inputs and rebuild the whole OS — do NOT use them
# to bump the hermes binary. These recipes upgrade the profile entry to the
# latest commit on main: no nixos-rebuild, no cluster-wide switch, miners safe.
# The running TUI/desktop must be restarted to load the new build.
hermes-upgrade-profile:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! nix profile list 2>/dev/null | grep -q 'hermes-agent'; then
        echo "ERROR: hermes-agent is not in this host's nix profile." >&2
        echo "       Install it first: nix profile install github:NousResearch/hermes-agent" >&2
        exit 1
    fi
    OLD=$(nix profile list 2>/dev/null | grep -oP 'rev=\K[0-9a-f]+' | head -1)
    echo "Upgrading hermes-agent in user nix profile (tracking main)..."
    nix profile upgrade hermes-agent 2>&1 | tail -15
    NEW=$(nix profile list 2>/dev/null | grep -oP 'rev=\K[0-9a-f]+' | head -1)
    echo "  old rev: ${OLD:-none}"
    echo "  new rev: ${NEW:-none}"
    if [ "${OLD}" = "${NEW}" ]; then
        echo "  (already at latest commit on main — nothing changed)"
    else
        echo "  upgraded."
    fi
    echo "Installed: $(hermes --version 2>/dev/null | head -1)"
    echo "Restart the running TUI/desktop to load the new build."

# Same as above, looped over every cluster host. Hermes runs from each host's
# own user nix profile; any host without the entry is skipped (not an error).
hermes-upgrade-profile-all:
    #!/usr/bin/env bash
    set -euo pipefail
    for host in {{HOSTS}}; do
        echo "=== $host ==="
        if [ "$host" = "$(hostname -s)" ]; then
            just hermes-upgrade-profile
        else
            ssh -o ConnectTimeout=15 "$host" 'bash --norc --noprofile -c "
                if ! nix profile list 2>/dev/null | grep -q hermes-agent; then
                    echo \"  hermes-agent not in profile - skipping\"; exit 0; fi
                nix profile upgrade hermes-agent 2>&1 | tail -5
                echo \"  installed: $(hermes --version 2>/dev/null | head -1)\"
            "' 2>&1 || echo "  (ssh failed)"
        fi
    done


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
    set -euo pipefail
    echo "Active docs are verified from source; historical docs are never freshened by timestamp."
    echo "Review docs/current-state.md, docs/runbooks/, and docs/ci-cd/README.md against source."
    exec just docs-audit

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
        -f /etc/nixos/secretspec.toml \
        -P production

# List every declared secret grouped by category. Useful for audit + new-member
# onboarding ("what does the cluster expect, in human terms?").
secretspec-list:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -v secretspec >/dev/null 2>&1; then
        echo "secretspec not on PATH - built via /etc/nixos/pkgs/secretspec + overlay wiring" >&2
        exit 127
    fi
    secretspec schema -f /etc/nixos/secretspec.toml --json 2>/dev/null | jq -r '.properties | keys[]' | sort

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

lint:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "=== alejandra --check ==="
    alejandra --check --exclude modules/system/agenix-secrets-registry.nix --exclude modules/services/spacebot/container.nix --exclude kubernetes/modules .
    echo "=== statix check ==="
    statix check
    echo "=== deadnix ==="
    deadnix --fail --no-lambda-arg --no-lambda-pattern-names

# Format all .nix files with alejandra (in-place).
fmt:
    alejandra --exclude modules/system/agenix-secrets-registry.nix --exclude modules/services/spacebot/container.nix --exclude kubernetes/modules .

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

# ── COLMENA BUILD-FARM ──────────────────────────────────────────────────
# Uses colmena 0.5.0-pre for cluster-wide builds and deployment.
# The build-farm machines file at machines defines 3 entries:
#   nexus (primary), sentry (secondary), zephyr (disabled / zero jobs).
# Forge is intentionally excluded because it is the GPU/mining host.
#
# Quick reference:
#   just colmena-check       # Build for sentry (smoke test)
#   just colmena-deploy      # Full deploy to all 4 hosts (via Nexus dispatcher preferred)
#   just colmena-deploy-host host=sentry  # Deploy to one host
#   just colmena-list        # List all hosts

# Build all configurations (no deploy)
colmena-build:
    @echo "Building all configurations..."
    colmena build --eval-node-limit 2 2>&1

# Build a single host
colmena-check host="sentry":
    @echo "Building {{host}}..."
    colmena build --on {{host}} 2>&1

# Deploy to all hosts through the Nexus dispatcher
colmena-deploy:
    @just deploy all

# Deploy to a single host through the Nexus dispatcher
colmena-deploy-host host="sentry":
    @just deploy {{host}}

# List all hosts in the cluster
colmena-list:
    @echo "Cluster hosts:"
    @colmena eval -E '{ nodes, ... }: builtins.attrNames nodes'
