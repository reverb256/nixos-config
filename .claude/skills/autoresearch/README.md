# Autoresearch — General Skill Optimizer

A **universal meta-skill** that automatically optimizes ANY Claude Code skill using the Karpathy autoresearch pattern.

`★ Insight ─────────────────────────────────────`
**Test-Driven Evolution**: Unlike manual prompt tuning, this uses objective test suites as the fitness function. Skills evolve toward passing all tests automatically.

**Auto-Generated Test Suites**: The system analyzes skill structure (triggers, workflow, examples) and generates 8-12 comprehensive test cases without manual intervention.

**General-Purpose Architecture**: Works on ANY skill in your `.claude/skills/` directory — nix-rebuild, knowledge-fabric, akash, or custom skills you create.
`─────────────────────────────────────────────────`

## 🎯 What It Does

When you invoke `autoresearch <skill-name>`, it:

1. **Analyzes** the target skill structure
2. **Auto-generates** 8-12 test cases (positive, negative, edge)
3. **Tests** the skill against all cases
4. **Scores** each test 0-100 across 5 criteria
5. **Evolves** instructions — keeps improvements, discards regressions
6. **Mutates** best version using 5 strategies
7. **Repeats** every 5 minutes until stopped

## 🚀 Usage

```bash
# Optimize nix-rebuild skill
autoresearch nix-rebuild

# Optimize with custom parameters
autoresearch knowledge-fabric 10 cycles every 3 minutes

# Check optimization status
autoresearch status
```

## 📁 Architecture

```
.claude/skills/autoresearch/
├── SKILL.md              # Skill definition (invoke with "autoresearch X")
├── test_generator.py     # Auto-generate test suites from skill structure
├── evaluator.py          # Score skill outputs (LLM-as-a-judge)
├── mutator.py            # Mutate skill instructions
├── optimizer.py          # Main optimization loop
├── dashboard.py          # Streamlit dashboard
└── data/
    ├── {skill_name}/
    │   ├── current.md          # Current skill version
    │   ├── best.md             # Best version found
    │   ├── test_suite.json     # Auto-generated test suite
    │   ├── state.json          # Run state, best score
    │   ├── results.jsonl       # All test results
    │   └── runs/               # Per-run logs
```

## 🔧 Components

### 1. Test Generator (`test_generator.py`)

**Extracts skill structure:**
- Trigger keywords
- Workflow steps
- Few-shot examples
- Critical rules
- Forbidden actions

**Generates 3 test types:**
- **Positive** (3-4 cases): Skill SHOULD trigger
- **Negative** (2-3 cases): Skill should NOT trigger
- **Edge** (3-4 cases): Tricky scenarios

**Uses LLM to enhance tests:**
- Fixes unrealistic queries
- Adds missing expected behaviors
- Ensures specificity

### 2. Evaluator (`evaluator.py`)

**LLM-as-a-judge** scoring across 5 criteria:

1. **Correct Triggering** (20 pts) — Did it activate appropriately?
2. **Workflow Adherence** (20 pts) — Did it follow steps correctly?
3. **Error Avoidance** (20 pts) — Did it avoid mistakes?
4. **Output Quality** (20 pts) — Was the output clear?
5. **User Intent** (20 pts) — Did it solve the user's problem?

### 3. Mutator (`mutator.py`)

**5 mutation strategies:**
1. **Add Example** — Insert few-shot examples
2. **Clarify Rule** — Strengthen instructions
3. **Add Warning** — Emphasize constraints (⚠️)
4. **Simplify** — Remove redundancy
5. **Reorder** — Improve flow

### 4. Optimizer (`optimizer.py`)

**Main loop:**
```python
while True:
    # Load current skill
    skill = load_skill(skill_name)

    # Run test suite
    results = run_tests(skill, test_suite)
    avg_score = calculate_average(results)

    # Evolution
    if avg_score > best_score:
        save_as_best(skill)
        mutate_skill(skill)
    else:
        revert_to_best()
        mutate_skill(best_skill)

    # Log and sleep
    log_results(results)
    sleep(5 * 60)  # 5 minutes
```

### 5. Dashboard (`dashboard.py`)

**Real-time monitoring:**
- Score progression chart
- Test case breakdown
- Criterion analysis
- Mutation history
- Cost tracking

## 💡 Key Innovations

### 1. Skill-Agnostic Design

Works on ANY skill without code changes:
- Analyzes skill structure automatically
- Generates appropriate test cases
- Adapts evaluation to skill type

### 2. Auto-Generated Test Suites

No manual test writing required:
- Extracts test patterns from skill content
- Uses few-shot examples as templates
- Creates realistic scenarios
- LLM-enhanced for quality

### 3. Multi-Dimensional Scoring

Not just pass/fail — detailed criteria:
- Catch different failure modes
- Identify specific weaknesses
- Guide mutation direction
- Explain why scores changed

### 4. Evolutionary Optimization

Not random search — directed evolution:
- Keeps what works
- Discards what doesn't
- Mutates toward improvement
- Maintains best version

## 📊 Example: Optimizing nix-rebuild

```bash
$ autoresearch nix-rebuild

🔍 Analyzing nix-rebuild skill...
  → Found 3 trigger keywords: rebuild, deploy, switch
  → Extracted 4-step workflow
  → Found 2 few-shot examples
  → Found 3 critical rules

📋 Generated 10 test cases:
   → Positive: 4 cases
   → Negative: 3 cases
   → Edge: 3 cases

🚀 Starting optimization loop (every 5 min)...
📊 Dashboard: http://localhost:8502

[Run 1] Score: 72/100 → Best: 72/100 ✨
[Run 2] Score: 68/100 → Keeping best (72/100)
[Run 3] Score: 79/100 → New best! ✨
[Run 4] Score: 75/100 → Keeping best (79/100)
[Run 5] Score: 83/100 → New best! ✨
...
```

**After optimization:**
- Score improved from 72 → 83/100
- Better triggering accuracy
- Improved workflow adherence
- Fewer forbidden actions

## 💰 Cost

**Per 5-minute cycle:**
- 4 test executions (Sonnet 4)
- 4 evaluations (Opus 4)
- 1 mutation (Sonnet 4)

**Estimated:** $0.05-0.15 per cycle

**Overnight run (100 cycles):** $5-15

## 🛡️ Safety

- ✅ Dry-run mode (no destructive commands)
- ✅ Isolated testing (doesn't affect production)
- ✅ Rollback protection (always keeps best)
- ✅ Cost tracking (monitor spend)
- ✅ Auto-pause (stops if plateaued)

## 🎓 When to Use

**Good candidates:**
- Skills with clear triggers
- Well-defined workflows
- Existing few-shot examples
- Observable behavior

**Examples:**
- `nix-rebuild` — Clear workflow, good examples
- `knowledge-fabric` — Strict rules, multiple tools
- `akash` — Specific procedures
- Custom skills you've created

**Not ideal for:**
- Very simple skills (not worth optimizing)
- Highly creative skills (hard to test objectively)
- Skills without clear success criteria

## 🔄 Comparison: Diagram vs Skill Autoresearch

| Aspect | Diagrams | Skills (General) |
|--------|----------|-------------------|
| **Domain** | Image generation | Any Claude Code skill |
| **Output** | Images (Gemini) | Text (Claude Code) |
| **Evaluation** | Vision model | LLM judge |
| **Test Suite** | Manual topics | Auto-generated from skill |
| **Criteria** | 4 visual (40 pts) | 5 behavioral (100 pts) |
| **Cost/Cycle** | ~$0.50-1.00 | ~$0.05-0.15 |
| **Applicability** | Diagram prompts only | Universal meta-skill |

## 📚 Next Steps

1. **Try it out**: `autoresearch nix-rebuild`
2. **Monitor dashboard**: http://localhost:8502
3. **Let it run overnight**: 100 cycles
4. **Review results**: Check top 3 versions
5. **Apply winner**: Copy to production skills
6. **Commit improvements**: Git commit changes

## 🚀 Future Enhancements

**Planned:**
- [ ] Multi-skill optimization (compatible skill sets)
- [ ] Automatic test suite regeneration
- [ ] A/B testing between branches
- [ ] Integration with Claude Code API for real testing
- [ ] Transfer learning between skills
- [ ] Parallel optimization (multiple skills at once)

---

**Version**: 2.0.0 — Universal meta-skill optimizer
**Last Updated**: 2026-03-23
**Inspired by**: Andrej Karpathy's autoresearch pattern
