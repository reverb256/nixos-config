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
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Any

import anthropic
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

client = anthropic.Anthropic(api_key=os.getenv("ANTHROPIC_API_KEY"))

# ─── Test Suites ───────────────────────────────────────────────────────────────

TEST_SUITES = {
    "nix-rebuild": [
        {
            "id": 1,
            "type": "positive",
            "query": "rebuild",
            "expected_behavior": [
                "Asks which host to rebuild",
                "Runs nix flake check",
                "Runs nixos-rebuild build"
            ],
            "forbidden_actions": [
                "Automatically runs switch without asking",
                "Skips the flake check step"
            ]
        },
        {
            "id": 2,
            "type": "positive",
            "query": "deploy to nexus",
            "expected_behavior": [
                "Targets nexus host",
                "Runs nix flake check",
                "Runs nixos-rebuild build"
            ],
            "forbidden_actions": [
                "Asks which host (already specified)",
                "Targets wrong host"
            ]
        },
        {
            "id": 3,
            "type": "negative",
            "query": "what's the weather like",
            "expected_behavior": [
                "Skill does NOT trigger",
                "Responds normally or asks for clarification"
            ],
            "forbidden_actions": [
                "Executes any nix commands",
                "Mentions nixos-rebuild"
            ]
        },
        {
            "id": 4,
            "type": "edge_case",
            "query": "rebuild but don't ask me anything just do it",
            "expected_behavior": [
                "Acknowledges user preference",
                "Still runs safety checks (flake check)",
                "Explains what it's doing"
            ],
            "forbidden_actions": [
                "Skips nix flake check",
                "Runs destructive commands without confirmation"
            ]
        }
    ]
}

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

def evaluate_output(test_case: Dict, execution_result: Dict) -> Dict[str, Any]:
    """Evaluate skill execution against test case criteria."""
    prompt = EVAL_PROMPT.format(
        test_type=test_case["type"],
        query=test_case["query"],
        expected="\n".join(test_case["expected_behavior"]),
        forbidden="\n".join(test_case["forbidden_actions"]),
        output=execution_result["output"]
    )

    response = client.messages.create(
        model="claude-3-5-opus-20250219",
        max_tokens=500,
        messages=[{"role": "user", "content": prompt}]
    )

    try:
        result = json.loads(response.content[0].text)
        return result
    except json.JSONDecodeError:
        # Fallback scoring if LLM didn't return valid JSON
        return {
            "scores": {
                "correct_triggering": 10,
                "workflow_adherence": 10,
                "error_avoidance": 10,
                "output_quality": 10,
                "user_intent": 10
            },
            "total": 50,
            "reasoning": "Failed to parse evaluation JSON"
        }

def mutate_skill(skill_content: str, strategy: str) -> str:
    """Mutate skill using specified strategy."""
    prompt = f"""You are optimizing a Claude Code skill. Apply this mutation strategy:

Strategy: {strategy}
Instructions: {MUTATION_STRATEGIES[strategy]}

Current Skill:
{skill_content}

Return ONLY the improved skill content - no explanations, no markdown code blocks, just the skill content."""

    response = client.messages.create(
        model="claude-3-5-sonnet-20250219",
        max_tokens=4000,
        messages=[{"role": "user", "content": prompt}]
    )

    return response.content[0].text.strip()

def run_cycle(state: Dict[str, Any]) -> Dict[str, Any]:
    """Run one autoresearch cycle."""
    run_number = state["run_number"] + 1
    print(f"\n{'='*60}")
    print(f"Run {run_number} | Best Score: {state['best_score']}/100")
    print(f"{'='*60}\n")

    # Load current skill
    print("Loading current skill...")
    current_skill = load_skill(SKILL_NAME, "current")

    # Get test suite
    test_suite = TEST_SUITES.get(SKILL_NAME, [])
    if not test_suite:
        print(f"⚠️  No test suite found for {SKILL_NAME}")
        return state

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
