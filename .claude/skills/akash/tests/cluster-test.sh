#!/usr/bin/env bash
# Akash Assistant Skill - Cluster Integration Test
# Tests the skill against a real Kubernetes cluster

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test configuration
AKASH_NAMESPACE="${AKASH_NAMESPACE:-akash-services}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Helper functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Test: Check if kubectl is available
test_kubectl_available() {
    log_info "Testing kubectl availability..."
    ((TESTS_RUN++))

    if command -v kubectl &> /dev/null; then
        log_info "✓ kubectl is available"
        ((TESTS_PASSED++))
        return 0
    else
        log_error "✗ kubectl not found"
        ((TESTS_FAILED++))
        return 1
    fi
}

# Test: Check if cluster is accessible
test_cluster_accessible() {
    log_info "Testing cluster connectivity..."
    ((TESTS_RUN++))

    if kubectl get nodes &> /dev/null; then
        log_info "✓ Cluster is accessible"
        ((TESTS_PASSED++))
        return 0
    else
        log_error "✗ Cannot connect to cluster"
        ((TESTS_FAILED++))
        return 1
    fi
}

# Test: Check if akash namespace exists
test_akash_namespace() {
    log_info "Testing Akash namespace..."
    ((TESTS_RUN++))

    if kubectl get namespace "$AKASH_NAMESPACE" &> /dev/null; then
        log_info "✓ Namespace $AKASH_NAMESPACE exists"
        ((TESTS_PASSED++))
        return 0
    else
        log_warn "✗ Namespace $AKASH_NAMESPACE not found (may not be deployed)"
        ((TESTS_FAILED++))
        return 1
    fi
}

# Test: Check if provider pod is running
test_provider_pod() {
    log_info "Testing provider pod..."
    ((TESTS_RUN++))

    local provider_pod
    provider_pod=$(kubectl get pods -n "$AKASH_NAMESPACE" -l app=akash-provider -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    if [[ -n "$provider_pod" ]]; then
        local pod_status
        pod_status=$(kubectl get pod "$provider_pod" -n "$AKASH_NAMESPACE" -o jsonpath='{.status.phase}')

        if [[ "$pod_status" == "Running" ]]; then
            log_info "✓ Provider pod $provider_pod is Running"
            ((TESTS_PASSED++))
            return 0
        else
            log_warn "✗ Provider pod $provider_pod status: $pod_status"
            ((TESTS_FAILED++))
            return 1
        fi
    else
        log_warn "✗ No provider pod found"
        ((TESTS_FAILED++))
        return 1
    fi
}

# Test: Run skill diagnostics
test_skill_diagnostics() {
    log_info "Testing skill diagnostics..."
    ((TESTS_RUN++))

    cd "$SKILL_DIR"

    # Run the main index.js with check command
    if node src/index.js check --namespace="$AKASH_NAMESPACE" &> /dev/null; then
        log_info "✓ Skill diagnostics executed successfully"
        ((TESTS_PASSED++))
        return 0
    else
        log_error "✗ Skill diagnostics failed"
        ((TESTS_FAILED++))
        return 1
    fi
}

# Test: Verify all required modules exist
test_module_structure() {
    log_info "Testing module structure..."
    ((TESTS_RUN++))

    local required_modules=(
        "src/index.js"
        "src/diagnostics.js"
        "src/prioritizer.js"
        "src/explainer.js"
        "src/auto-fix.js"
        "src/knowledge.js"
        "src/utils/kubectl.js"
    )

    local all_exist=true
    for module in "${required_modules[@]}"; do
        if [[ -f "$SKILL_DIR/$module" ]]; then
            : # File exists
        else
            log_error "✗ Missing module: $module"
            all_exist=false
        fi
    done

    if [[ "$all_exist" == "true" ]]; then
        log_info "✓ All required modules present"
        ((TESTS_PASSED++))
        return 0
    else
        ((TESTS_FAILED++))
        return 1
    fi
}

# Test: Run unit tests
test_unit_tests() {
    log_info "Running unit tests..."
    ((TESTS_RUN++))

    cd "$SKILL_DIR"

    if npm test -- --silent 2>&1 | grep -q "passed"; then
        log_info "✓ All unit tests passing"
        ((TESTS_PASSED++))
        return 0
    else
        log_error "✗ Some unit tests failed"
        ((TESTS_FAILED++))
        return 1
    fi
}

# Main test runner
main() {
    echo "========================================"
    echo "Akash Assistant - Cluster Integration Tests"
    echo "========================================"
    echo ""
    log_info "Namespace: $AKASH_NAMESPACE"
    log_info "Skill Directory: $SKILL_DIR"
    echo ""

    # Run all tests
    test_module_structure
    test_kubectl_available
    test_cluster_accessible
    test_akash_namespace
    test_provider_pod
    test_unit_tests
    test_skill_diagnostics

    # Print summary
    echo ""
    echo "========================================"
    echo "Test Summary"
    echo "========================================"
    echo "Tests Run:    $TESTS_RUN"
    echo -e "Tests Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Tests Failed: ${RED}$TESTS_FAILED${NC}"
    echo ""

    if [[ $TESTS_FAILED -eq 0 ]]; then
        log_info "✓ All integration tests passed!"
        exit 0
    else
        log_error "✗ Some tests failed"
        exit 1
    fi
}

# Run main function
main "$@"
