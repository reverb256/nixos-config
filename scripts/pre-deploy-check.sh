#!/usr/bin/env bash
# Pre-Deployment Validation Script
# Checks all prerequisites before deploying to cluster
#
# Usage: ./scripts/pre-deploy-check.sh [target]
#   target: "all" (default), "zephyr", "nexus", "forge", "sentry"

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_WARNING=0

# Functions
log_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
    ((CHECKS_PASSED++))
}

log_error() {
    echo -e "${RED}✗${NC} $1"
    ((CHECKS_FAILED++))
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
    ((CHECKS_WARNING++))
}

section() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Check functions
check_git_clean() {
    section "Git Status Check"

    if git diff --quiet HEAD 2>/dev/null; then
        log_success "Git tree is clean"
    else
        log_warning "Git tree is dirty (uncommitted changes)"
        git status --short
    fi
}

check_flake() {
    section "Flake Configuration Check"

    log_info "Running 'nix flake check'..."
    if nix flake check --print-build-logs 2>&1 | tee /tmp/flake-check.log; then
        log_success "Flake check passed"
    else
        log_error "Flake check failed"
        cat /tmp/flake-check.log
        return 1
    fi
}

check_secrets() {
    section "Agenix Secrets Validation"

    log_info "Checking agenix secrets..."

    # Check if agenix is available
    if ! command -v agenix &>/dev/null; then
        log_warning "agenix not found in PATH, skipping secrets validation"
        return 0
    fi

    # Check if secrets exist
    local secrets_dir="/etc/nixos/secrets"
    if [ ! -d "$secrets_dir" ]; then
        log_error "Secrets directory not found: $secrets_dir"
        return 1
    fi

    # Check if age key exists
    if [ ! -f "/home/j_kro/.age/key.txt" ] && [ ! -f "/root/.age/key.txt" ]; then
        log_warning "Age identity key not found (secrets won't be decrypted on target hosts)"
        log_info "Expected: /home/j_kro/.age/key.txt or /root/.age/key.txt"
    else
        log_success "Age identity key found"
    fi

    # Count encrypted secrets
    local secret_count=$(find "$secrets_dir" -name "*.age" 2>/dev/null | wc -l)
    if [ "$secret_count" -gt 0 ]; then
        log_success "Found $secret_count encrypted secrets"
    else
        log_warning "No encrypted secrets found in $secrets_dir"
    fi
}

check_distributed_builds() {
    section "Distributed Build Connectivity"

    local targets=()
    case "${1:-all}" in
        zephyr) targets=() ;;  # No remote builders needed
        nexus) targets=(nexus) ;;
        forge) targets=(nexus forge) ;;
        sentry) targets=(nexus sentry) ;;
        all) targets=(nexus forge sentry) ;;
    esac

    if [ ${#targets[@]} -eq 0 ]; then
        log_info "Skipping distributed build check (local build only)"
        return 0
    fi

    log_info "Checking SSH connectivity to distributed build hosts..."

    for host in "${targets[@]}"; do
        if ssh -o ConnectTimeout=5 -o BatchMode=yes "$host" "echo 'OK'" >/dev/null 2>&1; then
            log_success "SSH to $host: reachable"

            # Check if remote nix-daemon is running
            if ssh "$host" "systemctl is-active nix-daemon" >/dev/null 2>&1; then
                log_success "nix-daemon on $host: active"
            else
                log_error "nix-daemon on $host: not active"
            fi
        else
            log_error "SSH to $host: unreachable"
        fi
    done
}

check_storage_mounts() {
    section "Storage Verification"

    log_info "Checking NFS mount..."

    if mountpoint -q /data/@projects; then
        log_success "NFS mount /data/@projects: active"

        # Check if it's writable
        if [ -w /data/@projects ]; then
            log_success "NFS mount: writable"
        else
            log_error "NFS mount: not writable"
        fi
    else
        log_warning "NFS mount /data/@projects: not mounted (this may be expected on some hosts)"
    fi

    # Check available disk space
    local root_avail=$(df -h / | awk 'NR==2 {print $4}')
    log_info "Root filesystem available space: $root_avail"
}

check_build_targets() {
    section "Build Target Validation"

    local targets=()
    case "${1:-all}" in
        zephyr) targets=(zephyr) ;;
        nexus) targets=(nexus) ;;
        forge) targets=(forge) ;;
        sentry) targets=(sentry) ;;
        all) targets=(zephyr nexus forge sentry) ;;
    esac

    log_info "Validating build targets: ${targets[*]}"

    for host in "${targets[@]}"; do
        log_info "Testing build evaluation for $host..."

        if nix eval ".#nixosConfigurations.${host}.config.system.build.toplevel" >/dev/null 2>&1; then
            log_success "Build target $host: valid"
        else
            log_error "Build target $host: invalid or evaluation failed"
        fi
    done
}

check_network() {
    section "Network Connectivity"

    # Check if we can reach the cluster hosts
    local hosts=(nexus forge sentry)

    for host in "${hosts[@]}"; do
        if ping -c 1 -W 2 "$host" >/dev/null 2>&1; then
            log_success "Ping to $host: reachable"
        else
            log_warning "Ping to $host: unreachable (may be offline)"
        fi
    done

    # Check DNS resolution
    if host -W 2 nexus.local >/dev/null 2>&1 || host -W 2 nexus >/dev/null 2>&1; then
        log_success "DNS resolution: working"
    else
        log_warning "DNS resolution: may have issues"
    fi
}

check_mining_pause() {
    section "Mining Status Check"

    if systemctl is-active --quiet xmrig@* || systemctl is-active --quiet lolminer-*; then
        log_warning "Mining services are active"
        log_info "Mining will be automatically paused during deployment"
    else
        log_success "Mining services: stopped (build performance optimized)"
    fi
}

# Main
main() {
    local target="${1:-all}"

    echo -e "${BLUE}"
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║     NixOS Cluster Pre-Deployment Validation               ║"
    echo "║     Target: $target$(printf ' %.0s' {1..40})║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    cd /etc/nixos

    # Run all checks
    check_git_clean
    check_flake || exit 1
    check_secrets
    check_distributed_builds "$target"
    check_storage_mounts
    check_build_targets "$target"
    check_network
    check_mining_pause

    # Summary
    section "Validation Summary"

    echo -e "  Passed:  ${GREEN}$CHECKS_PASSED${NC}"
    echo -e "  Failed:  ${RED}$CHECKS_FAILED${NC}"
    echo -e "  Warnings: ${YELLOW}$CHECKS_WARNING${NC}"
    echo ""

    if [ $CHECKS_FAILED -gt 0 ]; then
        echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${RED}  VALIDATION FAILED${NC}"
        echo -e "${RED}  Please fix the errors above before deploying${NC}"
        echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        exit 1
    else
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${GREEN}  VALIDATION PASSED${NC}"
        echo -e "${GREEN}  Ready to deploy to: $target${NC}"
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        exit 0
    fi
}

# Run main
main "$@"
