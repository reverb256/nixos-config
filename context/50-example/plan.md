# Implementation Plan for #50

## Steps

1. Create `/data/agents/context/` directory structure
   - `context/README.md` — conventions and usage
   - `context/.gitkeep` — keep directory in version control

2. Update `dispatch.py` to create context directory on task creation
   - Add `--context-dir` parameter
   - Auto-create `<context-dir>/<task_id>/` after task creation

3. Update `kelos.py` to write initial context when dispatching
   - Write `analysis.md` from issue body
   - Write initial `results.json` with stage=analysis

4. Create example context files for issue #50 (this issue)
   - `analysis.md` — this analysis
   - `plan.md` — this plan
   - `results.json` — structured results

5. Update Hermes skills
   - `skills/agent-dispatch/SKILL.md` — add context bridge reference
   - `skills/cluster-conventions/SKILL.md` — add handoff protocol

6. Update `AGENTS.md` with cross-reference to context bridge

## Files Modified

| File | Change |
|------|--------|
| `context/README.md` | New — conventions documentation |
| `context/.gitkeep` | New — keep directory tracked |
| `context/50-example/analysis.md` | New — example analysis |
| `context/50-example/plan.md` | New — example plan |
| `context/50-example/results.json` | New — example structured results |
| `context/50-example/handoff.md` | New — example handoff notes |
| `scripts/dispatch.py` | New — dispatch with context bridge |
| `scripts/kelos.py` | New — kelos with context bridge |
| `skills/agent-dispatch/SKILL.md` | Updated — reference context bridge |
| `AGENTS.md` | Updated — cross-reference |

## Risks

- NFS write conflicts if multiple agents write simultaneously (mitigated by per-issue directories)
- Stale context accumulation (mitigated by 30-day cleanup convention)
- Agents ignoring context (mitigated by skill updates and AGENTS.md documentation)

## Rollback

If context bridge causes issues:
1. Remove context directory creation from dispatch.py
2. Remove context writing from kelos.py
3. Delete `/data/agents/context/` contents
4. Revert skill and AGENTS.md changes
