#!/usr/bin/env bash
# OpenCode Kubernetes Access Wrapper
# Simple wrapper for kubectl exec into OpenCode pod

set -e

NAMESPACE="ai-coding"
SELECTOR="app=opencode"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}ℹ️  $1${NC}"
}

print_header() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Find running pod
find_pod() {
    local pod=$(kubectl get pods -n "$NAMESPACE" -l "$SELECTOR" \
        -o jsonpath='{range .items[?(.status.phase=="Running")]}{.metadata.name}{"\n"}{end}' 2>/dev/null | head -1)

    if [ -z "$pod" ]; then
        echo "❌ No running OpenCode pods found"
        echo "→ Run: kubectl get pods -n $NAMESPACE"
        exit 1
    fi

    echo "$pod"
}

main() {
    print_header "OpenCode on Kubernetes"

    if ! kubectl get nodes &>/dev/null; then
        echo "❌ Cannot connect to Kubernetes cluster"
        exit 1
    fi

    print_info "Finding OpenCode pod..."
    POD=$(find_pod)
    print_success "Connected to: $POD"
    echo ""

    print_info "OpenCode pod is ready! Use these commands:"
    echo ""
    echo "  # Start OpenCode (interactive)"
    echo "  kubectl exec -it -n $NAMESPACE $POD -- /home/j_kro/.nix-profile/bin/opencode"
    echo ""
    echo "  # Check pod status"
    echo "  kubectl get pods -n $NAMESPACE"
    echo ""
    echo "  # View logs"
    echo "  kubectl logs -n $NAMESPACE $POD"
    echo ""

    if [ $# -gt 0 ]; then
        print_info "Executing in pod: $*"
        kubectl exec -it -n "$NAMESPACE" "$POD" -- "$@"
    fi
}

show_help() {
    cat << EOF
OpenCode Kubernetes Wrapper

Usage:
    $0 [command [args...]

Examples:
    $0                  # Show status and usage
    $0 /bin/bash        # Open shell in pod
    $0 /bin/ls         # Run command in pod

Environment:
    NAMESPACE        Kubernetes namespace (default: ai-coding)

EOF
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            break
            ;;
    esac
done

main "$@"
