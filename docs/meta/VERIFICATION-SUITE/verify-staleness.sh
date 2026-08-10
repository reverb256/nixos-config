#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT"

MAX_DAYS="${DOC_MAX_AGE_DAYS:-7}"
# These are maintained operator/navigation docs. Historical files and pointers
# are intentionally excluded; they retain their original verification dates.
active_manifest="docs/meta/VERIFICATION-SUITE/ACTIVE-DOCUMENTS.txt"
if [ ! -f "$active_manifest" ]; then
  printf 'MISSING: %s\n' "$active_manifest" >&2
  exit 1
fi
mapfile -t active_files < <(grep -Ev '^[[:space:]]*(#|$)' "$active_manifest")
if [ "${#active_files[@]}" -eq 0 ]; then
  echo "FAIL: active-document manifest is empty" >&2
  exit 1
fi

# Reject duplicate or directory entries so the manifest remains an explicit,
# reviewable contract rather than an accidentally broad glob.
if [ "$(printf '%s\n' "${active_files[@]}" | sort -u | wc -l)" -ne "${#active_files[@]}" ]; then
  echo "FAIL: active-document manifest contains duplicate paths" >&2
  exit 1
fi
for file in "${active_files[@]}"; do
  if [ -d "$file" ]; then
    printf 'FAIL: active-document manifest contains directory: %s\n' "$file" >&2
    exit 1
  fi
done

printf '  OK: active-document manifest (%s files)\n' "${#active_files[@]}"

# The manifest itself is tooling metadata, not an operator document, so it is
# deliberately not included in the freshness loop.
failed=0
for file in "${active_files[@]}"; do
  if [ ! -f "$file" ]; then
    printf 'MISSING: %s\n' "$file" >&2
    failed=$((failed + 1))
    continue
  fi

  date_value=$(grep -Eim1 -o 'Last[[:space:]]+Verified:[^0-9]*[0-9]{4}-[0-9]{2}-[0-9]{2}' "$file" \
    | grep -Eo '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1 || true)
  if [ -z "$date_value" ]; then
    # Metadata may be a Markdown blockquote or bold label; accept only an
    # explicit ISO date, never a filesystem mtime.
    printf 'MISSING METADATA: %s (Last Verified required)\n' "$file" >&2
    failed=$((failed + 1))
    continue
  fi

  if ! grep -qiE '^[>#* -]*\\**Status\\**:' "$file"; then
    printf 'MISSING METADATA: %s (Status required)\\n' "$file" >&2
    failed=$((failed + 1))
  fi
  if ! grep -qiE '^[>#* -]*\\**(Owner|Source)\\**:' "$file"; then
    printf 'MISSING METADATA: %s (Owner or Source required)\\n' "$file" >&2
    failed=$((failed + 1))
  fi

  if ! last_epoch=$(date -d "$date_value" +%s 2>/dev/null); then
    printf 'INVALID DATE: %s (%s)\n' "$file" "$date_value" >&2
    failed=$((failed + 1))
    continue
  fi
  now_epoch=$(date +%s)
  age_days=$(( (now_epoch - last_epoch) / 86400 ))
  if [ "$age_days" -gt "$MAX_DAYS" ]; then
    printf 'STALE: %s (%s days old; last verified %s)\n' "$file" "$age_days" "$date_value" >&2
    failed=$((failed + 1))
  else
    printf '  OK: %s (%s days old)\n' "$file" "$age_days"
  fi
done

if [ "$failed" -gt 0 ]; then
  printf '%s active-document metadata failure(s).\n' "$failed" >&2
  exit 1
fi
