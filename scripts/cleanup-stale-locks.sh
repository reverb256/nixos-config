#!/usr/bin/env bash
# Cleanup stale colmena and nix-build locks
# Run automatically before deployments to prevent stuck locks

set -euo pipefail

LOCK_DIR="/tmp"
MAX_AGE_MINUTES=30

echo "=== Lock Cleanup ===" >&2
echo "Checking for locks older than ${MAX_AGE_MINUTES} minutes..." >&2

# Kill stale colmena processes (running > 2 hours)
echo "Checking for stale colmena processes..." >&2
stale_colmena=$(ps aux | grep -E '[c]olmena.*apply' | awk '{if ($10 ~ /old/ || $9 ~ /[0-9]+:[0-9]+/) print $2}' || true)
if [[ -n "$stale_colmena" ]]; then
  echo "Killing stale colmena processes: $stale_colmena" >&2
  echo "$stale_colmena" | xargs -r kill -9
else
  echo "No stale colmena processes found" >&2
fi

# Remove stale colmena lock
if [[ -f "${LOCK_DIR}/colmena-deploy.lock" ]]; then
  lock_age=$(($(date +%s) - $(stat -c %Y "${LOCK_DIR}/colmena-deploy.lock")))
  lock_age_minutes=$((lock_age / 60))

  if [[ $lock_age_minutes -gt $MAX_AGE_MINUTES ]]; then
    echo "Removing stale colmena lock (${lock_age_minutes} minutes old)" >&2
    rm -f "${LOCK_DIR}/colmena-deploy.lock"
  else
    echo "Colmena lock is recent (${lock_age_minutes} minutes old), keeping" >&2
  fi
fi

# Clean up old colmena asset directories (> 7 days)
echo "Cleaning up old colmena asset directories..." >&2
find "${LOCK_DIR}" -type d -name "colmena-assets-*" -mtime +7 -exec rm -rf {} + 2>/dev/null || true

# Check for nix-build locks
echo "Checking for nix-build locks..." >&2
find /tmp -name "nix-build-*" -type f -mtime +1 -delete 2>/dev/null || true

echo "=== Lock Cleanup Complete ===" >&2
