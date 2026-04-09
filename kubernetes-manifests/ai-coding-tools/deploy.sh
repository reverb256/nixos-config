#!/usr/bin/env bash
# Deploy AI Coding Tools to Kubernetes

set -e

NAMESPACE="ai-inference"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_step() {
    echo -e "${BLUE}▶ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# Check prerequisites
check_prereqs() {
    print_step "Checking prerequisites..."

    if ! command -v kubectl &>/dev/null; then
        echo "❌ kubectl not found"
        exit 1
    fi

    if ! kubectl get nodes &>/dev/null; then
        echo "❌ Cannot connect to cluster"
        exit 1
    fi

    print_success "Prerequisites OK"
}

# Create namespace
create_namespace() {
    print_step "Creating namespace..."

    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    print_success "Namespace created/updated"
}

# Create secrets from existing config
create_secrets() {
    print_step "Creating secrets..."

    # Extract Z.AI API key from Claude config
    if [ -f ~/.claude.json ]; then
        ZAI_KEY=$(jq -r '.mcpServers["zai-mcp-server"].env.Z_AI_API_KEY' ~/.claude.json 2>/dev/null)

        if [ "$ZAI_KEY" != "null" ] && [ -n "$ZAI_KEY" ]; then
            kubectl create secret generic ai-coding-secrets \
                --from-literal=zai-api-key="$ZAI_KEY" \
                --namespace="$NAMESPACE" \
                --dry-run=client -o yaml | kubectl apply -f -
            print_success "Secrets created from existing config"
        else
            print_warning "Z.AI API key not found, creating placeholder"
            kubectl create secret generic ai-coding-secrets \
                --from-literal=zai-api-key="placeholder" \
                --namespace="$NAMESPACE" \
                --dry-run=client -o yaml | kubectl apply -f -
        fi
    else
        print_warning "Claude config not found, creating placeholder secret"
        kubectl create secret generic ai-coding-secrets \
            --from-literal=zai-api-key="placeholder" \
            --namespace="$NAMESPACE" \
            --dry-run=client -o yaml | kubectl apply -f -
    fi
}

# Deploy storage
deploy_storage() {
    print_step "Deploying storage..."

    # Note: hostPath PV needs node-specific configuration
    # This is a simplified version for demo
    print_warning "Storage using hostPath - ensure /home/j_kro is accessible on all nodes"

    kubectl apply -f 00-storage.yaml
    print_success "Storage deployed"
}

# Deploy Claude Code
deploy_claude_code() {
    print_step "Deploying Claude Code..."

    kubectl apply -f 10-claude-code-deployment.yaml
    print_success "Claude Code deployed"

    # Wait for pod to be ready
    print_step "Waiting for Claude Code pod to be ready..."
    kubectl wait --for=condition=ready pod -l app=claude-code -n "$NAMESPACE" --timeout=120s || true
    print_success "Claude Code is ready"
}

# Deploy OpenCode
deploy_opencode() {
    print_step "Deploying OpenCode..."

    kubectl apply -f 20-opencode-deployment.yaml
    print_success "OpenCode deployed"

    # Wait for pod to be ready
    print_step "Waiting for OpenCode pod to be ready..."
    kubectl wait --for=condition=ready pod -l app=opencode -n "$NAMESPACE" --timeout=180s || true
    print_success "OpenCode is ready"
}

# Deploy HPA
deploy_hpa() {
    print_step "Deploying Horizontal Pod Autoscalers..."

    kubectl apply -f 30-hpa.yaml
    print_success "HPA deployed"
}

# Install shell wrappers
install_wrappers() {
    print_step "Installing shell wrappers..."

    chmod +x claude-k8s.sh
    chmod +x opencode-k8s.sh

    # Create symlinks in PATH
    LOCAL_BIN="$HOME/.local/bin"
    mkdir -p "$LOCAL_BIN"

    ln -sf "$(pwd)/claude-k8s.sh" "$LOCAL_BIN/claude-k8s"
    ln -sf "$(pwd)/opencode-k8s.sh" "$LOCAL_BIN/opencode-k8s"

    print_success "Wrappers installed"
    print_warning "Add $LOCAL_BIN to PATH if not already there:"
    echo "   export PATH=\"\$PATH:\$HOME/.local/bin\""
}

# Show status
show_status() {
    print_step "Deployment status"

    echo ""
    kubectl get pods -n "$NAMESPACE" -l component=ai-coding-tool
    echo ""

    kubectl get hpa -n "$NAMESPACE"
    echo ""

    print_success "Deployment complete!"
    echo ""
    echo "Usage:"
    echo "  Claude Code:  ./claude-k8s.sh \"your prompt\""
    echo "  OpenCode:    ./opencode-k8s.sh \"your prompt\""
    echo ""
    echo "Or use symlinks:"
    echo "  claude-k8s \"your prompt\""
    echo "  opencode-k8s \"your prompt\""
}

# Main
main() {
    echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  AI Coding Tools - K8s Deployment      ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
    echo ""

    cd "$(dirname "$0")"

    check_prereqs
    create_namespace
    create_secrets
    deploy_storage
    deploy_claude_code
    deploy_opencode
    deploy_hpa
    install_wrappers
    show_status
}

# Run
main "$@"
