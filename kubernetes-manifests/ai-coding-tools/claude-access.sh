#!/usr/bin/env bash
# Claude Code Kubernetes Access Wrapper
# Simple wrapper for kubectl exec into Claude pod

set -e

NAMESPACE="ai-coding"
SELECTOR="app=claude-code"

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
        echo "❌ No running Claude pods found"
        echo "→ Run: kubectl get pods -n $NAMESPACE"
        exit 1
    fi

    echo "$pod"
}

main() {
    print_header "Claude Code on Kubernetes"

    # Check if cluster is accessible
    if ! kubectl get nodes &>/dev/null; then
        echo "❌ Cannot connect to Kubernetes cluster"
        exit 1
    fi

    # Find pod
    print_info "Finding Claude pod..."
    POD=$(find_pod)
    print_success "Connected to: $POD"
    echo ""

    # Show usage info
    print_info "Claude pod is ready! Use these commands:"
    echo ""
    echo "  # Open shell in pod (busybox only)"
    echo "  kubectl exec -it -n $NAMESPACE $POD -- /bin/sh"
    echo ""
    echo "  # Check pod status"
    echo "  kubectl get pods -n $NAMESPACE"
    echo ""
    echo "  # View logs"
    echo "  kubectl logs -n $NAMESPACE $POD"
    echo ""
    echo "  # Access home directory"
    echo "  kubectl exec -it -n $NAMESPACE $POD -- /bin/sh -c 'ls -la /home/j_kro'"
    echo ""

    # If user passed arguments, exec into pod
    if [ $# -gt 0 ]; then
        print_info "Executing in pod: $*"
        kubectl exec -it -n "$NAMESPACE" "$POD" -- "$@"
    fi
}

# Help
show_help() {
    cat << EOF
Claude Code Kubernetes Wrapper

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

# Parse args
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
