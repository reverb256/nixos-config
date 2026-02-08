#!/usr/bin/env bash
#
# NixOS Cluster Sync & Handoff Script
# Fixes drift across all cluster nodes and sets up safeguards
#
# USAGE: sudo ./scripts/sync-cluster.sh
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CLUSTER_REPO="/etc/nixos"
TARGET_BRANCH="refactor/-hm-service"
CURRENT_HOST=$(hostname -s)

# Nodes configuration
declare -A NODES
NODES[zephyr]="j_kro@10.1.1.110"
NODES[nexus]="j_kro@10.1.1.120"
NODES[forge]="j_kro@10.1.1.130"
NODES[sentry]="j_kro@10.1.1.140"

# SSH options
SSH_OPTS="-o StrictHostKeyChecking=accept-new -o ConnectTimeout=30 -o ServerAliveInterval=60"

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[⚠]${NC} $*"
}

log_error() {
    echo -e "${RED}[✗]${NC} $*"
}

log_section() {
    echo ""
    echo -e "${BLUE}=== $* ===${NC}"
}

# Check if running as root or with sudo
check_privileges() {
    if [ "$EUID" -ne 0 ] && ! sudo -n true 2>/dev/null; then
        log_error "This script requires root privileges. Run with sudo."
        exit 1
    fi
}

# Check if running on zephyr (source of truth)
check_source_host() {
    if [ "$CURRENT_HOST" != "zephyr" ]; then
        log_error "This script must be run on zephyr (10.1.1.110) - the source of truth."
        log_info "Current host: $CURRENT_HOST"
        exit 1
    fi
}

# Check git status on current host
check_zephyr_status() {
    log_section "Checking zephyr git status"

    cd "$CLUSTER_REPO"

    local current_branch=$(git branch --show-current)
    local has_changes=$(git status --porcelain | wc -l)

    log_info "Current branch: $current_branch"

    if [ "$current_branch" != "$TARGET_BRANCH" ]; then
        log_warning "Zephyr is on branch '$current_branch' (should be '$TARGET_BRANCH')"
        read -p "Switch to $TARGET_BRANCH? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            git checkout "$TARGET_BRANCH"
            log_success "Switched to $TARGET_BRANCH"
        else
            log_error "Cannot proceed without correct branch"
            exit 1
        fi
    fi

    if [ "$has_changes" -gt 0 ]; then
        log_warning "Found $has_changes unstaged change(s) on zephyr:"
        git status --short

        echo ""
        read -p "Commit and push these changes? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Committing changes..."
            git add -A
            git commit -m "chore: sync cluster - use j_kro user for distributed builds"
            log_success "Changes committed"

            log_info "Pushing to origin..."
            git push origin "$TARGET_BRANCH"
            log_success "Pushed to origin/$TARGET_BRANCH"
        else
            log_error "Cannot proceed with pending changes"
            exit 1
        fi
    else
        log_success "Zephyr working tree clean"
    fi
}

# Check and sync remote hosts
check_remote_host() {
    local host=$1
    local user_host="${NODES[$host]}"

    log_info "Checking $host..."

    # Get current branch and status
    local remote_branch=$(ssh $SSH_OPTS "$user_host" "cd $CLUSTER_REPO && git branch --show-current")
    local remote_has_changes=$(ssh $SSH_OPTS "$user_host" "cd $CLUSTER_REPO && git status --porcelain | wc -l")
    local remote_behind=$(ssh $SSH_OPTS "$user_host" "cd $CLUSTER_REPO && git rev-list --count HEAD..origin/$TARGET_BRANCH 2>/dev/null || echo 0")

    log_info "  Branch: $remote_branch"
    log_info "  Changes: $remote_has_changes"
    log_info "  Behind: $remote_behind commits"

    if [ "$remote_branch" != "$TARGET_BRANCH" ]; then
        log_warning "  $host is on '$remote_branch', switching to '$TARGET_BRANCH'..."
        ssh $SSH_OPTS "$user_host" "cd $CLUSTER_REPO && git checkout $TARGET_BRANCH"
        log_success "  Switched to $TARGET_BRANCH"
    fi

    if [ "$remote_has_changes" -gt 0 ]; then
        log_warning "  $host has $remote_has_changes uncommitted change(s):"
        ssh $SSH_OPTS "$user_host" "cd $CLUSTER_REPO && git status --short"

        log_info "  Stashing changes..."
        ssh $SSH_OPTS "$user_host" "cd $CLUSTER_REPO && git stash push -m 'sync-cluster-stash-$(date +%s)'"
        log_success "  Changes stashed"
    fi

    if [ "$remote_behind" -gt 0 ]; then
        log_warning "  $host is behind by $remote_behind commit(s), resetting..."
        ssh $SSH_OPTS "$user_host" "cd $CLUSTER_REPO && git fetch origin && git reset --hard origin/$TARGET_BRANCH"
        log_success "  Reset to origin/$TARGET_BRANCH"
    fi

    log_success "  $host synced"
}

# Deploy to a host
deploy_to_host() {
    local host=$1

    if [ "$host" = "zephyr" ]; then
        log_info "Deploying to $host (local)..."
        sudo nixos-rebuild switch --flake "${CLUSTER_REPO}#${host}" 2>&1 | tail -20
    else
        local user_host="${NODES[$host]}"
        log_info "Deploying to $host (remote)..."
        ssh $SSH_OPTS "$user_host" "cd ${CLUSTER_REPO} && sudo nixos-rebuild switch --flake '${CLUSTER_REPO}#${host}' --use-remote-sudo" 2>&1 | tail -20
    fi

    log_success "  Deployed to $host"
}

# Install pre-commit hook to prevent commits on remote hosts
install_pre_commit_hook() {
    local host=$1

    if [ "$host" = "zephyr" ]; then
        log_info "Skipping pre-commit hook on zephyr (allowed to commit)"
        return
    fi

    local user_host="${NODES[$host]}"
    log_info "Installing pre-commit hook on $host..."

    ssh $SSH_OPTS "$user_host" "cat > ${CLUSTER_REPO}/.git/hooks/pre-commit << 'EOF'
#!/bin/bash
# Prevent commits on remote hosts - source of truth is zephyr

HOSTNAME=\$(hostname -s)
if [ \"\$HOSTNAME\" != \"zephyr\" ]; then
  echo \"\"
  echo \"\${RED}ERROR: Commit on \$HOSTNAME is not allowed.\${NC}\"
  echo \"\"
  echo \"Make configuration changes on zephyr (10.1.1.110) and use:\"
  echo \"  just deploy          # Deploy to all hosts\"
  echo \"  just <host>          # Deploy to specific host\"
  echo \"\"
  echo \"To bypass this check (emergency only):\"
  echo \"  git commit --no-verify ...\"
  echo \"\"
  exit 1
fi
EOF
chmod +x ${CLUSTER_REPO}/.git/hooks/pre-commit
"

    log_success "  Pre-commit hook installed on $host"
}

# Verify sync status
verify_sync() {
    log_section "Verifying cluster sync status"

    local all_synced=true

    for host in "${!NODES[@]}"; do
        local user_host="${NODES[$host]}"
        local local_commit=$(cd "$CLUSTER_REPO" && git rev-parse HEAD)
        local remote_commit=$(ssh $SSH_OPTS "$user_host" "cd $CLUSTER_REPO && git rev-parse HEAD" 2>/dev/null || echo "unknown")

        if [ "$local_commit" = "$remote_commit" ]; then
            log_success "$host: SYNCED"
        else
            log_warning "$host: OUT OF SYNC"
            log_info "  Zephyr: $local_commit"
            log_info "  $host:   $remote_commit"
            all_synced=false
        fi
    done

    if [ "$all_synced" = true ]; then
        log_success "All hosts are in sync!"
    else
        log_error "Some hosts are still out of sync"
        return 1
    fi
}

# Main execution
main() {
    clear
    echo -e "${BLUE}"
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║  NixOS Cluster Sync & Handoff Script                      ║"
    echo "║  Fixes drift and sets up safeguards                       ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    check_privileges
    check_source_host

    # Phase 1: Sync git repos
    log_section "Phase 1: Syncing Git Repositories"

    check_zephyr_status

    for host in nexus forge sentry; do
        check_remote_host "$host"
    done

    # Phase 2: Deploy to all hosts
    log_section "Phase 2: Deploying Configuration"

    for host in zephyr nexus forge sentry; do
        deploy_to_host "$host"
        echo ""
    done

    # Phase 3: Set up safeguards
    log_section "Phase 3: Setting Up Safeguards"

    for host in nexus forge sentry; do
        install_pre_commit_hook "$host"
    done

    # Phase 4: Verify sync
    verify_sync

    # Summary
    log_section "Handoff Complete"

    log_success "Cluster is now in sync and protected against drift"
    echo ""
    log_info "Safeguards installed:"
    log_info "  • Pre-commit hooks on nexus, forge, sentry prevent commits"
    log_info "  • All hosts are on branch: $TARGET_BRANCH"
    log_info "  • All hosts have same commit hash"
    echo ""
    log_info "Future workflow:"
    log_info "  1. Make changes on zephyr only"
    log_info "  2. Commit and push: git push origin $TARGET_BRANCH"
    log_info "  3. Deploy: just deploy"
    echo ""
    log_warning "To bypass pre-commit hook (emergency): git commit --no-verify ..."
}

# Run main function
main "$@"
