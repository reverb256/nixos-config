#!/usr/bin/env bash
# Scheduler Rollback Script
# Safely rolls back YuniKorn and/or Volcano installations

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Rollback YuniKorn
rollback_yunikorn() {
    log_info "Rolling back YuniKorn..."

    # Uninstall YuniKorn
    if helm list -n yunikorn | grep -q yunikorn; then
        log_info "Uninstalling YuniKorn Helm release..."
        helm uninstall yunikorn -n yunikorn || log_warn "YuniKorn Helm uninstall failed"
    fi

    # Delete priority classes
    log_info "Deleting priority classes..."
    kubectl delete priorityclass ai-inference-critical ai-inference-high ai-inference-medium mining-low mining-background \
        --ignore-not-found=true 2>/dev/null || true

    # Delete ConfigMap
    log_info "Deleting state ConfigMap..."
    kubectl delete configmap gpu-scheduler-state -n kube-system --ignore-not-found=true 2>/dev/null || true

    # Delete RBAC
    log_info "Deleting RBAC..."
    kubectl delete rolebinding gpu-scheduler-state-updater yunikorn-state-reader -n kube-system \
        --ignore-not-found=true 2>/dev/null || true
    kubectl delete role gpu-scheduler-state-updater -n kube-system \
        --ignore-not-found=true 2>/dev/null || true

    # Delete namespace
    log_info "Deleting YuniKorn namespace..."
    kubectl delete namespace yunikorn --ignore-not-found=true 2>/dev/null || true

    log_info "YuniKorn rollback complete ✓"
}

# Rollback Volcano
rollback_volcano() {
    log_info "Rolling back Volcano..."

    # Uninstall Volcano
    if helm list -n volcano-system | grep -q volcano; then
        log_info "Uninstalling Volcano Helm release..."
        helm uninstall volcano -n volcano-system || log_warn "Volcano Helm uninstall failed"
    fi

    # Delete PodGroups
    log_info "Deleting PodGroups..."
    kubectl delete podgroup --all -A --ignore-not-found=true 2>/dev/null || true

    # Delete Queues
    log_info "Deleting Queues..."
    kubectl delete queue --all -n volcano-system --ignore-not-found=true 2>/dev/null || true

    # Delete CRDs
    log_info "Deleting Volcano CRDs..."
    kubectl delete crd \
        podgroups.scheduling.volcano.sh \
        queues.scheduling.volcano.sh \
        --ignore-not-found=true 2>/dev/null || true

    # Delete namespace
    log_info "Deleting Volcano namespace..."
    kubectl delete namespace volcano-system --ignore-not-found=true 2>/dev/null || true

    log_info "Volcano rollback complete ✓"
}

# Revert deployments to default scheduler
revert_deployments() {
    log_info "Reverting deployments to default scheduler..."

    # Remove schedulerName from deployments
    local deployments=(
        "ai-inference-yunikorn:ai-inference"
        "gpu-miner-zephyr-yunikorn:mining"
        "distributed-training-volcano:ai-inference"
        "gpu-miner-forge-volcano:mining"
    )

    for dep in "${deployments[@]}"; do
        IFS=':' read -r deployment namespace <<< "$dep"

        if kubectl get deployment "$deployment" -n "$namespace" &>/dev/null; then
            log_info "Reverting $deployment in $namespace..."

            # Remove schedulerName
            kubectl patch deployment "$deployment" -n "$namespace" --type=json \
                -p='[{"op": "remove", "path": "/spec/template/spec/schedulerName"}]' \
                --ignore-not-found=true 2>/dev/null || true

            # Remove PodGroup label if present
            kubectl label deployment "$deployment" -n "$namespace" \
                scheduling.volcano.sh/pod-group- \
                --ignore-not-found=true 2>/dev/null || true
        fi
    done

    log_info "Deployments reverted ✓"
}

# Display completion message
display_completion() {
    log_info "Rollback complete!"
    echo ""
    log_warn "Note: Custom Python scheduler (k8s-gpu-scheduler.py) must be re-enabled manually:"
    echo "  kubectl scale deployment k8s-gpu-scheduler -n kube-system --replicas=1"
    echo ""
    log_warn "And bare metal state management must be reverted:"
    echo "  git checkout modules/services/ai-inference/ai_inference_gateway/gpu_scheduler.py"
    echo "  just switch"
    echo ""
}

# Main rollback flow
main() {
    local rollback_yunikorn_flag=false
    local rollback_volcano_flag=false
    local revert_deployments_flag=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --yunikorn)
                rollback_yunikorn_flag=true
                shift
                ;;
            --volcano)
                rollback_volcano_flag=true
                shift
                ;;
            --all)
                rollback_yunikorn_flag=true
                rollback_volcano_flag=true
                revert_deployments_flag=true
                shift
                ;;
            --revert-deployments)
                revert_deployments_flag=true
                shift
                ;;
            --help)
                echo "Usage: $0 [--yunikorn] [--volcano] [--all] [--revert-deployments]"
                echo ""
                echo "Options:"
                echo "  --yunikorn          Rollback YuniKorn only"
                echo "  --volcano           Rollback Volcano only"
                echo "  --all               Rollback both schedulers and revert deployments"
                echo "  --revert-deployments Revert deployments to default scheduler"
                echo ""
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done

    # If no arguments, rollback everything
    if [[ "$rollback_yunikorn_flag" == false && "$rollback_volcano_flag" == false ]]; then
        log_warn "No arguments provided. Rolling back everything..."
        rollback_yunikorn_flag=true
        rollback_volcano_flag=true
        revert_deployments_flag=true
    fi

    log_info "Starting scheduler rollback..."
    echo ""

    if [[ "$rollback_volcano_flag" == true ]]; then
        rollback_volcano
        echo ""
    fi

    if [[ "$rollback_yunikorn_flag" == true ]]; then
        rollback_yunikorn
        echo ""
    fi

    if [[ "$revert_deployments_flag" == true ]]; then
        revert_deployments
        echo ""
    fi

    display_completion
}

# Run main function
main "$@"
