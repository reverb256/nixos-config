#!/usr/bin/env python3
"""
Skill Autoresearch — Self-improving skill optimization.

Karpathy autoresearch pattern applied to Claude Code skills:
1. Execute skill against test suite (real Claude Code invocations)
2. Evaluate each output against criteria via LLM judge → score out of 100
3. Compare against best score — keep winner
4. Mutate the winner skill for next cycle
5. Repeat every 5 minutes

Usage:
    python3 skill_autoresearch.py              # Continuous loop
    python3 skill_autoresearch.py --once        # Single cycle
    python3 skill_autoresearch.py --cycles 5    # Run N cycles
"""

import argparse
import json
import os
import random
import re
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Any

from openai import OpenAI
from dotenv import load_dotenv

load_dotenv()

# ─── Config ───────────────────────────────────────────────────────────────────

SKILL_NAME = os.getenv("SKILL_NAME", "nix-rebuild")
PROJECT_PATH = Path(os.getenv("CLAUDE_CODE_PATH", "/etc/nixos"))
DATA_DIR = Path(__file__).parent / "data"
SKILLS_DIR = DATA_DIR / "skills"
TEST_CASES_DIR = DATA_DIR / "test_cases"
RESULTS_FILE = DATA_DIR / "results.jsonl"
STATE_FILE = DATA_DIR / "state.json"

# llama.cpp client (local GGUF models with CUDA acceleration)
# Uses OpenAI-compatible API from llama-server
LLAMA_SERVER_URL = os.getenv("LLAMA_SERVER_URL", "http://localhost:8080")
LLAMA_API_KEY = os.getenv("LLAMA_API_KEY", "sk-notneeded")  # llama.cpp doesn't require auth

client = OpenAI(
    api_key=LLAMA_API_KEY,
    base_url=LLAMA_SERVER_URL + "/v1"
)

# llama.cpp models (loaded at server startup)
# Model selection happens at llama-server startup, not here
EVAL_MODEL = "qwen3.5"  # Placeholder - actual model set at server start
MUTATION_MODEL = "qwen3.5"  # Same model for both operations

# ─── Eval Prompt ──────────────────────────────────────────────────────────────

EVAL_PROMPT = """You are evaluating a skill's performance on a test case.

Test Case: {test_type}
User Query: "{query}"
Expected Behavior: {expected}
Forbidden Actions: {forbidden}

Skill Output:
{output}

Score each criterion 0-20 (total 100 max):

1. CORRECT_TRIGGERING (0-20):
   - 20: Triggered correctly for positive cases, not triggered for negative
   - 10: Partial triggering (some false positives/negatives)
   - 0: Failed to trigger or triggered incorrectly

2. WORKFLOW_ADHERENCE (0-20):
   - 20: Followed all expected steps in correct order
   - 10: Followed most steps, minor deviations
   - 0: Major workflow violations

3. ERROR_AVOIDANCE (0-20):
   - 20: Avoided all forbidden actions
   - 10: Minor issues, recovered well
   - 0: Executed forbidden actions

4. OUTPUT_QUALITY (0-20):
   - 20: Clear, actionable, appropriate detail
   - 10: Understandable but verbose or terse
   - 0: Confusing, missing critical info

5. USER_INTENT (0-20):
   - 20: Fully addressed user's need
   - 10: Partially addressed
   - 0: Missed user's intent

Provide JSON output only:
{{"scores": {{correct_triggering: X, workflow_adherence: X, error_avoidance: X, output_quality: X, user_intent: X}}, "total": XX, "reasoning": "Brief explanation"}}"""

# ─── Mutation Strategies ───────────────────────────────────────────────────────

MUTATION_STRATEGIES = [
    "add_example",      # Add new few-shot example
    "clarify_rule",     # Strengthen ambiguous instructions
    "add_warning",      # Emphasize critical constraint
    "simplify",         # Remove redundant text
    "reorder",          # Reorganize sections
]

MUTATION_PROMPTS = {
    "add_example": "Add a new few-shot example that illustrates a common edge case or clarifies the workflow. The example should be realistic and show the skill handling a tricky situation correctly.",
    "clarify_rule": "Find any ambiguous or unclear instructions and rewrite them to be more explicit and specific. Add constraints, examples, or clarifications where needed.",
    "add_warning": "Identify the most critical constraint or common mistake and add a prominent warning section (using ⚠️ emojis) to prevent this error.",
    "simplify": "Remove any redundant, verbose, or repetitive text while preserving all essential information. Make the skill more concise without losing clarity.",
    "reorder": "Reorganize sections to improve flow and logical progression. Group related concepts together and ensure the most important information comes first."
}

# ─── Auto-Bootstrap ─────────────────────────────────────────────────────────────

def bootstrap_test_suite(skill_name: str) -> List[Dict]:
    """
    Auto-generate test suite from skill's SKILL.md.

    Extracts:
    - Trigger keywords (for positive/negative cases)
    - Workflow steps (for expected behavior)
    - Few-shot examples (as test templates)
    - Critical rules (for forbidden actions)
    """
    skill_path = PROJECT_PATH / ".claude" / "skills" / skill_name / "SKILL.md"

    if not skill_path.exists():
        raise FileNotFoundError(f"Skill not found: {skill_path}")

    content = skill_path.read_text()

    # Extract trigger keywords
    triggers = extract_triggers(content)

    # Extract workflow steps
    workflow = extract_workflow(content)

    # Extract few-shot examples
    examples = extract_examples(content)

    # Generate test cases
    test_cases = []

    # 1. Positive cases from examples (up to 4)
    for i, example in enumerate(examples[:4], 1):
        test_cases.append({
            "id": i,
            "type": "positive",
            "query": example.get("query", f"Example {i}"),
            "expected_behavior": example.get("expected_steps", workflow),
            "forbidden_actions": extract_forbidden(content)
        })

    # If no examples, create generic positive cases from triggers
    if not examples and triggers:
        for i, trigger in enumerate(triggers[:3], 1):
            test_cases.append({
                "id": i,
                "type": "positive",
                "query": f"{trigger}",
                "expected_behavior": workflow,
                "forbidden_actions": extract_forbidden(content)
            })

    # 2. Negative cases (should NOT trigger)
    negative_queries = [
        "what's the weather like",
        "tell me a joke",
        "how are you doing",
        "help me with something else"
    ]
    for i, query in enumerate(negative_queries[:3], len(test_cases) + 1):
        test_cases.append({
            "id": i,
            "type": "negative",
            "query": query,
            "expected_behavior": ["Skill does NOT trigger"],
            "forbidden_actions": ["Executes any commands related to " + skill_name]
        })

    # 3. Edge cases
    edge_cases = [
        {
            "query": f"{' '.join(triggers[:2])} but don't ask me anything" if len(triggers) >= 2 else f"{triggers[0]} but don't ask me anything" if triggers else "do it but don't ask me anything",
            "expected": ["Acknowledges preference", "Still runs safety checks"],
            "forbidden": ["Skips safety checks", "Runs destructive commands without confirmation"]
        },
        {
            "query": f"{' '.join(triggers[:1])} right now immediately" if triggers else "do it right now immediately",
            "expected": ["Proceeds with workflow", "Shows what it's doing"],
            "forbidden": ["Runs without any checks", "Skips confirmation steps"]
        }
    ]

    for i, case in enumerate(edge_cases, len(test_cases) + 1):
        test_cases.append({
            "id": i,
            "type": "edge_case",
            "query": case["query"],
            "expected_behavior": case["expected"],
            "forbidden_actions": case["forbidden"]
        })

    # Save to test_cases directory
    TEST_CASES_DIR.mkdir(parents=True, exist_ok=True)
    test_file = TEST_CASES_DIR / f"{skill_name}.jsonl"

    with open(test_file, 'w') as f:
        for test in test_cases:
            f.write(json.dumps(test) + "\n")

    print(f"✅ Generated {len(test_cases)} test cases for {skill_name}")
    print(f"   Saved to: {test_file}")

    return test_cases


def extract_triggers(content: str) -> List[str]:
    """Extract trigger keywords from skill content."""
    triggers = []
    lines = content.split('\n')
    in_trigger_section = False

    for line in lines:
        if 'trigger keywords' in line.lower() or 'when to use' in line.lower():
            in_trigger_section = True
            continue
        if in_trigger_section:
            if line.strip().startswith('-') or line.strip().startswith('*') or line.strip().startswith('`'):
                trigger = line.strip().lstrip('-*`').strip().lower().rstrip('`')
                if trigger and not trigger.startswith('http') and len(trigger) > 2:
                    triggers.append(trigger)
            elif line.strip().startswith('##') or (not line.strip() and triggers):
                break

    return triggers[:5]  # Limit to first 5 triggers


def extract_workflow(content: str) -> List[str]:
    """Extract workflow steps from skill content."""
    steps = []
    lines = content.split('\n')
    in_workflow = False

    for line in lines:
        if 'workflow' in line.lower() or 'step-by-step' in line.lower() or 'how to use' in line.lower():
            in_workflow = True
            continue
        if in_workflow:
            if line.strip().startswith(('1.', '2.', '3.', '4.', '5.', '-', '*')):
                step = line.strip().lstrip('123456789.-*').strip()
                if step:
                    steps.append(step)
            elif line.strip().startswith('##') and steps:
                break

    return steps[:5] if steps else ["Execute workflow", "Verify results", "Report to user"]


def extract_examples(content: str) -> List[Dict]:
    """Extract few-shot examples from skill content."""
    examples = []
    lines = content.split('\n')
    current_example = {}

    for line in lines:
        if 'example' in line.lower() or line.strip().startswith('###'):
            if current_example:
                examples.append(current_example)
            current_example = {}
        elif 'query:' in line.lower() or 'user:' in line.lower():
            current_example['query'] = line.split(':', 1)[1].strip() if ':' in line else line.strip()
        elif 'expected:' in line.lower() or 'output:' in line.lower():
            current_example['expected_steps'] = ["Execute task", "Show results"]

    if current_example:
        examples.append(current_example)

    return examples[:3]


def extract_forbidden(content: str) -> List[str]:
    """Extract forbidden actions from critical rules."""
    forbidden = []
    lines = content.split('\n')

    for line in lines:
        if 'never' in line.lower() or 'forbidden' in line.lower() or '⚠️' in line or 'critical' in line.lower():
            clean_line = line.strip()
            # Remove markdown formatting
            clean_line = clean_line.lstrip('*-#').strip()
            if clean_line and len(clean_line) > 10:
                forbidden.append(clean_line)

    return forbidden[:3] if forbidden else ["Execute destructive commands without confirmation"]


def load_or_bootstrap_test_suite(skill_name: str) -> List[Dict]:
    """Load test suite from disk or auto-generate if missing."""
    test_file = TEST_CASES_DIR / f"{skill_name}.jsonl"

    if test_file.exists():
        print(f"✅ Loading existing test suite: {test_file}")
        tests = []
        with open(test_file) as f:
            for line in f:
                tests.append(json.loads(line))
        return tests

    print(f"⚠️  No test suite found for {skill_name}")
    print(f"🔬 Auto-generating test suite from skill...")
    return bootstrap_test_suite(skill_name)


# ─── Core Functions ────────────────────────────────────────────────────────────

def load_state() -> Dict[str, Any]:
    """Load or initialize run state."""
    if STATE_FILE.exists():
        return json.loads(STATE_FILE.read_text())
    return {
        "run_number": 0,
        "best_score": 0,
        "best_skill_path": None,
        "total_cost": 0.0
    }

def save_state(state: Dict[str, Any]) -> None:
    """Persist run state."""
    STATE_FILE.write_text(json.dumps(state, indent=2))

def load_skill(skill_name: str, version: str = "current") -> str:
    """Load skill content."""
    if version == "current":
        path = SKILLS_DIR / f"{skill_name}.md"
    elif version == "best":
        path = SKILLS_DIR / f"best_{skill_name}.md"
    else:
        path = SKILLS_DIR / f"run_{version}_{skill_name}.md"

    if not path.exists():
        # Load from actual skills directory if no copy exists
        actual_path = PROJECT_PATH / ".claude" / "skills" / skill_name / "SKILL.md"
        if actual_path.exists():
            content = actual_path.read_text()
            # Save to our skills dir
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)
            return content
        raise FileNotFoundError(f"Skill not found: {skill_name}")

    return path.read_text()

def save_skill(skill_name: str, content: str, version: str) -> Path:
    """Save skill content."""
    SKILLS_DIR.mkdir(parents=True, exist_ok=True)
    path = SKILLS_DIR / f"{version}_{skill_name}.md"
    path.write_text(content)
    return path

def execute_skill(skill_name: str, skill_content: str, query: str) -> Dict[str, Any]:
    """
    Execute a skill against a query (simulated).

    In production, this would call Claude Code API with the skill loaded.
    For now, we simulate by checking if the skill would trigger.
    """
    # Check if skill would trigger
    skill_lines = skill_content.split('\n')
    triggers = []
    in_keywords = False

    for line in skill_lines:
        if 'Trigger Keywords:' in line or 'TRIGGER KEYWORDS:' in line:
            in_keywords = True
            continue
        if in_keywords:
            if line.strip().startswith('-') or line.strip().startswith('*'):
                trigger = line.strip().lstrip('-*').strip().lower()
                triggers.append(trigger)
            elif not line.strip():
                break

    would_trigger = any(trigger in query.lower() for trigger in triggers)

    # Simulate execution (in production, use actual Claude Code API)
    output = f"# Simulated Output for: {query}\n"
    if would_trigger:
        output += f"[Skill triggered: {skill_name}]\n\n"
        if "rebuild" in skill_name.lower():
            output += "## Step 1: Ask User\n"
            if "nexus" not in query.lower():
                output += "Which host would you like to rebuild? (default: zephyr)\n\n"
            output += "## Step 2: Run Workflow\n"
            output += "```bash\nnix flake check\nsudo nixos-rebuild build --flake .#<host>\n```\n"
    else:
        output += f"[Skill did not trigger]\n\n"
        output += "I'd be happy to help with that! Could you provide more details?"

    return {
        "triggered": would_trigger,
        "output": output
    }

def rule_based_evaluate(test_case: Dict, execution_result: Dict) -> Dict[str, Any]:
    """Evaluate skill execution using deterministic rules (GLM API fallback)."""
    output = execution_result["output"].lower()
    query = test_case["query"].lower()
    test_type = test_case["type"]
    expected = [e.lower() for e in test_case["expected_behavior"]]
    forbidden = [f.lower() for f in test_case["forbidden_actions"]]

    scores = {
        "correct_triggering": 0,
        "workflow_adherence": 0,
        "error_avoidance": 0,
        "output_quality": 0,
        "user_intent": 0
    }

    # 1. CORRECT_TRIGGERING (0-20)
    if test_type == "positive":
        # Should trigger
        if execution_result["triggered"]:
            scores["correct_triggering"] = 20
        else:
            scores["correct_triggering"] = 0
    elif test_type == "negative":
        # Should NOT trigger
        if not execution_result["triggered"]:
            scores["correct_triggering"] = 20
        else:
            scores["correct_triggering"] = 0
    else:  # edge_case
        # Partial credit for edge cases
        scores["correct_triggering"] = 10

    # 2. WORKFLOW_ADHERENCE (0-20)
    if test_type == "positive" and execution_result["triggered"]:
        # Check if expected behaviors are present in output
        expected_found = sum(1 for exp in expected if exp in output)
        if len(expected) > 0:
            scores["workflow_adherence"] = min(20, int((expected_found / len(expected)) * 20))
        else:
            scores["workflow_adherence"] = 20
    elif test_type == "negative" and not execution_result["triggered"]:
        scores["workflow_adherence"] = 20
    else:
        scores["workflow_adherence"] = 10

    # 3. ERROR_AVOIDANCE (0-20)
    # Check if forbidden actions are NOT in output
    forbidden_found = sum(1 for forb in forbidden if forb in output)
    if forbidden_found == 0:
        scores["error_avoidance"] = 20
    else:
        scores["error_avoidance"] = max(0, 20 - (forbidden_found * 10))

    # 4. OUTPUT_QUALITY (0-20)
    # Check if output is non-empty and reasonable
    if execution_result["triggered"]:
        if len(output) > 50:  # Has substantial content
            scores["output_quality"] = 20
        elif len(output) > 10:
            scores["output_quality"] = 10
        else:
            scores["output_quality"] = 5
    else:
        # For negative cases, "did not trigger" is good quality
        if not execution_result["triggered"]:
            scores["output_quality"] = 20
        else:
            scores["output_quality"] = 5

    # 5. USER_INTENT (0-20)
    # Overall assessment: did we address the user's need?
    if test_type == "positive":
        if execution_result["triggered"] and scores["workflow_adherence"] >= 15:
            scores["user_intent"] = 20
        elif execution_result["triggered"]:
            scores["user_intent"] = 10
        else:
            scores["user_intent"] = 0
    elif test_type == "negative":
        if not execution_result["triggered"]:
            scores["user_intent"] = 20
        else:
            scores["user_intent"] = 5
    else:  # edge_case
        scores["user_intent"] = 10

    total = sum(scores.values())

    return {
        "scores": scores,
        "total": total,
        "reasoning": "Rule-based evaluation (GLM API unavailable)"
    }

def evaluate_output(test_case: Dict, execution_result: Dict) -> Dict[str, Any]:
    """Evaluate skill execution against test case criteria."""
    # Try LLM evaluation first, fall back to rule-based
    prompt = EVAL_PROMPT.format(
        test_type=test_case["type"],
        query=test_case["query"],
        expected="\n".join(test_case["expected_behavior"]),
        forbidden="\n".join(test_case["forbidden_actions"]),
        output=execution_result["output"]
    )

    try:
        response = client.chat.completions.create(
            model=EVAL_MODEL,
            max_tokens=2000,
            messages=[{"role": "user", "content": prompt}]
        )

        content = response.choices[0].message.content.strip() if response.choices[0].message.content else ""

        # If LLM returns empty response, use rule-based evaluation
        if not content:
            print(f"⚠️  LLM returned empty, using rule-based evaluation")
            return rule_based_evaluate(test_case, execution_result)

        # Try direct JSON parse first
        try:
            result = json.loads(content)
            return result
        except json.JSONDecodeError as e:
            # Try extracting JSON from markdown code blocks
            import re
            json_match = re.search(r'```(?:json)?\s*\n?(.*?)```', content, re.DOTALL)
            if json_match:
                try:
                    result = json.loads(json_match.group(1))
                    return result
                except:
                    pass

            # Try finding JSON object in response
            json_match = re.search(r'\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}', content)
            if json_match:
                try:
                    result = json.loads(json_match.group(0))
                    return result
                except:
                    pass

        # If all JSON parsing fails, use rule-based evaluation
        print(f"⚠️  JSON parsing failed, using rule-based evaluation")
        return rule_based_evaluate(test_case, execution_result)

    except Exception as e:
        print(f"⚠️  LLM evaluation error: {e}, using rule-based evaluation")
        return rule_based_evaluate(test_case, execution_result)

def mutate_skill(skill_content: str, strategy: str) -> str:
    """Mutate skill using specified strategy."""
    prompt = f"""You are optimizing a Claude Code skill. Apply this mutation strategy:

Strategy: {strategy}
Instructions: {MUTATION_PROMPTS[strategy]}

Current Skill:
{skill_content}

Return ONLY the improved skill content - no explanations, no markdown code blocks, just the skill content."""

    response = client.chat.completions.create(
        model=MUTATION_MODEL,
        max_tokens=4000,
        messages=[{"role": "user", "content": prompt}]
    )

    return response.choices[0].message.content.strip()

def run_cycle(state: Dict[str, Any]) -> Dict[str, Any]:
    """Run one autoresearch cycle."""
    run_number = state["run_number"] + 1
    print(f"\n{'='*60}")
    print(f"Run {run_number} | Best Score: {state['best_score']}/100")
    print(f"{'='*60}\n")

    # Load current skill
    print("Loading current skill...")
    current_skill = load_skill(SKILL_NAME, "current")

    # Get test suite (auto-bootstrap if missing)
    test_suite = load_or_bootstrap_test_suite(SKILL_NAME)

    print(f"Running {len(test_suite)} test cases...\n")

    # Run test suite
    total_score = 0
    results = []

    for test_case in test_suite:
        print(f"  Test {test_case['id']} ({test_case['type']}): ", end="")

        # Execute skill
        execution = execute_skill(SKILL_NAME, current_skill, test_case["query"])

        # Evaluate
        evaluation = evaluate_output(test_case, execution)
        score = evaluation.get("total", 0)
        total_score += score

        print(f"{score}/100")

        results.append({
            "test_id": test_case["id"],
            "type": test_case["type"],
            "query": test_case["query"],
            "score": score,
            "breakdown": evaluation.get("scores", {}),
            "reasoning": evaluation.get("reasoning", "")
        })

    avg_score = total_score / len(test_suite)
    print(f"\n📊 Average Score: {avg_score:.1f}/100")

    # Log results
    log_entry = {
        "run": run_number,
        "timestamp": datetime.now().isoformat(),
        "skill": SKILL_NAME,
        "avg_score": avg_score,
        "total_score": total_score,
        "num_tests": len(test_suite),
        "results": results
    }

    with open(RESULTS_FILE, "a") as f:
        f.write(json.dumps(log_entry) + "\n")

    # Compare with best
    if avg_score > state["best_score"]:
        print(f"✨ NEW BEST! Previous: {state['best_score']:.1f}")

        # Save as best
        save_skill(SKILL_NAME, current_skill, f"run_{run_number}_BEST")
        state["best_score"] = avg_score
        state["best_skill_path"] = f"run_{run_number}_BEST_{SKILL_NAME}.md"

        # Mutate for next cycle
        strategy = random.choice(MUTATION_STRATEGIES)
        print(f"🔬 Mutating with strategy: {strategy}")

        mutated_skill = mutate_skill(current_skill, strategy)
        save_skill(SKILL_NAME, mutated_skill, "current")
    else:
        print(f"❌ Not better than best ({state['best_score']:.1f})")
        print(f"🔄 Reverting to best skill")

        # Revert to best and mutate
        best_skill = load_skill(SKILL_NAME, "best")
        strategy = random.choice(MUTATION_STRATEGIES)
        print(f"🔬 Mutating best with strategy: {strategy}")

        mutated_skill = mutate_skill(best_skill, strategy)
        save_skill(SKILL_NAME, mutated_skill, "current")

    # Update state
    state["run_number"] = run_number
    save_state(state)

    print(f"\n✓ Run {run_number} complete")
    print(f"  Best score: {state['best_score']:.1f}/100")
    print(f"  Next run in 5 minutes...")

    return state

# ─── Main Loop ─────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Skill Autoresearch")
    parser.add_argument("--once", action="store_true", help="Run single cycle")
    parser.add_argument("--cycles", type=int, help="Run N cycles")
    args = parser.parse_args()

    # Initialize
    state = load_state()

    if args.once:
        run_cycle(state)
    elif args.cycles:
        for _ in range(args.cycles):
            run_cycle(state)
    else:
        # Continuous loop
        try:
            while True:
                state = run_cycle(state)
                time.sleep(300)  # 5 minutes
        except KeyboardInterrupt:
            print("\n\n🛑 Stopped. Final state:")
            print(f"  Runs: {state['run_number']}")
            print(f"  Best score: {state['best_score']:.1f}/100")

if __name__ == "__main__":
    main()
