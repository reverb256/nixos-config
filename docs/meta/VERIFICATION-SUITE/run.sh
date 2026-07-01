#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo '/etc/nixos')"
cd "$REPO_ROOT"

echo "=== NixOS Documentation Verification Suite ==="
echo "Repository root: $REPO_ROOT"
echo "Last run: $(date -u +%Y-%m-%d)"
echo

echo "→ Staleness check..."
docs/meta/VERIFICATION-SUITE/verify-staleness.sh

echo "→ Infrastructure claims check..."
docs/meta/VERIFICATION-SUITE/verify-infra.sh

echo "→ Cross-reference check..."
docs/meta/VERIFICATION-SUITE/cross-reference-check.sh

echo
echo "All checks passed."
echo "Documentation is healthy."
exit 0
  else
    echo "❌ MISSING"
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
else
  echo "Documentation rot detected. Fix before merging."
  exit 1
fi
