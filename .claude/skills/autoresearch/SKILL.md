---
name: autoresearch
description: Self-improving skill optimizer. Automatically tests, scores, and evolves Claude Code skills using the Karpathy autoresearch pattern. Specify which skill to optimize, auto-generates test suites, runs continuous improvement cycles. Usage: "autoresearch nix-rebuild" or "autoresearch knowledge-fabric"
disable-model-invocation: false
---

# Autoresearch — Self-Improving Skill Optimizer

## 🧬 What It Does

Automatically optimizes **any Claude Code skill** through continuous testing and evolution:
1. **Analyzes** skill structure and auto-generates test suite
2. **Tests** skill against diverse scenarios (positive, negative, edge cases)
3. **Scores** outputs across 5 criteria (triggering, workflow, errors, quality, intent)
4. **Evolves** instructions — keeps improvements, discards regressions
5. **Mutates** best version using 5 strategies
6. **Logs** everything for analysis and review

## 🎯 Quick Start

```
User: autoresearch nix-rebuild
Model: [ANALYZE] Skill structure...
      [GENERATE] Test suite (8 cases)...
      [RUN] Optimization loop (every 5 min)...
      [MONITOR] Dashboard at http://localhost:8502
```

**Parameters:**
- `skill_name` — Which skill to optimize (required)
- `cycles` — Number of cycles (optional, default: continuous)
- `interval` — Minutes between cycles (optional, default: 5)

## 📋 Step-by-Step Workflow

### Step 1: Analyze Skill Structure

When invoked, first analyze the target skill:

```bash
# Find skill location
ls -la .claude/skills/{SKILL_NAME}/SKILL.md

# Extract key components:
# - Trigger keywords
# - Workflow steps
# - Examples/few-shot cases
# - Critical rules/constraints
# - Common mistakes to avoid
```

### Step 2: Auto-Generate Test Suite

Create 8-12 test cases automatically:

**Positive Cases (3-4)** — Skill SHOULD trigger:
- Extract from trigger keywords
- Use few-shot examples as templates
- Cover common scenarios

**Negative Cases (2-3)** — Skill should NOT trigger:
- Unrelated queries
- Similar but different domains
- Edge cases that should be handled by other skills

**Edge Cases (3-4)** — Tricky situations:
- Ambiguous queries
- Conflicting instructions
- User overrides/preferences
- Error scenarios

### Step 3: Run Optimization Loop

Every cycle (default: 5 minutes):

```python
# 1. Load current skill version
skill = load_skill(skill_name)

# 2. Run test suite
for test_case in test_suite:
    output = execute_skill(skill, test_case.query)
    score = evaluate(output, test_case.criteria)

# 3. Compare with best
if avg_score > best_score:
    save_as_best(skill)
    mutate_skill(skill)
else:
    revert_to_best()
    mutate_skill(best_skill)

# 4. Log results
log_results(run_number, scores, mutations)
```

### Step 4: Monitor Progress

Start dashboard for real-time monitoring:

```bash
python3 .claude/skills/autoresearch/dashboard.py --skill {SKILL_NAME}
```

Dashboard shows:
- Score progression over time
- Test case pass/fail breakdown
- Criterion-level analysis
- Mutation history
- Cost tracking

## 🔧 Test Suite Generation Algorithm

```python
def generate_test_suite(skill_content):
    """Auto-generate test suite from skill structure."""

    # Extract trigger keywords
    triggers = extract_triggers(skill_content)

    # Extract workflow steps
    workflow = extract_workflow(skill_content)

    # Extract few-shot examples
    examples = extract_examples(skill_content)

    # Generate positive cases
    positive_cases = [
        create_test_from_example(example)
        for example in examples[:3]
    ]

    # Generate negative cases
    negative_cases = [
        create_negative_test(triggers, similar_domains)
        for similar_domains in get_similar_skills(skill_name)
    ]

    # Generate edge cases
    edge_cases = [
        create_ambiguity_test(workflow),
        create_override_test(workflow),
        create_error_test(workflow),
        create_constraint_test(skill_content)
    ]

    return positive_cases + negative_cases + edge_cases
```

## 📊 Evaluation Criteria

Each test case scored 0-100 across 5 dimensions:

### 1. Correct Triggering (20 pts)
- **20 pts**: Triggered correctly for positive cases, NOT triggered for negative
- **10 pts**: Partial triggering (some false positives/negatives)
- **0 pts**: Failed to trigger or triggered incorrectly

### 2. Workflow Adherence (20 pts)
- **20 pts**: Followed all expected steps in correct order
- **10 pts**: Followed most steps, minor deviations
- **0 pts**: Major workflow violations or skipped critical steps

### 3. Error Avoidance (20 pts)
- **20 pts**: Avoided all forbidden actions
- **10 pts**: Minor issues, recovered well
- **0 pts**: Executed forbidden actions or critical errors

### 4. Output Quality (20 pts)
- **20 pts**: Clear, actionable, appropriate detail
- **10 pts**: Understandable but verbose or terse
- **0 pts**: Confusing, missing critical info, or unhelpful

### 5. User Intent (20 pts)
- **20 pts**: Fully addressed user's need
- **10 pts**: Partially addressed
- **0 pts**: Missed user's intent entirely

## 🧬 Mutation Strategies

5 strategies (selected randomly each cycle):

### 1. Add Example
Insert new few-shot example illustrating edge case or clarifying workflow.

### 2. Clarify Rule
Strengthen ambiguous instructions with specific constraints or examples.

### 3. Add Warning
Emphasize critical constraint with prominent warning section (⚠️).

### 4. Simplify
Remove redundant text while preserving essential information.

### 5. Reorder
Reorganize sections for better flow and logical progression.

## 💻 Implementation

**File Structure:**
```
.claude/skills/autoresearch/
├── SKILL.md                    # This file
├── optimizer.py                # Main optimization loop
├── test_generator.py           # Auto-generate test suites
├── evaluator.py                # Score skill outputs
├── mutator.py                  # Mutate skill instructions
├── dashboard.py                # Streamlit dashboard
├── data/
│   ├── {skill_name}/
│   │   ├── current.md          # Current skill version
│   │   ├── best.md             # Best version found
│   │   ├── test_suite.json     # Generated test suite
│   │   ├── state.json          # Run state, best score
│   │   ├── results.jsonl       # All test results
│   │   └── runs/
│   │       ├── run_001/
│   │       └── ...
```

**Dependencies:**
```bash
pip install anthropic streamlit pandas plotly python-dotenv
```

**Environment:**
```bash
export ANTHROPIC_API_KEY="sk-ant-..."
export CLAUDE_CODE_PATH="/etc/nixos"
```

## 🎮 Usage Examples

### Example 1: Optimize nix-rebuild skill

```
User: autoresearch nix-rebuild
Model: 🔍 Analyzing nix-rebuild skill...
      ✅ Found 3 trigger keywords: rebuild, deploy, switch
      ✅ Extracted 4-step workflow
      ✅ Found 2 few-shot examples

      📋 Generated 10 test cases:
         - 4 positive cases
         - 3 negative cases
         - 3 edge cases

      🚀 Starting optimization loop (every 5 min)...
      📊 Dashboard: http://localhost:8502

      [Run 1] Score: 72/100 → Best: 72/100
      [Run 2] Score: 68/100 → Keeping best (72/100)
      [Run 3] Score: 79/100 → New best! ✨
      ...
```

### Example 2: Optimize knowledge-fabric skill

```
User: autoresearch knowledge-fabric 10 cycles every 3 minutes
Model: 🔍 Analyzing knowledge-fabric skill...
      ✅ Found 8 MCP tools
      ✅ Extracted query classification logic
      ✅ Identified critical rule: NO API calls

      📋 Generated 12 test cases:
         - 5 positive cases (code, research, devops, general)
         - 4 negative cases (API calls, HTTP requests)
         - 3 edge cases (mixed queries, ambiguous intent)

      🚀 Running 10 cycles (3 min interval)...
      ⏱️  Estimated time: 30 minutes
      💰 Estimated cost: $1.50

      [Run 1] Score: 65/100
      [Run 2] Score: 71/100 → New best! ✨
      ...
      [Run 10] Score: 84/100

      ✅ Complete! Best score improved from 65 → 84/100
      📁 Best version saved to: data/knowledge-fabric/best.md
      📊 Full results: data/knowledge-fabric/results.jsonl

      Next: Review top 3 versions and apply winner to production?
```

### Example 3: Check current optimization status

```
User: autoresearch status
Model: 📊 Active optimizations:

      nix-rebuild:
        - Runs: 47
        - Best score: 82/100
        - Started: 2 hours ago
        - Status: Running...
        - Dashboard: http://localhost:8502

      knowledge-fabric:
        - Runs: 12
        - Best score: 76/100
        - Started: 45 min ago
        - Status: Running...
        - Dashboard: http://localhost:8503
```

## 🛡️ Safety Features

- ✅ **Dry-run mode** — No destructive commands executed
- ✅ **Isolated testing** — Tests don't affect production skills
- ✅ **Rollback protection** — Always keep best version
- ✅ **Cost tracking** — Monitor API spend in real-time
- ✅ **Auto-pause** — Stops if score plateaus for 10 cycles
- ✅ **Manual review** — Always ask before applying to production

## 📈 Best Practices

### 1. Start Simple
Begin with skills that have:
- Clear trigger conditions
- Well-defined workflows
- Existing few-shot examples

**Good candidates:** nix-rebuild, knowledge-fabric, akash

### 2. Review Generated Tests
Always review auto-generated test suite before starting:
```bash
cat data/{skill_name}/test_suite.json
```

### 3. Monitor Dashboard
Check dashboard every few hours:
- Is score improving?
- Are tests passing/failing as expected?
- Any stuck test cases?

### 4. Manual Intervention
When score plateaus:
1. Examine top 3 versions
2. Identify failure patterns
3. Manually adjust skill
4. Restart autoresearch

### 5. Apply Improvements
When satisfied:
```bash
# Copy best version to production
cp data/{skill_name}/best.md \
   .claude/skills/{skill_name}/SKILL.md

# Commit changes
git add .claude/skills/{skill_name}/SKILL.md
git commit -m "feat({skill_name}): Auto-optimized via autoresearch"
```

## 🔍 Troubleshooting

**Issue**: Auto-generated tests are poor quality
- **Fix**: Manually curate test_suite.json
- **Fix**: Add more few-shot examples to source skill

**Issue**: Score stuck at 0
- **Fix**: Check trigger keywords are correct
- **Fix**: Verify skill format is valid

**Issue**: No improvement after 20 cycles
- **Fix**: Add more diverse test cases
- **Fix**: Manually improve base skill
- **Fix**: Try different mutation strategies

**Issue**: Too many false positives
- **Fix**: Add more negative test cases
- **Fix**: Strengthen trigger requirements

## 💡 Advanced Usage

### Custom Test Suites

Override auto-generation with custom tests:

```bash
# Create custom test suite
cat > data/{skill_name}/test_suite.json <<'EOF'
{
  "test_cases": [
    {
      "id": 1,
      "type": "positive",
      "query": "your custom test",
      "expected_behavior": ["Should do X"],
      "forbidden_actions": ["Should NOT do Y"]
    }
  ]
}
EOF

# Run with custom tests
autoresearch {skill_name} --use-custom-tests
```

### Adjust Mutation Weights

Prioritize specific strategies:

```bash
autoresearch {skill_name} --mutation-weights add_example=40 clarify=30 simplify=10 warn=10 reorder=10
```

### Multi-Skill Optimization

Optimize multiple skills in parallel:

```bash
# Terminal 1
autoresearch nix-rebuild

# Terminal 2
autoresearch knowledge-fabric

# Terminal 3
autoresearch akash

# Monitor all at http://localhost:8502/?skills=nix-rebuild,knowledge-fabric,akash
```

## 📚 Related Skills

- **superpowers:writing-skills** — Manual skill creation patterns
- **superpowers:test-driven-development** — TDD methodology
- **code-review:code-review** — Review optimized skills

## 🎓 Theory

**Karpathy Autoresearch Pattern:**
- Treat prompt/skill engineering as optimization problem
- Generate → Evaluate → Keep Winner → Mutate → Repeat
- Objective scoring replaces human judgment
- Continuous autonomous improvement

**Key Insight:** Skills are code. Test them, evolve them, improve them automatically.

---

**Version**: 2.0.0 — General meta-skill optimizer
**Last Updated**: 2026-03-23
**Author**: Adapted from Karpathy autoresearch pattern
