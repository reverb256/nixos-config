#!/usr/bin/env python3
"""
Optimizer — Main optimization loop for autoresearch system.

Coordinates test generation, execution, evaluation, and mutation.
Implements evolutionary optimization with best version tracking.
"""

import json
import os
import sys
import time
from pathlib import Path
from typing import Dict, Any

from dotenv import load_dotenv

# Import local modules
from test_generator import generate_test_suite
from evaluator import evaluate_output
from mutator import mutate_skill, mutate_with_weights

load_dotenv()


def load_skill(skill_name: str) -> str:
    """Load current skill version from data directory."""
    skill_path = Path(__file__).parent / "data" / skill_name / "current.md"
    if not skill_path.exists():
        # Copy from skills directory if first run
        source_path = Path("/etc/nixos/.claude/skills") / skill_name / "SKILL.md"
        if not source_path.exists():
            raise FileNotFoundError(f"Skill not found: {skill_name}")

        skill_path.parent.mkdir(parents=True, exist_ok=True)
        skill_path.write_text(source_path.read_text())

    return skill_path.read_text()


def load_best(skill_name: str) -> tuple[str, float]:
    """Load best skill version and its score."""
    best_path = Path(__file__).parent / "data" / skill_name / "best.md"
    state_path = Path(__file__).parent / "data" / skill_name / "state.json"

    if not best_path.exists():
        return None, 0.0

    best_content = best_path.read_text()

    if state_path.exists():
        state = json.loads(state_path.read_text())
        return best_content, state.get("best_score", 0.0)

    return best_content, 0.0


def save_current(skill_name: str, content: str):
    """Save current skill version."""
    skill_path = Path(__file__).parent / "data" / skill_name / "current.md"
    skill_path.parent.mkdir(parents=True, exist_ok=True)
    skill_path.write_text(content)


def save_best(skill_name: str, content: str, score: float, run_number: int):
    """Save best skill version and update state."""
    best_path = Path(__file__).parent / "data" / skill_name / "best.md"
    state_path = Path(__file__).parent / "data" / skill_name / "state.json"

    best_path.parent.mkdir(parents=True, exist_ok=True)
    best_path.write_text(content)

    state = {
        "best_score": score,
        "best_run": run_number,
        "last_updated": time.strftime("%Y-%m-%d %H:%M:%S")
    }
    state_path.write_text(json.dumps(state, indent=2))


def load_test_suite(skill_name: str) -> Dict[str, Any]:
    """Load or generate test suite."""
    test_suite_path = Path(__file__).parent / "data" / skill_name / "test_suite.json"

    if test_suite_path.exists():
        return json.loads(test_suite_path.read_text())

    # Generate test suite
    skill_path = Path("/etc/nixos/.claude/skills") / skill_name / "SKILL.md"
    test_suite = generate_test_suite(skill_path)

    test_suite_path.parent.mkdir(parents=True, exist_ok=True)
    test_suite_path.write_text(json.dumps(test_suite, indent=2))

    return test_suite


def log_results(skill_name: str, run_number: int, results: list, mutation: str, avg_score: float):
    """Log results to results.jsonl."""
    results_path = Path(__file__).parent / "data" / skill_name / "results.jsonl"
    results_path.parent.mkdir(parents=True, exist_ok=True)

    log_entry = {
        "run": run_number,
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        "mutation": mutation,
        "avg_score": avg_score,
        "results": results
    }

    with open(results_path, "a") as f:
        f.write(json.dumps(log_entry) + "\n")


def execute_skill(skill_name: str, skill_content: str, query: str) -> Dict[str, Any]:
    """Execute skill against query (dry-run simulation)."""

    # For dry-run, we simulate what would happen
    # In production, this would call Claude Code API

    prompt = f"""You are testing a Claude Code skill. Simulate its response to this query.

**Skill Content:**
{skill_content[:2000]}  # Truncate for context

**User Query:**
{query}

**Instructions:**
- Simulate how this skill would respond
- Follow the skill's workflow exactly
- Show the skill's output
- Return ONLY the skill response (no explanations)

**Response:**"""

    # Simulate execution (in production, use actual Claude Code API)
    # For now, return a mock response
    return {
        "output": f"[Simulated response for: {query[:50]}...]",
        "triggered": True
    }


def run_optimization_cycle(
    skill_name: str,
    run_number: int,
    test_suite: Dict[str, Any],
    mutation_weights: dict = None
) -> tuple[float, str]:
    """Run one optimization cycle."""

    print(f"\n[Run {run_number}] Starting optimization cycle...")

    # Load current skill
    current_skill = load_skill(skill_name)
    best_skill, best_score = load_best(skill_name)

    # If no best yet, save current as best
    if best_skill is None:
        best_skill = current_skill
        save_best(skill_name, current_skill, 0.0, 0)

    # Mutate current skill
    print(f"  → Mutating skill...")
    if mutation_weights:
        mutated_skill, strategy = mutate_with_weights(current_skill, mutation_weights)
    else:
        mutated_skill = mutate_skill(current_skill)
        strategy = "random"

    # Save mutated version as current
    save_current(skill_name, mutated_skill)

    # Run test suite
    print(f"  → Running {len(test_suite['test_cases'])} test cases...")
    results = []
    total_score = 0.0

    for test_case in test_suite['test_cases']:
        print(f"    - Test {test_case['id']}: {test_case['type']}", end="")

        # Execute skill
        execution = execute_skill(skill_name, mutated_skill, test_case['query'])

        # Evaluate
        evaluation = evaluate_output(test_case, execution)
        score = evaluation.get('total', 0)
        total_score += score

        results.append({
            "test_id": test_case['id'],
            "type": test_case['type'],
            "score": score,
            "evaluation": evaluation
        })

        print(f" → {score}/100")

    avg_score = total_score / len(test_suite['test_cases'])
    print(f"  → Average score: {avg_score:.1f}/100")

    # Evolution: keep improvement or revert
    if avg_score > best_score:
        print(f"  ✨ New best! ({avg_score:.1f} > {best_score:.1f})")
        save_best(skill_name, mutated_skill, avg_score, run_number)
        best_score = avg_score
    else:
        print(f"  → Keeping best ({best_score:.1f})")
        # Revert to best for next mutation
        save_current(skill_name, best_skill)

    # Log results
    log_results(skill_name, run_number, results, strategy, avg_score)

    return avg_score, strategy


def main():
    """Main optimization loop."""

    if len(sys.argv) < 2:
        print("Usage: python3 optimizer.py <skill_name> [cycles] [interval_minutes]")
        sys.exit(1)

    skill_name = sys.argv[1]
    cycles = int(sys.argv[2]) if len(sys.argv) > 2 else None
    interval = int(sys.argv[3]) * 60 if len(sys.argv) > 3 else 5 * 60

    print(f"🚀 Auto-Research: {skill_name}")
    print(f"   Cycles: {'Continuous' if cycles is None else cycles}")
    print(f"   Interval: {interval // 60} minutes")
    print()

    # Load or generate test suite
    print("📋 Loading test suite...")
    test_suite = load_test_suite(skill_name)
    print(f"   → {len(test_suite['test_cases'])} test cases loaded")

    # Main loop
    run_number = 1
    plateau_count = 0
    last_best_score = 0.0

    try:
        while True:
            # Run cycle
            avg_score, strategy = run_optimization_cycle(
                skill_name,
                run_number,
                test_suite
            )

            # Check for plateau
            if abs(avg_score - last_best_score) < 1.0:
                plateau_count += 1
            else:
                plateau_count = 0

            last_best_score = avg_score

            # Auto-pause if plateaued
            if plateau_count >= 10:
                print(f"\n⚠️  Score plateaued for 10 cycles. Pausing.")
                print(f"   Review and manually restart if needed.")
                break

            # Check cycle limit
            if cycles and run_number >= cycles:
                print(f"\n✅ Completed {cycles} cycles.")
                break

            # Wait for next cycle
            print(f"\n⏳ Waiting {interval // 60} minutes...")
            time.sleep(interval)

            run_number += 1

    except KeyboardInterrupt:
        print(f"\n\n⚠️  Optimization stopped by user.")
        print(f"   Best score: {last_best_score:.1f}/100")
        print(f"   Runs completed: {run_number}")


if __name__ == "__main__":
    main()
