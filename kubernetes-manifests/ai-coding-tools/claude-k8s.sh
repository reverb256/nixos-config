#!/usr/bin/env bash
# Claude Code Kubernetes Wrapper
# Usage: ./claude-k8s.sh [options] [prompt]

set -e

NAMESPACE="ai-inference"
SELECTOR="app=claude-code"
TIMEOUT=3600  # 1 hour default session timeout

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
print_header() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}ℹ️  $1${NC}"
}

# Find best pod (least active)
find_best_pod() {
    local pods=($(kubectl get pods -n "$NAMESPACE" -l "$SELECTOR" \
        -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null))

    if [ ${#pods[@]} -eq 0 ]; then
        print_error "No Claude Code pods found"
        echo "→ Run: kubectl get pods -n $NAMESPACE -l $SELECTOR"
        exit 1
    fi

    # Get active sessions for each pod
    local best_pod=""
    local min_sessions=999999

    for pod in "${pods[@]}"; do
        local sessions=$(kubectl exec -n "$NAMESPACE" "$pod" -- \
            curl -s localhost:9090/metrics 2>/dev/null | \
            grep claude_active_sessions | awk '{print $2}' || echo "0")

        if [ "$sessions" -lt "$min_sessions" ]; then
            min_sessions=$sessions
            best_pod=$pod
        fi
    done

    echo "$best_pod"
}

# Interactive mode
interactive_mode() {
    local pod=$1

    print_header "Claude Code Interactive Session"

    print_info "Pod: $pod"
    print_info "Namespace: $NAMESPACE"
    print_info "Session timeout: ${TIMEOUT}s"
    echo ""

    print_info "Starting interactive shell..."
    echo "Type 'exit' to end session"
    echo ""

    kubectl exec -it -n "$NAMESPACE" "$pod" -- \
        /bin/bash -c "cd /home/j_kro && exec /bin/bash"
}

# Prompt mode
prompt_mode() {
    local pod=$1
    shift
    local prompt="$*"

    print_header "Claude Code - Prompt Mode"

    print_info "Pod: $pod"
    print_info "Prompt: $prompt"
    echo ""

    # Execute claude-code with prompt
    kubectl exec -i -n "$NAMESPACE" "$pod" -- \
        /bin/bash -c "cd /home/j_kro && echo '$prompt' | claude-code"
}

# Main
main() {
    # Check if cluster is accessible
    if ! kubectl get nodes &>/dev/null; then
        print_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi

    # Find best pod
    print_info "Finding available Claude Code pod..."
    POD=$(find_best_pod)

    if [ -z "$POD" ]; then
        print_error "No pods available"
        exit 1
    fi

    print_success "Connected to pod: $POD"
    echo ""

    # Parse arguments
    if [ $# -eq 0 ]; then
        # Interactive mode
        interactive_mode "$POD"
    else
        # Prompt mode
        prompt_mode "$POD" "$@"
    fi

    echo ""
    print_success "Session ended"
}

# Help
show_help() {
    cat << EOF
Claude Code Kubernetes Wrapper

Usage:
    $0 [options] [prompt]

Options:
    -h, --help          Show this help
    -i, --interactive   Force interactive mode
    -p, --pod POD       Use specific pod

Examples:
    $0                              # Interactive mode
    $0 "explain this code"          # Single prompt
    $0 --interactive                # Force interactive mode
    $0 --pod claude-code-xxxxx "help"  # Use specific pod

Environment:
    NAMESPACE        Kubernetes namespace (default: ai-inference)
    TIMEOUT          Session timeout in seconds (default: 3600)

EOF
}

# Parse flags
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -i|--interactive)
            INTERACTIVE=true
            shift
            ;;
        -p|--pod)
            POD="$2"
            shift 2
            ;;
        *)
            break
            ;;
    esac
done

# Run main
main "$@"
