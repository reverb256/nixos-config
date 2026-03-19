#!/usr/bin/env bash
# Volcano Installation Script
# Deploys Volcano scheduler with gang scheduling and advanced features

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

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl not found. Please install kubectl."
        exit 1
    fi

    # Check helm
    if ! command -v helm &> /dev/null; then
        log_error "helm not found. Please install helm."
        exit 1
    fi

    # Check cluster access
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot access Kubernetes cluster. Please configure kubeconfig."
        exit 1
    fi

    log_info "Prerequisites check passed ✓"
}

# Create namespace
create_namespace() {
    log_info "Creating Volcano namespace..."
    kubectl apply -f volcano/00-namespace.yaml
    log_info "Namespace created ✓"
}

# Add Volcano Helm repo
add_helm_repo() {
    log_info "Adding Volcano Helm repository..."
    helm repo add volcano https://volcano-sh.github.io/charts
    helm repo update
    log_info "Helm repository added ✓"
}

# Install Volcano
install_volcano() {
    log_info "Installing Volcano scheduler..."

    helm upgrade --install volcano volcano/volcano \
        --namespace volcano-system \
        --create-namespace \
        --set basic.scheduler_image_tag="v1.9.0" \
        --set basic.webhook_image_tag="v1.9.0" \
        --wait \
        --timeout 5m

    log_info "Volcano installed ✓"
}

# Create PodGroups
create_podgroups() {
    log_info "Creating PodGroups for gang scheduling..."
    kubectl apply -f volcano/02-podgroups.yaml
    log_info "PodGroups created ✓"
}

# Create Queues
create_queues() {
    log_info "Creating queues for resource allocation..."
    kubectl apply -f volcano/03-queues.yaml
    log_info "Queues created ✓"
}

# Verify installation
verify_installation() {
    log_info "Verifying Volcano installation..."

    # Check CRDs
    local crds=$(kubectl get crd | grep volcano | wc -l)
    if [[ $crds -eq 0 ]]; then
        log_error "Volcano CRDs not found. Installation may have failed."
        exit 1
    fi

    # Check pods
    local pods=$(kubectl get pods -n volcano-system --no-headers 2>/dev/null | wc -l)
    if [[ $pods -eq 0 ]]; then
        log_error "No Volcano pods found. Installation may have failed."
        exit 1
    fi

    # Check PodGroups
    local podgroups=$(kubectl get podgroup -A --no-headers 2>/dev/null | wc -l)

    # Check Queues
    local queues=$(kubectl get queue -n volcano-system --no-headers 2>/dev/null | wc -l)
    if [[ $queues -eq 0 ]]; then
        log_warn "No queues found. Resource allocation may not work."
    fi

    log_info "Volcano installation verified ✓"
    log_info "CRDs installed: $crds"
    log_info "Pods running: $pods"
    log_info "PodGroups: $podgroups"
    log_info "Queues: $queues"
}

# Display access information
display_access_info() {
    log_info "Volcano installation complete!"
    echo ""
    log_info "View Volcano scheduler logs:"
    echo "  kubectl logs -n volcano-system deployment/volcano-scheduler -f"
    echo ""
    log_info "Check PodGroups:"
    echo "  kubectl get podgroup -A"
    echo "  kubectl describe podgroup ai-inference-single-gpu -n ai-inference"
    echo ""
    log_info "Check Queues:"
    echo "  kubectl get queue -n volcano-system"
    echo "  kubectl describe queue ai-queue -n volcano-system"
    echo ""
    log_info "Test gang scheduling:"
    echo "  kubectl apply -f deployments/ai-inference-example.yaml"
    echo ""
}

# Main installation flow
main() {
    log_info "Starting Volcano installation..."
    echo ""

    check_prerequisites
    create_namespace
    add_helm_repo
    install_volcano
    create_podgroups
    create_queues
    verify_installation
    display_access_info

    log_info "Installation complete! 🎉"
}

# Run main function
main "$@"
