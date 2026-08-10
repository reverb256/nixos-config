#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT"

required_paths=(
  contracts/host-inventory.nix
  kubernetes/cluster.nix
  modules/system/distributed-builds.nix
  secretspec.toml
  docs/current-state.md
  STATUS.md
  docs/archive/ARCHIVE_INDEX.md
  docs/archive/legacy/ARCHIVE/INDEX.md
  docs/archive/legacy/live-snapshots/INDEX.md
  docs/archive/legacy/live-snapshots/ARCHITECTURE.md
  docs/archive/legacy/live-snapshots/INFRASTRUCTURE-AUDIT.md
  docs/archive/legacy/live-snapshots/STATUS.md
  docs/archive/legacy/live-snapshots/RUNBOOK.md
  docs/archive/legacy/LEGACY-CONTENTS.md
  docs/archive/legacy/LEGACY-LINK-AUDIT.md
  docs/archive/legacy/CONTENTS.txt
  docs/meta/VERIFICATION-SUITE/ACTIVE-DOCUMENTS.txt
)
failed=0
for path in "${required_paths[@]}"; do
  if [ -e "$path" ]; then
    printf '  OK: %s\n' "$path"
  else
    printf 'MISSING: %s\n' "$path" >&2
    failed=$((failed + 1))
  fi
done

if ! grep -q 'Source-of-truth snapshot' scripts/update-status.sh; then
  echo 'FAIL: STATUS generator does not declare snapshot provenance' >&2
  failed=$((failed + 1))
else
  echo '  OK: STATUS generator declares static/dynamic provenance'
fi

if ! grep -q 'nixos-status-update.lock' scripts/update-status.sh \
  || ! grep -q 'timeout 20 kubectl get nodes' scripts/update-status.sh \
  || ! grep -q 'timeout 30 kubectl' scripts/update-status.sh \
  || ! grep -q 'for cmd in nix jq kubectl flock timeout' scripts/update-status.sh; then
  echo 'FAIL: STATUS generator lacks recursion/query-timeout safeguards' >&2
  failed=$((failed + 1))
else
  echo '  OK: STATUS generator recursion/query-timeout safeguards present'
fi

if ! grep -q 'default = "1h"' modules/system/status-auto-update.nix; then
  echo 'FAIL: STATUS timer interval is not a valid systemd duration' >&2
  failed=$((failed + 1))
else
  echo '  OK: STATUS timer uses a valid duration interval'
fi

if ! grep -q 'Nexus is the deployment dispatcher' docs/current-state.md; then
  echo 'FAIL: current-state.md lacks deployment authority boundary' >&2
  failed=$((failed + 1))
else
  echo '  OK: deployment authority boundary documented'
fi

if ! grep -qi 'source of truth' kubernetes-manifests/AGENTS.md; then
  echo 'FAIL: Kubernetes manifest guidance lacks source-of-truth wording' >&2
  failed=$((failed + 1))
else
  echo '  OK: Kubernetes manifest source-of-truth guidance present'
fi

legacy_manifest=docs/archive/legacy/CONTENTS.txt
if [ ! -f "$legacy_manifest" ]; then
  echo 'FAIL: legacy archive contents manifest is missing' >&2
  failed=$((failed + 1))
else
  actual_manifest=$(mktemp)
  trap 'rm -f "$actual_manifest"' EXIT
  find docs/archive/legacy -type f ! -name CONTENTS.txt -printf '%P\n' | sort > "$actual_manifest"
  if diff -u "$legacy_manifest" "$actual_manifest" >/dev/null; then
    printf '  OK: legacy archive exact path manifest (%s files)\n' "$(wc -l < "$actual_manifest")"
  else
    echo 'FAIL: legacy archive contents differ from CONTENTS.txt' >&2
    diff -u "$legacy_manifest" "$actual_manifest" | head -80 >&2 || true
    failed=$((failed + 1))
  fi
fi

if [ "$failed" -gt 0 ]; then
  printf '%s source-of-truth check(s) failed.\n' "$failed" >&2
  exit 1
fi
