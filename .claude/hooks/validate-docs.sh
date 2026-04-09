#!/usr/bin/env bash
# Documentation validation script
# Checks for common documentation issues: stale timestamps, resolved issues, line count limits

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

ERRORS=0
WARNINGS=0

echo "🔍 Validating documentation..."
echo ""

# Function to check timestamp consistency
check_timestamps() {
    echo "📅 Checking timestamp consistency..."

    local today=$(date +%Y-%m-%d)
    local files=(
        "/etc/nixos/STATUS.md"
        "/etc/nixos/ROADMAP.md"
        "/etc/nixos/AGENTS.md"
        "/etc/nixos/DOCUMENTATION_INDEX.md"
    )

    for file in "${files[@]}"; do
        if [[ ! -f "$file" ]]; then
            echo -e "${YELLOW}⚠️  $file not found${NC}"
            continue
        fi

        local file_date=$(grep -oP "Last Updated:.*?(\d{4}-\d{2}-\d{2})" "$file" 2>/dev/null | grep -oP "\d{4}-\d{2}-\d{2}" | head -1 || echo "")
        if [[ -z "$file_date" ]]; then
            echo -e "${YELLOW}⚠️  $file: No timestamp found${NC}"
            ((WARNINGS++))
        elif [[ "$file_date" != "$today" ]]; then
            local file_date_sec=$(date -d "$file_date" +%s 2>/dev/null || echo "0")
            local today_sec=$(date -d "$today" +%s)
            local days_diff=$(( (today_sec - file_date_sec) / 86400 ))
            if [[ $days_diff -gt 3 ]]; then
                echo -e "${YELLOW}⚠️  $file: Timestamp is $days_diff days old (file: $file_date, today: $today)${NC}"
                ((WARNINGS++))
            fi
        fi
    done
    echo ""
}

# Function to check for RESOLVED items in Known Issues tables
check_resolved_issues() {
    echo "✅ Checking for RESOLVED issues in Known Issues tables..."

    local status_file="/etc/nixos/STATUS.md"
    if [[ ! -f "$status_file" ]]; then
        echo -e "${RED}❌ $status_file not found${NC}"
        ((ERRORS++))
        return
    fi

    local resolved_count
    resolved_count=$(grep -c "RESOLVED\|FIXED\|SOLVED" "$status_file" 2>/dev/null) || true
    resolved_count=${resolved_count:-0}
    if [[ "$resolved_count" -gt 0 ]]; then
        echo -e "${RED}❌ Found $resolved_count RESOLVED/FIXED/SOLVED items in Known Issues table${NC}"
        echo -e "${RED}   → Move these to docs/CHANGELOG.md${NC}"
        ((ERRORS++))
    else
        echo -e "${GREEN}✓ No RESOLVED issues found${NC}"
    fi
    echo ""
}

# Function to check line count limits
check_line_counts() {
    echo "📏 Checking line count limits..."

    local status_lines=$(wc -l < /etc/nixos/STATUS.md 2>/dev/null || echo "9999")
    local roadmap_lines=$(wc -l < /etc/nixos/ROADMAP.md 2>/dev/null || echo "9999")

    # STATUS.md should be under 150 lines
    if [[ $status_lines -gt 150 ]]; then
        echo -e "${YELLOW}⚠️  STATUS.md: $status_lines lines (target: ≤150 lines)${NC}"
        ((WARNINGS++))
    else
        echo -e "${GREEN}✓ STATUS.md: $status_lines lines (OK)${NC}"
    fi

    # ROADMAP.md should be under 800 lines
    if [[ $roadmap_lines -gt 800 ]]; then
        echo -e "${YELLOW}⚠️  ROADMAP.md: $roadmap_lines lines (target: ≤800 lines)${NC}"
        ((WARNINGS++))
    else
        echo -e "${GREEN}✓ ROADMAP.md: $roadmap_lines lines (OK)${NC}"
    fi
    echo ""
}

# Function to check for contradictions
check_contradictions() {
    echo "🔍 Checking for common contradictions..."

    local status_file="/etc/nixos/STATUS.md"
    if [[ ! -f "$status_file" ]]; then
        echo -e "${RED}❌ $status_file not found${NC}"
        ((ERRORS++))
        return
    fi

    # Check for "4/4 READY" but "NotReady" in node table
    local ready_count=$(grep -c "4/4 READY" "$status_file" 2>/dev/null || echo "0")
    local notready_count=$(grep -c "NotReady" "$status_file" 2>/dev/null || echo "0")

    if [[ $ready_count -gt 0 ]] && [[ $notready_count -gt 0 ]]; then
        echo -e "${RED}❌ STATUS.md: Claims '4/4 READY' but shows 'NotReady' node${NC}"
        ((ERRORS++))
    fi

    # Check for "95% COMPLETE" or similar when all phases show ✅
    local incomplete_percent=$(grep -c "95%\|90%\|80%" "$status_file" 2>/dev/null || echo "0")
    local all_complete=$(grep -c "✅ COMPLETE" "$status_file" 2>/dev/null || echo "0")

    if [[ $incomplete_percent -gt 0 ]] && [[ $all_complete -gt 7 ]]; then
        echo -e "${YELLOW}⚠️  STATUS.md: Shows incomplete percentage but all phases complete${NC}"
        ((WARNINGS++))
    fi

    if [[ $ERRORS -eq 0 ]] && [[ $WARNINGS -eq 0 ]]; then
        echo -e "${GREEN}✓ No contradictions found${NC}"
    fi
    echo ""
}

# Function to check for phase status inconsistencies
check_phase_status() {
    echo "🔍 Checking phase status consistency..."

    local roadmap_file="/etc/nixos/ROADMAP.md"
    if [[ ! -f "$roadmap_file" ]]; then
        echo -e "${RED}❌ $roadmap_file not found${NC}"
        ((ERRORS++))
        return
    fi

    # Check for "Phase 7 In Progress" vs "Phase 7: ✅ COMPLETE"
    local in_progress=$(grep -c "Phase 7 In Progress\|Phase 7: ⚠️" "$roadmap_file" 2>/dev/null || echo "0")
    local complete=$(grep -c "Phase 7: ✅ COMPLETE\|Phase 7.*100%" "$roadmap_file" 2>/dev/null || echo "0")

    if [[ $in_progress -gt 0 ]] && [[ $complete -gt 0 ]]; then
        echo -e "${RED}❌ ROADMAP.md: Phase 7 both 'In Progress' and 'COMPLETE'${NC}"
        ((ERRORS++))
    fi

    if [[ $ERRORS -eq 0 ]] && [[ $WARNINGS -eq 0 ]]; then
        echo -e "${GREEN}✓ Phase status consistent${NC}"
    fi
    echo ""
}

# Run all checks
check_timestamps
check_resolved_issues
check_line_counts
check_contradictions
check_phase_status

# Summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Documentation Validation Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "Errors:   ${RED}$ERRORS${NC}"
echo -e "Warnings: ${YELLOW}$WARNINGS${NC}"
echo ""

if [[ $ERRORS -gt 0 ]]; then
    echo -e "${RED}❌ Validation FAILED - Fix errors before committing${NC}"
    exit 1
elif [[ $WARNINGS -gt 0 ]]; then
    echo -e "${YELLOW}⚠️  Validation passed with warnings - Review recommended${NC}"
    exit 0
else
    echo -e "${GREEN}✅ Validation PASSED - Documentation is clean${NC}"
    exit 0
fi
