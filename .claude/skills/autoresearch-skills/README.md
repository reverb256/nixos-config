# Skill Autoresearch - Self-Improving Skill Optimization

Apply the Karpathy autoresearch pattern to **Claude Code skill optimization**. Automatically evolves your skills through continuous testing and mutation.

## What It Does

Every 5 minutes, the system:
1. **Tests** your skill against a suite of real-world scenarios
2. **Scores** each test case across 5 criteria (triggering, workflow, errors, quality, intent)
3. **Evolves** the skill — keeps improvements, discards regressions
4. **Mutates** the best version to try new variations
5. **Logs** everything for analysis and review

## Quick Start

```bash
cd /etc/nixos/.claude/skills/autoresearch-skills

# Install dependencies
pip install -r requirements.txt

# Set up environment
export ANTHROPIC_API_KEY="sk-ant-..."
export CLAUDE_CODE_PATH="/etc/nixos"
export SKILL_NAME="nix-rebuild"  # or any skill name

# Run single cycle (test)
python3 autoresearch.py --once

# Run continuous loop
python3 autoresearch.py

# Start dashboard (in another terminal)
python3 dashboard.py --port 8502
# Open http://localhost:8502
```

## How It Works

### Test Suites

Each skill has a test suite with 3 types of test cases:

**Positive Cases** — Skill SHOULD trigger:
```json
{
  "id": 1,
  "type": "positive",
  "query": "rebuild",
  "expected_behavior": ["Asks which host", "Runs flake check"],
  "forbidden_actions": ["Auto-runs switch", "Skips checks"]
}
```

**Negative Cases** — Skill should NOT trigger:
```json
{
  "id": 2,
  "type": "negative",
  "query": "what's the weather",
  "expected_behavior": ["Skill does NOT trigger"],
  "forbidden_actions": ["Executes nix commands"]
}
```

**Edge Cases** — Tricky situations:
```json
{
  "id": 3,
  "type": "edge_case",
  "query": "rebuild but don't ask me anything",
  "expected_behavior": ["Acknowledges preference", "Still runs safety checks"],
  "forbidden_actions": ["Skips flake check"]
}
```

### Evaluation Criteria

Each test case is scored 0-100 across 5 dimensions:

1. **Correct Triggering (20 pts)** — Did it activate appropriately?
2. **Workflow Adherence (20 pts)** — Did it follow the prescribed steps?
3. **Error Avoidance (20 pts)** — Did it avoid common mistakes?
4. **Output Quality (20 pts)** — Was the output clear and actionable?
5. **User Intent (20 pts)** — Did it solve the user's problem?

### Mutation Strategies

The system uses 5 mutation strategies (selected randomly each cycle):

1. **Add Example** — Insert new few-shot examples
2. **Clarify Rule** — Strengthen ambiguous instructions
3. **Add Warning** — Emphasize critical constraints
4. **Simplify** — Remove redundant text
5. **Reorder** — Improve flow and organization

## File Structure

```
.claude/skills/autoresearch-skills/
├── SKILL.md              # This file
├── autoresearch.py       # Main optimization loop
├── dashboard.py          # Streamlit dashboard
├── requirements.txt      # Python dependencies
└── data/
    ├── skills/
    │   ├── nix-rebuild.md           # Current skill version
    │   ├── best_nix-rebuild.md      # Best version found
    │   ├── run_001_nix-rebuild.md   # Run-specific versions
    │   └── ...
    ├── state.json                   # Run state, best score
    ├── results.jsonl                # All test results
    └── runs/
        ├── run_001/                 # Per-run logs
        └── ...
```

## Dashboard Features

- **Live score tracking** — Watch your skill improve over time
- **Test case breakdown** — See which tests pass/fail
- **Criterion analysis** — Identify weak areas
- **Version comparison** — Compare skill iterations
- **Mutation history** — Track what changed

## Cost Estimation

**Per 5-minute cycle**:
- 4 test case executions (Sonnet 4)
- 4 evaluations (Opus 4)
- 1 mutation (Sonnet 4)

**Estimated**: $0.05-0.15 per cycle = $0.60-1.80/hour

**Recommended**: Run overnight (100 cycles) = $5-15 total

## Safety Features

✅ **Dry-run mode** — No destructive commands executed
✅ **Isolated testing** — Tests don't affect your actual skills
✅ **Rollback protection** — Always keep best version
✅ **Cost tracking** — Monitor API spend in real-time

## Best Practices

### 1. Start Simple
Begin with a skill that has:
- Clear trigger conditions
- Well-defined workflow
- Easy-to-test behavior

Good candidates: `nix-rebuild`, `akash`, `knowledge-fabric`

### 2. Write Good Test Suites
- 3-5 positive cases (common scenarios)
- 2-3 negative cases (should NOT trigger)
- 2-3 edge cases (tricky situations)

### 3. Review Regularly
Check the dashboard every few hours:
- Is the score improving?
- Are there stuck test cases?
- Is the mutation direction helpful?

### 4. Manual Intervention
When score plateaus:
1. Examine top 3 versions
2. Identify common failure patterns
3. Manually adjust skill
4. Restart autoresearch

### 5. Apply Improvements
When satisfied with results:
```bash
# Copy best version to actual skills
cp data/skills/best_nix-rebuild.md \
   /etc/nixos/.claude/skills/nix-rebuild/SKILL.md

# Commit to git
cd /etc/nixos
git add .claude/skills/nix-rebuild/SKILL.md
git commit -m "feat(nix-rebuild): Auto-optimized via autoresearch"
```

## Example Workflow

```bash
# Terminal 1: Run autoresearch overnight
cd /etc/nixos/.claude/skills/autoresearch-skills
export SKILL_NAME="knowledge-fabric"
python3 autoresearch.py

# Terminal 2: Monitor dashboard
python3 dashboard.py --port 8502
# Open http://localhost:8502

# Next morning: Review results
# 1. Check dashboard for best score
# 2. Examine top 3 skill versions
# 3. Manually inspect and test
# 4. Apply winner to production
# 5. Commit changes
```

## Advanced Usage

### Custom Test Suites

Create test suites for any skill:

```python
# autoresearch.py
TEST_SUITES = {
    "your-skill": [
        {
            "id": 1,
            "type": "positive",
            "query": "your trigger phrase",
            "expected_behavior": ["Should do X", "Should do Y"],
            "forbidden_actions": ["Should NOT do Z"]
        },
        # ... more test cases
    ]
}
```

### Adjust Cycle Time

```python
# autoresearch.py (line ~450)
time.sleep(300)  # 5 minutes → change to 60 for 1 minute
```

### Change Mutation Strategies

```python
# autoresearch.py (line ~150)
MUTATION_STRATEGIES = [
    "add_example",
    "your_custom_strategy",  # Add new strategy
]
```

## Troubleshooting

**Issue**: Score stuck at 0
- **Fix**: Check test suite matches skill format
- **Fix**: Verify skill trigger keywords are correct

**Issue**: No improvement after 20 cycles
- **Fix**: Add more diverse test cases
- **Fix**: Manually improve base skill
- **Fix**: Try different mutation strategies

**Issue**: Too many false positives
- **Fix**: Add more negative test cases
- **Fix**: Strengthen trigger keyword requirements

## Comparison with Diagram Autoresearch

| Aspect | Diagram Autoresearch | Skill Autoresearch |
|--------|---------------------|-------------------|
| **Output** | Images (Gemini) | Text (Claude Code) |
| **Evaluation** | Vision model | LLM judge |
| **Criteria** | 4 visual (40 pts) | 5 behavioral (100 pts) |
| **Test Suite** | Diagram topics | Positive/negative/edge cases |
| **Cost/Cycle** | ~$0.50-1.00 | ~$0.05-0.15 |
| **Cycle Time** | 2 minutes | 5 minutes |

## Future Enhancements

**Planned features**:
- [ ] Multi-objective optimization (speed vs quality)
- [ ] A/B testing between skill branches
- [ ] Automatic test case generation
- [ ] Integration with Claude Code API for real testing
- [ ] Multi-skill optimization (compatible skill sets)
- [ ] Transfer learning between skills

## Contributing

Ideas and improvements welcome! Consider:
- New evaluation criteria
- Better mutation strategies
- Additional test case patterns
- Dashboard enhancements

## License

MIT License — Feel free to adapt and use in your own projects.

---

**Version**: 1.0.0
**Last Updated**: 2026-03-23
**Author**: Adapted from Karpathy autoresearch pattern
