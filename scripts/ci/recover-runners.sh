#!/usr/bin/env bash
# recover-runners.sh — diagnose and recover self-hosted GitHub Actions runners.
#
# Symptom: nixos-config CI queues forever ("pending") while GitHub shows
# nexus-runner / sentry-runner OFFLINE. Root causes seen in the field:
#   1. GitHub auto-deletes runner registrations that haven't connected
#      recently ("The runner registration has been deleted from the server,
#      please re-configure"). The run service exits CLEANLY (no crash), so
#      Restart= never fires and CI dies silently.
#   2. Stale systemd unit symlinks after a switch (unit shows "not-found"),
#      so the run service never starts.
#   3. Setup oneshot failed at boot because the PAT file (secretspec creds)
#      had not mounted yet; a failed oneshot does not re-run when the secret
#      later appears.
#
# The NixOS config (modules/services/ci-runners.nix) already ships self-heal
# units: daily re-registration timer + PAT-rotation path unit, both calling
# `config.sh --replace` idempotently. This script just drives those units and
# verifies the result — it is the manual "kick it now" equivalent.
#
# Usage:
#   ./scripts/ci/recover-runners.sh                 # all hosts, all repos
#   ./scripts/ci/recover-runners.sh nexus           # one host
#   ./scripts/ci/recover-runners.sh nexus sentry    # a subset
#
# Safe: only reads + restarts the runner systemd units it can identify; never
# rebuilds, never deploys, never touches nixos-rebuild.

set -uo pipefail

# Hosts that run self-hosted runners (inventory: contracts/host-inventory.nix).
HOSTS=(nexus sentry)

REPO="${REPO:-reverb256/nixos-config}"

# --- GitHub API helpers ------------------------------------------------------

gh_runner_status() {
  # Returns "name status" lines for runners registered to REPO.
  gh api "repos/${REPO}/actions/runners" \
    --jq '.runners[] | "\(.name)\t\(.status)"' 2>/dev/null || true
}

runner_online() {
  gh api "repos/${REPO}/actions/runners" \
    --jq "[.runners[] | select(.name == \"$1\" and .status == \"online\")] | length" 2>/dev/null
}

# --- Per-host recovery --------------------------------------------------------

recover_host() {
  local host="$1"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Host: $host"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  if ! ssh -o ConnectTimeout=5 "$host" true 2>/dev/null; then
    echo "!! Cannot reach $host — skipping"
    return
  fi

  echo "── systemd state of runner units ──"
  ssh "$host" "systemctl list-units --all | grep -iE 'runner' | head -20" 2>/dev/null || true

  echo "── setup/run/reregister services for this host's runners ──"
  # Re-run every setup + re-register service (idempotent config.sh --replace),
  # then restart every run service. This heals all three root causes:
  # registration deleted (re-register), stale unit (daemon-reload + start),
  # failed setup at boot (PAT now mounted → retry succeeds).
  ssh "$host" "systemctl daemon-reload 2>/dev/null || true; \
    for s in \$(systemctl list-unit-files --type=service --no-legend | awk '{print \$1}' | grep -E 'github-actions-runner-(setup|reregister)-'); do \
      echo \"== restarting \$s\"; systemctl restart \"\$s\" || echo \"   !! failed: \$s\"; \
    done; \
    for s in \$(systemctl list-unit-files --type=service --no-legend | awk '{print \$1}' | grep -E 'github-actions-runner-.*\.service' | grep -vE 'setup|reregister'); do \
      echo \"== restarting \$s\"; systemctl restart \"\$s\" || echo \"   !! failed: \$s\"; \
    done" 2>&1

  echo "── post-recovery unit state ──"
  ssh "$host" "systemctl list-units --all | grep -iE 'runner' | head -20" 2>/dev/null || true
}

# --- Main ----------------------------------------------------------------------

if [ $# -gt 0 ]; then
  HOSTS=("$@")
fi

echo "=== Pre-recovery GitHub runner status for ${REPO} ==="
gh_runner_status | while IFS=$'\t' read -r name status; do
  [ -n "$name" ] && echo "  $name: $status"
done
echo

for host in "${HOSTS[@]}"; do
  recover_host "$host"
done

echo
echo "=== Post-recovery GitHub runner status for ${REPO} ==="
gh_runner_status | while IFS=$'\t' read -r name status; do
  [ -n "$name" ] && echo "  $name: $status"
done

echo
echo "=== Verifying each runner comes online (up to 90s) ==="
for host in "${HOSTS[@]}"; do
  # Map host → registered runner name: nexus → nexus-runner, sentry → sentry-runner
  local_name="${host}-runner"
  for i in $(seq 1 18); do
    if [ "$(runner_online "$local_name")" = "1" ]; then
      echo "  ✓ $local_name is ONLINE"
      break
    fi
    [ "$i" = 18 ] && echo "  ✗ $local_name still not online after 90s (check journalctl -u github-actions-runner-nixos-config on $host)"
    sleep 5
  done
done
