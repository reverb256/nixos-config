#!/usr/bin/env bash
# YuniKorn Installation Script
# Deploys YuniKorn scheduler with GPU workload scheduling configuration

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
    log_info "Creating YuniKorn namespace..."
    kubectl apply -f yunikorn/00-namespace.yaml
    log_info "Namespace created ✓"
}

# Add YuniKorn Helm repo
add_helm_repo() {
    log_info "Adding YuniKorn Helm repository..."
    helm repo add yunikorn https://apache.github.io/yunikorn-release
    helm repo update
    log_info "Helm repository added ✓"
}

# Install YuniKorn
install_yunikorn() {
    log_info "Installing YuniKorn scheduler..."

    helm upgrade --install yunikorn yunikorn/yunikorn \
        --namespace yunikorn \
        --values yunikorn/values.yaml \
        --wait \
        --timeout 5m

    log_info "YuniKorn installed ✓"
}

# Create priority classes
create_priority_classes() {
    log_info "Creating priority classes..."
    kubectl apply -f yunikorn/02-priority-classes.yaml
    log_info "Priority classes created ✓"
}

# Create ConfigMap and RBAC
create_state_management() {
    log_info "Creating state management ConfigMap and RBAC..."
    kubectl apply -f yunikorn/03-configmap-rbac.yaml
    log_info "State management created ✓"
}

# Verify installation
verify_installation() {
    log_info "Verifying YuniKorn installation..."

    # Check pods
    local pods=$(kubectl get pods -n yunikorn --no-headers 2>/dev/null | wc -l)
    if [[ $pods -eq 0 ]]; then
        log_error "No YuniKorn pods found. Installation may have failed."
        exit 1
    fi

    # Check priority classes
    local priority_classes=$(kubectl get priorityclasses --no-headers 2>/dev/null | grep -E "ai-inference|mining" | wc -l)
    if [[ $priority_classes -lt 4 ]]; then
        log_warn "Some priority classes may be missing."
    fi

    # Check ConfigMap
    if ! kubectl get configmap gpu-scheduler-state -n kube-system &> /dev/null; then
        log_warn "State ConfigMap not found."
    fi

    log_info "YuniKorn installation verified ✓"
    log_info "Pods running: $pods"
    log_info "Priority classes: $priority_classes"
}

# Display access information
display_access_info() {
    log_info "YuniKorn installation complete!"
    echo ""
    log_info "Access YuniKorn Web UI:"
    echo "  kubectl port-forward svc/yunikorn-service 9889:9889 -n yunikorn"
    echo "  Open http://localhost:9889"
    echo ""
    log_info "View YuniKorn logs:"
    echo "  kubectl logs -n yunikorn deployment/yunikorn-scheduler -f"
    echo ""
    log_info "Check scheduling decisions:"
    echo "  kubectl get queues -n yunikorn"
    echo "  kubectl describe queue root.default -n yunikorn"
    echo ""
}

# Main installation flow
main() {
    log_info "Starting YuniKorn installation..."
    echo ""

    check_prerequisites
    create_namespace
    add_helm_repo
    install_yunikorn
    create_priority_classes
    create_state_management
    verify_installation
    display_access_info

    log_info "Installation complete! 🎉"
}

# Run main function
main "$@"
