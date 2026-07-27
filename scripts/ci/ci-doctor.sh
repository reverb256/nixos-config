#!/usr/bin/env bash
# CI Doctor — diagnose NixOS CI failures, create analysis issue, post kanban event.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Source the kanban helper from site-agency (or local if available)
if [ -f "$SCRIPT_DIR/../kanban_helper.sh" ]; then
  source "$SCRIPT_DIR/../kanban_helper.sh"
elif [ -f "/home/j_kro/Projects/site-agency/scripts/kanban_helper.sh" ]; then
  source "/home/j_kro/Projects/site-agency/scripts/kanban_helper.sh"
else
  # Fallback: define minimal inline wrapper
  kanban_post() { echo "kanban_post: hermes helper not available" >&2; echo "mock-${1}"; }
  kanban_close() { echo "kanban_close: hermes helper not available" >&2; }
  kanban_block() { echo "kanban_block: hermes helper not available" >&2; }
fi

REPO="${1:-reverb256/nixos-config}"
RUN_ID="${2:-unknown}"
RUN_NUMBER="${3:-0}"
SHA="${4:-unknown}"
FAILED_JOBS="${5:-unknown}"

echo "=== NixOS CI Doctor ==="
echo "Repo: $REPO  Run: $RUN_ID  SHA: $SHA"
echo "Failed jobs: $FAILED_JOBS"

# ── Collect logs for failed jobs ──
TMPDIR=$(mktemp -d)
DIAG_FILE="$TMPDIR/diagnosis.txt"

for job in $FAILED_JOBS; do
  echo "  Fetching logs for job: $job"
  JOB_ID=$(gh api "/repos/$REPO/actions/runs/$RUN_ID/jobs" -q ".jobs[] | select(.name == \"$job\") | .id" 2>&1) || {
    echo "  Warning: failed to get job ID for $job"
    continue
  }
  gh api "/repos/$REPO/actions/jobs/$JOB_ID/logs" > "$TMPDIR/${job}_log.txt" 2>/dev/null || {
    echo "  Warning: failed to fetch logs for $job"
    continue
  }
  echo "=== Job: $job ===" >> "$DIAG_FILE"
  tail -c 3000 "$TMPDIR/${job}_log.txt" >> "$DIAG_FILE" 2>/dev/null
done

LOGS=$(tail -c 6000 "$DIAG_FILE" 2>/dev/null || echo "no logs")

# ── Build diagnosis summary ──
TITLE="NixOS CI failure: $FAILED_JOBS (run #$RUN_NUMBER)"
BODY=$(printf '## NixOS CI Failure Report\n\n**Failed jobs:** %s\n**Run:** https://github.com/%s/actions/runs/%s\n**SHA:** %s\n\n### Logs\n\n```\n%s\n```\n' \
  "$FAILED_JOBS" "$REPO" "$RUN_ID" "$SHA" "${LOGS: -3000}")

# ── Create GitHub issue ──
echo "Creating diagnosis issue..."
gh issue create --repo "$REPO" --title "$TITLE" --body "$BODY" 2>&1 || {
  echo "  Failed to create issue"
  echo "$BODY" > "$TMPDIR/issue_body.md"
  gh issue create --repo "$REPO" --title "$TITLE" --body-file "$TMPDIR/issue_body.md" 2>&1
}
echo "✅ Issue created"

# ── Kanban event ──
kanban_post "ci-failure" "$TITLE" \
  --urgency high \
  --labels "type:ci-failure,source:ci-doctor,repo:${REPO//\//-}" \
  --body "NixOS CI failure — run #$RUN_NUMBER, jobs: $FAILED_JOBS" || true

# ── Cleanup ──
rm -rf "$TMPDIR"
echo "Done."
