#!/usr/bin/env python3
"""
Mutator — Evolve skill instructions using 5 strategies.

Applies targeted mutations to improve skill performance:
1. Add Example — Insert few-shot examples
2. Clarify Rule — Strengthen instructions
3. Add Warning — Emphasize constraints
4. Simplify — Remove redundancy
5. Reorder — Improve flow
"""

import json
import os
import random
from typing import List

import anthropic
from dotenv import load_dotenv

load_dotenv()

client = anthropic.Anthropic(api_key=os.getenv("ANTHROPIC_API_KEY"))

MUTATION_STRATEGIES = [
    "add_example",
    "clarify_rule",
    "add_warning",
    "simplify",
    "reorder"
]

MUTATION_PROMPTS = {
    "add_example": """Add a new few-shot example to this skill that illustrates a common edge case or clarifies the workflow.

Guidelines:
- The example should be realistic and show the skill handling a tricky situation correctly
- Follow the existing example format in the skill
- Include User/Model or Query/Response pattern
- Make the example specific and detailed
- Add it in the appropriate section (few-shot examples section)

Return ONLY the improved skill content - no explanations, no markdown code blocks, just the skill.""",

    "clarify_rule": """Find any ambiguous, unclear, or vague instructions in this skill and rewrite them to be more explicit and specific.

Guidelines:
- Look for phrases like "appropriate", "should", "may" — replace with specific requirements
- Add constraints, examples, or clarifications where needed
- Strengthen weak requirements into strong ones
- Add specific values or criteria where generic ones exist
- Make rules more concrete and actionable

Return ONLY the improved skill content - no explanations, no markdown code blocks, just the skill.""",

    "add_warning": """Identify the most critical constraint, common mistake, or dangerous action in this skill and add a prominent warning section.

Guidelines:
- Use ⚠️ emoji and bold text for prominence
- Place the warning near the relevant section
- Explain WHAT is forbidden and WHY it matters
- Include consequences of violating the rule
- Make it impossible to miss

Return ONLY the improved skill content - no explanations, no markdown code blocks, just the skill.""",

    "simplify": """Remove redundant, verbose, or repetitive text from this skill while preserving all essential information.

Guidelines:
- Remove duplicate explanations
- Shorten verbose paragraphs
- Eliminate redundant warnings
- Consolidate similar points
- Make the skill more concise without losing clarity
- Preserve all critical information and examples

Return ONLY the improved skill content - no explanations, no markdown code blocks, just the skill.""",

    "reorder": """Reorganize the sections of this skill to improve flow, logical progression, and readability.

Guidelines:
- Group related concepts together
- Ensure the most important information comes first
- Put critical warnings near relevant actions
- Create a logical narrative flow
- Move examples closer to the content they illustrate
- Use clear section headers

Return ONLY the improved skill content - no explanations, no markdown code blocks, just the skill."""
}


def mutate_skill(
    skill_content: str,
    strategy: str = None,
    model: str = "claude-3-5-sonnet-20250219"
) -> str:
    """Mutate skill using specified or random strategy."""

    if strategy is None:
        strategy = random.choice(MUTATION_STRATEGIES)

    if strategy not in MUTATION_PROMPTS:
        raise ValueError(f"Unknown strategy: {strategy}")

    prompt = f"""You are optimizing a Claude Code skill. Apply this mutation strategy:

**Strategy:** {strategy.upper()}

**Instructions:** {MUTATION_PROMPTS[strategy]}

**Current Skill:**
{skill_content}

**Important:** Return ONLY the improved skill content - no explanations outside the skill, no markdown code blocks (`````), just the skill content itself starting from the first line."""

    try:
        response = client.messages.create(
            model=model,
            max_tokens=8000,
            messages=[{"role": "user", "content": prompt}]
        )

        mutated_content = response.content[0].text.strip()

        # Clean up any markdown code blocks
        if mutated_content.startswith("```"):
            first_newline = mutated_content.find("\n")
            last_backticks = mutated_content.rfind("```")
            if first_newline > 0 and last_backticks > first_newline:
                mutated_content = mutated_content[first_newline+1:last_backticks].strip()

        return mutated_content

    except Exception as e:
        print(f"⚠️  Mutation failed: {e}")
        return skill_content


def mutate_with_weights(
    skill_content: str,
    weights: dict = None,
    model: str = "claude-3-5-sonnet-20250219"
) -> tuple:
    """Mutate skill using weighted strategy selection.

    Returns: (mutated_content, strategy_used)
    """

    if weights is None:
        # Default equal weights
        weights = {s: 1.0 for s in MUTATION_STRATEGIES}

    # Select strategy based on weights
    strategies = list(weights.keys())
    weights_list = list(weights.values())
    total = sum(weights_list)
    probs = [w/total for w in weights_list]

    strategy = random.choices(strategies, weights=probs, k=1)[0]

    mutated = mutate_skill(skill_content, strategy, model)
    return mutated, strategy


def get_mutation_history(results_file: str) -> List[dict]:
    """Extract mutation history from results.jsonl."""

    history = []
    try:
        with open(results_file) as f:
            for line in f:
                result = json.loads(line)
                if "mutation" in result:
                    history.append({
                        "run": result.get("run"),
                        "mutation": result["mutation"],
                        "score": result.get("avg_score", 0)
                    })
    except FileNotFoundError:
        pass

    return history
