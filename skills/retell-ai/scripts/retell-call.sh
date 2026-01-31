#!/bin/bash
# retell-call.sh — Make outbound phone calls via Retell AI
#
# Usage:
#   retell-call.sh <phone_number> <goal> [context]
#   retell-call.sh "+18015551234" "Ask about their hours" "This is a restaurant"
#   retell-call.sh status <call_id>
#   retell-call.sh transcript <call_id>
#   retell-call.sh recent [limit]
#
set -euo pipefail

# ─── Configuration ───────────────────────────────────────────────
# Load API key from secrets
SECRETS_FILE="${RETELL_SECRETS_FILE:-$HOME/.clawdbot/secrets/retell.env}"
if [ -f "$SECRETS_FILE" ]; then
    source "$SECRETS_FILE"
fi

if [ -z "${RETELL_API_KEY:-}" ]; then
    echo "❌ RETELL_API_KEY not set. Create ~/.clawdbot/secrets/retell.env with:"
    echo "   RETELL_API_KEY=your_key_here"
    exit 1
fi

API="https://api.retellai.com"

# ⚠️  Set these to match your Retell dashboard setup:
FROM_NUMBER="${RETELL_FROM_NUMBER:?Set RETELL_FROM_NUMBER env var or edit this script}"
AGENT_ID="${RETELL_AGENT_ID:?Set RETELL_AGENT_ID env var or edit this script}"
DEFAULT_CONTEXT="${RETELL_DEFAULT_CONTEXT:-}"

# Audit log location (auto-created)
AUDIT_LOG="${RETELL_AUDIT_LOG:-$HOME/clawd/memory/audit/retell-calls.jsonl}"
mkdir -p "$(dirname "$AUDIT_LOG")"

# ─── Status command ──────────────────────────────────────────────
if [ "${1:-}" = "status" ] && [ -n "${2:-}" ]; then
    curl -s "$API/v2/get-call/${2}" \
        -H "Authorization: Bearer $RETELL_API_KEY" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(f'Call ID:    {d.get(\"call_id\",\"?\")}')
print(f'Status:     {d.get(\"call_status\",\"unknown\")}')
print(f'Duration:   {d.get(\"duration_ms\",0)/1000:.0f}s')
print(f'Direction:  {d.get(\"direction\",\"?\")}')
print(f'To:         {d.get(\"to_number\",\"?\")}')
print(f'From:       {d.get(\"from_number\",\"?\")}')
if d.get('disconnection_reason'):
    print(f'Ended:      {d[\"disconnection_reason\"]}')
if d.get('call_analysis'):
    ca = d['call_analysis']
    print(f'Summary:    {ca.get(\"call_summary\",\"none\")}')
    print(f'Sentiment:  {ca.get(\"user_sentiment\",\"?\")}')
    print(f'Successful: {ca.get(\"call_successful\",\"?\")}')
    if ca.get('custom_analysis_data'):
        for k,v in ca['custom_analysis_data'].items():
            print(f'  {k}: {v}')
if d.get('transcript'):
    print()
    print('=== TRANSCRIPT ===')
    print(d['transcript'])
"
    exit 0
fi

# ─── Transcript command ─────────────────────────────────────────
if [ "${1:-}" = "transcript" ] && [ -n "${2:-}" ]; then
    curl -s "$API/v2/get-call/${2}" \
        -H "Authorization: Bearer $RETELL_API_KEY" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('transcript', 'No transcript available'))
"
    exit 0
fi

# ─── Recent calls command ───────────────────────────────────────
if [ "${1:-}" = "recent" ]; then
    LIMIT="${2:-5}"
    curl -s -X POST "$API/v2/list-calls" \
        -H "Authorization: Bearer $RETELL_API_KEY" \
        -H "Content-Type: application/json" \
        -d "{\"limit\": $LIMIT, \"sort_order\": \"descending\"}" | python3 -c "
import sys, json, datetime
data = json.load(sys.stdin)
calls = data if isinstance(data, list) else data.get('calls', data.get('data', []))
for c in calls:
    ts = c.get('start_timestamp', 0)
    dt = datetime.datetime.fromtimestamp(ts/1000).strftime('%Y-%m-%d %H:%M') if ts else '?'
    dur = c.get('duration_ms', 0) / 1000
    status = c.get('call_status', '?')
    to_num = c.get('to_number', '?')
    cid = c.get('call_id', '?')
    summary = ''
    if c.get('call_analysis', {}).get('call_summary'):
        summary = c['call_analysis']['call_summary'][:80]
    print(f'{dt} | {to_num:15s} | {status:8s} | {dur:5.0f}s | {cid}')
    if summary:
        print(f'  └─ {summary}')
"
    exit 0
fi

# ─── Make a call ─────────────────────────────────────────────────
if [ -z "${1:-}" ] || [ -z "${2:-}" ]; then
    echo "Usage: retell-call.sh <phone_number> <goal> [context]"
    echo "       retell-call.sh status <call_id>"
    echo "       retell-call.sh transcript <call_id>"
    echo "       retell-call.sh recent [limit]"
    exit 1
fi

TO_NUMBER="$1"
GOAL="$2"
CONTEXT="${3:-$DEFAULT_CONTEXT}"

# Ensure + prefix for E.164
if [[ ! "$TO_NUMBER" =~ ^\+ ]]; then
    TO_NUMBER="+1${TO_NUMBER}"
fi

echo "📞 Calling $TO_NUMBER..."
echo "Goal: $GOAL"
echo ""

# Escape JSON strings properly
GOAL_JSON=$(python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$GOAL")
CONTEXT_JSON=$(python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$CONTEXT")

RESPONSE=$(curl -s -X POST "$API/v2/create-phone-call" \
    -H "Authorization: Bearer $RETELL_API_KEY" \
    -H "Content-Type: application/json" \
    -d "{
        \"from_number\": \"$FROM_NUMBER\",
        \"to_number\": \"$TO_NUMBER\",
        \"override_agent_id\": \"$AGENT_ID\",
        \"retell_llm_dynamic_variables\": {
            \"user_goal\": $GOAL_JSON,
            \"caller_context\": $CONTEXT_JSON
        }
    }")

# Parse result
CALL_ID=$(echo "$RESPONSE" | python3 -c "
import sys, json
d = json.load(sys.stdin)
if 'call_id' in d:
    print(d['call_id'])
else:
    print('ERROR')
    sys.exit(1)
" 2>/dev/null)

if [ "$CALL_ID" = "ERROR" ] || [ -z "$CALL_ID" ]; then
    echo "❌ Call failed:"
    echo "$RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$RESPONSE"
    exit 1
fi

echo "✅ Call ID: $CALL_ID"
echo "Status: registered"
echo ""
echo "Check status: retell-call.sh status $CALL_ID"

# Audit log
python3 -c "
import json, datetime, sys
entry = {
    'timestamp': datetime.datetime.utcnow().isoformat() + 'Z',
    'type': 'retell-call',
    'call_id': '$CALL_ID',
    'to_number': '$TO_NUMBER',
    'from_number': '$FROM_NUMBER',
    'goal': $GOAL_JSON,
    'source': 'retell-call.sh'
}
with open('$AUDIT_LOG', 'a') as f:
    f.write(json.dumps(entry) + '\n')
print('📝 Logged to audit trail')
"
