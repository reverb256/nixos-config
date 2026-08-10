#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT"

failed=0
python3 - <<'PY'
from pathlib import Path
import re
import sys

# Check Markdown links in the explicit maintained-document manifest plus
# compatibility pointers. Archive material is preserved history and is checked
# separately by Git/link review.
manifest = Path("docs/meta/VERIFICATION-SUITE/ACTIVE-DOCUMENTS.txt")
files = [
    Path(line.strip())
    for line in manifest.read_text().splitlines()
    if line.strip() and not line.lstrip().startswith("#")
]
files += [
    Path("docs/LIVE/INDEX.md"),
    Path("docs/LIVE/INFRASTRUCTURE-AUDIT.md"),
    Path("docs/LIVE/STATUS.md"),
    Path("docs/LIVE/RUNBOOK.md"),
    Path("docs/LIVE/ARCHITECTURE.md"),
]
pattern = re.compile(r"!?\[[^]]*\]\(([^)]+)\)")
bad = []
for source in files:
    if not source.exists():
        bad.append(f"missing source: {source}")
        continue
    for target in pattern.findall(source.read_text()):
        target = target.split("#", 1)[0].strip()
        if not target or "://" in target or target.startswith("mailto:"):
            continue
        target_path = (source.parent / target).resolve()
        if not target_path.exists():
            bad.append(f"{source}: {target}")
if bad:
    print("\n".join(bad), file=sys.stderr)
    raise SystemExit(1)
print("  OK: maintained internal links resolve")
PY

# The old LIVE directory remains only for backwards-compatible pointers.
if grep -RniE 'single source of truth|canonical, always-current|edit files outside LIVE' docs/LIVE --include='*.md' >/dev/null 2>&1; then
  echo 'FAIL: retired LIVE pointers still claim canonical authority' >&2
  failed=$((failed + 1))
else
  echo '  OK: retired LIVE paths do not claim authority'
fi

if [ "$failed" -gt 0 ]; then
  printf '%s cross-reference check(s) failed.\n' "$failed" >&2
  exit 1
fi
