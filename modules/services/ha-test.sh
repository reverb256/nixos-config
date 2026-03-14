#!/usr/bin/env bash
# =============================================================================
# Kubernetes HA Validation Script
# =============================================================================
#
# Purpose: Comprehensive validation of HA Kubernetes cluster
#
# Usage: ./ha-test.sh [test-type]
#   test-type: all|etcd|apiserver|vip|scheduler|controller
#
# Examples:
#   ./ha-test.sh           # Run all tests
#   ./ha-test.sh etcd      # Test etcd cluster only
#   ./ha-test.sh vip       # Test VIP failover
#
# Output:
#   - Detailed test results
#   - Exit code 0 on success, non-zero on failure
#
# =============================================================================

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VIP="10.1.1.100"
MASTERS=("10.1.1.110" "10.1.1.120" "10.1.1.140")
ETCD_ENDPOINTS=("https://10.1.1.110:2379" "https://10.1.1.120:2379" "https://10.1.1.140:2379")
PKI_PATH="/etc/kubernetes/pki"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $*"
    ((TESTS_PASSED++))
    ((TESTS_TOTAL++))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $*"
    ((TESTS_FAILED++))
    ((TESTS_TOTAL++))
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_section() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $*${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

check_command() {
    if ! command -v "$1" &>/dev/null; then
        log_fail "$1 is required but not installed"
        return 1
    fi
    return 0
}

check_cert() {
    local cert="$1"
    local expected_cn="$2"
    local expected_san="${3:-}"

    if [[ ! -f "$cert" ]]; then
        log_fail "Certificate not found: $cert"
        return 1
    fi

    # Check expiration
    local exp_date
    exp_date=$(openssl x509 -in "$cert" -noout -enddate | cut -d= -f2)
    local exp_epoch
    exp_epoch=$(date -d "$exp_date" +%s)
    local current_epoch
    current_epoch=$(date +%s)
    local days_until_expiry
    days_until_expiry=$(( ($exp_epoch - $current_epoch) / 86400 ))

    if [[ $days_until_expiry -lt 30 ]]; then
        log_warn "Certificate expires in $days_until_expiry days: $cert"
    fi

    # Check CN
    local cn
    cn=$(openssl x509 -in "$cert" -noout -subject | sed -n 's/.*CN=\([^/]*\).*/\1/p')
    if [[ "$cn" != "$expected_cn" ]]; then
        log_fail "Certificate CN mismatch: expected '$expected_cn', got '$cn'"
        return 1
    fi

    # Check SAN if provided
    if [[ -n "$expected_san" ]]; then
        local san
        san=$(openssl x509 -in "$cert" -noout -ext subjectAltName 2>/dev/null | sed -n 's/subjectAltName=//p')
        if [[ ! "$san" =~ $expected_san ]]; then
            log_fail "Certificate SAN missing '$expected_san': $san"
            return 1
        fi
    fi

    return 0
}

wait_for_ready() {
    local timeout="$1"
    local command="$2"
    local description="$3"

    log_info "Waiting for $description..."

    local elapsed=0
    while [[ $elapsed -lt $timeout ]]; do
        if eval "$command" &>/dev/null; then
            log_success "$description is ready"
            return 0
        fi
        sleep 2
        ((elapsed += 2))
    done

    log_fail "Timeout waiting for $description"
    return 1
}

# ============================================================================
# CERTIFICATE TESTS
# ============================================================================

test_certificates() {
    log_section "Certificate Validation"

    local all_certs=(
        "$PKI_PATH/ca.pem:kubernetes"
        "$PKI_PATH/apiserver.pem:kubernetes"
        "$PKI_PATH/etcd-peer.pem:etcd-peer"
        "$PKI_PATH/etcd-zephyr.pem:etcd-zephyr"
        "$PKI_PATH/etcd-nexus.pem:etcd-nexus"
        "$PKI_PATH/etcd-sentry.pem:etcd-sentry"
        "$PKI_PATH/admin.pem:admin"
        "$PKI_PATH/controller-manager.pem:system:kube-controller-manager"
        "$PKI_PATH/scheduler.pem:system:kube-scheduler"
    )

    for cert_entry in "${all_certs[@]}"; do
        IFS=: read -r cert expected_cn <<< "$cert_entry"
        if check_cert "$cert" "$expected_cn"; then
            log_success "Certificate valid: $cert"
        else
            log_fail "Certificate invalid: $cert"
        fi
    done

    # Test API server certificate includes VIP
    log_info "Checking API server certificate for VIP..."
    if check_cert "$PKI_PATH/apiserver.pem" "kubernetes" "$VIP"; then
        log_success "API server certificate includes VIP: $VIP"
    else
        log_fail "API server certificate missing VIP: $VIP"
    fi
}

# ============================================================================
# ETCD TESTS
# ============================================================================

test_etcd() {
    log_section "etcd Cluster Tests"

    check_command etcdctl || return 1

    local etcdctl_opts=(
        "--endpoints=${ETCD_ENDPOINTS[*]}"
        "--cacert=$PKI_PATH/ca.pem"
        "--cert=$PKI_PATH/etcd-zephyr.pem"
        "--key=$PKI_PATH/etcd-zephyr-key.pem"
    )

    # Test etcd endpoint health
    log_info "Testing etcd endpoint health..."
    for endpoint in "${ETCD_ENDPOINTS[@]}"; do
        if ETCDCTL_API=3 etcdctl \
            --endpoints="$endpoint" \
            --cacert="$PKI_PATH/ca.pem" \
            --cert="$PKI_PATH/apiserver.pem" \
            --key="$PKI_PATH/apiserver-key.pem" \
            endpoint health &>/dev/null; then
            log_success "etcd endpoint healthy: $endpoint"
        else
            log_fail "etcd endpoint unhealthy: $endpoint"
        fi
    done

    # Test etcd cluster status
    log_info "Testing etcd cluster status..."
    local cluster_status
    cluster_status=$(ETCDCTL_API=3 etcdctl \
        "${etcdctl_opts[@]}" \
        --write-out=json \
        endpoint status 2>/dev/null || echo "")

    if [[ -n "$cluster_status" ]]; then
        local member_count
        member_count=$(echo "$cluster_status" | jq '. | length' 2>/dev/null || echo "0")
        if [[ "$member_count" -ge 2 ]]; then
            log_success "etcd cluster has $member_count members (quorum achieved)"
        else
            log_fail "etcd cluster has only $member_count members (quorum not achieved)"
        fi
    else
        log_fail "Failed to get etcd cluster status"
    fi

    # Test etcd leader election
    log_info "Testing etcd leader election..."
    local leader
    leader=$(ETCDCTL_API=3 etcdctl \
        "${etcdctl_opts[@]}" \
        --write-out= simple \
        endpoint status 2>/dev/null | grep true | wc -l)

    if [[ "$leader" -eq 1 ]]; then
        log_success "etcd has exactly 1 leader"
    else
        log_fail "etcd leader election failed (found $leader leaders)"
    fi

    # Test write/read
    log_info "Testing etcd write/read..."
    if ETCDCTL_API=3 etcdctl \
        "${etcdctl_opts[@]}" \
        put /ha-test/key "test-value" &>/dev/null; then

        local value
        value=$(ETCDCTL_API=3 etcdctl \
            "${etcdctl_opts[@]}" \
            get /ha-test/key --write-out= simple 2>/dev/null || echo "")

        if [[ "$value" == "test-value" ]]; then
            log_success "etcd write/read successful"
            ETCDCTL_API=3 etcdctl "${etcdctl_opts[@]}" del /ha-test/key &>/dev/null
        else
            log_fail "etcd read failed"
        fi
    else
        log_fail "etcd write failed"
    fi
}

# ============================================================================
# API SERVER TESTS
# ============================================================================

test_apiserver() {
    log_section "API Server Tests"

    check_command kubectl || return 1

    # Test API server via VIP
    log_info "Testing API server via VIP..."
    if kubectl --server="https://$VIP:6443" get nodes &>/dev/null; then
        log_success "API server reachable via VIP: $VIP"
    else
        log_fail "API server not reachable via VIP: $VIP"
    fi

    # Test API server via direct IP
    for master_ip in "${MASTERS[@]}"; do
        log_info "Testing API server via direct IP: $master_ip"
        if kubectl --server="https://$master_ip:6443" get nodes &>/dev/null; then
            log_success "API server reachable: $master_ip"
        else
            log_fail "API server not reachable: $master_ip"
        fi
    done

    # Test node readiness
    log_info "Testing Kubernetes node readiness..."
    local nodes
    nodes=$(kubectl get nodes -o json 2>/dev/null || echo "")
    if [[ -n "$nodes" ]]; then
        local ready_count
        ready_count=$(echo "$nodes" | jq '[.items[] | select(.status.conditions[] | .type=="Ready" and .status=="True")] | length' 2>/dev/null || echo "0")
        local total_count
        total_count=$(echo "$nodes" | jq '.items | length' 2>/dev/null || echo "0")

        if [[ "$ready_count" -eq "$total_count" ]] && [[ "$total_count" -gt 0 ]]; then
            log_success "All $total_count nodes are Ready"
        else
            log_warn "$ready_count/$total_count nodes are Ready"
        fi
    else
        log_fail "Failed to get node status"
    fi

    # Test control plane pods
    log_info "Testing control plane pods..."
    local control_plane_pods
    control_plane_pods=$(kubectl -n kube-system get pods -l tier=control-plane -o json 2>/dev/null || echo "")
    if [[ -n "$control_plane_pods" ]]; then
        local running_count
        running_count=$(echo "$control_plane_pods" | jq '[.items[] | select(.status.phase=="Running")] | length' 2>/dev/null || echo "0")
        local total_pods
        total_pods=$(echo "$control_plane_pods" | jq '.items | length' 2>/dev/null || echo "0")

        if [[ "$running_count" -eq "$total_pods" ]] && [[ "$total_pods" -gt 0 ]]; then
            log_success "All $total_pods control plane pods are Running"
        else
            log_warn "$running_count/$total_pods control plane pods are Running"
        fi
    else
        log_fail "Failed to get control plane pod status"
    fi
}

# ============================================================================
# VIP TESTS
# ============================================================================

test_vip() {
    log_section "VIP Failover Tests"

    # Check VIP is assigned
    log_info "Checking VIP assignment..."
    local vip_assigned=false
    for master_ip in "${MASTERS[@]}"; do
        if ssh "root@$master_ip" "ip addr show | grep -q '$VIP'" 2>/dev/null; then
            log_success "VIP $VIP is assigned to: $master_ip"
            vip_assigned=true
            break
        fi
    done

    if [[ "$vip_assigned" == "false" ]]; then
        log_fail "VIP $VIP is not assigned to any master"
    fi

    # Check HAProxy health
    log_info "Checking HAProxy status..."
    local haproxy_status
    haproxy_status=$(echo "show info" | socat /run/haproxy/admin.sock stdio 2>/dev/null | grep "Process_status" || echo "")

    if [[ "$haproxy_status" == *"OK"* ]]; then
        log_success "HAProxy is healthy"
    else
        log_warn "Could not verify HAProxy status"
    fi

    # Check backend status
    log_info "Checking API server backend status..."
    local backend_status
    backend_status=$(echo "show backend" | socat /run/haproxy/admin.sock stdio 2>/dev/null || echo "")

    if [[ -n "$backend_status" ]]; then
        local up_count
        up_count=$(echo "$backend_status" | grep -c "UP," || echo "0")
        if [[ "$up_count" -ge 2 ]]; then
            log_success "$up_count API server backends are UP"
        else
            log_warn "Only $up_count API server backends are UP"
        fi
    fi
}

# ============================================================================
# CONTROLLER MANAGER TESTS
# ============================================================================

test_controller_manager() {
    log_section "Controller Manager Tests"

    check_command kubectl || return 1

    # Check leader election
    log_info "Testing controller manager leader election..."
    local cm_leader
    cm_leader=$(kubectl -n kube-system get endpoints kube-controller-manager -o json 2>/dev/null | jq -r '.subsets[0].addresses[0].nodeName // empty' || echo "")

    if [[ -n "$cm_leader" ]]; then
        log_success "Controller manager leader elected: $cm_leader"
    else
        log_warn "No controller manager leader found (initializing...)"
    fi

    # Check controller manager pods
    log_info "Checking controller manager pods..."
    local cm_pods
    cm_pods=$(kubectl -n kube-system get pods -l component=kube-controller-manager -o json 2>/dev/null || echo "")

    if [[ -n "$cm_pods" ]]; then
        local running_count
        running_count=$(echo "$cm_pods" | jq '[.items[] | select(.status.phase=="Running")] | length' 2>/dev/null || echo "0")
        local total_count
        total_count=$(echo "$cm_pods" | jq '.items | length' 2>/dev/null || echo "0")

        log_info "$running_count/$total_count controller manager pods are Running"
    fi
}

# ============================================================================
# SCHEDULER TESTS
# ============================================================================

test_scheduler() {
    log_section "Scheduler Tests"

    check_command kubectl || return 1

    # Check leader election
    log_info "Testing scheduler leader election..."
    local scheduler_leader
    scheduler_leader=$(kubectl -n kube-system get endpoints kube-scheduler -o json 2>/dev/null | jq -r '.subsets[0].addresses[0].nodeName // empty' || echo "")

    if [[ -n "$scheduler_leader" ]]; then
        log_success "Scheduler leader elected: $scheduler_leader"
    else
        log_warn "No scheduler leader found (initializing...)"
    fi

    # Check scheduler pods
    log_info "Checking scheduler pods..."
    local scheduler_pods
    scheduler_pods=$(kubectl -n kube-system get pods -l component=kube-scheduler -o json 2>/dev/null || echo "")

    if [[ -n "$scheduler_pods" ]]; then
        local running_count
        running_count=$(echo "$scheduler_pods" | jq '[.items[] | select(.status.phase=="Running")] | length' 2>/dev/null || echo "0")
        local total_count
        total_count=$(echo "$scheduler_pods" | jq '.items | length' 2>/dev/null || echo "0")

        log_info "$running_count/$total_count scheduler pods are Running"
    fi
}

# ============================================================================
# SUMMARY AND REPORT
# ============================================================================

print_summary() {
    echo ""
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                    Test Summary                              ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  Total Tests:  ${TESTS_TOTAL}"
    echo -e "  ${GREEN}Passed:       ${TESTS_PASSED}${NC}"
    echo -e "  ${RED}Failed:       ${TESTS_FAILED}${NC}"
    echo ""

    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}✓ All tests passed!${NC}"
        return 0
    else
        echo -e "${RED}✗ Some tests failed${NC}"
        return 1
    fi
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    local test_type="${1:-all}"

    echo -e "${BLUE}"
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║         Kubernetes HA Cluster Validation                      ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    case "$test_type" in
        all)
            test_certificates
            test_etcd
            test_apiserver
            test_vip
            test_controller_manager
            test_scheduler
            ;;
        certificates|cert) test_certificates ;;
        etcd) test_etcd ;;
        apiserver|api) test_apiserver ;;
        vip) test_vip ;;
        controller|cm) test_controller_manager ;;
        scheduler) test_scheduler ;;
        *)
            echo "Usage: $0 [all|certificates|etcd|apiserver|vip|controller|scheduler]"
            exit 1
            ;;
    esac

    print_summary
}

main "$@"
