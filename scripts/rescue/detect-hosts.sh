#!/usr/bin/env bash
# detect-hosts.sh - Scan network for cluster hosts
# Usage: detect-hosts.sh

set -e

echo "=== Scanning cluster network ==="
echo ""

# Known cluster hosts
declare -A HOSTS=(
  ["zephyr"]="10.1.1.110"
  ["nexus"]="10.1.1.120"
  ["forge"]="10.1.1.130"
  ["sentry"]="10.1.1.140"
)

# Check each host
UP_HOSTS=()
DOWN_HOSTS=()

for host in "${!HOSTS[@]}"; do
  ip="${HOSTS[$host]}"
  if ping -c 1 -W 2 "$ip" &>/dev/null; then
    echo "✓ $name ($ip) is UP"
    UP_HOSTS+=("$host:$ip")
  else
    echo "✗ $host ($ip) is DOWN"
    DOWN_HOSTS+=("$host:$ip")
  fi
done

echo ""
echo "=== Summary ==="
echo "UP: ${#UP_HOSTS[@]} hosts"
echo "DOWN: ${#DOWN_HOSTS[@]} hosts"

if [ ${#UP_HOSTS[@]} -gt 0 ]; then
  echo ""
  echo "Available hosts:"
  for entry in "${UP_HOSTS[@]}"; do
    echo "  - $entry"
  done
fi

# Export available hosts for other scripts
if [ ${#UP_HOSTS[@]} -gt 0 ]; then
  export RESCUE_AVAILABLE_HOSTS="${UP_HOSTS[*]}"
fi
