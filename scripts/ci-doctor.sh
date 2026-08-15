#!/usr/bin/env bash
# CI Doctor for NixOS config — Ring 1: diagnose failures, create issues.
set -uo pipefail

REPO="$1"
RUN_ID="$2"
RUN_NUMBER="$3"
FAILED_JOBS="$4"
OPENAI_API_KEY="${5:-}"
OPENAI_BASE_URL="${6:-https://integrate.api.nvidia.com/v1}"

TMPDIR=$(mktemp -d)
DIAG_FILE="$TMPDIR/diagnosis.txt"
echo "=== NixOS CI Doctor ===" > "$DIAG_FILE"
echo "Run: https://github.com/$REPO/actions/runs/$RUN_ID" >> "$DIAG_FILE"

for job in $FAILED_JOBS; do
  JOB_ID=$(gh api "/repos/$REPO/actions/runs/$RUN_ID/jobs" -q ".jobs[] | select(.name == \"$job\") | .id" 2>&1) || continue
  gh api "/repos/$REPO/actions/jobs/$JOB_ID/logs" > "$TMPDIR/${job}_log.txt" 2>/dev/null || continue
  echo "=== Job: $job ===" >> "$DIAG_FILE"
  tail -c 4000 "$TMPDIR/${job}_log.txt" >> "$DIAG_FILE" 2>/dev/null
done

LOGS=$(tail -c 7000 "$DIAG_FILE" 2>/dev/null || echo "no logs")

# LLM diagnosis via Python payload builder
DIAGNOSIS='{"class":"unknown","confidence":0.0,"root_cause":"see logs","severity":"medium"}'
if [ -n "$OPENAI_API_KEY" ]; then
  PAYLOAD=$(python3 -c "
import json
logs = '''$(echo "$LOGS" | sed "s/'/\\\\'/g" | head -c 4000)'''
p = {
    'model': 'minimax-m3',
    'messages': [
        {'role': 'system', 'content': 'You are a NixOS CI failure doctor. Classify the failure. Output valid JSON with: class (nix_build|nixos_rebuild|deploy|flake_lock|network|infrastructure|unknown), confidence 0-1, root_cause (one sentence), severity (low|medium|high), suggested_action (one sentence).'},
        {'role': 'user', 'content': f'Failed jobs: $FAILED_JOBS. Logs: {logs[:3000]}'}
    ],
    'max_tokens': 300,
    'temperature': 0.1
}
print(json.dumps(p))
" 2>/dev/null)

  LLM_OUT=$(curl -s -m 30 "$OPENAI_BASE_URL/chat/completions" \
    -H "Authorization: Bearer $OPENAI_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" 2>&1)

  DIAGNOSIS=$(echo "$LLM_OUT" | python3 -c "
import json,sys
try:
    d = json.load(sys.stdin)
    c = d['choices'][0]['message']['content'].strip()
    if c.startswith('\`\`\`'): c = c.split('\n',1)[1].rsplit('\`\`\`',1)[0].strip()
    print(json.dumps(json.loads(c)))
except: print(json.dumps({'class':'unknown','confidence':0.0,'root_cause':'parse error','severity':'medium'}))
" 2>/dev/null)
fi

CLASS=$(echo "$DIAGNOSIS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('class','unknown'))" 2>/dev/null || echo "unknown")
CONFIDENCE=$(echo "$DIAGNOSIS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('confidence',0))" 2>/dev/null || echo 0)
ROOT_CAUSE=$(echo "$DIAGNOSIS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('root_cause','unknown'))" 2>/dev/null || echo "unknown")
SEVERITY=$(echo "$DIAGNOSIS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('severity','medium'))" 2>/dev/null || echo "medium")
SUGGESTION=$(echo "$DIAGNOSIS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('suggested_action','See logs'))" 2>/dev/null || echo "See logs")

echo "  Class: $CLASS (confidence: $CONFIDENCE) severity: $SEVERITY"
echo "  Root cause: $ROOT_CAUSE"

# Create issue (Ring 1 — NixOS failures too complex for auto-fix)
TITLE="NixOS CI: $CLASS — $(echo "$ROOT_CAUSE" | head -c 60)"
BODY=$(cat << ISSUE
## NixOS CI Failure Report

**Failed jobs:** $FAILED_JOBS
**Class:** $CLASS
**Confidence:** $(echo "$CONFIDENCE * 100" | bc 2>/dev/null || echo 0)%
**Severity:** $SEVERITY
**Root cause:** $ROOT_CAUSE
**Run:** https://github.com/$REPO/actions/runs/$RUN_ID

### Suggested Action

$SUGGESTION

### Diagnosis

\`\`\`json
$DIAGNOSIS
\`\`\`

### Logs

\`\`\`
$(echo "$LOGS" | tail -c 3000)
\`\`\`
ISSUE
)

# Dedup: the doctor fires on every failed CI run; without this guard one
# failure mode spawns a new issue per run (2026-08-15 triage: 143 duplicate
# "NixOS CI: unknown — parse error" issues). Skip if an open issue with this
# exact title already exists.
if gh issue list --repo "$REPO" --search "state:open \"$TITLE\" in:title" --json number --jq 'length' 2>/dev/null | grep -q '^[1-9]'; then
  echo "⏭️  Open issue already exists for: $TITLE — skipping"
  rm -rf "$TMPDIR"
  exit 0
fi

gh issue create --repo "$REPO" --title "$TITLE" --body "$BODY" 2>&1 || {
  echo "$BODY" > "$TMPDIR/issue_body.md"
  gh issue create --repo "$REPO" --title "$TITLE" --body-file "$TMPDIR/issue_body.md" 2>&1
}

echo "✅ Issue created"
rm -rf "$TMPDIR"
echo "Done."
