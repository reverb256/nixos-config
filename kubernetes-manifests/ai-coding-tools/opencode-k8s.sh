#!/usr/bin/env bash
# OpenCode Kubernetes Wrapper
# Usage: ./opencode-k8s.sh [options] [prompt]

set -e

NAMESPACE="ai-inference"
SELECTOR="app=opencode"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}ℹ️  $1${NC}"
}

find_best_pod() {
    local pods=($(kubectl get pods -n "$NAMESPACE" -l "$SELECTOR" \
        -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null))

    if [ ${#pods[@]} -eq 0 ]; then
        print_error "No OpenCode pods found"
        exit 1
    fi

    # Return first running pod
    for pod in "${pods[@]}"; do
        local status=$(kubectl get pod -n "$NAMESPACE" "$pod" \
            -o jsonpath='{.status.phase}')
        if [ "$status" = "Running" ]; then
            echo "$pod"
            return
        fi
    done

    echo "${pods[0]}"
}

interactive_mode() {
    local pod=$1

    print_header "OpenCode Interactive Session"

    print_info "Pod: $pod"
    print_info "Config: /home/j_kro/.opencode/config.json"
    print_info "LM Studio: http://127.0.0.1:8080/v1"
    echo ""

    print_info "Starting OpenCode shell..."
    echo "Type 'exit' to end session"
    echo ""

    kubectl exec -it -n "$NAMESPACE" "$pod" -- \
        /bin/bash -c "cd /home/j_kro && opencode"
}

prompt_mode() {
    local pod=$1
    shift
    local prompt="$*"

    print_header "OpenCode - Prompt Mode"

    print_info "Pod: $pod"
    print_info "Prompt: $prompt"
    echo ""

    # Execute opencode with prompt
    kubectl exec -i -n "$NAMESPACE" "$pod" -- \
        /bin/bash -c "cd /home/j_kro && echo '$prompt' | opencode"
}

main() {
    if ! kubectl get nodes &>/dev/null; then
        print_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi

    print_info "Finding available OpenCode pod..."
    POD=$(find_best_pod)

    if [ -z "$POD" ]; then
        print_error "No pods available"
        exit 1
    fi

    print_success "Connected to pod: $POD"
    echo ""

    if [ $# -eq 0 ]; then
        interactive_mode "$POD"
    else
        prompt_mode "$POD" "$@"
    fi

    echo ""
    print_success "Session ended"
}

show_help() {
    cat << EOF
OpenCode Kubernetes Wrapper

Usage:
    $0 [options] [prompt]

Options:
    -h, --help          Show this help
    -i, --interactive   Force interactive mode
    -p, --pod POD       Use specific pod

Examples:
    $0                              # Interactive mode
    $0 "explain this function"      # Single prompt
    $0 --interactive                # Force interactive mode
    $0 --pod opencode-xxxxx "help"  # Use specific pod

Configuration:
    Config file: ~/.opencode/config.json
    LM Studio:  http://127.0.0.1:8080/v1
    Model:       magnum-opus-35b-a3b-i1

EOF
}

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

main "$@"
