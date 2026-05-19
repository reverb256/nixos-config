# Agent Context Bridge

Shared workspace for passing state between agent stages (Hermes, Kelos, OpenCode, OMP, Pi).

## Directory Structure

```
/data/agents/context/
├── <issue-number>/
│   ├── analysis.md       — Problem analysis / investigation results
│   ├── plan.md           — Implementation plan (steps, files, risks)
│   ├── review.md         — Code review findings (from reviewing agent)
│   ├── results.json      — Structured: {branch, commit, pr, status}
│   └── handoff.md        — Notes for the next agent in the chain
├── README.md             — This file
└── .gitkeep              — Keep the directory in version control
```

## File Format

### Markdown Files (`.md`)
Human-readable documents for agent-to-agent communication:

| File | Stage | Purpose |
|------|-------|---------|
| `analysis.md` | Stage 1 (Analysis) | Problem investigation, root cause, affected systems |
| `plan.md` | Stage 2 (Implementation) | Implementation steps, files to modify, risks, rollback plan |
| `review.md` | Stage 3 (Review) | Code review findings, suggestions, approval/rejection |
| `handoff.md` | Any stage | Free-form notes for the next agent in the chain |

### Structured Data (`results.json`)
Machine-readable JSON for dispatch/kelos consumption:

```json
{
  "stage": "analysis | implementation | review | deploy",
  "agent": "hermes | opencode | omp | pi | kelos",
  "issue": 42,
  "branch": "fix/42-oom-protect",
  "commit": "abc123def456",
  "pr": "https://github.com/reverb256/nixos-config/pull/43",
  "status": "completed | failed | blocked",
  "blocker": "Waiting for #41 to merge",
  "timestamp": "2026-05-19T10:30:00Z"
}
```

## Protocol

### Reading Context (Agent Startup)
At the start of a task, check for existing context:

```bash
#!/usr/bin/env bash
CONTEXT_DIR="/data/agents/context/$ISSUE_NUMBER"
if [ -d "$CONTEXT_DIR" ]; then
  echo "=== Loading prior context for #$ISSUE_NUMBER ==="
  for f in "$CONTEXT_DIR"/*.md; do
    [ -f "$f" ] && echo "--- $(basename "$f") ---" && cat "$f"
  done
fi
```

### Writing Context (Stage Completion)
At the end of each stage, save your output:

```python
import json, os
from datetime import datetime, timezone

ctxt_dir = f"/data/agents/context/{issue_number}"
os.makedirs(ctxt_dir, exist_ok=True)

# Write analysis/plan/review
with open(f"{ctxt_dir}/analysis.md", "w") as f:
    f.write(f"# Analysis for #{issue_number}\n\n{findings}")

# Write structured results
with open(f"{ctxt_dir}/results.json", "w") as f:
    json.dump({
        "stage": "analysis",
        "agent": "kelos",
        "issue": issue_number,
        "branch": branch,
        "commit": commit,
        "pr": pr_url,
        "status": "completed",
        "timestamp": datetime.now(timezone.utc).isoformat()
    }, f, indent=2)
```

## Agent Handoff Flow

```
Issue created & labeled agent-ready
  │
  └─→ Kelos agent (stage 1: analysis)
      ├── Reads GitHub issue
      ├── Writes /data/agents/context/NNN/analysis.md
      └── Updates results.json with status
  │
  └─→ Kelos agent (stage 2: implementation)
      ├── Reads analysis.md for context
      ├── Implements changes
      ├── Opens PR
      ├── Writes plan.md, results.json
      └── Updates dispatch task status
  │
  └─→ Hermes (stage 3: review)
      ├── Reads results.json for PR URL
      ├── Reviews PR
      ├── Writes review.md
      └── Merges or requests changes
```

## NFS Sharing

The `/data/agents/` directory is on the NFS-backed filesystem (shared across all 4 nodes: zephyr, nexus, forge, sentry). Any agent on any node can read/write context files. No sync needed.

## Conventions

1. **Create** context directory on task creation (dispatch.py handles this)
2. **Write** analysis/plan before implementation — don't skip stages
3. **Read** existing context before starting work — prior agents may have critical info
4. **Update** results.json on completion — enables automated handoff
5. **Clean up** stale contexts after issue resolution (>30 days old)
6. **Never delete** context files while an issue is open
