#!/usr/bin/env bash
# AI Inference Gateway Refactoring - Apply Script
# Fixes backend URL from localhost to Kubernetes service DNS

set -e

NAMESPACE="ai-inference"
GATEWAY_DEPLOYMENT="ai-inference-gateway"
BACKEND_SERVICE="llama-cpp-qwen"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}ℹ️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Check if cluster is accessible
check_cluster() {
    print_info "Checking Kubernetes cluster connection..."
    if ! kubectl get nodes &>/dev/null; then
        print_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    print_success "Cluster connection OK"
}

# Check current gateway status
check_current_status() {
    print_header "Current Gateway Status"
    echo ""
    kubectl get pods -n "$NAMESPACE" -l app=ai-inference-gateway
    echo ""
    kubectl get configmap ai-gateway-config -n "$NAMESPACE" -o jsonpath='{.data.BACKEND_URL}'
    echo ""
}

# Apply updated configuration
apply_fix() {
    print_header "Applying Gateway Fix"
    echo ""
    print_info "Updating gateway deployment with fixed backend URL..."
    kubectl apply -f /etc/nixos/kubernetes-manifests/ai-inference/gateway-deployment.yaml
    echo ""
    print_success "Gateway deployment updated"
}

# Wait for rollout to complete
wait_for_rollout() {
    print_header "Waiting for Rollout"
    echo ""
    print_info "Waiting for gateway pods to become ready..."
    kubectl rollout status deployment/"$GATEWAY_DEPLOYMENT" -n "$NAMESPACE" --timeout=120s
    echo ""
    print_success "Rollout complete"
}

# Verify the fix
verify_fix() {
    print_header "Verification"
    echo ""

    # Check pod status
    print_info "Checking pod status..."
    READY=$(kubectl get pods -n "$NAMESPACE" -l app=ai-inference-gateway -o jsonpath='{.items[0].status.readyReplicas}' || echo "0")
    if [ "$READY" -ge 1 ]; then
        print_success "Gateway pods are ready"
    else
        print_error "Gateway pods not ready"
        return 1
    fi

    # Check backend URL
    print_info "Verifying backend URL in ConfigMap..."
    BACKEND_URL=$(kubectl get configmap ai-gateway-config -n "$NAMESPACE" -o jsonpath='{.data.BACKEND_URL}')
    if [[ "$BACKEND_URL" == *"llama-cpp-qwen.ai-inference.svc.cluster.local"* ]]; then
        print_success "Backend URL correctly set to: $BACKEND_URL"
    else
        print_error "Backend URL incorrect: $BACKEND_URL"
        return 1
    fi

    # Test backend connectivity
    print_info "Testing backend connectivity..."
    POD=$(kubectl get pods -n "$NAMESPACE" -l app=ai-inference-gateway -o jsonpath='{.items[0].metadata.name}')
    if kubectl exec -n "$NAMESPACE" "$POD" -- curl -s http://llama-cpp-qwen.ai-inference.svc.cluster.local:8080/health >/dev/null 2>&1; then
        print_success "Backend connectivity OK"
    else
        print_error "Backend connectivity failed"
        return 1
    fi

    echo ""
    print_success "All verifications passed!"
}

# Show final status
show_final_status() {
    print_header "Final Status"
    echo ""
    kubectl get pods -n "$NAMESPACE" -l app=ai-inference-gateway
    echo ""
    kubectl get svc -n "$NAMESPACE" "$GATEWAY_DEPLOYMENT"
    echo ""
    print_info "Gateway available at:"
    echo "  - Internal: http://$GATEWAY_DEPLOYMENT.$NAMESPACE.svc.cluster.local:8080"
    echo "  - NodePort: Check service with 'kubectl get svc -n $NAMESPACE'"
    echo ""
}

# Main execution
main() {
    print_header "AI Inference Gateway Refactoring"
    echo ""
    print_info "This script fixes the gateway backend URL from localhost to Kubernetes service DNS"
    echo ""

    check_cluster
    echo ""

    check_current_status
    echo ""

    read -p "Continue with applying the fix? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Aborted by user"
        exit 0
    fi

    apply_fix
    echo ""

    wait_for_rollout
    echo ""

    if verify_fix; then
        show_final_status
        echo ""
        print_success "Gateway refactoring complete!"
        echo ""
    else
        print_error "Verification failed. Check logs with:"
        echo "  kubectl logs -n $NAMESPACE -l app=ai-inference-gateway --tail=50"
        exit 1
    fi
}

# Help
show_help() {
    cat << EOF
AI Inference Gateway Refactoring Script

Fixes the gateway backend URL from localhost (127.0.0.1:8083) to
Kubernetes service DNS (llama-cpp-qwen.ai-inference.svc.cluster.local:8080)

Usage:
    $0 [options]

Options:
    -h, --help     Show this help
    --skip-verify  Skip verification steps
    --dry-run      Show changes without applying

Environment:
    NAMESPACE        Kubernetes namespace (default: ai-inference)

Examples:
    $0              # Apply fix with verification
    $0 --dry-run    # Show what would be changed

EOF
}

# Parse args
DRY_RUN=false
SKIP_VERIFY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --skip-verify)
            SKIP_VERIFY=true
            shift
            ;;
        *)
            print_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Run main
main
