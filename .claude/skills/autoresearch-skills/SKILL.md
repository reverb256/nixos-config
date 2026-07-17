---
name: autoresearch-skills
description: Self-improving skill optimization using the Karpathy autoresearch pattern. Tests skills against evaluation suites, scores outputs, mutates skill instructions, keeps winners. Includes live dashboard for tracking evolution.
disable-model-invocation: false
---

# Skill Autoresearch — Self-Improving Skill Optimization

## What It Does

Applies the Karpathy autoresearch pattern to **Claude Code skill optimization**. Every cycle:
1. **Executes** current skill against test suite (real Claude Code invocations)
2. **Evaluates** each output against criteria via LLM judge (score out of 100)
3. **Keeps** the skill if it beats the best score, discards otherwise
4. **Mutates** the best skill instructions to try to improve further
5. **Logs** everything to JSONL for tracking

## Quick Start

```bash
# Run continuous loop (every 5 minutes)
python3 .claude/skills/autoresearch-skills/autoresearch.py

# Single cycle (test)
python3 .claude/skills/autoresearch-skills/autoresearch.py --once

# Run N cycles
python3 .claude/skills/autoresearch-skills/autoresearch.py --cycles 10

# Start the live dashboard
python3 .claude/skills/autoresearch-skills/dashboard.py --port 8502
# Then open http://localhost:8502
```

## Environment

**Required:**
```bash
pip install anthropic streamlit pandas python-dotenv
```

**Environment Variables:**
```bash
export ANTHROPIC_API_KEY="sk-ant-..."
export CLAUDE_CODE_PATH="/etc/nixos"  # Path to your project
```

## File Structure

```
.claude/skills/autoresearch-skills/
  SKILL.md              # This file
  autoresearch.py       # Main execute → eval → mutate loop
  dashboard.py          # Live web dashboard (Streamlit)
  data/
    skills/
      nix-rebuild.md     # Current skill being optimized
      best_nix-rebuild.md  # Best skill found so far
    test_cases/
      nix-rebuild.jsonl  # Test suite for this skill
    state.json          # Loop state (run number, best score)
    results.jsonl       # Append-only experiment log
    runs/
      run_001/          # Logs and outputs per run
      run_002/
      ...
```

## Models

- **Execution**: Claude Sonnet 4 (via Claude Code API)
- **Evaluation**: Claude Opus 4 (via Anthropic API)
- **Mutation**: Claude Sonnet 4 (via Anthropic API)

## Dashboard Features

- **Live score tracking** — See skill improvement over time
- **Side-by-side comparisons** — Compare skill versions
- **Test case breakdown** — See which tests pass/fail
- **Mutation history** — Track what changed between versions
- **Cost tracking** — Monitor API spend per run

## Cost

**Per cycle** (varies by skill complexity):
- 10 test case executions (Claude Sonet)
- 10 evaluations (Claude Opus)
- 1 mutation (Claude Sonet)

**Estimated**: ~$0.10-0.30 per cycle (depending on test case complexity)

## Eval Criteria

Skills are scored on 5 criteria (20 points each = 100 max):

### 1. Correct Triggering (20 pts)
- Did the skill activate for its intended queries?
- Did it avoid activating for unrelated queries?
- **Measured by**: Test suite with positive/negative examples

### 2. Workflow Adherence (20 pts)
- Did the skill follow its prescribed steps?
- Were all critical steps executed in order?
- **Measured by**: Checklist evaluation of output

### 3. Error Avoidance (20 pts)
- Did the skill avoid common mistakes?
- Did it handle edge cases correctly?
- **Measured by**: Test suite with edge cases

### 4. Output Quality (20 pts)
- Was the final output clear and actionable?
- Did it provide the right level of detail?
- **Measured by**: LLM judge evaluation

### 5. User Intent (20 pts)
- Did the skill solve the user's actual problem?
- Was the response helpful and appropriate?
- **Measured by**: Simulated user feedback

## Example Test Suite

```json
{
  "skill": "nix-rebuild",
  "test_cases": [
    {
      "id": 1,
      "type": "positive",
      "query": "rebuild",
      "expected_behavior": [
        "Asks which host",
        "Runs nix flake check",
        "Runs nixos-rebuild build"
      ],
      "forbidden_actions": [
        "Automatically runs switch",
        "Skips the check step"
      ]
    },
    {
      "id": 2,
      "type": "negative",
      "query": "what's the weather",
      "expected_behavior": [
        "Skill does NOT trigger"
      ],
      "forbidden_actions": [
        "Executes any nix commands"
      ]
    },
    {
      "id": 3,
      "type": "edge_case",
      "query": "rebuild but don't ask me anything",
      "expected_behavior": [
        "Acknowledges preference",
        "Still runs safety checks"
      ],
      "forbidden_actions": [
        "Skips nix flake check"
      ]
    }
  ]
}
```

## Mutation Strategies

The system uses 5 mutation strategies (selected randomly):

1. **Add Example** — Insert a new few-shot example
2. **Clarify Rule** — Strengthen ambiguous instructions
3. **Add Warning** — Emphasize critical constraints
4. **Simplify** — Remove redundant text
5. **Reorder** — Reorganize sections for clarity

## Evaluation Prompt Template

```
You are evaluating a skill's performance on a test case.

Test Case: {test_case}
User Query: {query}
Skill Output: {output}

Score (0-20 on each criterion):
1. CORRECT_TRIGGERING: Did the skill activate appropriately?
2. WORKFLOW_ADHERENCE: Did it follow the prescribed steps?
3. ERROR_AVOIDANCE: Did it handle edge cases correctly?
4. OUTPUT_QUALITY: Was the output clear and actionable?
5. USER_INTENT: Did it solve the user's problem?

Provide scores and reasoning.
```

## Dashboard Usage

```bash
# Start dashboard
python3 .claude/skills/autoresearch-skills/dashboard.py

# View at http://localhost:8502

Features:
- Real-time score charts
- Test case pass/fail breakdown
- Skill version diff viewer
- Mutation history explorer
- Cost tracking per run
```

## Integration with Claude Code

**Best workflow:**
1. Start autoresearch on a skill
2. Let it run overnight (100+ cycles)
3. Review dashboard in morning
4. Manually inspect top 3 skill versions
5. Apply winner to `.claude/skills/`
6. Commit improved skill to git

## Safety

**Built-in guardrails:**
- All tests run in isolated environment
- No destructive commands executed
- Dry-run mode for testing
- Automatic rollback on error

**For skills like nix-rebuild:**
- Replace `sudo nixos-rebuild switch` with `--dry-run`
- Never auto-confirm user prompts
- Log all commands for review
