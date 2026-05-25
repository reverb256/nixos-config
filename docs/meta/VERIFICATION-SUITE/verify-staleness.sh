#!/usr/bin/env bash
set -euo pipefail

echo "Checking for stale documentation in LIVE/ and PATTERNS/..."

STALE_FOUND=0

for file in $(find docs/LIVE docs/PATTERNS -name "*.md" 2>/dev/null || true); do
  if grep -q "last-verified:" "$file"; then
    DATE=$(grep "last-verified:" "$file" | head -1 | sed 's/.*last-verified: *//')
    if [ -n "$DATE" ]; then
      LAST=$(date -d "$DATE" +%s 2>/dev/null || echo "0")
      NOW=$(date +%s)
      DAYS=$(( (NOW - LAST) / 86400 ))
      if [ "$DAYS" -gt 14 ]; then
        echo "STALE: $file ($DAYS days old, last-verified $DATE)"
        STALE_FOUND=1
      else
        echo "  OK: $file ($DAYS days old)"
      fi
    fi
  else
    echo "WARNING: $file has no last-verified date"
    STALE_FOUND=1
  fi
done

if [ $STALE_FOUND -eq 0 ]; then
  echo "No stale documents found."
  exit 0
else
  echo "Stale documentation found."
  exit 1
fi
