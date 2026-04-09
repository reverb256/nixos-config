---
name: gateway-code-worker
description: Worker for AI Inference Gateway Python code changes (debug cleanup, refactoring, dead code removal)
---

# Gateway Code Worker

NOTE: Startup and cleanup are handled by `mission-worker-base`. This skill defines the WORK PROCEDURE.

## When to Use This Skill

Features that involve editing Python files in the AI Inference Gateway (`/etc/nixos/modules/services/ai-inference/ai_inference_gateway/`).

## Required Skills

None (all tools are standard bash/Python)

## Work Procedure

1. **Read the feature description** - understand exactly which code changes are needed
2. **Enter the gateway shell**: `nix-shell /etc/nixos/modules/services/ai-inference/ai_inference_gateway/shell.nix`
3. **Read target files** - understand existing patterns before editing
4. **Make changes following gateway conventions**:
   - Use `logger.debug()` instead of `print()` to stderr
   - Follow existing import patterns (try/except with availability flags)
   - Use Pydantic config classes for configurable values
   - Keep the middleware pipeline pattern intact
5. **Run tests**: `nix-shell shell.nix --run "pytest tests/ -v"` (from gateway directory)
6. **Run tests specific to changed area**: e.g., `pytest tests/test_pipeline.py -v`
7. **Verify no import errors**: `nix-shell shell.nix --run "python -c 'from ai_inference_gateway.main import create_app'"`
8. **Commit**: Stage only changed files

## Important Notes

- The gateway runs in K8s - do NOT try to restart it
- Tests run with mocks - no K8s, Redis, or Qdrant needed
- Python 3.13 is the target version
- main.py is 5000+ lines - be careful with edits, use line-specific replacements
- Do NOT modify the NixOS module files (default.nix, gateway.nix) unless explicitly in the feature

## Example Handoff

```json
{
  "salientSummary": "Replaced 42 print() debug statements in main.py with logger.debug() calls. Deleted model_defaults.py (513 lines dead code). Fixed 2 hardcoded stale IPs (10.0.0.102) in searxng files.",
  "whatWasImplemented": "Replaced all [DEBUG] and [LIFESPAN DEBUG] print statements in main.py with logger.debug() using existing logger instance. Deleted model_defaults.py entirely (never imported anywhere). Replaced hardcoded 10.0.0.102 with config references in searxng_exports.py and searxng_source.py.",
  "whatWasLeftUndone": "",
  "verification": {
    "commandsRun": [
      { "command": "rg -c 'print\\(' main.py", "exitCode": 0, "observation": "0 remaining print statements" },
      { "command": "test -f model_defaults.py", "exitCode": 1, "observation": "File deleted" },
      { "command": "rg '10\\.0\\.0\\.102' .", "exitCode": 1, "observation": "No stale IPs remaining" },
      { "command": "nix-shell shell.nix --run 'pytest tests/ -v --tb=short'", "exitCode": 0, "observation": "All 21 test files passed" }
    ],
    "interactiveChecks": []
  },
  "tests": { "added": [] },
  "discoveredIssues": [
    { "severity": "non_blocking", "description": "test_redis_client.py has some tests that try to connect to actual Redis - they pass when Redis is available but may fail otherwise", "suggestedFix": "Add pytest.mark.skipif for Redis-dependent tests" }
  ]
}
```

## When to Return to Orchestrator

- Tests fail and the fix requires changes outside the feature scope
- Found code that is dead but referenced by another module (potential breaking change)
- Changes would require a gateway container rebuild to take effect
