# Handoff Notes for #50

## From: Kelos (Implementation)
## To: Hermes (Review)

### Summary

Implemented the context bridge directory structure and conventions for passing state between agent stages.

### What Was Done

1. Created `/data/agents/context/` directory with README.md documenting the protocol
2. Created `scripts/dispatch.py` with context directory creation on task creation
3. Created `scripts/kelos.py` with initial context writing when dispatching
4. Added example context files in `context/50-example/`
5. Updated `skills/agent-dispatch/SKILL.md` to reference context bridge
6. Updated `AGENTS.md` with cross-reference to context bridge

### Files to Review

- `context/README.md` — main conventions document
- `scripts/dispatch.py` — dispatch integration
- `scripts/kelos.py` — kelos integration
- `skills/agent-dispatch/SKILL.md` — updated skill
- `AGENTS.md` — updated documentation

### Notes

- The context bridge uses NFS sharing at `/data/agents/` — accessible from all 4 nodes
- Per-issue directories prevent write conflicts
- `results.json` is machine-readable for automated handoff
- Markdown files are human-readable for agent context loading
