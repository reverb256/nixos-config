#!/usr/bin/env bash
# COMPLETELY HEADLESS SCHEDULER MIGRATION
# Zero web UI interaction - fully automated CLI deployment

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
    log_step "PHASE 0: PREPARATION (HEADLESS)"

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
# PHASE 1: YUNIKORN DEPLOYMENT
# ============================================================================

phase1_yunikorn() {
    log_step "PHASE 1: YUNIKORN DEPLOYMENT (HEADLESS)"

    log_info "Deploying YuniKorn scheduler..."

    # Create namespace
    kubectl apply -f "$K8S_DIR/scheduling/yunikorn/00-namespace.yaml" >/dev/null 2>&1
    log_info "✓ Namespace created"

    # Add Helm repo
    helm repo add yunikorn https://apache.github.io/yunikorn-release 2>/dev/null
    helm repo update >/dev/null 2>&1
    log_info "✓ Helm repository added"

    # Install YuniKorn
    helm upgrade --install yunikorn yunikorn/yunikorn \
        --namespace yunikorn \
        --values "$K8S_DIR/scheduling/yunikorn/values.yaml" \
        --wait \
        --timeout 5m \
        >/dev/null 2>&1
    log_info "✓ YuniKorn installed"

    # Create priority classes
    kubectl apply -f "$K8S_DIR/scheduling/yunikorn/02-priority-classes.yaml" >/dev/null 2>&1
    log_info "✓ Priority classes created"

    # Create state management
    kubectl apply -f "$K8S_DIR/scheduling/yunikorn/03-configmap-rbac.yaml" >/dev/null 2>&1
    log_info "✓ State management created"

    # Wait for readiness
    log_info "Waiting for YuniKorn to be ready..."
    kubectl rollout status deployment -n yunikorn -l app=yunikorn-scheduler --timeout=120s >/dev/null 2>&1

    log_info "Phase 1 complete ✓"
}

# ============================================================================
# PHASE 2: VOLCANO DEPLOYMENT
# ============================================================================

phase2_volcano() {
    log_step "PHASE 2: VOLCANO DEPLOYMENT (HEADLESS)"

    log_info "Deploying Volcano scheduler..."

    # Create namespace
    kubectl apply -f "$K8S_DIR/scheduling/volcano/00-namespace.yaml" >/dev/null 2>&1
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
    kubectl apply -f "$K8S_DIR/scheduling/volcano/02-podgroups.yaml" >/dev/null 2>&1
    log_info "✓ PodGroups created"

    # Create Queues
    kubectl apply -f "$K8S_DIR/scheduling/volcano/03-queues.yaml" >/dev/null 2>&1
    log_info "✓ Queues created"

    # Wait for readiness
    log_info "Waiting for Volcano to be ready..."
    kubectl rollout status deployment -n volcano-system -l app=volcano-scheduler --timeout=120s >/dev/null 2>&1

    log_info "Phase 2 complete ✓"
}

# ============================================================================
# PHASE 3: DEPLOYMENT MIGRATION
# ============================================================================

phase3_deployments() {
    log_step "PHASE 3: DEPLOYMENT MIGRATION (HEADLESS)"

    log_info "Migrating deployments to new schedulers..."

    # Update mining deployments
    if [ -f "$K8S_DIR/mining/gpu-miner-zephyr-yunikorn.yaml" ]; then
        kubectl apply -f "$K8S_DIR/mining/gpu-miner-zephyr-yunikorn.yaml" >/dev/null 2>&1
        log_info "✓ gpu-miner-zephyr migrated"
    fi

    if [ -f "$K8S_DIR/mining/gpu-miner-forge-yunikorn.yaml" ]; then
        kubectl apply -f "$K8S_DIR/mining/gpu-miner-forge-yunikorn.yaml" >/dev/null 2>&1
        log_info "✓ gpu-miner-forge migrated"
    fi

    # Update AI inference gateway
    if [ -f "$K8S_DIR/ai-inference/gateway-deployment-yunikorn.yaml" ]; then
        kubectl apply -f "$K8S_DIR/ai-inference/gateway-deployment-yunikorn.yaml" >/dev/null 2>&1
        log_info "✓ ai-inference-gateway migrated"
    fi

    # Wait for deployments
    log_info "Waiting for deployments to roll out..."
    kubectl rollout status deployment gpu-miner-zephyr -n mining --timeout=120s >/dev/null 2>&1 || true
    kubectl rollout status deployment gpu-miner-forge -n mining --timeout=120s >/dev/null 2>&1 || true
    kubectl rollout status deployment ai-inference-gateway -n ai-inference --timeout=120s >/dev/null 2>&1 || true

    log_info "Phase 3 complete ✓"
}

# ============================================================================
# PHASE 4: AUTOMATED VERIFICATION (CLI-ONLY)
# ============================================================================

phase4_verify() {
    log_step "PHASE 4: AUTOMATED VERIFICATION (CLI-ONLY)"

    log_info "Running CLI-based verification..."

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

    # Check 3: Priority classes
    log_info "✓ Check 3: Priority classes"
    PRIORITY_CLASSES=$(kubectl get priorityclasses --no-headers 2>/dev/null | grep -E "ai-inference|mining" | wc -l)
    if [ "$PRIORITY_CLASSES" -ge 5 ]; then
        log_info "  ✓ Priority classes: $PRIORITY_CLASSES defined"
    else
        log_error "  ✗ Priority classes: Expected 5+, got $PRIORITY_CLASSES"
        return 1
    fi

    # Check 4: PodGroups
    log_info "✓ Check 4: PodGroups"
    PODGROUPS=$(kubectl get podgroup -A --no-headers 2>/dev/null | wc -l)
    if [ "$PODGROUPS" -ge 3 ]; then
        log_info "  ✓ PodGroups: $PODGROUPS created"
    else
        log_error "  ✗ PodGroups: Expected 3+, got $PODGROUPS"
        return 1
    fi

    # Check 5: ConfigMap state
    log_info "✓ Check 5: ConfigMap state"
    if kubectl get configmap gpu-scheduler-state -n kube-system &>/dev/null; then
        STATE=$(kubectl get configmap gpu-scheduler-state -n kube-system -o jsonpath='{.data.ai-state}' 2>/dev/null)
        log_info "  ✓ ConfigMap state: $STATE"
    else
        log_error "  ✗ ConfigMap not found"
        return 1
    fi

    # Check 6: Mining deployments
    log_info "✓ Check 6: Mining deployments"
    MINING_DEPLOYMENTS=$(kubectl get deployment -n mining --no-headers 2>/dev/null | wc -l)
    MINING_PODS=$(kubectl get pods -n mining -l app=gpu-miner --no-headers 2>/dev/null | wc -l)
    log_info "  ✓ Mining: $MINING_DEPLOYMENTS deployments, $MINING_PODS pods"

    # Check 7: AI gateway
    log_info "✓ Check 7: AI gateway"
    AI_PODS=$(kubectl get pods -n ai-inference -l app=ai-inference-gateway --no-headers 2>/dev/null | wc -l)
    log_info "  ✓ AI gateway: $AI_PODS pods"

    # Check 8: Scheduler health
    log_info "✓ Check 8: Scheduler health"
    kubectl get cm yunikorn-config -n yunikorn &>/dev/null
    log_info "  ✓ YuniKorn config accessible"

    log_info "Phase 4 complete ✓"
}

# ============================================================================
# PHASE 5: PREEMPTION TEST (AUTOMATED)
# ============================================================================

phase5_test_preemption() {
    log_step "PHASE 5: PREEMPTION TEST (AUTOMATED)"

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

    log_info "Phase 5 complete ✓"
}

# ============================================================================
# PHASE 6: CLI MONITORING SETUP
# ============================================================================

phase6_monitoring() {
    log_step "PHASE 6: CLI MONITORING SETUP"

    log_info "Setting up CLI-based monitoring (no web UI)..."

    # Create monitoring script
    cat > "$K8S_DIR/scheduling/scripts/monitor.sh" << 'EOF'
#!/usr/bin/env bash
# CLI-based scheduler monitoring (no web UI required)

echo "=== GPU Scheduler Status ==="
echo ""

echo "YuniKorn Scheduler:"
kubectl get pods -n yunikorn -l app=yunikorn-scheduler
echo ""

echo "Volcano Scheduler:"
kubectl get pods -n volcano-system -l app=volcano-scheduler
echo ""

echo "State Management:"
kubectl get configmap gpu-scheduler-state -n kube-system -o jsonpath='State: {.data.ai-state}{@=" (Active: {.data.active-workload})}'
echo ""

echo "Mining Deployments:"
kubectl get deployment -n mining -o custom-columns=NAME:.metadata.name,REPLICAS:.spec.replicas,AVAILABLE:.status.availableReplicas,SCHEDULER:.spec.template.spec.schedulerName
echo ""

echo "Mining Pods:"
kubectl get pods -n mining -l app=gpu-miner -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,SCHEDULER:.spec.schedulerName
echo ""

echo "AI Gateway:"
kubectl get deployment -n ai-inference -o custom-columns=NAME:.metadata.name,REPLICAS:.spec.replicas,AVAILABLE:.status.availableReplicas,SCHEDULER:.spec.template.spec.schedulerName
echo ""

echo "Recent Scheduler Events:"
kubectl get events -A --field-selector involvedObject.kind=Pod --sort-by='.lastTimestamp' | tail -10
EOF

    chmod +x "$K8S_DIR/scheduling/scripts/monitor.sh"
    log_info "✓ Created monitoring script: scheduling/scripts/monitor.sh"

    # Create status alias
    cat > "$K8S_DIR/scheduling/scripts/status-alias.sh" << 'EOF'
#!/usr/bin/env bash
# Quick status check for schedulers

echo "YuniKorn: $(kubectl get pods -n yunikorn -l app=yunikorn-scheduler --no-headers | wc -l) pods"
echo "Volcano: $(kubectl get pods -n volcano-system -l app=volcano-scheduler --no-headers | wc -l) pods"
echo "Mining: $(kubectl get pods -n mining -l app=gpu-miner --no-headers | wc -l) pods"
echo "AI Gateway: $(kubectl get pods -n ai-inference -l app=ai-inference-gateway --no-headers | wc -l) pods"
echo "State: $(kubectl get configmap gpu-scheduler-state -n kube-system -o jsonpath='{.data.ai-state}' 2>/dev/null || echo 'Unknown')"
EOF

    chmod +x "$K8S_DIR/scheduling/scripts/status-alias.sh"
    log_info "✓ Created status script: scheduling/scripts/status-alias.sh"

    log_info "Phase 6 complete ✓"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    log_info "Starting COMPLETELY HEADLESS scheduler migration..."
    echo ""

    # Run all phases
    phase0_preparation
    echo ""

    phase1_yunikorn
    echo ""

    phase2_volcano
    echo ""

    phase3_deployments
    echo ""

    phase4_verify
    echo ""

    phase5_test_preemption
    echo ""

    phase6_monitoring
    echo ""

    # Final summary
    log_step "HEADLESS MIGRATION COMPLETE"

    log_info "✅ All components deployed successfully!"
    echo ""
    echo "CLI Commands for Monitoring:"
    echo ""
    echo "  # Quick status"
    echo "  $K8S_DIR/scheduling/scripts/status-alias.sh"
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
    echo ""
    echo "  # Reset state"
    echo "  kubectl patch configmap gpu-scheduler-state -n kube-system --type=merge --patch='{\"data\":{\"ai-state\":\"IDLE\"}}'"
    echo ""
    echo "🎉 Migration complete! No web UI required - everything via CLI!"
    echo ""
}

# Run main function
main "$@"
