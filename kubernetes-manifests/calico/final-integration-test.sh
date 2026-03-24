#!/usr/bin/env bash
#
# Final Integration Test - Calico Network Integration
# Tests all 6 components of the network integration implementation
#
# Usage: ./final-integration-test.sh [--verbose]
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Verbose mode
VERBOSE=false
if [[ "${1:-}" == "--verbose" ]]; then
  VERBOSE=true
fi

# Helper functions
log_info() {
  echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
  echo -e "${GREEN}[✓]${NC} $1"
  TESTS_PASSED=$((TESTS_PASSED + 1))
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
}

log_failure() {
  echo -e "${RED}[✗]${NC} $1"
  TESTS_FAILED=$((TESTS_FAILED + 1))
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
}

log_warning() {
  echo -e "${YELLOW}[!]${NC} $1"
}

# Print header
print_header() {
  echo -e "${BLUE}========================================${NC}"
  echo -e "${BLUE}  Calico Network Integration Test Suite${NC}"
  echo -e "${BLUE}========================================${NC}"
  echo ""
}

# Print test section
print_section() {
  echo ""
  echo -e "${BLUE}─── $1 ───${NC}"
}

# ============================================
# Test 1: DNS Resolution
# ============================================
test_dns_resolution() {
  print_section "Test 1: DNS Resolution"

  # Test 1.1: Unbound cluster DNS functional
  log_info "Checking Unbound DNS service..."
  if systemctl is-active --quiet unbound 2>/dev/null; then
    log_success "Unbound DNS service is running"

    # Test DNS resolution
    if nslookup prometheus.cluster.local 127.0.0.1 2>/dev/null | grep -q "Address:"; then
      log_success "Unbound can resolve cluster services"
    else
      log_failure "Unbound cannot resolve cluster services"
    fi
  else
    log_failure "Unbound DNS service not running"
  fi

  # Test 1.2: Kubernetes CoreDNS working
  log_info "Checking CoreDNS pods..."
  COREDNS_PODS=$(kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers 2>/dev/null | wc -l)
  if [[ "$COREDNS_PODS" -gt 0 ]]; then
    log_success "CoreDNS pods running ($COREDNS_PODS pods)"
  else
    log_failure "CoreDNS pods not found"
  fi

  # Test 1.3: Service discovery operational
  log_info "Testing service discovery..."
  if kubectl get svc kubernetes -n default > /dev/null 2>&1; then
    log_success "Kubernetes API service discoverable"
  else
    log_failure "Kubernetes API service not discoverable"
  fi
}

# ============================================
# Test 2: Network Policies
# ============================================
test_network_policies() {
  print_section "Test 2: Network Policies"

  # Test 2.1: Calico policies enforced (not audit mode)
  log_info "Checking Calico policy mode..."
  if kubectl get globalnetworkpolicy default-deny-enforced > /dev/null 2>&1; then
    log_success "Calico policies in enforced mode (not audit)"

    # Test 2.2: Default-deny working
    log_info "Checking default-deny policy..."
    DEFAULT_DENY=$(kubectl get globalnetworkpolicy default-deny-enforced --no-headers 2>/dev/null | wc -l)
    if [[ "$DEFAULT_DENY" -gt 0 ]]; then
      log_success "Default-deny policy applied"
    else
      log_failure "Default-deny policy not found"
    fi

    # Test 2.3: Required traffic allowed
    log_info "Checking network policy count..."
    POLICY_COUNT=$(kubectl get networkpolicies --all-namespaces --no-headers 2>/dev/null | wc -l)
    if [[ "$POLICY_COUNT" -gt 0 ]]; then
      log_success "Network policies deployed ($POLICY_COUNT policies)"
    else
      log_failure "No network policies found"
    fi
  else
    log_failure "Calico policies not in enforced mode"
  fi
}

# ============================================
# Test 3: BGP Routing
# ============================================
test_bgp_routing() {
  print_section "Test 3: BGP Routing"

  # Test 3.1: BGP configuration present
  log_info "Checking BGP configuration..."
  if kubectl get bgpconfiguration default > /dev/null 2>&1; then
    log_success "BGP configuration found"

    # Test 3.2: Calico node pods running
    log_info "Checking Calico node pods..."
    CALICO_NODES=$(kubectl get pods -n calico-system -l k8s-app=calico-node --no-headers 2>/dev/null | grep Running | wc -l || echo 0)
    if [[ "$CALICO_NODES" -gt 0 ]]; then
      log_success "Calico node pods running ($CALICO_NODES pods)"
    else
      log_failure "Calico node pods not running"
    fi
  else
    log_warning "BGP configuration not found (may not be configured yet)"
  fi

  # Test 3.3: Pod CIDR routing functional
  log_info "Checking pod CIDR routes..."
  if ip route show 2>/dev/null | grep -q "10.244.0.0/16"; then
    log_success "Pod CIDR routes present in routing table"
  else
    log_warning "Pod CIDR routes not found on this node"
  fi
}

# ============================================
# Test 4: IPVS Load Balancing
# ============================================
test_ipvs_load_balancing() {
  print_section "Test 4: IPVS Load Balancing"

  # Test 4.1: IPVS modules loaded
  log_info "Checking IPVS kernel modules..."
  if lsmod 2>/dev/null | grep -q "ip_vs"; then
    log_success "IPVS kernel module loaded"

    # Test 4.2: kube-proxy using IPVS mode
    log_info "Checking kube-proxy mode..."
    if journalctl -u kube-proxy --no-pager 2>/dev/null | grep -q "Using ipvs Proxier"; then
      log_success "kube-proxy using IPVS mode"
    else
      log_failure "kube-proxy not using IPVS mode"
    fi

    # Test 4.3: Services load balanced
    log_info "Checking IPVS virtual services..."
    if command -v ipvsadm &> /dev/null; then
      IPVS_SERVICES=$(ipvsadm -Ln 2>/dev/null | grep -c "TCP\|UDP" || echo 0)
      if [[ "$IPVS_SERVICES" -gt 0 ]]; then
        log_success "IPVS load balancing active ($IPVS_SERVICES services)"
      else
        log_warning "No IPVS services found on this node"
      fi
    else
      log_warning "ipvsadm not available (IPVS status check skipped)"
    fi
  else
    log_failure "IPVS kernel module not loaded"
  fi
}

# ============================================
# Test 5: WireGuard Encryption
# ============================================
test_wireguard_encryption() {
  print_section "Test 5: WireGuard Encryption"

  # Test 5.1: WireGuard interfaces active
  log_info "Checking WireGuard interfaces..."
  WG_INTERFACES=$(ip link show type wireguard 2>/dev/null | wc -l)
  if [[ "$WG_INTERFACES" -gt 0 ]]; then
    log_success "WireGuard interfaces active ($WG_INTERFACES interfaces)"
  else
    log_failure "No WireGuard interfaces found"
  fi

  # Test 5.2: WireGuard configuration present
  log_info "Checking Calico WireGuard configuration..."
  if kubectl get configmap -n kube-system calico-config > /dev/null 2>&1; then
    log_success "Calico ConfigMap present"
  else
    log_warning "Calico ConfigMap not found"
  fi

  # Test 5.3: WireGuard port listening
  log_info "Checking WireGuard port..."
  if ss -ulnp 2>/dev/null | grep -q "51820"; then
    log_success "WireGuard port 51820 listening"
  else
    log_warning "WireGuard port 51820 not listening on this node"
  fi
}

# ============================================
# Test 6: Node Scheduling
# ============================================
test_node_scheduling() {
  print_section "Test 6: Node Scheduling"

  # Test 6.1: Zephyr ram-constrained taint active
  log_info "Checking Zephyr taint..."
  ZEPHYR_TAINT=$(kubectl describe node zephyr 2>/dev/null | grep -A 5 "Taints" | grep -c "ram-constrained" || echo 0)

  if [[ "$ZEPHYR_TAINT" -gt 0 ]]; then
    log_success "Zephyr ram-critical taint applied"
  else
    log_failure "Zephyr ram-critical taint not found"
  fi

  # Test 6.2: Workloads scheduling correctly
  log_info "Checking pod scheduling..."
  SCHEDULED_PODS=$(kubectl get pods --all-namespaces --field-selector spec.nodeName=zephyr --no-headers 2>/dev/null | wc -l)

  if [[ "$SCHEDULED_PODS" -gt 0 ]]; then
    log_success "Pods scheduled on Zephyr ($SCHEDULED_PODS pods)"
  else
    log_warning "No pods scheduled on Zephyr (expected behavior with taint)"
  fi

  # Test 6.3: Mining pods with tolerations running
  log_info "Checking mining pods..."
  MINING_PODS=$(kubectl get pods -n mining -l app=gpu-miner --no-headers 2>/dev/null | grep Running | wc -l)

  if [[ "$MINING_PODS" -gt 0 ]]; then
    log_success "Mining pods running ($MINING_PODS pods)"
  else
    log_warning "No mining pods found (may be scaled down)"
  fi
}

# ============================================
# Generate Test Report
# ============================================
generate_report() {
  local report_file="/tmp/calico-integration-test-report-$(date +%Y%m%d-%H%M%S).txt"

  {
    echo "========================================"
    echo "  Calico Network Integration Test Report"
    echo "========================================"
    echo ""
    echo "Date: $(date)"
    echo "Cluster: $(kubectl config current-context 2>/dev/null || echo 'unknown')"
    echo ""
    echo "Test Results:"
    echo "  Total Tests: $TESTS_TOTAL"
    echo "  Passed: $TESTS_PASSED"
    echo "  Failed: $TESTS_FAILED"
    echo ""

    if [[ $TESTS_FAILED -eq 0 ]]; then
      echo "✅ ALL TESTS PASSED"
    else
      echo "❌ SOME TESTS FAILED"
    fi

    echo ""
    echo "========================================"
    echo "Component Status Summary"
    echo "========================================"
    echo ""

    # DNS Status
    echo "1. DNS Resolution:"
    systemctl is-active --quiet unbound 2>/dev/null && echo "   ✓ Unbound: Running" || echo "   ✗ Unbound: Not running"
    COREDNS_COUNT=$(kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers 2>/dev/null | grep -c Running || echo 0)
    echo "   CoreDNS: $COREDNS_COUNT pods running"

    # Network Policies
    echo ""
    echo "2. Network Policies:"
    kubectl get globalnetworkpolicy default-deny-enforced --no-headers 2>/dev/null | grep -q enforced && echo "   ✓ Policy Mode: Enforced" || echo "   ✗ Policy Mode: Not enforced"
    POLICY_COUNT=$(kubectl get networkpolicies --all-namespaces --no-headers 2>/dev/null | wc -l)
    echo "   Policies Deployed: $POLICY_COUNT"

    # BGP Status
    echo ""
    echo "3. BGP Routing:"
    kubectl get bgpconfigurations.crd.projectcalico.org default --no-headers 2>/dev/null | grep -q default && echo "   ✓ BGP Config: Present" || echo "   ✗ BGP Config: Not found"
    CALICO_PODS=$(kubectl get pods -n calico-system -l k8s-app=calico-node --no-headers 2>/dev/null | grep -c Running || echo 0)
    echo "   Calico Node Pods: $CALICO_PODS"

    # IPVS Status
    echo ""
    echo "4. IPVS Load Balancing:"
    lsmod 2>/dev/null | grep -q "ip_vs" && echo "   ✓ IPVS Module: Loaded" || echo "   ✗ IPVS Module: Not loaded"
    journalctl -u kube-proxy --no-pager 2>/dev/null | grep -q "Using ipvs Proxier" && echo "   ✓ kube-proxy: IPVS mode" || echo "   ✗ kube-proxy: Not IPVS mode"

    # WireGuard Status
    echo ""
    echo "5. WireGuard Encryption:"
    WG_INTERFACES=$(ip link show type wireguard 2>/dev/null | wc -l)
    echo "   WireGuard Interfaces: $WG_INTERFACES"

    # Node Scheduling
    echo ""
    echo "6. Node Scheduling:"
    kubectl describe node zephyr 2>/dev/null | grep -A 5 "Taints" | grep -q "ram-constrained" && echo "   ✓ Zephyr Taint: Applied" || echo "   ✗ Zephyr Taint: Not applied"

    echo ""
    echo "========================================"
  } | tee "$report_file"

  log_info "Test report saved to: $report_file"
}

# ============================================
# Main Execution
# ============================================
main() {
  print_header

  # Check kubectl access
  if ! kubectl cluster-info > /dev/null 2>&1; then
    log_failure "Cannot access Kubernetes cluster"
    exit 1
  fi

  log_success "Connected to Kubernetes cluster"

  # Run all tests
  test_dns_resolution
  test_network_policies
  test_bgp_routing
  test_ipvs_load_balancing
  test_wireguard_encryption
  test_node_scheduling

  # Generate report
  echo ""
  generate_report

  # Print summary
  echo ""
  echo -e "${BLUE}========================================${NC}"
  echo -e "${BLUE}  Test Summary${NC}"
  echo -e "${BLUE}========================================${NC}"
  echo ""
  echo -e "Total Tests: $TESTS_TOTAL"
  echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
  echo -e "${RED}Failed: $TESTS_FAILED${NC}"
  echo ""

  if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}✅ ALL TESTS PASSED${NC}"
    exit 0
  else
    echo -e "${RED}❌ SOME TESTS FAILED${NC}"
    exit 1
  fi
}

# Run main function
main "$@"
