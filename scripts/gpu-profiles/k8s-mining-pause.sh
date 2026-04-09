#!/usr/bin/env bash
# Kubernetes Mining Pause for GameMode
# Pauses ALL mining pods on the local host when GameMode activates (gaming starts)
# Resumes them when GameMode deactivates (gaming ends)
#
# Saves pre-pause replica counts so we restore exact state (e.g. if
# gpu-miner-zephyr was already at 0, we don't accidentally scale it to 1).

set -euo pipefail

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
NAMESPACE="mining"
HOSTNAME="$(hostname)"
STATE_FILE="/var/cache/gamemode-mining-state.json"
LOG_FILE="/var/log/gamemode-mining.log"

mkdir -p "$(dirname "$LOG_FILE")" "$(dirname "$STATE_FILE")" 2>/dev/null || true

log() {
	echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >>"$LOG_FILE"
}

# List all mining deployments targeted at this host
get_local_deployments() {
	kubectl get deploy -n "$NAMESPACE" -o json 2>/dev/null |
		jq -r '.items[] | select(.spec.template.spec.nodeName == "'"$HOSTNAME"'") | .metadata.name'
}

# Save current replica counts to a simple JSON file
save_state() {
	# Use kubectl jsonpath to avoid jq pipe issues with while/read subshells
	local tmp="${STATE_FILE}.tmp"
	echo "{" >"$tmp"
	local first=true
	while read -r name; do
		[ -z "$name" ] && continue
		local replicas
		replicas=$(kubectl get deploy "$name" -n "$NAMESPACE" \
			-o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
		$first || echo "," >>"$tmp"
		printf '  "%s": %s' "$name" "$replicas" >>"$tmp"
		first=false
	done < <(get_local_deployments)
	echo "" >>"$tmp"
	echo "}" >>"$tmp"
	mv "$tmp" "$STATE_FILE"
	log "Saved mining state: $(cat "$STATE_FILE")"
}

pause_mining() {
	log "=== GameMode START: Pausing all mining on $HOSTNAME ==="

	if ! command -v kubectl &>/dev/null; then
		log "kubectl not found — skipping K8s pause"
		return 0
	fi

	# Save current state BEFORE pausing so we can restore exactly
	save_state

	# Scale every local deployment to 0
	while read -r name; do
		[ -z "$name" ] && continue
		if kubectl scale deploy "$name" -n "$NAMESPACE" --replicas=0 >/dev/null 2>&1; then
			log "✓ Scaled $name → 0"
		else
			log "✗ Failed to scale $name → 0"
		fi
	done < <(get_local_deployments)

	# Also stop any host-systemd mining services (legacy fallback)
	for svc in lolminer-nvidia xmrig xmrig-flexible; do
		if systemctl is-active --quiet "$svc" 2>/dev/null; then
			log "Stopping host service: $svc"
			systemctl stop "$svc" 2>/dev/null && log "✓ Stopped $svc" || log "✗ Failed to stop $svc"
		fi
	done

	log "=== All mining paused ==="
}

resume_mining() {
	log "=== GameMode END: Resuming mining on $HOSTNAME ==="

	if ! command -v kubectl &>/dev/null; then
		log "kubectl not found — skipping K8s resume"
		return 0
	fi

	# Restore from saved state
	if [ -f "$STATE_FILE" ]; then
		log "Restoring from saved state: $(cat "$STATE_FILE")"
		local names
		names=$(jq -r 'keys[]' "$STATE_FILE")
		for name in $names; do
			local target
			target=$(jq -r '."'"$name"'"' "$STATE_FILE")
			if [ "$target" != "null" ] && [ "$target" -gt 0 ] 2>/dev/null; then
				if kubectl scale deploy "$name" -n "$NAMESPACE" --replicas="$target" >/dev/null 2>&1; then
					log "✓ Scaled $name → $target"
				else
					log "✗ Failed to scale $name → $target"
				fi
			else
				log "  $name: was at 0 before pause — skipping"
			fi
		done
		rm -f "$STATE_FILE"
	else
		log "No state file found — resuming all local deployments to 1"
		while read -r name; do
			[ -z "$name" ] && continue
			if kubectl scale deploy "$name" -n "$NAMESPACE" --replicas=1 >/dev/null 2>&1; then
				log "✓ Scaled $name → 1"
			fi
		done < <(get_local_deployments)
	fi

	log "=== Mining resumed ==="
}

ACTION="${1:-}"
case "$ACTION" in
start) pause_mining ;;
end) resume_mining ;;
*)
	echo "Usage: $0 {start|end}"
	exit 1
	;;
esac
