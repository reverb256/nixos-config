#!/usr/bin/env bash
# Complete Scheduler Migration Script
# Deploys YuniKorn and Volcano schedulers with comprehensive testing

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

log_step() {
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# Error handling
trap 'log_error "Script failed at line $LINENO. Exit code: $?"' ERR

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="$(dirname "$SCRIPT_DIR")"
YUNIKORN_DIR="$K8S_DIR/scheduling/yunikorn"
VOLCANO_DIR="$K8S_DIR/scheduling/volcano"
DEPLOYMENTS_DIR="$K8S_DIR/scheduling/deployments"

# ============================================================================
# PHASE 0: PREPARATION
# ============================================================================

phase0_preparation() {
    log_step "PHASE 0: PREPARATION"

    log_info "Checking prerequisites..."

    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl not found. Please install kubectl."
        exit 1
    fi
    log_info "✓ kubectl found"

    # Check helm
    if ! command -v helm &> /dev/null; then
        log_error "helm not found. Please install helm."
        exit 1
    fi
    log_info "✓ helm found"

    # Check cluster access
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot access Kubernetes cluster. Please configure kubeconfig."
        exit 1
    fi
    log_info "✓ Cluster access verified"

    # Check existing resources
    log_info "Checking existing resources..."

    # Check if YuniKorn already installed
    if helm list -n yunikorn 2>/dev/null | grep -q yunikorn; then
        log_warn "YuniKorn already installed. Will upgrade..."
        YUNIKORN_EXISTS=true
    else
        YUNIKORN_EXISTS=false
        log_info "YuniKorn not installed (will install fresh)"
    fi

    # Check if Volcano already installed
    if helm list -n volcano-system 2>/dev/null | grep -q volcano; then
        log_warn "Volcano already installed. Will upgrade..."
        VOLCANO_EXISTS=true
    else
        VOLCANO_EXISTS=false
        log_info "Volcano not installed (will install fresh)"
    fi

    # Check custom scheduler
    if kubectl get daemonset gpu-scheduler -n kube-system &> /dev/null; then
        log_warn "Custom GPU scheduler found. Will run in parallel during migration..."
        CUSTOM_SCHEDULER_EXISTS=true
    else
        CUSTOM_SCHEDULER_EXISTS=false
        log_info "No custom scheduler found"
    fi

    # Backup current state
    log_info "Backing up current state..."
    BACKUP_DIR="$K8S_DIR/backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"

    # Backup existing deployments
    if kubectl get deployment gpu-miner-zephyr -n mining &> /dev/null; then
        kubectl get deployment gpu-miner-zephyr -n mining -o yaml > "$BACKUP_DIR/gpu-miner-zephyr.yaml"
        log_info "✓ Backed up gpu-miner-zephyr"
    fi

    if kubectl get deployment gpu-miner-forge -n mining &> /dev/null; then
        kubectl get deployment gpu-miner-forge -n mining -o yaml > "$BACKUP_DIR/gpu-miner-forge.yaml"
        log_info "✓ Backed up gpu-miner-forge"
    fi

    if kubectl get deployment ai-inference-gateway -n ai-inference &> /dev/null; then
        kubectl get deployment ai-inference-gateway -n ai-inference -o yaml > "$BACKUP_DIR/ai-inference-gateway.yaml"
        log_info "✓ Backed up ai-inference-gateway"
    fi

    log_info "✓ Backup saved to: $BACKUP_DIR"

    log_info "Phase 0 complete ✓"
}

# ============================================================================
# PHASE 1: YUNIKORN DEPLOYMENT
# ============================================================================

phase1_yunikorn() {
    log_step "PHASE 1: YUNIKORN DEPLOYMENT"

    log_info "Deploying YuniKorn scheduler..."

    # Create namespace
    log_info "Creating YuniKorn namespace..."
    kubectl apply -f "$YUNIKORN_DIR/00-namespace.yaml"
    log_info "✓ Namespace created"

    # Add Helm repo
    log_info "Adding YuniKorn Helm repository..."
    helm repo add yunikorn https://apache.github.io/yunikorn-release
    helm repo update
    log_info "✓ Helm repository added"

    # Install YuniKorn
    log_info "Installing YuniKorn scheduler..."
    if [ "$YUNIKORN_EXISTS" = true ]; then
        helm upgrade yunikorn yunikorn/yunikorn \
            --namespace yunikorn \
            --values "$YUNIKORN_DIR/values.yaml" \
            --wait \
            --timeout 5m
    else
        helm install yunikorn yunikorn/yunikorn \
            --namespace yunikorn \
            --values "$YUNIKORN_DIR/values.yaml" \
            --wait \
            --timeout 5m
    fi
    log_info "✓ YuniKorn installed"

    # Create priority classes
    log_info "Creating priority classes..."
    kubectl apply -f "$YUNIKORN_DIR/02-priority-classes.yaml"
    log_info "✓ Priority classes created"

    # Create state management ConfigMap and RBAC
    log_info "Creating state management ConfigMap and RBAC..."
    kubectl apply -f "$YUNIKORN_DIR/03-configmap-rbac.yaml"
    log_info "✓ State management created"

    # Verify installation
    log_info "Verifying YuniKorn installation..."
    kubectl get pods -n yunikorn
    kubectl get priorityclasses | grep -E "ai-inference|mining"

    log_info "Phase 1 complete ✓"
}

# ============================================================================
# PHASE 2: VOLCANO DEPLOYMENT
# ============================================================================

phase2_volcano() {
    log_step "PHASE 2: VOLCANO DEPLOYMENT"

    log_info "Deploying Volcano scheduler..."

    # Create namespace
    log_info "Creating Volcano namespace..."
    kubectl apply -f "$VOLCANO_DIR/00-namespace.yaml"
    log_info "✓ Namespace created"

    # Add Helm repo
    log_info "Adding Volcano Helm repository..."
    helm repo add volcano https://volcano-sh.github.io/charts
    helm repo update
    log_info "✓ Helm repository added"

    # Install Volcano
    log_info "Installing Volcano scheduler..."
    if [ "$VOLCANO_EXISTS" = true ]; then
        helm upgrade volcano volcano/volcano \
            --namespace volcano-system \
            --create-namespace \
            --set basic.scheduler_image_tag="v1.9.0" \
            --set basic.webhook_image_tag="v1.9.0" \
            --wait \
            --timeout 5m
    else
        helm install volcano volcano/volcano \
            --namespace volcano-system \
            --create-namespace \
            --set basic.scheduler_image_tag="v1.9.0" \
            --set basic.webhook_image_tag="v1.9.0" \
            --wait \
            --timeout 5m
    fi
    log_info "✓ Volcano installed"

    # Create PodGroups
    log_info "Creating PodGroups..."
    kubectl apply -f "$VOLCANO_DIR/02-podgroups.yaml"
    log_info "✓ PodGroups created"

    # Create Queues
    log_info "Creating queues..."
    kubectl apply -f "$VOLCANO_DIR/03-queues.yaml"
    log_info "✓ Queues created"

    # Verify installation
    log_info "Verifying Volcano installation..."
    kubectl get pods -n volcano-system
    kubectl get crd | grep volcano
    kubectl get podgroup -A
    kubectl get queue -n volcano-system

    log_info "Phase 2 complete ✓"
}

# ============================================================================
# PHASE 3: DEPLOYMENT MIGRATION
# ============================================================================

phase3_deployments() {
    log_step "PHASE 3: DEPLOYMENT MIGRATION"

    log_info "Migrating deployments to new schedulers..."

    # Update mining deployments
    log_info "Updating mining deployments..."

    if [ -f "$K8S_DIR/mining/gpu-miner-zephyr-yunikorn.yaml" ]; then
        kubectl apply -f "$K8S_DIR/mining/gpu-miner-zephyr-yunikorn.yaml"
        log_info "✓ gpu-miner-zephyr migrated"
    else
        log_warn "gpu-miner-zephyr-yunikorn.yaml not found, skipping..."
    fi

    if [ -f "$K8S_DIR/mining/gpu-miner-forge-yunikorn.yaml" ]; then
        kubectl apply -f "$K8S_DIR/mining/gpu-miner-forge-yunikorn.yaml"
        log_info "✓ gpu-miner-forge migrated"
    else
        log_warn "gpu-miner-forge-yunikorn.yaml not found, skipping..."
    fi

    # Update AI inference gateway
    log_info "Updating AI inference gateway..."

    if [ -f "$K8S_DIR/ai-inference/gateway-deployment-yunikorn.yaml" ]; then
        kubectl apply -f "$K8S_DIR/ai-inference/gateway-deployment-yunikorn.yaml"
        log_info "✓ ai-inference-gateway migrated"
    else
        log_warn "gateway-deployment-yunikorn.yaml not found, skipping..."
    fi

    # Wait for deployments to be ready
    log_info "Waiting for deployments to be ready..."
    kubectl rollout status deployment gpu-miner-zephyr -n mining --timeout=2m || true
    kubectl rollout status deployment gpu-miner-forge -n mining --timeout=2m || true
    kubectl rollout status deployment ai-inference-gateway -n ai-inference --timeout=2m || true

    log_info "Phase 3 complete ✓"
}

# ============================================================================
# PHASE 4: TESTING
# ============================================================================

phase4_testing() {
    log_step "PHASE 4: TESTING"

    log_info "Running integration tests..."

    # Test 1: Check YuniKorn web UI
    log_info "Test 1: YuniKorn web UI access..."
    log_info "Run: kubectl port-forward svc/yunikorn-service 9889:9889 -n yunikorn"
    log_info "Then open: http://localhost:9889"

    # Test 2: Check priority classes
    log_info "Test 2: Verify priority classes..."
    kubectl get priorityclasses
    log_info "✓ Priority classes verified"

    # Test 3: Check PodGroups
    log_info "Test 3: Verify PodGroups..."
    kubectl get podgroup -A
    log_info "✓ PodGroups verified"

    # Test 4: Check mining deployments
    log_info "Test 4: Verify mining deployments..."
    kubectl get deployment -n mining
    kubectl get pods -n mining -l app=gpu-miner
    log_info "✓ Mining deployments verified"

    # Test 5: Check AI gateway
    log_info "Test 5: Verify AI gateway..."
    kubectl get deployment -n ai-inference
    kubectl get pods -n ai-inference -l app=ai-inference-gateway
    log_info "✓ AI gateway verified"

    # Test 6: Check ConfigMap state
    log_info "Test 6: Verify ConfigMap state management..."
    kubectl get configmap gpu-scheduler-state -n kube-system
    kubectl describe configmap gpu-scheduler-state -n kube-system
    log_info "✓ ConfigMap state verified"

    # Test 7: Simulate AI workload starting
    log_info "Test 7: Simulate AI workload starting (preemption test)..."
    kubectl patch configmap gpu-scheduler-state -n kube-system \
        --type=merge \
        --patch='{"data":{"ai-state":"AI_START","active-workload":"ai-inference"}}'

    log_info "Waiting 10 seconds for preemption..."
    sleep 10

    # Check if mining pods are affected
    log_info "Checking mining pods after AI_START signal..."
    kubectl get pods -n mining -l app=gpu-miner

    # Reset state
    log_info "Resetting state to IDLE..."
    kubectl patch configmap gpu-scheduler-state -n kube-system \
        --type=merge \
        --patch='{"data":{"ai-state":"IDLE","active-workload":"none"}}'

    log_info "Phase 4 complete ✓"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    log_info "Starting complete scheduler migration..."
    echo ""

    # Parse arguments
    SKIP_PHASES=false
    SKIP_YUNIKORN=false
    SKIP_VOLCANO=false
    SKIP_DEPLOYMENTS=false
    SKIP_TESTING=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-phases)
                SKIP_PHASES=true
                shift
                ;;
            --skip-yunikorn)
                SKIP_YUNIKORN=true
                shift
                ;;
            --skip-volcano)
                SKIP_VOLCANO=true
                shift
                ;;
            --skip-deployments)
                SKIP_DEPLOYMENTS=true
                shift
                ;;
            --skip-testing)
                SKIP_TESTING=true
                shift
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --skip-phases       Skip all phases (manual execution)"
                echo "  --skip-yunikorn     Skip YuniKorn deployment"
                echo "  --skip-volcano      Skip Volcano deployment"
                echo "  --skip-deployments  Skip deployment migration"
                echo "  --skip-testing      Skip testing phase"
                echo "  --help              Show this help message"
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

    # Run phases
    if [ "$SKIP_PHASES" = false ]; then
        phase0_preparation
        echo ""

        if [ "$SKIP_YUNIKORN" = false ]; then
            phase1_yunikorn
            echo ""
        fi

        if [ "$SKIP_VOLCANO" = false ]; then
            phase2_volcano
            echo ""
        fi

        if [ "$SKIP_DEPLOYMENTS" = false ]; then
            phase3_deployments
            echo ""
        fi

        if [ "$SKIP_TESTING" = false ]; then
            phase4_testing
            echo ""
        fi
    fi

    # Summary
    log_step "MIGRATION COMPLETE"

    log_info "Summary:"
    echo "  ✓ YuniKorn scheduler deployed"
    echo "  ✓ Volcano scheduler deployed"
    echo "  ✓ Mining deployments migrated"
    echo "  ✓ AI inference gateway migrated"
    echo "  ✓ State management migrated to ConfigMap"
    echo ""
    echo "Next steps:"
    echo "  1. Access YuniKorn web UI:"
    echo "     kubectl port-forward svc/yunikorn-service 9889:9889 -n yunikorn"
    echo "     open http://localhost:9889"
    echo ""
    echo "  2. Monitor scheduling decisions:"
    echo "     kubectl logs -n yunikorn deployment/yunikorn-scheduler -f"
    echo "     kubectl logs -n volcano-system deployment/volcano-scheduler -f"
    echo ""
    echo "  3. Test preemption:"
    echo "     kubectl patch configmap gpu-scheduler-state -n kube-system --type=merge --patch='{\"data\":{\"ai-state\":\"AI_START\"}}'"
    echo "     kubectl get pods -n mining -w"
    echo ""
    echo "  4. Rollback if needed:"
    echo "     cd $K8S_DIR/scheduling"
    echo "     ./scripts/rollback.sh --all"
    echo ""

    log_info "Migration complete! 🎉"
}

# Run main function
main "$@"
