---
name: retell-ai
description: Make outbound phone calls via Retell AI voice agents. Use when the user asks to call someone, make a phone call, check call status, get a call transcript, or list recent calls. Supports dynamic call goals, caller context, call status checking, transcript retrieval, and recent call listing with audit logging.
---

# Retell AI — Outbound Phone Calls

Make AI-powered outbound phone calls via [Retell AI](https://www.retellai.com). The voice agent calls on behalf of the user, accomplishes a stated goal (info gathering, appointment booking, transfers, etc.), and logs everything.

## Setup

### 1. API Key

Store your Retell API key:

```bash
mkdir -p ~/.clawdbot/secrets
echo 'RETELL_API_KEY=your_key_here' > ~/.clawdbot/secrets/retell.env
```

### 2. Configure the skill

Edit `scripts/retell-call.sh` and set these variables at the top:

| Variable | Description | Example |
|---|---|---|
| `FROM_NUMBER` | Your Retell phone number (E.164) | `+15005551234` |
| `AGENT_ID` | Your Retell agent ID | `agent_abc123...` |
| `DEFAULT_CONTEXT` | Default caller context sent to the agent | `"John Doe, CEO of Acme Corp"` |

### 3. Retell Dashboard Setup

In your [Retell dashboard](https://dashboard.retellai.com):
- Create an agent with a phone number
- Configure a `user_goal` dynamic variable in your agent's LLM prompt — this is how the script tells the agent what to accomplish on each call
- Optionally add `caller_context` dynamic variable for background info about the caller

## Usage

### Make a call

```bash
scripts/retell-call.sh "+18005551234" "Ask about their business hours and if they accept walk-ins"
```

With optional context:
```bash
scripts/retell-call.sh "+18005551234" "Schedule a haircut for Thursday" "This is a barbershop I've been to before"
```

### Check call status

```bash
scripts/retell-call.sh status <call_id>
```

Returns: status, duration, disconnect reason, call analysis (summary, sentiment, success), and full transcript.

### Get transcript only

```bash
scripts/retell-call.sh transcript <call_id>
```

### List recent calls

```bash
scripts/retell-call.sh recent        # last 5
scripts/retell-call.sh recent 20     # last 20
```

## Workflow Guidance

1. **Always confirm with the user before calling.** Phone calls are irreversible external actions.
2. After placing a call, wait ~30-60 seconds then check status for the result.
3. All calls are logged to an audit trail at `memory/audit/retell-calls.jsonl` (auto-created).
4. Phone numbers without a `+` prefix get `+1` prepended automatically (US default).

## Combining with SMS/iMessage

For a "text then call" workflow:
1. Send a heads-up text first (via iMessage, SMS, or WhatsApp skill)
2. Call via this skill with instructions to accomplish the goal
3. Check transcript for results

This reduces cold-call friction and improves pickup rates.

## API Reference

The script uses Retell's REST API v2:
- `POST /v2/create-phone-call` — initiate call
- `GET /v2/get-call/<id>` — status + transcript
- `POST /v2/list-calls` — recent calls

Full docs: https://docs.retellai.com
