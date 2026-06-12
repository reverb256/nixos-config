#!/usr/bin/env bash
set -euo pipefail

# Verification Suite for LIVE Documentation
# Enforces: Pocock Rule (7-day fresh verification)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
LIVE_DIR="$REPO_ROOT/docs/LIVE"
ARCHIVE_DIR="$REPO_ROOT/docs/ARCHIVE"

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

ERRORS=0
WARNINGS=0

echo "=== Documentation Verification Suite ==="
echo "Repo: $REPO_ROOT"
echo ""

# Check 1: LIVE docs exist
echo "Check 1: LIVE directory structure"
if [ ! -d "$LIVE_DIR" ]; then
  echo -e "${RED}ERROR${NC}: $LIVE_DIR not found"
  ((ERRORS++))
else
  echo -e "${GREEN}PASS${NC}: LIVE directory exists"
fi
echo ""

# Check 2: Frontmatter validation
echo "Check 2: Frontmatter validation (LIVE docs)"
for doc in "$LIVE_DIR"/*.md; do
  [ -f "$doc" ] || continue
  filename=$(basename "$doc")
  
  # Check for required fields
  if ! grep -q "last-verified:" "$doc"; then
    echo -e "${RED}ERROR${NC}: $filename missing 'last-verified' field"
    ((ERRORS++))
    continue
  fi
  
  if ! grep -q "verified-by:" "$doc"; then
    echo -e "${RED}ERROR${NC}: $filename missing 'verified-by' field"
    ((ERRORS++))
    continue
  fi
  
  if ! grep -q "expires:" "$doc"; then
    echo -e "${RED}ERROR${NC}: $filename missing 'expires' field"
    ((ERRORS++))
    continue
  fi
  
  # Extract dates
  LAST_VERIFIED=$(grep "last-verified:" "$doc" | cut -d: -f2 | xargs)
  EXPIRES=$(grep "expires:" "$doc" | cut -d: -f2 | xargs)
  
  # Check if expired
  EXPIRY_EPOCH=$(date -d "$EXPIRES" +%s 2>/dev/null || echo "0")
  CURRENT_EPOCH=$(date +%s)
  
  if [ "$EXPIRY_EPOCH" -lt "$CURRENT_EPOCH" ]; then
    echo -e "${RED}ERROR${NC}: $filename EXPIRED (last-verified: $LAST_VERIFIED, expires: $EXPIRES)"
    ((ERRORS++))
  else
    DAYS_UNTIL_EXPIRY=$(( (EXPIRY_EPOCH - CURRENT_EPOCH) / 86400 ))
    if [ "$DAYS_UNTIL_EXPIRY" -lt 3 ]; then
      echo -e "${YELLOW}WARNING${NC}: $filename expires in $DAYS_UNTIL_EXPIRY days (last-verified: $LAST_VERIFIED)"
      ((WARNINGS++))
    else
      echo -e "${GREEN}PASS${NC}: $filename valid ($DAYS_UNTIL_EXPIRY days until expiry)"
    fi
  fi
done
echo ""

# Check 3: Stale plans outside archive
echo "Check 3: Stale plan detection (>30 days, not in ARCHIVE/)"
find "$REPO_ROOT" -name "*plan*.md" -o -name "*PLAN*.md" | while read -r plan; do
  if [[ "$plan" == *ARCHIVE* ]] || [[ "$plan" == *archived* ]]; then
    continue
  fi
  
  MTIME=$(stat -c %Y "$plan" 2>/dev/null || stat -f %m "$plan" 2>/dev/null)
  CURRENT=$(date +%s)
  AGE_DAYS=$(( (CURRENT - MTIME) / 86400 ))
  
  if [ "$AGE_DAYS" -gt 30 ]; then
    filename=$(basename "$plan")
    echo -e "${YELLOW}WARNING${NC}: $plan is $AGE_DAYS days old (consider archiving)"
    ((WARNINGS++))
  fi
done
echo ""

# Check 4: Single source of truth (duplicate AUDIT/STATUS files)
echo "Check 4: Single source of truth check"
AUDIT_COUNT=$(find "$REPO_ROOT" -maxdepth 1 -name "INFRASTRUCTURE-AUDIT.md" 2>/dev/null | wc -l)
STATUS_COUNT=$(find "$REPO_ROOT" -maxdepth 1 -name "STATUS.md" 2>/dev/null | wc -l)

if [ "$AUDIT_COUNT" -gt 0 ]; then
  echo -e "${YELLOW}WARNING${NC}: Found $AUDIT_COUNT INFRASTRUCTURE-AUDIT.md at root (use docs/LIVE/ instead)"
  ((WARNINGS++))
fi

if [ "$STATUS_COUNT" -gt 0 ]; then
  echo -e "${YELLOW}WARNING${NC}: Found $STATUS_COUNT STATUS.md at root (use docs/LIVE/ instead)"
  ((WARNINGS++))
fi

if [ "$AUDIT_COUNT" -eq 0 ] && [ "$STATUS_COUNT" -eq 0 ]; then
  echo -e "${GREEN}PASS${NC}: No duplicate audit/status files at root"
fi
echo ""

# Check 5: AGENTS.md fragmentation
echo "Check 5: AGENTS.md consolidation check"
AGENTS_COUNT=$(find "$REPO_ROOT" -name "AGENTS.md" | wc -l)
if [ "$AGENTS_COUNT" -gt 1 ]; then
  echo -e "${YELLOW}WARNING${NC}: Found $AGENTS_COUNT AGENTS.md files (should be 1: /etc/nixos/AGENTS.md)"
  ((WARNINGS++))
  find "$REPO_ROOT" -name "AGENTS.md" | head -5 | while read -r file; do
    if [ "$file" != "$REPO_ROOT/AGENTS.md" ]; then
      echo "  - $file"
    fi
  done
else
  echo -e "${GREEN}PASS${NC}: Only 1 AGENTS.md found"
fi
echo ""

# Summary
echo "=== Verification Summary ==="
echo -e "${GREEN}PASSED${NC}: Core checks completed"
echo -e "${YELLOW}WARNINGS${NC}: $WARNINGS"
echo -e "${RED}ERRORS${NC}: $ERRORS"
echo ""

if [ "$ERRORS" -gt 0 ]; then
  echo -e "${RED}VERIFICATION FAILED${NC}: Fix errors before merge"
  exit 1
elif [ "$WARNINGS" -gt 0 ]; then
  echo -e "${YELLOW}VERIFICATION PASSED WITH WARNINGS${NC}: Review warnings"
  exit 0
else
  echo -e "${GREEN}VERIFICATION PASSED${NC}: All checks successful"
  exit 0
fi