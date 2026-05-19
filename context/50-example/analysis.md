# Analysis for #50

## Problem

No standard mechanism exists for passing state between agent stages in the multi-agent pipeline (Hermes → Kelos → OpenCode → OMP → Pi). Agents have no way to:

- Share investigation findings with the implementing agent
- Pass implementation details to the reviewing agent
- Track structured results (branch, commit, PR) for automated handoff

## Current State

- `/data/agents/dispatch.py` — shared task queue with claim/done/fail lifecycle
- `/data/agents/kelos.py` — creates Kelos Task CRDs from dispatch tasks
- `/data/agents/state/tasks.json` — shared state file (NFS-accessible)
- **Gap**: No per-task context bridge

## Impact

Without a context bridge:
- Each agent starts from scratch, re-reading the GitHub issue
- Analysis findings are lost between stages
- Reviewers must manually find the PR URL
- No structured handoff for automated pipelines

## Proposed Solution

Create `/data/agents/context/<issue-number>/` directory with:
- `analysis.md` — Problem analysis from stage 1
- `plan.md` — Implementation plan from stage 2
- `review.md` — Review findings from stage 3
- `results.json` — Structured machine-readable results
- `handoff.md` — Free-form notes for next agent

## Affected Systems

- `/data/agents/dispatch.py` — add context directory creation
- `/data/agents/kelos.py` — write initial context on dispatch
- Hermes skills — reference context bridge in kelos/agent-dispatch skills
- AGENTS.md — document the convention
