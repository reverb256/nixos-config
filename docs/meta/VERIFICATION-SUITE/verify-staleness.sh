#!/usr/bin/env bash
set -euo pipefail

echo "Checking for stale documentation..."

find docs/LIVE docs/PATTERNS -name "*.md" -exec grep -l "last-verified:" {} + | while read -r file; do
  date_str=$(grep "last-verified:" "$file" | head -1 | cut -d: -f2 | tr -d ' ')
  if [ -n "$date_str" ]; then
    last=$(date -d "$date_str" +%s)
    now=$(date +%s)
    days=$(( (now - last) / 86400 ))
    if [ "$days" -gt 14 ]; then
      echo "STALE: $file ($days days old)"
      exit 1
    fi
  fi
done

echo "No stale LIVE/PATTERNS documents found."
exit 0
