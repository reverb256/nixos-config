#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT"

printf '%s\n' '=== NixOS Documentation Verification Suite ==='
printf 'Repository root: %s\n' "$REPO_ROOT"
printf 'Run date: %s\n\n' "$(date -u +%Y-%m-%d)"

checks=(
  "Active metadata|docs/meta/VERIFICATION-SUITE/verify-staleness.sh"
  "Source-of-truth declarations|docs/meta/VERIFICATION-SUITE/verify-infra.sh"
  "Internal links and retired authority|docs/meta/VERIFICATION-SUITE/cross-reference-check.sh"
)

failed=0
for entry in "${checks[@]}"; do
  name=${entry%%|*}
  script=${entry#*|}
  printf '→ %s...\n' "$name"
  if "$script"; then
    printf '  PASS: %s\n\n' "$name"
  else
    printf '  FAIL: %s\n\n' "$name" >&2
    failed=$((failed + 1))
  fi
done

if [ "$failed" -eq 0 ]; then
  echo 'All documentation checks passed.'
else
  printf '%s documentation check(s) failed.\n' "$failed" >&2
  exit 1
fi
