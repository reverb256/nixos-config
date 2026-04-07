#!/usr/bin/env bash
# Documentation Simplification Script
# Run from /etc/nixos directory

set -euo pipefail

DRY_RUN="${DRY_RUN:-1}"  # Set to 0 to actually delete

log() {
    echo "[$(date '+%H:%M:%S')] $1"
}

confirm() {
    if [ "$DRY_RUN" = "1" ]; then
        echo "[DRY RUN] Would: $1"
    else
        read -p "$1 (y/N) " -n 1 -r
        echo
        [[ $REPLY =~ ^[Yy]$ ]]
    fi
}

# Phase 1: Remove duplicate audit files (superseded by CHANGELOG)
phase1_audits() {
    log "Phase 1: Removing duplicate audit files..."

    local files=(
        "docs/audit/system-audit-report-2026-03-21-1112.md"
        "docs/audit/system-audit-report-2026-03-21-1715.md"
        "docs/audit/system-audit-report-2026-03-21-0912.md"
        "docs/audit/comprehensive-audit-2026-03-21.md"
        "docs/DOCUMENTATION_AUDIT_2026-03-21.md"
        "docs/DOCUMENTATION_AUDIT_SUMMARY.md"
    )

    local count=0
    for f in "${files[@]}"; do
        if [ -f "$f" ]; then
            if confirm "Delete $f"; then
                [ "$DRY_RUN" = "0" ] && rm "$f"
                ((count++))
            fi
        fi
    done
    log "Phase 1 complete: $count files removed"
}

# Phase 2: Consolidate daily incident status into summary
phase2_incidents() {
    log "Phase 2: Consolidating daily incident status..."

    # Keep only major incidents, delete daily status files
    local daily_files=(
        docs/incidents/2026-03-21/status-check-*.md
        docs/incidents/2026-03-21/default-status*.md
        docs/incidents/2026-03-21/audit-status-*.md
        docs/incidents/2026-03-21/final-status-report-*.md
        docs/incidents/2026-03-21/comprehensive-status-report-*.md
    )

    local count=0
    for pattern in "${daily_files[@]}"; do
        for f in $pattern; do
            if [ -f "$f" ]; then
                if confirm "Delete $f"; then
                    [ "$DRY_RUN" = "0" ] && rm "$f"
                    ((count++))
                fi
            fi
        done
    done
    log "Phase 2 complete: $count files removed"
}

# Phase 3: Remove completed plans (documented in CHANGELOG)
phase3_plans() {
    log "Phase 3: Removing completed implementation plans..."

    local plans=(
        "docs/plans/2026-03-20-k8s-mining-migration-design.md"
        "docs/plans/2026-03-22-caddy-ingress-design.md"
        "docs/plans/2026-03-22-caddy-ingress-migration.md"
        "docs/plans/2026-03-22-caddy-ingress-implementation.md"
        "docs/plans/2026-03-22-xmrig-intelligent-autoscaling-design.md"
        "docs/plans/2026-03-22-xmrig-intelligent-autoscaling-implementation.md"
        "docs/plans/2026-03-24-network-integration-design.md"
        "docs/plans/2026-03-24-network-integration-implementation.md"
        "docs/compute-workload-monitor-implementation-plan.md"
        "docs/vllm-deployment-plan.md"
        "docs/kubernetes/nix-csi-exploration.md"
        "docs/kubernetes/nix-csi-phase0-summary.md"
        "docs/kubernetes/nix-csi-migration-plan.md"
    )

    local count=0
    for f in "${plans[@]}"; do
        if [ -f "$f" ]; then
            if confirm "Delete $f (documented in CHANGELOG)"; then
                [ "$DRY_RUN" = "0" ] && rm "$f"
                ((count++))
            fi
        fi
    done
    log "Phase 3 complete: $count files removed"
}

# Phase 4: Consolidate kubernetes status files
phase4_k8s_status() {
    log "Phase 4: Consolidating Kubernetes status/check files..."

    # These are all superseded by STATUS.md
    local k8s_status=(
        docs/kubernetes/system-status-2026-03-22-final.md
        docs/kubernetes/system-verification-2026-03-21.md
        docs/kubernetes/cluster-analysis-2026-03-21.md
        docs/kubernetes/comprehensive-audit-2026-03-23.md
        docs/kubernetes/comprehensive-audit-2026-03-24.md
    )

    local count=0
    for f in "${k8s_status[@]}"; do
        if [ -f "$f" ]; then
            if confirm "Delete $f"; then
                [ "$DRY_RUN" = "0" ] && rm "$f"
                ((count++))
            fi
        fi
    done
    log "Phase 4 complete: $count files removed"
}

# Phase 5: Create weekly status summaries
phase5_summarize() {
    log "Phase 5: Creating weekly summaries..."

    mkdir -p docs/status

    # Week of Mar 21-27 (files already exist in CHANGELOG)
    if [ ! -f "docs/status/2026-03-week-4.md" ]; then
        cat > docs/status/2026-03-week-4.md << 'EOF'
# Week of 2026-03-21 to 2026-03-27

## Summary

Major infrastructure week: Kubernetes migration completed, Calico networking deployed,
monitoring stack operational.

## Key Events

- **Mar 21**: Gaming detection deployed to Kubernetes
- **Mar 22**: Caddy Ingress deployed, replacing nginx
- **Mar 22**: Volcano scheduler migrated from YuniKorn
- **Mar 23**: Calico CNI migrated from Flannel
- **Mar 24**: Network integration completed
- **Mar 25**: Cluster health verification

## Issues

- Calico BGP peering degraded on Forge/Sentry (IPv6 link-local only)
- AMD GPU mining GLIBC incompatibility (workaround: host-based mining)

## Files Changed

See [CHANGELOG.md](../CHANGELOG.md) for complete details.
EOF
        log "Created docs/status/2026-03-week-4.md"
    fi
}

main() {
    log "Starting documentation simplification..."
    log "DRY_RUN=$DRY_RUN (set DRY_RUN=0 to execute)"

    phase1_audits
    phase2_incidents
    phase3_plans
    phase4_k8s_status
    phase5_summarize

    log ""
    log "Simplification complete!"
    log ""
    log "Next steps:"
    log "1. Review changes: git diff --stat"
    log "2. Commit: git add docs && git commit -m 'docs: simplify documentation'"
    log "3. Update DOCUMENTATION_INDEX.md"
}

main "$@"
