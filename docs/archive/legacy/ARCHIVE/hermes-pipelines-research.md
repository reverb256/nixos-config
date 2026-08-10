# Hermes Pipelines Upgrade — Research Against Best Practices

**Date:** 2026-04-23
**Plan reviewed:** `~/.hermes/plans/2026-04-23_hermes-pipelines-upgrade.md`
**Status:** RESEARCH COMPLETE — issues and recommendations below

---

## 1. CRITICAL: `pre_tool_call` BLOCK Semantics — Verified Working

The plan claims `pre_tool_call` can BLOCK by returning `{"action": "block", "message": "reason"}`.

**VERIFIED: This is correct.** The blocking mechanism exists in `hermes_cli/plugins.py:587-623` via `get_pre_tool_call_block_message()` and is wired into `model_tools.py:495-510`. The first plugin to return a block directive wins.

```python
# CORRECT blocking pattern (verified in source)
def pre_tool_callback(tool_name, args, **kwargs):
    if should_block(tool_name, args):
        return {"action": "block", "message": "Reason for blocking"}
    return None  # Allow (None or non-block returns are ignored)
```

**However**, the official hooks documentation at `hermes-agent.nousresearch.com/docs/user-guide/features/hooks` says `pre_tool_call` return value is "ignored". This documentation is outdated — the code supports blocking. Issue #9388 was closed confirming this.

**Action:** No code change needed, but be aware that online docs may confuse future contributors.

---

## 2. Plugin Architecture — Against Official Best Practices

### 2a. Plugin Discovery is Opt-In

**Finding:** ALL plugins are disabled by default. Must be explicitly enabled in `config.yaml`:

```yaml
plugins:
  enabled:
    - nixos-guard
    - secret-scanner
```

**Plan gap:** Phase 0 creates directory structure but doesn't mention enabling the plugins in config.yaml. Without this step, nothing loads.

### 2b. `plugin.yaml` Fields

**Plan uses:**
```yaml
name: <plugin-name>
version: 1.0.0
description: <description>
provides_hooks:
  - <hook1>
```

**Official docs show:**
```yaml
name: <plugin-name>
version: 1.0.0
description: <description>
provides_tools:    # Plan MISSING this
  - <tool1>
provides_hooks:
  - <hook1>
```

**Action:** Add `provides_tools` to plugins that register tools (chain-checkpoint, session-analytics, diff-quality, repo-graph).

### 2c. File Structure

**Plan proposes:** `plugin.yaml` + `__init__.py` (2 files per plugin)

**Official guide recommends:** `plugin.yaml` + `__init__.py` + `schemas.py` + `tools.py` (4 files, separation of concerns)

**Recommendation:** For simple guard plugins (Tier 1), `__init__.py` alone is fine — the disk-cleanup bundled plugin uses this pattern. For Tier 2-3 plugins with tools, split into `schemas.py` + `tools.py` per official convention.

### 2d. Handler Contract

**Plan is correct on:** Always return JSON strings, accept `**kwargs`, catch all exceptions.

**Plan misses:** The `check_fn` parameter on `ctx.register_tool()` for conditional availability:
```python
ctx.register_tool(
    name="diff_score",
    schema=schemas.DIFF_SCORE,
    handler=tools.diff_score,
    check_fn=lambda: Path(".git").exists(),  # Only in git repos
)
```

---

## 3. Tier 1 Guards — Against Industry Best Practices

### 3a. nixos-guard (G1) — Read-Before-Write Pattern

**Industry pattern:** Arthur AI's "pre-LLM guardrails" — validate before execution. This matches the plan.

**Issue with the plan:** The "in-memory set of files read per session" state will be lost on:
- Context compression (`on_session_reset` doesn't fire for compression)
- Session reset (`/new`)
- Gateway session expiry

**Recommendation:** Persist read-set to a small SQLite or JSON file under `~/.hermes/plugins/nixos-guard/`. Reset on `on_session_start` only.

### 3b. secret-scanner (G2) — Against Industry Standards

**Industry standard:** Pre-commit + pre-push dual scanning (detect-secrets, gitleaks, trufflehog).

**Plan is correct** — does post-commit scan + pre-push block.

**Missing patterns from plan:**
1. **Entropy-based detection**: High-entropy strings (Shannon entropy > 4.5) catch secrets without known patterns. Gitleaks uses this.
2. **Allowlist/baseline**: `detect-secrets` uses `.secrets.baseline` for known false positives. Plan's `.hermes-no-secret-scan` is too coarse (disables ALL scanning). Should support per-line ignores.
3. **Git history scanning**: Plan only scans staged diff. For existing repos, add `git log -p` scanning.

**NixOS false-positive filtering** — Plan correctly identifies `/run/agenix/`, `age.secrets.`, `${...}`, `pkgs.`, `.path`. Add:
- `builtins.readFile` (reads secret at build time)
- `config.age.secrets.*.path` (runtime secret path)

### 3c. stuck-escape (G3) — Against Loop Detection Research

**Industry patterns (StuckLoopDetection, dev.to stuck-pattern):**
1. **Identical call detection** — same tool + same args repeated
2. **A-B-A-B alternating** — two tools calling each other back and forth
3. **No-op loops** — tool calls that produce zero progress

**Plan covers pattern 1 partially** (consecutive failures with same error signature).

**Missing patterns:**
- **Alternating loops**: tool A → tool B → tool A → tool B (plan only tracks "consecutive failures")
- **Progress detection**: count tokens of tool output — if output keeps shrinking or repeating, stuck
- **Budget-based escape**: absolute token budget per task (plan mentions "generation budget" but only for context saturation, not per-task limits)

**Recommendation:** Track tool call history (last 10 calls), detect both identical and alternating patterns. Use a simple hash of `(tool_name, frozen_args)` for dedup.

### 3d. imperative-tracker (G4) — Novel but Sound

**Industry analog:** Infrastructure-as-Code drift detection (snyk/driftctl, Terraform state drift).

**Plan pattern matches** — detect imperative changes, track as "drift", block deployments with uncodified drift.

**Issue:** The detection regex patterns will false-positive on:
- `systemctl status` (read-only)
- `systemctl is-active` (read-only)
- `echo "hello" >> /tmp/test` (not system state)

**Fix:** Only match destructive systemctl verbs AND require path prefixes under /etc/, /var/lib/, or NixOS-managed directories.

### 3e. subagent-guard (G5) — Matches Industry Practice

**Industry pattern:** "Enforce scope at the allowed-tools level" (foojay.io best practices). Default-deny for subagents.

**Plan is correct.** One enhancement: also block `execute_code` targeting NixOS paths, not just `delegate_task`.

---

## 4. Tier 2 Intelligence — Against Best Practices

### 4a. brain-context (I1) — Context Injection Pattern

**Plan uses `pre_llm_call` for context injection — CORRECT.** This is the official pattern:
```python
return {"context": "Recalled: ..."}
```

**Key constraint from docs:** Injected context goes into the **user message**, NOT the system prompt. This preserves prompt caching. Plan doesn't mention this, but it doesn't need to — the framework handles it automatically.

**Issue:** Plan says "Every 15th LLM call, inject reminder." This will be noisy and waste tokens. Better approach: inject only when imperative-fixes.json has new entries since last injection.

### 4b. style-scout (I2) — Auto-Formatter Risk

**Industry consensus:** Auto-formatting in AI agents is dangerous because:
1. AI-generated diffs become huge (formatter changes unrelated lines)
2. Git blame becomes meaningless
3. Mixes formatting changes with logic changes

**Recommendation:** Don't auto-run formatters. Instead, inject style rules as context so the model generates correctly-styled code from the start. Only auto-format if the user explicitly asks.

### 4c. diff-quality (I3) — Scoring Metrics

**Industry metrics (AugmentCode, Codacy, Atlassian):**
1. Cyclomatic complexity change
2. Code churn (lines added+deleted/total)
3. Test-to-code ratio
4. File count per PR/diff

**Plan's metrics are reasonable** but missing:
- **Code churn rate** — high churn indicates thrashing
- **Test coverage delta** — are new tests added for new code?

**Scoring threshold of 70** is arbitrary. Better to make it configurable per project.

### 4d. repo-graph (I4) — Good Pattern, Minor Concerns

**SQLite scanning is fine** but should be lazy-loaded on `on_session_start`, not eager. The `on_session_start` hook fires once per session — if Hermes has many short sessions, scanning large repos on every start adds latency.

**Recommendation:** Cache scan results, only rescan if `git HEAD` changed.

---

## 5. Tier 3 Pipeline — Against Best Practices

### 5a. chain-checkpoint (P1)

**Good pattern.** The SQLite storage is appropriate. One issue:

**Plan says "parse subagent-artifacts/" — this assumes a specific directory layout.** Should be configurable or auto-detected.

### 5b. session-analytics (P2)

**Good pattern.** Metrics (tokens, duration, tool calls, success/fail) are standard.

**Missing metric:** Cost estimation (tokens * model price). This is valuable for the ZAI expiry deadline.

### 5c. commit-hygiene (P5)

**Good pattern.** The `.gitignore` auto-update is smart.

**Issue:** `git reset HEAD <file>` to unstage artifacts will fail if run from a non-git directory. Add a guard.

---

## 6. Cross-Cutting Concerns

### 6a. Opt-Out / Escape Hatches

**Plan only has opt-out for secret-scanner** (`.hermes-no-secret-scan`).

**Industry best practice (Fast.io, Arthur AI):** Every hard guard needs an escape hatch for emergencies. Recommended pattern:

```python
# Check for emergency bypass
if os.environ.get(f"HERMES_BYPASS_{plugin_name.upper()}"):
    return None  # Allow
```

This lets you temporarily disable a stuck guard without editing config.

### 6b. Error Recovery

**Plan has no recovery procedure** when a guard blocks incorrectly.

**Recommendation:** Each block message should include a hint:
```python
return {"action": "block", "message": "File not read in current session. Read it first, or set HERMES_BYPASS_NIXOS_GUARD=1 to override."}
```

### 6c. Plugin Loading Order

**Plan doesn't address this.** Discovery order is alphabetical by directory name. If `imperative-tracker` loads before `nixos-guard`, the colmena block might not have the full fix list.

**Recommendation:** Both G1 and G4 read from the same `imperative-fixes.json` file, so order doesn't matter for data. But ensure there's no race condition on concurrent writes.

### 6d. Thread Safety

**Official docs require:** `sync_turn()` and hooks must be non-blocking. Use daemon threads for I/O.

**Plan's Tier 1 guards are fine** (in-memory state, no I/O in hooks). **Tier 2-3 plugins with SQLite** must use locks or write in background threads.

---

## 7. BOOT.md — Against Official Pattern

**Official docs show BOOT.md runs as a gateway hook.** The plan treats it as a startup checklist.

**Key insight from docs:** BOOT.md instructions run in a **background thread** and can call tools. This means BOOT.md can:
- Run `kubectl get nodes` directly
- Run `hermes cron list` directly
- Check imperative-fixes.json staleness

**Plan's approach is correct** but underestimates what BOOT.md can do.

---

## 8. Testing Strategy — Gaps

**Plan proposes:** 3 tests per plugin (happy, block, bypass) via manual interaction.

**Official plugin testing pattern:**
```python
from agent.memory_manager import MemoryManager
mgr = MemoryManager()
mgr.add_provider(my_provider)
mgr.initialize_all(session_id="test-1", platform="cli")
result = mgr.handle_tool_call("my_tool", {"action": "add", "content": "test"})
```

**Recommendation:** Write automated tests in Python that can be run via `hermes chat -q` or as standalone scripts. Don't rely solely on manual testing.

---

## Summary Table

| Plugin | Plan Status | Critical Fix Needed? | Action |
|--------|------------|---------------------|--------|
| nixos-guard (G1) | Good | Yes — persist read-set | Add JSON/SQLite persistence |
| secret-scanner (G2) | Good | No | Add entropy detection + baseline |
| stuck-escape (G3) | Partial | Yes — add alternating detection | Track tool call history |
| imperative-tracker (G4) | Good | Yes — filter read-only verbs | Add verb whitelist |
| subagent-guard (G5) | Good | No | Also block execute_code |
| brain-context (I1) | Good | Minor — reduce injection freq | Inject on change, not every 15th call |
| style-scout (I2) | Risky | Yes — remove auto-format | Inject style rules only |
| diff-quality (I3) | Good | No | Add churn metric |
| chain-checkpoint (P1) | Good | No | Make artifact path configurable |
| session-analytics (P2) | Good | No | Add cost estimation |
| repo-graph (I4) | Good | Minor — cache scans | Check git HEAD before rescan |
| commit-hygiene (P5) | Good | No | Add git-dir guard |

**Cross-cutting:** Add bypass env vars, block message hints, config.yaml enable step.

---

## Sources

- [Hermes Agent Hooks Documentation](https://hermes-agent.nousresearch.com/docs/user-guide/features/hooks)
- [Build a Hermes Plugin Guide](https://hermes-agent.nousresearch.com/docs/guides/build-a-hermes-plugin/)
- [Hermes Tools Runtime](https://hermes-agent.nousresearch.com/docs/developer-guide/tools-runtime)
- [Context Engine Plugin Guide](https://hermes-agent.nousresearch.com/docs/developer-guide/context-engine-plugin)
- [Memory Provider Plugin Guide](https://hermes-agent.nousresearch.com/docs/developer-guide/memory-provider-plugin)
- [Hermes Plugins Overview](https://hermes-agent.nousresearch.com/docs/user-guide/features/plugins)
- [GitHub Issue #9388: pre_tool_call REJECT semantics](https://github.com/NousResearch/hermes-agent/issues/9388)
- [Bundled plugin: disk-cleanup](https://github.com/NousResearch/hermes-agent/tree/main/plugins/disk-cleanup)
- [Arthur AI: Best Practices for Building Agents — Guardrails](https://www.arthur.ai/blog/best-practices-for-building-agents-guardrails)
- [Fast.io: AI Agent Guardrails — 7 Essential Safety Controls](https://fast.io/resources/ai-agent-guardrails/)
- [Agentic AI Safety & Guardrails 2025](https://skywork.ai/blog/agentic-ai-safety-best-practices-2025-enterprise/)
- [StuckLoopDetection: Stopping $12 Burn on 47 Identical Calls](https://medium.com/@kacperwlodarczyk/stuckloopdetection-how-we-stopped-an-agent-burning-12-on-47-identical-calls-a12b5ea1f193)
- [7 Patterns That Stop Your AI Agent From Going Rogue](https://dev.to/pockit_tools/7-patterns-that-stop-your-ai-agent-from-going-rogue-in-production-5hb1)
- [Detect-secrets Best Practices](https://medium.com/@mabhijit1998/pre-commit-and-detect-secrets-best-practises-6223877f39e4)
- [Truffle Security: Do Pre-Commit Hooks Prevent Secrets Leakage?](https://trufflesecurity.com/blog/do-pre-commit-hooks-prevent-secrets-leakage)
- [Codacy: 8 Code Quality Metrics](https://blog.codacy.com/code-quality-metrics)
- [AugmentCode: Code Review Best Practices That Scale](https://www.augmentcode.com/guides/code-review-best-practices-that-scale)
- [snyk/driftctl: Infrastructure Drift Detection](https://github.com/snyk/driftctl)
