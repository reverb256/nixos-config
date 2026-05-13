#!/usr/bin/env bash
# Kubernetes AI Inference Pause for GameMode
set -euo pipefail

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
NAMESPACE="ai-inference"
STATE_FILE="/var/cache/gamemode-ai-state.json"
LOG_FILE="/var/log/gamemode-ai.log"
AI_DEPLOYMENTS=("llama-server-zephyr-3090-moe")

mkdir -p "$(dirname "$LOG_FILE")" "$(dirname "$STATE_FILE")" 2>/dev/null || true
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >>"$LOG_FILE"; }

save_state() {
	local tmp="${STATE_FILE}.tmp"
	echo "{" >"$tmp"
	local first=true
	for dep in "${AI_DEPLOYMENTS[@]}"; do
		local r
		r=$(kubectl get deploy "$dep" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
		$first || echo "," >>"$tmp"
		echo -n "  \"$dep\": $r" >>"$tmp"
		first=false
	done
	echo "" >>"$tmp"; echo "}" >>"$tmp"
	mv "$tmp" "$STATE_FILE"
	log "Saved AI deployment state"
}

restore_state() {
	if [ ! -f "$STATE_FILE" ]; then
		log "No state file, scaling all to 1"
		for dep in "${AI_DEPLOYMENTS[@]}"; do
			kubectl scale deploy "$dep" -n "$NAMESPACE" --replicas=1 2>>"$LOG_FILE" || true
		done
		return
	fi
	log "Restoring AI deployment state"
	for dep in "${AI_DEPLOYMENTS[@]}"; do
		local r
		r=$(jq -r ".[\"$dep\"] // 1" "$STATE_FILE" 2>/dev/null || echo "1")
		kubectl scale deploy "$dep" -n "$NAMESPACE" --replicas="$r" 2>>"$LOG_FILE" || true
	done
	rm -f "$STATE_FILE"
}

pause_ai() {
	log "GameMode STARTED — pausing AI inference"
	save_state
	for dep in "${AI_DEPLOYMENTS[@]}"; do
		kubectl scale deploy "$dep" -n "$NAMESPACE" --replicas=0 2>>"$LOG_FILE" || true
	done
	log "AI inference paused"
}

resume_ai() {
	log "GameMode ENDED — resuming AI inference"
	restore_state
	log "AI inference resumed"
}

case "${1:-}" in
	start) pause_ai ;;
	end) resume_ai ;;
	status)
		echo "AI deployments:"
		for dep in "${AI_DEPLOYMENTS[@]}"; do
			r=$(kubectl get deploy "$dep" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "?")
			echo "  $dep: $r replicas"
		done
		;;
	*) echo "Usage: $0 {start|end|status}"; exit 1 ;;
esac
