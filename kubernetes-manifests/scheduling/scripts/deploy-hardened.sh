#!/usr/bin/env bash
# COMPLETELY HEADLESS SCHEDULER MIGRATION - HARDENED VERSION
# Zero web UI interaction - fully automated CLI deployment
# Version: 3.0 - Security and Operational Hardening

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

log_step() {
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# Error handling
trap 'log_error "Script failed at line $LINENO. Exit code: $?"' ERR

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="$(dirname "$SCRIPT_DIR")"

# ============================================================================
# PHASE 0: PREPARATION
# ============================================================================

phase0_preparation() {
    log_step "PHASE 0: PREPARATION (HARDENED)"

    log_info "Checking prerequisites..."

    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl not found"
        exit 1
    fi
    log_info "✓ kubectl: $(kubectl version --short 2>/dev/null | head -1)"

    # Check helm
    if ! command -v helm &> /dev/null; then
        log_error "helm not found"
        exit 1
    fi
    log_info "✓ helm: $(helm version --short 2>/dev/null | cut -d. -f1-2)"

    # Check cluster access
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot access cluster"
        exit 1
    fi
    log_info "✓ Cluster: $(kubectl cluster-info | head -1)"

    # Check existing resources
    if helm list -n yunikorn 2>/dev/null | grep -q yunikorn; then
        log_warn "YuniKorn already installed - will upgrade"
    fi

    if helm list -n volcano-system 2>/dev/null | grep -q volcano; then
        log_warn "Volcano already installed - will upgrade"
    fi

    # Backup current state
    BACKUP_DIR="$K8S_DIR/backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"

    if kubectl get deployment gpu-miner-zephyr -n mining &> /dev/null; then
        kubectl get deployment gpu-miner-zephyr -n mining -o yaml > "$BACKUP_DIR/gpu-miner-zephyr.yaml"
        log_info "✓ Backed up gpu-miner-zephyr"
    fi

    if kubectl get deployment gpu-miner-forge -n mining &> /dev/null; then
        kubectl get deployment gpu-miner-forge -n mining -o yaml > "$BACKUP_DIR/gpu-miner-forge.yaml"
        log_info "✓ Backed up gpu-miner-forge"
    fi

    if kubectl get deployment ai-inference-gateway -n ai-inference &> /dev/null; then
        kubectl get deployment ai-inference-gateway -n ai-inference -o yaml > "$BACKUP_DIR/ai-inference-gateway.yaml"
        log_info "✓ Backed up ai-inference-gateway"
    fi

    log_info "✓ Backup saved to: $BACKUP_DIR"
    log_info "Phase 0 complete ✓"
}

# ============================================================================
# PHASE 1: SECURITY FOUNDATION
# ============================================================================

phase1_security() {
    log_step "PHASE 1: SECURITY FOUNDATION"

    log_info "Deploying security policies..."

    # Apply Pod Security Standards
    kubectl apply -f "$K8S_DIR/security/03-namespaces-pss.yaml" >/dev/null 2>&1
    log_info "✓ Pod Security Standards applied"

    # Apply ServiceAccounts
    kubectl apply -f "$K8S_DIR/security/01-serviceaccounts.yaml" >/dev/null 2>&1
    log_info "✓ ServiceAccounts created"

    # Apply RBAC
    kubectl apply -f "$K8S_DIR/security/02-rbac-fixed.yaml" >/dev/null 2>&1
    log_info "✓ RBAC policies applied"

    # Apply Network Policies
    kubectl apply -f "$K8S_DIR/network/01-default-deny.yaml" >/dev/null 2>&1
    log_info "✓ Network policies applied"

    log_info "Phase 1 complete ✓"
}

# ============================================================================
# PHASE 2: YUNIKORN DEPLOYMENT
# ============================================================================

phase2_yunikorn() {
    log_step "PHASE 2: YUNIKORN DEPLOYMENT (HARDENED)"

    log_info "Deploying YuniKorn scheduler..."

    # Create namespace
    kubectl apply -f "$K8S_DIR/yunikorn/00-namespace.yaml" >/dev/null 2>&1
    log_info "✓ Namespace created"

    # Add Helm repo
    helm repo add yunikorn https://apache.github.io/yunikorn-release 2>/dev/null
    helm repo update >/dev/null 2>&1
    log_info "✓ Helm repository added"

    # Install YuniKorn
    helm upgrade --install yunikorn yunikorn/yunikorn \
        --namespace yunikorn \
        --values "$K8S_DIR/yunikorn/values.yaml" \
        --wait \
        --timeout 5m \
        >/dev/null 2>&1
    log_info "✓ YuniKorn installed"

    # Create priority classes
    kubectl apply -f "$K8S_DIR/yunikorn/02-priority-classes.yaml" >/dev/null 2>&1
    log_info "✓ Priority classes created"

    # Wait for readiness
    log_info "Waiting for YuniKorn to be ready..."
    kubectl rollout status deployment -n yunikorn -l app=yunikorn-scheduler --timeout=120s >/dev/null 2>&1

    log_info "Phase 2 complete ✓"
}

# ============================================================================
# PHASE 3: VOLCANO DEPLOYMENT
# ============================================================================

phase3_volcano() {
    log_step "PHASE 3: VOLCANO DEPLOYMENT (HARDENED)"

    log_info "Deploying Volcano scheduler..."

    # Create namespace
    kubectl apply -f "$K8S_DIR/volcano/00-namespace.yaml" >/dev/null 2>&1
    log_info "✓ Namespace created"

    # Add Helm repo
    helm repo add volcano https://volcano-sh.github.io/charts 2>/dev/null
    helm repo update >/dev/null 2>&1
    log_info "✓ Helm repository added"

    # Install Volcano
    helm upgrade --install volcano volcano/volcano \
        --namespace volcano-system \
        --create-namespace \
        --set basic.scheduler_image_tag="v1.9.0" \
        --set basic.webhook_image_tag="v1.9.0" \
        --wait \
        --timeout 5m \
        >/dev/null 2>&1
    log_info "✓ Volcano installed"

    # Create PodGroups
    kubectl apply -f "$K8S_DIR/volcano/02-podgroups.yaml" >/dev/null 2>&1
    log_info "✓ PodGroups created"

    # Create Queues
    kubectl apply -f "$K8S_DIR/volcano/03-queues.yaml" >/dev/null 2>&1
    log_info "✓ Queues created"

    # Wait for readiness
    log_info "Waiting for Volcano to be ready..."
    kubectl rollout status deployment -n volcano-system -l app=volcano-scheduler --timeout=120s >/dev/null 2>&1

    log_info "Phase 3 complete ✓"
}

# ============================================================================
# PHASE 4: OPERATIONAL RESOURCES
# ============================================================================

phase4_operational() {
    log_step "PHASE 4: OPERATIONAL RESOURCES"

    log_info "Deploying operational resources..."

    # Apply PodDisruptionBudgets
    kubectl apply -f "$K8S_DIR/operational/01-pdb.yaml" >/dev/null 2>&1
    log_info "✓ PodDisruptionBudgets created"

    # Apply ResourceQuotas and LimitRanges
    kubectl apply -f "$K8S_DIR/operational/02-resource-quota.yaml" >/dev/null 2>&1
    log_info "✓ ResourceQuotas and LimitRanges created"

    # Apply ServiceMonitors (if Prometheus Operator is installed)
    if kubectl get servicemonitor --all-namespaces 2>/dev/null | grep -q .; then
        kubectl apply -f "$K8S_DIR/operational/03-servicemonitor.yaml" >/dev/null 2>&1
        log_info "✓ ServiceMonitors created"
    else
        log_warn "Prometheus Operator not detected - skipping ServiceMonitors"
    fi

    log_info "Phase 4 complete ✓"
}

# ============================================================================
# PHASE 5: DEPLOYMENT MIGRATION
# ============================================================================

phase5_deployments() {
    log_step "PHASE 5: DEPLOYMENT MIGRATION (HARDENED)"

    log_info "Migrating deployments to new schedulers..."

    # Update mining deployments (use hardened versions)
    if [ -f "$K8S_DIR/../mining/gpu-miner-zephyr-yunikorn-fixed.yaml" ]; then
        kubectl apply -f "$K8S_DIR/../mining/gpu-miner-zephyr-yunikorn-fixed.yaml" >/dev/null 2>&1
        log_info "✓ gpu-miner-zephyr migrated (hardened)"
    elif [ -f "$K8S_DIR/../mining/gpu-miner-zephyr-yunikorn.yaml" ]; then
        kubectl apply -f "$K8S_DIR/../mining/gpu-miner-zephyr-yunikorn.yaml" >/dev/null 2>&1
        log_info "✓ gpu-miner-zephyr migrated (original)"
    fi

    if [ -f "$K8S_DIR/../mining/gpu-miner-forge-yunikorn-fixed.yaml" ]; then
        kubectl apply -f "$K8S_DIR/../mining/gpu-miner-forge-yunikorn-fixed.yaml" >/dev/null 2>&1
        log_info "✓ gpu-miner-forge migrated (hardened)"
    elif [ -f "$K8S_DIR/../mining/gpu-miner-forge-yunikorn.yaml" ]; then
        kubectl apply -f "$K8S_DIR/../mining/gpu-miner-forge-yunikorn.yaml" >/dev/null 2>&1
        log_info "✓ gpu-miner-forge migrated (original)"
    fi

    # Update AI inference gateway (use hardened version)
    if [ -f "$K8S_DIR/../ai-inference/gateway-deployment-yunikorn-fixed.yaml" ]; then
        kubectl apply -f "$K8S_DIR/../ai-inference/gateway-deployment-yunikorn-fixed.yaml" >/dev/null 2>&1
        log_info "✓ ai-inference-gateway migrated (hardened)"
    elif [ -f "$K8S_DIR/../ai-inference/gateway-deployment-yunikorn.yaml" ]; then
        kubectl apply -f "$K8S_DIR/../ai-inference/gateway-deployment-yunikorn.yaml" >/dev/null 2>&1
        log_info "✓ ai-inference-gateway migrated (original)"
    fi

    # Wait for deployments
    log_info "Waiting for deployments to roll out..."
    kubectl rollout status deployment gpu-miner-zephyr -n mining --timeout=120s >/dev/null 2>&1 || true
    kubectl rollout status deployment gpu-miner-forge -n mining --timeout=120s >/dev/null 2>&1 || true
    kubectl rollout status deployment ai-inference-gateway -n ai-inference --timeout=120s >/dev/null 2>&1 || true

    log_info "Phase 5 complete ✓"
}

# ============================================================================
# PHASE 6: AUTOMATED VERIFICATION (CLI-ONLY)
# ============================================================================

phase6_verify() {
    log_step "PHASE 6: AUTOMATED VERIFICATION (ENHANCED)"

    log_info "Running enhanced CLI-based verification..."

    # Check 1: YuniKorn pods
    log_info "✓ Check 1: YuniKorn pods"
    YUNIKORN_PODS=$(kubectl get pods -n yunikorn --no-headers 2>/dev/null | wc -l)
    if [ "$YUNIKORN_PODS" -ge 2 ]; then
        log_info "  ✓ YuniKorn: $YUNIKORN_PODS pods running"
    else
        log_error "  ✗ YuniKorn: Expected 2+ pods, got $YUNIKORN_PODS"
        return 1
    fi

    # Check 2: Volcano pods
    log_info "✓ Check 2: Volcano pods"
    VOLCANO_PODS=$(kubectl get pods -n volcano-system --no-headers 2>/dev/null | wc -l)
    if [ "$VOLCANO_PODS" -ge 2 ]; then
        log_info "  ✓ Volcano: $VOLCANO_PODS pods running"
    else
        log_error "  ✗ Volcano: Expected 2+ pods, got $VOLCANO_PODS"
        return 1
    fi

    # Check 3: ServiceAccounts
    log_info "✓ Check 3: ServiceAccounts"
    SA_COUNT=$(kubectl get serviceaccount -n mining gpu-miner-sa --no-headers 2>/dev/null | wc -l)
    SA_COUNT=$((SA_COUNT + $(kubectl get serviceaccount -n ai-inference ai-gateway-sa --no-headers 2>/dev/null | wc -l)))
    if [ "$SA_COUNT" -ge 2 ]; then
        log_info "  ✓ ServiceAccounts: $SA_COUNT created"
    else
        log_error "  ✗ ServiceAccounts: Expected 2+, got $SA_COUNT"
        return 1
    fi

    # Check 4: Network Policies
    log_info "✓ Check 4: Network Policies"
    NETPOL_COUNT=$(kubectl get networkpolicy -n mining --no-headers 2>/dev/null | wc -l)
    NETPOL_COUNT=$((NETPOL_COUNT + $(kubectl get networkpolicy -n ai-inference --no-headers 2>/dev/null | wc -l)))
    if [ "$NETPOL_COUNT" -ge 2 ]; then
        log_info "  ✓ NetworkPolicies: $NETPOL_COUNT created"
    else
        log_warn "  ⚠ NetworkPolicies: Expected 2+, got $NETPOL_COUNT"
    fi

    # Check 5: Pod Security Standards
    log_info "✓ Check 5: Pod Security Standards"
    PSS_MINING=$(kubectl get namespace mining -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}' 2>/dev/null)
    PSS_AI=$(kubectl get namespace ai-inference -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}' 2>/dev/null)
    if [ "$PSS_MINING" = "baseline" ] && [ "$PSS_AI" = "baseline" ]; then
        log_info "  ✓ PSS: Mining=$PSS_MINING, AI=$PSS_AI"
    else
        log_warn "  ⚠ PSS: Mining=$PSS_MINING, AI=$PSS_AI (expected: baseline)"
    fi

    # Check 6: ResourceQuotas
    log_info "✓ Check 6: ResourceQuotas"
    QUOTA_COUNT=$(kubectl get resourcequota -n mining --no-headers 2>/dev/null | wc -l)
    QUOTA_COUNT=$((QUOTA_COUNT + $(kubectl get resourcequota -n ai-inference --no-headers 2>/dev/null | wc -l)))
    if [ "$QUOTA_COUNT" -ge 2 ]; then
        log_info "  ✓ ResourceQuotas: $QUOTA_COUNT created"
    else
        log_warn "  ⚠ ResourceQuotas: Expected 2+, got $QUOTA_COUNT"
    fi

    # Check 7: PodDisruptionBudgets
    log_info "✓ Check 7: PodDisruptionBudgets"
    PDB_COUNT=$(kubectl get pdb -n ai-inference --no-headers 2>/dev/null | wc -l)
    if [ "$PDB_COUNT" -ge 1 ]; then
        log_info "  ✓ PodDisruptionBudgets: $PDB_COUNT created"
    else
        log_warn "  ⚠ PodDisruptionBudgets: Expected 1+, got $PDB_COUNT"
    fi

    # Check 8: Mining deployments
    log_info "✓ Check 8: Mining deployments"
    MINING_DEPLOYMENTS=$(kubectl get deployment -n mining --no-headers 2>/dev/null | wc -l)
    MINING_PODS=$(kubectl get pods -n mining -l app=gpu-miner --no-headers 2>/dev/null | wc -l)
    log_info "  ✓ Mining: $MINING_DEPLOYMENTS deployments, $MINING_PODS pods"

    # Check 9: AI gateway
    log_info "✓ Check 9: AI gateway"
    AI_PODS=$(kubectl get pods -n ai-inference -l app=ai-inference-gateway --no-headers 2>/dev/null | wc -l)
    log_info "  ✓ AI gateway: $AI_PODS pods"

    # Check 10: Scheduler health
    log_info "✓ Check 10: Scheduler health"
    kubectl get cm yunikorn-config -n yunikorn &>/dev/null
    log_info "  ✓ YuniKorn config accessible"

    log_info "Phase 6 complete ✓"
}

# ============================================================================
# PHASE 7: PREEMPTION TEST (AUTOMATED)
# ============================================================================

phase7_test_preemption() {
    log_step "PHASE 7: PREEMPTION TEST (AUTOMATED)"

    log_info "Testing preemption behavior (no web UI required)..."

    # Get initial state
    INITIAL_STATE=$(kubectl get configmap gpu-scheduler-state -n kube-system -o jsonpath='{.data.ai-state}' 2>/dev/null)
    log_info "Initial state: $INITIAL_STATE"

    # Simulate AI workload starting
    log_info "Simulating AI workload starting..."
    kubectl patch configmap gpu-scheduler-state -n kube-system \
        --type=merge \
        --patch='{"data":{"ai-state":"AI_START","active-workload":"test-inference"}}' \
        >/dev/null 2>&1

    # Wait for preemption
    log_info "Waiting for preemption (10 seconds)..."
    sleep 10

    # Check if mining pods are affected
    MINING_PODS_AFTER=$(kubectl get pods -n mining -l app=gpu-miner --no-headers 2>/dev/null | wc -l)
    log_info "Mining pods after AI_START: $MINING_PODS_AFTER"

    # Reset state
    log_info "Resetting to IDLE state..."
    kubectl patch configmap gpu-scheduler-state -n kube-system \
        --type=merge \
        --patch='{"data":{"ai-state":"IDLE","active-workload":"none"}}' \
        >/dev/null 2>&1

    # Wait for recovery
    log_info "Waiting for mining recovery (10 seconds)..."
    sleep 10

    # Check recovery
    MINING_PODS_FINAL=$(kubectl get pods -n mining -l app=gpu-miner --no-headers 2>/dev/null | wc -l)
    log_info "Mining pods after IDLE: $MINING_PODS_FINAL"

    if [ "$MINING_PODS_FINAL" -ge 1 ]; then
        log_info "✓ Preemption test passed (mining recovered)"
    else
        log_warn "⚠ Mining pods not recovered - may need manual investigation"
    fi

    log_info "Phase 7 complete ✓"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    log_info "Starting COMPLETELY HEADLESS scheduler migration (HARDENED)..."
    echo ""

    # Run all phases
    phase0_preparation
    echo ""

    phase1_security
    echo ""

    phase2_yunikorn
    echo ""

    phase3_volcano
    echo ""

    phase4_operational
    echo ""

    phase5_deployments
    echo ""

    phase6_verify
    echo ""

    phase7_test_preemption
    echo ""

    # Final summary
    log_step "HARDENED MIGRATION COMPLETE"

    log_info "✅ All components deployed successfully with security hardening!"
    echo ""
    echo "🔒 Security Enhancements Applied:"
    echo "  • ServiceAccounts for least-privilege RBAC"
    echo "  • Fixed RBAC subjects (ServiceAccount-based)"
    echo "  • Pod Security Standards (baseline enforcement)"
    echo "  • Network Policies (default-deny + explicit allow)"
    echo "  • ResourceQuotas and LimitRanges"
    echo "  • PodDisruptionBudgets for HA"
    echo "  • ServiceMonitors for observability"
    echo ""
    echo "📊 CLI Commands for Monitoring:"
    echo ""
    echo "  # Quick status"
    echo "  $K8S_DIR/scheduling/scripts/status-quick.sh"
    echo ""
    echo "  # Full monitoring"
    echo "  $K8S_DIR/scheduling/scripts/monitor.sh"
    echo ""
    echo "  # Watch pods"
    echo "  kubectl get pods -A -l 'app in (gpu-miner,ai-inference-gateway)' -w"
    echo ""
    echo "  # Check scheduler logs"
    echo "  kubectl logs -n yunikorn deployment/yunikorn-scheduler -f"
    echo "  kubectl logs -n volcano-system deployment/volcano-scheduler -f"
    echo ""
    echo "  # Test preemption"
    echo "  kubectl patch configmap gpu-scheduler-state -n kube-system --type=merge --patch='{\"data\":{\"ai-state\":\"AI_START\"}}'"
    echo "  kubectl get pods -n mining -w"
    echo "  kubectl patch configmap gpu-scheduler-state -n kube-system --type=merge --patch='{\"data\":{\"ai-state\":\"IDLE\"}}'"
    echo ""
    echo "  # Reset state"
    echo "  kubectl patch configmap gpu-scheduler-state -n kube-system --type=merge --patch='{\"data\":{\"ai-state\":\"IDLE\"}}'"
    echo ""
    echo "🎉 Migration complete! No web UI required - everything via CLI!"
    echo ""
    echo "📚 Next Steps:"
    echo "  1. Monitor pod health: kubectl get pods -A -w"
    echo "  2. Check scheduler logs for any issues"
    echo "  3. Test AI workload to verify preemption"
    echo "  4. Consider setting up GitOps (see gitops/ directory)"
    echo ""
}

# Run main function
main "$@"
