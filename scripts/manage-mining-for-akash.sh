#!/usr/bin/env bash
#
# manage-mining-for-akash.sh
#
# Purpose: Stop/start mining deployments to show full GPU capacity to Akash provider
#
# Usage:
#   ./manage-mining-for-akash.sh stop    # Stop mining, show all GPUs as available
#   ./manage-mining-for-akash.sh start   # Resume mining
#   ./manage-mining-for-akash.sh status  # Show current status
#

MINING_DEPLOYMENTS=(
  "gpu-miner-zephyr"
  "gpu-miner-nexus"
  "gpu-miner-forge-nvidia-0"
  "gpu-miner-forge-nvidia-1"
  "xmrig-nexus"
  "xmrig-zephyr"
)

NAMESPACE="mining"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
  echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

check_status() {
  log_info "Checking mining deployment status..."
  echo ""

  local running_count=0
  local stopped_count=0

  for deployment in "${MINING_DEPLOYMENTS[@]}"; do
    # Get deployment spec and status
    local replicas_json
    local status_json

    replicas_json=$(kubectl get deployment -n "$NAMESPACE" "$deployment" -o json 2>/dev/null || echo "{}")
    status_json=$(kubectl get deployment -n "$NAMESPACE" "$deployment" -o jsonpath='{.status}' 2>/dev/null || echo "{}")

    local replicas
    local ready
    replicas=$(echo "$replicas_json" | grep -o '"replicas":[0-9]*' | cut -d: -f2 || echo "0")
    ready=$(echo "$status_json" | grep -o '"readyReplicas":[0-9]*' | cut -d: -f2 || echo "0")

    if [[ "$replicas" == "0" ]]; then
      echo -e "  ${YELLOW}[STOPPED]${NC} $deployment (0 replicas)"
      ((stopped_count++)) || true
    elif [[ "$ready" == "$replicas" ]]; then
      echo -e "  ${GREEN}[RUNNING]${NC} $deployment ($ready/$replicas ready)"
      ((running_count++)) || true
    else
      echo -e "  ${YELLOW}[STARTING]${NC} $deployment ($ready/$replicas ready)"
      ((running_count++)) || true
    fi
  done

  echo ""
  log_info "Summary: $running_count running, $stopped_count stopped"

  # Check provider GPU availability
  echo ""
  log_info "Checking Akash provider GPU availability..."

  # Try to get GPU availability from logs
  local gpu_info
  gpu_info=$(kubectl logs -n akash-services akash-provider-akash-provider-fixed-0 --tail=5 2>/dev/null | grep -o '"total_available":{[^}]*}' | tail -1)

  if [[ -n "$gpu_info" ]]; then
    local available_gpus
    available_gpus=$(echo "$gpu_info" | grep -o '"gpu":[0-9]*' | cut -d: -f2)
    echo "  GPUs available to Akash: ${available_gpus:-unknown}"
  else
    echo "  Unable to fetch GPU availability (provider logs unavailable)"
  fi

  return 0
}

stop_mining() {
  log_warn "Stopping all mining deployments..."
  echo ""

  for deployment in "${MINING_DEPLOYMENTS[@]}"; do
    log_info "Stopping $deployment..."
    kubectl scale deployment -n "$NAMESPACE" "$deployment" --replicas=0 2>/dev/null || true
  done

  echo ""
  log_info "Waiting for pods to terminate..."
  sleep 5

  echo ""
  log_info "✅ All mining deployments stopped"
  log_info "🎯 All GPUs should now show as available to Akash provider"
  echo ""
  log_info "Waiting 10 seconds for provider to refresh inventory..."
  sleep 10

  check_status
}

start_mining() {
  log_info "Starting all mining deployments..."
  echo ""

  for deployment in "${MINING_DEPLOYMENTS[@]}"; do
    log_info "Starting $deployment..."
    kubectl scale deployment -n "$NAMESPACE" "$deployment" --replicas=1 2>/dev/null || true
  done

  echo ""
  log_info "Waiting for pods to be ready..."
  sleep 10

  # Check status
  local all_ready=true
  for deployment in "${MINING_DEPLOYMENTS[@]}"; do
    local status_json
    status_json=$(kubectl get deployment -n "$NAMESPACE" "$deployment" -o jsonpath='{.status}' 2>/dev/null || echo "{}")
    local ready
    ready=$(echo "$status_json" | grep -o '"readyReplicas":[0-9]*' | cut -d: -f2 || echo "0")

    if [[ "$ready" == "0" ]]; then
      all_ready=false
      break
    fi
  done

  if [[ "$all_ready" == "true" ]]; then
    echo ""
    log_info "✅ All mining deployments started"
    log_info "⛏️  Mining operations resumed"
  else
    echo ""
    log_warn "⏳ Mining deployments are starting (pods may still be initializing)"
    log_info "Run './manage-mining-for-akash.sh status' to check progress"
  fi

  echo ""
  check_status
}

show_usage() {
  cat <<EOF
Usage: $0 <command>

Commands:
  start    Start all mining deployments (resume mining)
  stop     Stop all mining deployments (show full GPU capacity to Akash)
  status   Show current status of mining deployments and GPU availability

Examples:
  $0 stop     # Stop mining to show all GPUs as available
  $0 start    # Resume mining operations
  $0 status   # Check current status

Note: When mining is stopped, all 5 NVIDIA GPUs will show as available to the
      Akash provider. When you start mining again, GPUs will be allocated back
      to mining workloads.

The provider uses Kubernetes preemption, so even when mining is running, Akash
leases can preempt mining pods automatically. However, the provider's inventory
doesn't account for preemption, so stopping mining makes all GPUs visible to
potential bidders.
EOF
}

main() {
  local command="${1:-}"

  case "$command" in
    stop)
      stop_mining
      ;;
    start)
      start_mining
      ;;
    status)
      check_status
      ;;
    help|--help|-h)
      show_usage
      ;;
    *)
      log_error "Unknown command: $command"
      echo ""
      show_usage
      exit 1
      ;;
  esac
}

main "$@"
