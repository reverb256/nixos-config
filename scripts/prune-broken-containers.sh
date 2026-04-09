#!/run/current-system/sw/bin/bash
# Kubernetes Broken Container Pruning Script
# Identifies and safely removes broken/failed containers

set -e

echo "=== Kubernetes Broken Container Pruning ==="
echo "Started: $(date)"
echo ""

# Color codes for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Function to check pods
check_broken_pods() {
    echo -e "${YELLOW}Checking for broken containers...${NC}"

    # Find pods in bad states
    local broken_pods=$(kubectl get pods -A -o json | \
        jq -r '.items[] | select(
            .status.phase == "Failed" or
            (.status.containerStatuses != null and (
                any(.status.containerStatuses[].state.waiting.reason == "CrashLoopBackOff";
                     .status.containerStatuses[].state.waiting.reason == "Error";
                     .status.containerStatuses[].state.waiting.reason == "ImagePullBackOff")
            )
        ) | "\(.metadata.namespace)/\(.metadata.name)"')

    if [ -z "$broken_pods" ]; then
        echo -e "${GREEN}No broken pods found!${NC}"
        return 0
    fi

    echo -e "${RED}Found broken pods:${NC}"
    echo "$broken_pods" | while read -r pod; do
        local namespace=$(echo "$pod" | cut -d'/' -f1)
        local name=$(echo "$pod" | cut -d'/' -f2)
        echo "  - $namespace/$name"
    done

    echo "$broken_pods"
}

# Function to check high-restart pods
check_high_restart_pods() {
    echo ""
    echo -e "${YELLOW}Checking for high-restart pods (>5 restarts)...${NC}"

    local restart_pods=$(kubectl get pods -A -o json | \
        jq -r '.items[] | select(
            .status.containerStatuses != null and
            any(.status.containerStatuses[].restartCount > 5)
        ) | "\(.metadata.namespace)/\(.metadata.name) (\(.status.containerStatuses[0].restartCount) restarts)"')

    if [ -z "$restart_pods" ]; then
        echo -e "${GREEN}No high-restart pods found!${NC}"
        return 0
    fi

    echo -e "${YELLOW}High-restart pods:${NC}"
    echo "$restart_pods" | while read -r pod; do
        echo "  - $pod"
    done
}

# Function to prune completed pods
prune_completed_pods() {
    echo ""
    echo -e "${YELLOW}Pruning completed pods...${NC}"

    # Delete completed jobs
    local completed_jobs=$(kubectl get jobs -A -o json | \
        jq -r '.items[] | select(.status.succeeded == 1 and .status.completionTime != null) | "\(.metadata.namespace)/\(.metadata.name)"' | \
        head -20)  # Limit to 20 at a time

    if [ -n "$completed_jobs" ]; then
        echo "$completed_jobs" | while read -r job; do
            local namespace=$(echo "$job" | cut -d'/' -f1)
            local name=$(echo "$job" | cut -d'/' -f2)
            echo "  Deleting completed job: $namespace/$name"
            kubectl delete job "$name" -n "$namespace" --ignore-not-found=true
        done
    else
        echo "  No completed jobs to prune"
    fi

    # Delete succeeded pods not owned by jobs/controllers
    local orphan_succeeded=$(kubectl get pods -A -o json | \
        jq -r '.items[] | select(
            .status.phase == "Succeeded" and
            .metadata.ownerReferences == null
        ) | "\(.metadata.namespace)/\(.metadata.name)"')

    if [ -n "$orphan_succeeded" ]; then
        echo "$orphan_succeeded" | while read -r pod; do
            local namespace=$(echo "$pod" | cut -d'/' -f1)
            local name=$(echo "$pod" | cut -d'/' -f2)
            echo "  Deleting orphaned succeeded pod: $namespace/$name"
            kubectl delete pod "$name" -n "$namespace" --ignore-not-found=true
        done
    fi
}

# Function to prune evicted pods
prune_evicted_pods() {
    echo ""
    echo -e "${YELLOW}Pruning evicted pods...${NC}"

    local evicted_pods=$(kubectl get pods -A -o json | \
        jq -r '.items[] | select(
            .status.reason == "Evicted" or
            (.status.containerStatuses != null and
             any(.status.containerStatuses[].state.waiting.reason == "Evicted"))
        ) | "\(.metadata.namespace)/\(.metadata.name)"')

    if [ -z "$evicted_pods" ]; then
        echo "  No evicted pods to prune"
        return 0
    fi

    echo "$evicted_pods" | while read -r pod; do
        local namespace=$(echo "$pod" | cut -d'/' -f1)
        local name=$(echo "$pod" | cut -d'/' -f2)
        echo "  Deleting evicted pod: $namespace/$name"
        kubectl delete pod "$name" -n "$namespace" --ignore-not-found=true
    done
}

# Function to prune old failed pods (safe to delete if managed by controllers)
prune_old_failed_pods() {
    echo ""
    echo -e "${YELLOW}Pruning old failed pods (older than 1 hour, managed by controllers)...${NC}"

    local failed_pods=$(kubectl get pods -A -o json | \
        jq -r '.items[] | select(
            .status.phase == "Failed" and
            .metadata.ownerReferences != null and
            (.status.startTime | fromdateiso8601) < (now - 3600)
        ) | "\(.metadata.namespace)/\(.metadata.name)"')

    if [ -z "$failed_pods" ]; then
        echo "  No old failed pods to prune"
        return 0
    fi

    echo "$failed_pods" | while read -r pod; do
        local namespace=$(echo "$pod" | cut -d'/' -f1)
        local name=$(echo "$pod" | cut -d'/' -f2)
        echo "  Deleting old failed pod: $namespace/$name"
        kubectl delete pod "$name" -n "$namespace" --ignore-not-found=true
    done
}

# Function to show container image cleanup
show_image_cleanup() {
    echo ""
    echo -e "${YELLOW}Container image cleanup (manual):${NC}"
    echo "  To clean up unused container images on nodes:"
    echo "  ssh forge 'sudo crictl images prune -a'"
    echo "  ssh nexus 'sudo crictl images prune -a'"
    echo "  ssh zephyr 'sudo crictl images prune -a'"
    echo "  ssh sentry 'sudo crictl images prune -a'"
    echo ""
    echo "  Or use containerd directly:"
    echo "  ssh forge 'sudo ctr image prune'"
}

# Main execution
main() {
    echo "=== Phase 1: Check for broken pods ==="
    check_broken_pods

    echo ""
    echo "=== Phase 2: Check high-restart pods ==="
    check_high_restart_pods

    # Uncomment to actually prune
    # echo ""
    # echo "=== Phase 3: Prune completed pods ==="
    # prune_completed_pods

    # echo ""
    # echo "=== Phase 4: Prune evicted pods ==="
    # prune_evicted_pods

    # echo ""
    # echo "=== Phase 5: Prune old failed pods ==="
    # prune_old_failed_pods

    echo ""
    show_image_cleanup

    echo ""
    echo "=== Summary ==="
    echo -e "${GREEN}Container pruning check complete!${NC}"
    echo "Review the output above and decide which pods to prune manually."
    echo ""
    echo "To manually prune specific pods:"
    echo "  kubectl delete pod <pod-name> -n <namespace>"
    echo ""
    echo "To restart deployments with high-restart pods:"
    echo "  kubectl rollout restart deployment <deployment-name> -n <namespace>"
    echo ""
    echo "Completed: $(date)"
}

# Run main function
main "$@"
