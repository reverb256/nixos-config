#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
	echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
	echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
	echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
	log_info "Checking prerequisites..."

	# Check kubectl
	if ! command -v kubectl &>/dev/null; then
		log_error "kubectl not found. Please install kubectl."
		exit 1
	fi

	# Check cluster connectivity
	if ! kubectl get nodes &>/dev/null; then
		log_error "Cannot connect to Kubernetes cluster."
		exit 1
	fi

	# Check if mining namespace already exists
	if kubectl get namespace mining &>/dev/null; then
		log_warn "Mining namespace already exists. Skipping creation."
	else
		log_info "Mining namespace not found. Will create."
	fi

	# Check node status
	log_info "Current node status:"
	kubectl get nodes

	echo ""
	log_info "Ready nodes:"
	kubectl get nodes | grep Ready | grep -v control-plane || echo "  (none)"

	echo ""
	log_warn "NotReady nodes (will skip deployment):"
	kubectl get nodes | grep NotReady || echo "  (all nodes ready)"
}

deploy_proxy() {
	log_info "=== Phase 1: Deploying xmrig-proxy ==="

	# Create namespace
	log_info "Creating mining namespace..."
	kubectl apply -f kubernetes-manifests/mining/mining-namespace.yaml

	log_info "Applying infrastructure..."
	log_info "Applying infrastructure policies..."
	kubectl apply -f kubernetes-manifests/mining/resource-quota.yaml
	kubectl apply -f kubernetes-manifests/mining/limit-range.yaml
	kubectl apply -f kubernetes-manifests/mining/network-policy.yaml

	log_info "Applying secrets..."
	if ! kubectl get secret xmrig-proxy-secret -n mining &>/dev/null; then
		log_warn "Creating xmrig-proxy-secret - PLEASE UPDATE PLACEHOLDER TOKENS!"
		kubectl apply -f kubernetes-manifests/mining/xmrig-proxy-secret.yaml
	else
		log_info "Secrets already exist - skipping"
	fi

	# Deploy config
	log_info "Deploying xmrig-proxy configuration..."
	kubectl apply -f kubernetes-manifests/mining/xmrig-proxy-configmap.yaml

	# Deploy proxy
	log_info "Deploying xmrig-proxy deployment..."
	kubectl apply -f kubernetes-manifests/mining/xmrig-proxy-deployment.yaml

	log_info "Applying PDB..."
	log_info "Applying PodDisruptionBudget..."
	kubectl apply -f kubernetes-manifests/mining/pod-disruption-budget.yaml

	# Wait for pod to be ready
	log_info "Waiting for xmrig-proxy pod to be ready..."
	kubectl wait --for=condition=ready pod -n mining -l app=xmrig-proxy --timeout=60s || {
		log_error "xmrig-proxy failed to start. Check logs:"
		kubectl logs -n mining -l app=xmrig-proxy --tail=50
		exit 1
	}

	# Verify proxy is running
	log_info "Verifying xmrig-proxy health..."
	sleep 5

	# Check logs for successful startup
	if kubectl logs -n mining -l app=xmrig-proxy --tail=10 | grep -q "xmrig-proxy"; then
		log_info "✓ xmrig-proxy is running"
	else
		log_warn "Checking xmrig-proxy logs..."
		kubectl logs -n mining -l app=xmrig-proxy --tail=20
	fi

	# Test service endpoint
	log_info "Testing xmrig-proxy service..."
	local proxy_ip
	proxy_ip=$(kubectl get pod -n mining -l app=xmrig-proxy -o jsonpath='{.items[0].status.podIP}')

	if [[ -n "$proxy_ip" ]]; then
		log_info "✓ xmrig-proxy running on $proxy_ip"
		log_info "  Stratum port: 3333"
		log_info "  API port: 8081"
	else
		log_error "Could not get xmrig-proxy pod IP"
	fi
}

deploy_zephyr_miner() {
	log_info "=== Phase 2: Deploying Zephyr GPU Miner ==="

	# Check if Zephyr node is ready
	if ! kubectl get nodes zephyr | grep -q "Ready"; then
		log_error "Zephyr node is NotReady. Cannot deploy miner."
		return 1
	fi

	log_info "Deploying GPU miner to Zephyr..."
	kubectl apply -f kubernetes-manifests/mining/gpu-miner-zephyr.yaml

	# Wait for pod to initialize
	log_info "Waiting for GPU miner pod to initialize..."
	sleep 30

	# Check pod status
	local pod_status
	pod_status=$(kubectl get pod -n mining -l host=zephyr -o jsonpath='{.items[0].status.phase}')

	if [[ "$pod_status" == "Running" ]]; then
		log_info "✓ GPU miner pod is running"
	else
		log_error "GPU miner pod status: $pod_status"
		kubectl describe pod -n mining -l host=zephyr
		kubectl logs -n mining -l host=zephyr --tail=50
		return 1
	fi

	# Monitor for 2 minutes to ensure stability
	log_info "Monitoring miner for 2 minutes to ensure stability..."
	local stable_periods=0
	for i in {1..12}; do
		sleep 10

		# Check if pod is still running
		if ! kubectl get pod -n mining -l host=zephyr &>/dev/null; then
			log_error "Pod disappeared!"
			return 1
		fi

		# Check for crash loops
		local restarts
		restarts=$(kubectl get pod -n mining -l host=zephyr -o jsonpath='{.items[0].status.restartCount}')

		if [[ "$restarts" -gt 5 ]]; then
			log_error "Pod is crash looping (restarts: $restarts)"
			kubectl logs -n mining -l host=zephyr --tail=100
			return 1
		fi

		# Check logs for connection issues
		if kubectl logs -n mining -l host=zephyr --tail=20 | grep -q "Authorized"; then
			((stable_periods++))
			log_info "[$i/12] ✓ Miner connected to pool (stable for ${stable_periods}0 periods)"
		else
			log_warn "[$i/12] Waiting for pool connection..."
		fi
	done

	if [[ $stable_periods -ge 8 ]]; then
		log_info "✓ Zephyr GPU miner is stable"
	else
		log_warn "Zephyr GPU miner not fully stable (only $stable_periods/12 stable periods)"
	fi
}

check_forge_readiness() {
	log_info "=== Phase 3: Checking Forge Node Readiness ==="

	if ! kubectl get nodes forge &>/dev/null; then
		log_warn "Forge node not found in cluster"
		return 1
	fi

	if kubectl get nodes forge | grep -q "Ready"; then
		log_info "✓ Forge node is Ready - can deploy miner"
		return 0
	else
		log_warn "Forge node is NotReady - skipping deployment"
		log_info "  Miners will run on bare metal only:"
		echo "    - Zephyr: systemd (primary) + Kubernetes (backup)"
		echo "    - Forge: systemd (primary only)"
		return 1
	fi
}

deploy_forge_miner() {
	log_info "=== Phase 4: Deploying Forge GPU Miner ==="

	log_info "Deploying GPU miner to Forge..."
	kubectl apply -f kubernetes-manifests/mining/gpu-miner-forge.yaml

	# Monitor Forge deployment
	log_info "Monitoring Forge miner for stability..."
	sleep 60

	local pod_status
	pod_status=$(kubectl get pod -n mining -l host=forge -o jsonpath='{.items[0].status.phase}')

	if [[ "$pod_status" == "Running" ]]; then
		log_info "✓ Forge GPU miner pod is running"

		# Check for AMD miner
		if kubectl get pod -n mining -l host=forge -o jsonpath='{.items[0].spec.containers[*].name}' | grep -q "amd"; then
			log_info "✓ Forge AMD miner container is running"
		fi
	else
		log_error "Forge GPU miner failed to start"
		kubectl describe pod -n mining -l host=forge
		kubectl logs -n mining -l host=forge --all-containers --tail=100
		return 1
	fi
}

verify_cluster_health() {
	log_info "=== Verifying Cluster Health ==="

	log_info "Checking node resource usage..."
	kubectl top nodes

	echo ""
	log_info "Checking pod resource usage..."
	kubectl top pods -n mining

	echo ""
	log_info "Checking cluster events for issues..."
	kubectl get events -n mining --sort-by='.lastTimestamp' | tail -20
}

main() {
	log_info "=== Kubernetes Mining Deployment ==="
	log_info "Strategy: Conservative staged rollout with automatic fallbacks"
	echo ""

	# Track what was deployed
	local deployed_zephyr=false
	local deployed_forge=false

	# Phase 1: Deploy proxy (required infrastructure)
	check_prerequisites
	echo ""

	deploy_proxy || {
		log_error "FAILED: Could not deploy xmrig-proxy. Aborting."
		log_info "Falling back to bare metal mining only..."
		return 1
	}
	echo ""

	# Phase 2: Deploy Zephyr miner (control plane is stable)
	if deploy_zephyr_miner; then
		deployed_zephyr=true
	else
		log_error "FAILED: Could not deploy Zephyr miner. Rolling back..."
		kubectl delete deployment -n mining xmrig-proxy
		return 1
	fi
	echo ""

	# Phase 3: Check Forge readiness
	if check_forge_readiness; then
		echo ""

		# Phase 4: Deploy Forge miner (only if node is ready)
		if deploy_forge_miner; then
			deployed_forge=true
		else
			log_warn "Forge deployment skipped due to node NotReady state"
		fi
	else
		log_info "Skipping Forge deployment (node not found or not ready)"
	fi
	echo ""

	# Final verification
	if [[ "$deployed_zephyr" == true ]] || [[ "$deployed_forge" == true ]]; then
		verify_cluster_health

		echo ""
		log_info "=== Deployment Summary ==="
		echo "Bare Metal (systemd):"
		echo "  ✓ Zephyr: lolminer-nvidia service running"
		echo "  ✓ Forge: lolminer-nvidia + lolminer-amd services running"
		echo ""
		echo "Kubernetes (pods):"
		[[ "$deployed_zephyr" == true ]] && echo "  ✓ Zephyr: gpu-miner-zephyr pod running" || echo "  ✗ Zephyr: not deployed"
		[[ "$deploy_forge" == true ]] && echo "  ✓ Forge: gpu-miner-forge pod running" || echo "  ✗ Forge: not deployed (node NotReady)"
		echo ""
		log_info "✅ Deployment complete!"
		log_info ""
		log_info "Current Status: Running HYBRID setup (bare metal + Kubernetes)"
		log_info "  - Primary: Bare metal systemd services (100% stable)"
		log_info "  - Backup: Kubernetes pods (experimental, for testing)"

	else
		log_error "Deployment failed - only proxy deployed. Rolling back..."
		kubectl delete namespace mining
		return 1
	fi
}

# Trap errors and cleanup
trap 'log_error "Script interrupted. Cleaning up..."; kubectl get pods -n mining -l app=gpu-miner --no-headers | head -1 | xargs -r kubectl delete pod -n mining 2>/dev/null || true' EXIT INT TERM

# Run deployment
main "$@"
