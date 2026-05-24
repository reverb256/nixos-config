#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
cd "$REPO_ROOT"

echo "=== NixOS Documentation Verification Suite ==="
echo "Last run: $(date -u +%Y-%m-%d)"
echo

PASSED=0
FAILED=0

check() {
  local name=$1
  local script=$2
  echo -n "→ $name... "
  if "$REPO_ROOT/$script" > /tmp/verify.log 2>&1; then
    echo "✅ PASS"
    ((PASSED++))
  else
    echo "❌ FAIL"
    cat /tmp/verify.log
    ((FAILED++))
  fi
}

check "Staleness" "docs/meta/VERIFICATION-SUITE/verify-staleness.sh"
check "Infrastructure Claims" "docs/meta/VERIFICATION-SUITE/verify-infra.sh"
check "Cross References" "docs/meta/VERIFICATION-SUITE/cross-reference-check.sh"

echo
echo "Summary: $PASSED passed, $FAILED failed"
if [ $FAILED -eq 0 ]; then
  echo "Documentation is healthy."
  exit 0
else
  echo "Documentation rot detected. Fix before merging."
  exit 1
fi
