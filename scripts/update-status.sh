#!/run/current-system/sw/bin/bash
# STATUS.md Generated Snapshot Script
#
# Refactored (2026-07-24) to derive static sections from
# `/etc/nixos/cluster-state.nix` via `nix eval --json --file` and `jq`.
# Dynamic sections (pod list, pod summary, node + pod resource usage,
# last-updated timestamp) still come from `kubectl` because they have no
# offline equivalent.
#
# Render order:
#   1. Title + Quick Check + meta-notes (Nix-derived + jq)
#   2. Cluster Health Overview table (Nix-derived)
#   3. Kubernetes Nodes list (kubectl)
#   4. GPU Resources by Node (Nix-derived)
#   5. Migration Progress + Known Issues (Nix-derived)
#   6. Services Running: pods + summary (kubectl)
#   7. System Health Metrics: node + pod usage (kubectl)
#   8. Quick Reference + SOPS-NIX link (hard-coded)
#   9. Recent Changes (always emit header; conditionally preserve body)
#
# Atomic write: render to ${STATUS_MD}.tmp then mv into place. The cleanup
# trap rm's the .tmp file on ANY exit failure, so a failing render never
# leaves orphans in /etc/nixos. STATUS.md is published only when the
# entire render succeeded.

set -euo pipefail

STATUS_MD="${STATUS_MD:-/etc/nixos/STATUS.md}"
BACKUP_MD="${BACKUP_MD:-/etc/nixos/STATUS.md.backup}"
CLUSTER_STATE_NIX="${CLUSTER_STATE_NIX:-/etc/nixos/cluster-state.nix}"
TMP_STATUS="${STATUS_MD}.tmp.$$"

# Cleanup trap — fires on ANY exit (success OR failure). On success the
# final `mv` already consumed TMP_STATUS so rm is a no-op.
trap 'rm -f "$TMP_STATUS" 2>/dev/null || true' EXIT INT TERM

DATE=$(date +%Y-%m-%d)
TIME=$(date +%H:%M:%S)

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { printf "${GREEN}[INFO]${NC} %s\n" "$1"; }
log_warn()  { printf "${YELLOW}[WARN]${NC} %s\n" "$1"; }
log_error() { printf "${RED}[ERROR]${NC} %s\n" "$1"; }

# Serialize timer and manual refreshes. The non-blocking guard prevents a
# second invocation from racing STATUS.md.backup or the atomic publish.
exec 9>/run/lock/nixos-status-update.lock
if ! flock -n 9; then
    log_warn "another STATUS.md update is already running; exiting"
    exit 0
fi

# Pre-flight: required tools and source-of-truth file
for cmd in nix jq kubectl flock timeout; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        log_error "$cmd not found on PATH. ${0##*/} requires nix, jq, kubectl."
        exit 1
    fi
done

if [ ! -f "$CLUSTER_STATE_NIX" ]; then
    log_error "cluster-state.nix not found: $CLUSTER_STATE_NIX"
    exit 1
fi

# kubectl is best-effort: if cluster is unreachable, render offline.
KUBECTL_OK=0
if timeout 20 kubectl get nodes >/dev/null 2>&1; then
    KUBECTL_OK=1
    log_info "kubectl reachable"
else
    log_warn "kubectl unreachable; rendering STATUS.md with Nix-derived sections only"
fi

# Backup before any clobber
if [ -f "$STATUS_MD" ]; then
    cp "$STATUS_MD" "$BACKUP_MD"
    log_info "Backed up STATUS.md to $BACKUP_MD"
fi

log_info "Starting STATUS.md update at ${TIME} on ${DATE}"

# Static facts from cluster-state.nix
log_info "Rendering static facts from $CLUSTER_STATE_NIX..."
STATE_JSON=$(nix eval --json --file "$CLUSTER_STATE_NIX" 2>/dev/null) || {
    log_error "nix eval --json --file $CLUSTER_STATE_NIX failed (run \`nix flake update\` + check the file for syntax errors)"
    exit 1
}

COMPONENTS_COUNT=$(echo "$STATE_JSON" | jq '.components | length')
NODES_COUNT=$(echo      "$STATE_JSON" | jq '.nodes | length')
PHASES_COUNT=$(echo     "$STATE_JSON" | jq '.phases | length')
if [ "$COMPONENTS_COUNT" -le 0 ] || [ "$NODES_COUNT" -le 0 ] || [ "$PHASES_COUNT" -le 0 ]; then
    log_error "cluster-state.nix returned empty arrays (components=$COMPONENTS_COUNT nodes=$NODES_COUNT phases=$PHASES_COUNT)"
    exit 1
fi
LAST_UPDATED=$(echo "$STATE_JSON" | jq -r .last_updated)
SNAPSHOT_WARNING=""
if snapshot_epoch=$(date -d "$LAST_UPDATED" +%s 2>/dev/null); then
    snapshot_age_days=$(( ($(date +%s) - snapshot_epoch) / 86400 ))
    if [ "$snapshot_age_days" -gt 7 ]; then
        SNAPSHOT_WARNING="> **STALE SOURCE WARNING:** cluster-state.nix snapshot is ${snapshot_age_days} days old; run live health checks before relying on this report."
    fi
fi
log_info "  components=$COMPONENTS_COUNT nodes=$NODES_COUNT phases=$PHASES_COUNT (snapshot: $LAST_UPDATED)"

# Dynamic kubectl sections
if [ "$KUBECTL_OK" -eq 1 ]; then
    NODES=$(timeout 30 kubectl get nodes 2>&1 || echo "kubectl get nodes failed")
    ALL_PODS=$(timeout 30 kubectl get pods --all-namespaces 2>/dev/null || true)
    PODS_BY_NAMESPACE=$(timeout 30 kubectl get pods --all-namespaces --no-headers 2>/dev/null \
        | awk '{print $1}' | sort | uniq -c | sort -rn)
    NODE_USAGE=$(timeout 30 kubectl top nodes 2>/dev/null \
        || echo "Node metrics not available (metrics-server not deployed)")
    POD_USAGE=$(timeout 30 kubectl top pods --all-namespaces 2>/dev/null | head -20 \
        || echo "Pod metrics not available (metrics-server not deployed)")
else
    NODES="(unreachable — kubectl offline)"
    ALL_PODS=""
    PODS_BY_NAMESPACE=""
    NODE_USAGE=""
    POD_USAGE=""
fi

# Render Nix-derived rows via jq
COMPONENT_ROWS=$(echo "$STATE_JSON" | jq -r \
    '.components[] | "| **\(.name)** | \(.emoji) | \(.details) |"')

NODE_ROWS=$(echo "$STATE_JSON" | jq -r \
    '.nodes[] |
     "| **\(.name)** | \(.nvidia) | \(.amd) | " +
      (if .cuda   then "✅" else "-" end) + " | " +
      (if .rocm   then "✅" else "-" end) + " | " +
      (if .vulkan then "✅" else "-" end) + " |"')

PHASE_ROWS=$(echo "$STATE_JSON" | jq -r \
    '.phases[] | "| **\(.name)** | \(.status) | \(.completion) | \(.notes) |"')

KNOWN_ROWS=$(echo "$STATE_JSON" | jq -r \
    '.known_issues[] | "- \(.emoji) **\(.name):** \(.description) (\(.date))"')

NOTES_BLOCK=$(echo "$STATE_JSON" | jq -r '.notes[] | "> " + .')
OVERALL_PROGRESS=$(echo "$STATE_JSON" | jq -r .overall_progress)
OVERALL_LABEL=$(echo "$STATE_JSON" | jq -r .overall_progress_label)

# Recent Changes: ALWAYS emit the section header (fixes first-run regression
# where BACKUP_MD didn't exist and the entire merge was skipped). Conditionally
# append preserved prior log entries from BACKUP_MD. Use REAL NEWLINES in
# double-quoted strings — bash does not interpret \n escape sequences inside
# double quotes, so any `\n` literal would appear in STATUS.md verbatim.
# Single-pass variable, no intermediate .new file.
RECENT_HEADER='## Recent Changes'
LATEST_AUTO_ENTRY="**${DATE} ${TIME}:**
- 🔄 **AUTO-UPDATED:** STATUS.md regenerated; static sections from cluster-state.nix (snapshot $LAST_UPDATED), dynamic from kubectl."

if [ -f "$BACKUP_MD" ] && grep -qE '^## Recent Changes' "$BACKUP_MD"; then
    log_info "Preserving Recent Changes log from $BACKUP_MD"
    # Preserve only the Recent Changes section. Older snapshots may contain
    # generated sections after it; never append those sections to the new file.
    PRIOR_LOG=$(awk '/^## Recent Changes/{found=1; next} found && /^## /{exit} found {print}' "$BACKUP_MD" | tail -n +2)
    RECENT_CHANGES_BLOCK="${RECENT_HEADER}

${LATEST_AUTO_ENTRY}

${PRIOR_LOG}"
else
    log_info "First run (no BACKUP_MD or no prior Recent Changes section); emitting header + first entry only"
    RECENT_CHANGES_BLOCK="${RECENT_HEADER}

${LATEST_AUTO_ENTRY}"
fi

# Atomic write to TMP_STATUS then mv to STATUS_MD
log_info "Rendering to $TMP_STATUS..."

{
    cat << HEADER
# NixOS Cluster - Generated Status Snapshot

**Status:** Generated snapshot — verify source timestamp before relying on runtime claims.
**Generated By:** \`scripts/update-status.sh\`

**Last Updated:** ${DATE} ${TIME} | **Auto-Generated:** Yes | **Refresh:** \`./scripts/update-status.sh\` | **Source-of-truth snapshot:** ${LAST_UPDATED}
${SNAPSHOT_WARNING}

> **Quick Check:** Run \`just health\` for live host connectivity and Kubernetes node state; use \`just status\` for repository/deployment metadata.
>
> **Note:** This file is auto-generated by \`scripts/update-status.sh\`. Static sections (Cluster Health Overview, GPU Resources, Migration Progress, Known Issues, Notes) derive from \`/etc/nixos/cluster-state.nix\` via \`nix eval --json --file\` + \`jq\`. Dynamic sections (Kubernetes Nodes, Pods, Resource Usage) come from \`kubectl\`. Edit the source-of-truth file (\`cluster-state.nix\`), not STATUS.md directly.

---

## Cluster Health Overview

| Component | Status | Details |
|-----------|--------|---------|
${COMPONENT_ROWS}

---

## Kubernetes Nodes

\`\`\`
${NODES}
\`\`\`

${NOTES_BLOCK}

### GPU Resources by Node

| Node | NVIDIA GPUs | AMD GPUs | CUDA | ROCm | Vulkan |
|------|-------------|----------|------|------|--------|
${NODE_ROWS}

---

## Migration Progress (Kubernetes)

| Phase | Status | Completion | Notes |
|-------|--------|------------|-------|
${PHASE_ROWS}

**Overall Progress:** ${OVERALL_PROGRESS} (${OVERALL_LABEL})

**Known Issues:**
${KNOWN_ROWS}

---

## Services Running

### Kubernetes Pods by Namespace

\`\`\`
${ALL_PODS}
\`\`\`

### Pod Summary by Namespace
\`\`\`
${PODS_BY_NAMESPACE}
\`\`\`

---

## System Health Metrics

### Node Resource Usage
\`\`\`
${NODE_USAGE}
\`\`\`

### Pod Resource Usage
\`\`\`
${POD_USAGE}
\`\`\`

---

## Quick Reference

### Common Commands
\`\`\`bash
# Live host and Kubernetes node status
just health

# Node status
kubectl get nodes -o wide

# Pod status
kubectl get pods --all-namespaces

# Service status
kubectl get svc --all-namespaces

# Logs
kubectl logs -f <pod-name> -n <namespace>

# Exec into pod
kubectl exec -it <pod-name> -n <namespace> -- /bin/bash
\`\`\`

### Troubleshooting
\`\`\`bash
# Check node not ready
kubectl describe node <host-name>

# Check pod crashes
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace> --previous

# Check service connectivity
kubectl get endpoints <service-name> -n <namespace>
\`\`\`

---

**Auto-Generated:** ${DATE} ${TIME}
**Source-of-truth snapshot:** ${LAST_UPDATED} (cluster-state.nix)
**Update Script:** \`scripts/update-status.sh\`
**Run Manually:** \`sudo ./scripts/update-status.sh\`
**Auto-Refresh:** Hourly via systemd timer (status-update.timer)

---

## SOPS-NIX

See [SOPS-NIX.md](./SOPS-NIX.md) for sops-nix status, key file location, registry module reference, and recovery workflow.
HEADER
    printf '\n%s\n' "$RECENT_CHANGES_BLOCK"
} > "$TMP_STATUS"

# Atomic publish (no separate .new file; single-pass variable above)
mv "$TMP_STATUS" "$STATUS_MD"

log_info "STATUS.md updated successfully"
if [ "$KUBECTL_OK" -eq 1 ]; then
    log_info "Cluster Summary (first 5 lines):"
    echo "$NODES" | head -5
    log_info "Pod Summary by Namespace (top 10):"
    echo "$PODS_BY_NAMESPACE" | head -10
fi
log_info "Update complete! STATUS.md has been regenerated."
