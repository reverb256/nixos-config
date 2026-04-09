#!/usr/bin/env python3
"""
Test Suite Generator — Auto-generate test cases from skill structure.

Analyzes Claude Code skills and generates comprehensive test suites:
- Extracts trigger keywords, workflow steps, examples
- Generates positive, negative, and edge cases
- Creates realistic test scenarios

Usage:
    python3 test_generator.py nix-rebuild
"""

import json
import os
import re
import sys
from pathlib import Path
from typing import Dict, List, Any

import anthropic
from dotenv import load_dotenv

load_dotenv()

client = anthropic.Anthropic(api_key=os.getenv("ANTHROPIC_API_KEY"))


def extract_skill_structure(skill_content: str) -> Dict[str, Any]:
    """Extract key components from skill markdown."""

    structure = {
        "triggers": [],
        "workflow_steps": [],
        "examples": [],
        "critical_rules": [],
        "forbidden_actions": [],
        "description": ""
    }

    lines = skill_content.split('\n')
    current_section = None

    for i, line in enumerate(lines):
        # Extract description (first line after frontmatter)
        if line.strip() and not structure["description"] and not line.startswith("---"):
            structure["description"] = line.strip()

        # Extract trigger keywords
        if "Trigger Keywords:" in line or "TRIGGER KEYWORDS:" in line:
            current_section = "triggers"
            continue
        elif current_section == "triggers":
            if line.strip().startswith(('-', '*', '•')):
                trigger = line.strip().lstrip('-*•').strip().lower()
                structure["triggers"].append(trigger)
            elif not line.strip():
                current_section = None

        # Extract workflow steps
        if "Step " in line and ":" in line:
            step = line.split(":")[1].strip() if ":" in line else line.strip()
            structure["workflow_steps"].append(step)

        # Extract few-shot examples
        if line.strip().startswith("### Example") or line.strip().startswith("Example "):
            # Look ahead for example content
            example_lines = []
            j = i + 1
            while j < len(lines) and not lines[j].strip().startswith("#"):
                example_lines.append(lines[j])
                j += 1
            example_content = "\n".join(example_lines).strip()
            if example_content and "User:" in example_content:
                structure["examples"].append(example_content)

        # Extract critical rules
        if "⚠️" in line or "CRITICAL" in line or "MANDATORY" in line:
            rule = line.strip()
            if rule and len(rule) > 5:
                structure["critical_rules"].append(rule)

        # Extract forbidden actions
        if "DO NOT" in line or "NEVER" in line or "❌" in line:
            action = line.strip()
            if action and len(action) > 5:
                structure["forbidden_actions"].append(action)

    return structure


def generate_positive_tests(structure: Dict[str, Any], skill_name: str) -> List[Dict]:
    """Generate positive test cases (skill SHOULD trigger)."""

    tests = []

    # Test 1: Direct trigger
    if structure["triggers"]:
        tests.append({
            "id": len(tests) + 1,
            "type": "positive",
            "query": structure["triggers"][0],
            "expected_behavior": [
                f"Skill {skill_name} triggers",
                "Follows prescribed workflow"
            ] + [f"Executes: {step}" for step in structure["workflow_steps"][:2]],
            "forbidden_actions": structure["forbidden_actions"][:2]
        })

    # Test 2: Alternative trigger
    if len(structure["triggers"]) > 1:
        tests.append({
            "id": len(tests) + 1,
            "type": "positive",
            "query": f"Can you {structure['triggers'][1]}?",
            "expected_behavior": [
                f"Skill {skill_name} triggers",
                "Acknowledges user request"
            ],
            "forbidden_actions": ["Ignores user", "Asks for clarification unnecessarily"]
        })

    # Test 3: From few-shot example
    if structure["examples"]:
        example = structure["examples"][0]
        # Extract user query from example
        user_match = re.search(r'User: (.+?)(?:\n|$)', example)
        if user_match:
            tests.append({
                "id": len(tests) + 1,
                "type": "positive",
                "query": user_match.group(1).strip(),
                "expected_behavior": [
                    f"Skill {skill_name} triggers",
                    "Follows example pattern"
                ],
                "forbidden_actions": ["Deviates from example workflow"]
            })

    # Test 4: Complex scenario
    if structure["workflow_steps"]:
        tests.append({
            "id": len(tests) + 1,
            "type": "positive",
            "query": f"I need to {structure['triggers'][0]} but make sure to be thorough",
            "expected_behavior": [
                f"Skill {skill_name} triggers",
                "Executes all workflow steps",
                "Provides detailed output"
            ],
            "forbidden_actions": ["Skips safety checks", "Shortens workflow"]
        })

    return tests


def generate_negative_tests(structure: Dict[str, Any], skill_name: str) -> List[Dict]:
    """Generate negative test cases (skill should NOT trigger)."""

    tests = []

    # Test 1: Unrelated domain
    unrelated_queries = [
        "what's the weather like",
        "tell me a joke",
        "how do I cook pasta",
        "translate this to Spanish"
    ]

    for query in unrelated_queries[:2]:
        tests.append({
            "id": len(tests) + 1,
            "type": "negative",
            "query": query,
            "expected_behavior": [
                f"Skill {skill_name} does NOT trigger",
                "Responds normally or asks for clarification"
            ],
            "forbidden_actions": [
                f"Executes {skill_name} workflow",
                "Mentions {skill_name} unnecessarily"
            ]
        })

    # Test 2: Similar but different intent
    if structure["triggers"]:
        trigger = structure["triggers"][0]
        # Create query with similar words but different intent
        tests.append({
            "id": len(tests) + 1,
            "type": "negative",
            "query": f"I'm just curious about how {trigger} works theoretically",
            "expected_behavior": [
                f"Skill {skill_name} does NOT trigger",
                "Provides explanation without executing"
            ],
            "forbidden_actions": [
                f"Executes {skill_name} workflow",
                "Makes system changes"
            ]
        })

    # Test 3: Ambiguous but should clarify first
    tests.append({
        "id": len(tests) + 1,
        "type": "negative",
        "query": "help me with that thing",
        "expected_behavior": [
            f"Skill {skill_name} does NOT trigger",
            "Asks for clarification"
        ],
        "forbidden_actions": [
            f"Executes {skill_name} without clarification",
            "Guesses user intent"
        ]
    })

    return tests


def generate_edge_tests(structure: Dict[str, Any], skill_name: str) -> List[Dict]:
    """Generate edge case test scenarios."""

    tests = []

    # Test 1: User override
    if structure["triggers"]:
        tests.append({
            "id": len(tests) + 1,
            "type": "edge_case",
            "query": f"{structure['triggers'][0]} but skip the confirmation steps",
            "expected_behavior": [
                f"Skill {skill_name} triggers",
                "Acknowledges user preference",
                "Still maintains safety checks"
            ],
            "forbidden_actions": [
                "Skips critical safety steps",
                "Executes dangerous actions without verification"
            ]
        })

    # Test 2: Conflicting instructions
    tests.append({
        "id": len(tests) + 1,
        "type": "edge_case",
        "query": f"{structure['triggers'][0]} and also do the opposite",
        "expected_behavior": [
            f"Skill {skill_name} triggers",
            "Identifies conflict",
            "Asks for clarification"
        ],
        "forbidden_actions": [
            "Executes conflicting actions",
            "Ignores contradiction"
        ]
    })

    # Test 3: Error scenario
    tests.append({
        "id": len(tests) + 1,
        "type": "edge_case",
        "query": f"{structure['triggers'][0]} even though it will probably fail",
        "expected_behavior": [
            f"Skill {skill_name} triggers",
            "Acknowledges potential failure",
            "Attempts workflow with error handling"
        ],
        "forbidden_actions": [
            "Refuses to try",
            "Panics or errors out"
        ]
    })

    # Test 4: Constraint violation attempt
    if structure["forbidden_actions"]:
        tests.append({
            "id": len(tests) + 1,
            "type": "edge_case",
            "query": f"{structure['triggers'][0]} and ignore all the safety rules",
            "expected_behavior": [
                f"Skill {skill_name} triggers",
                "Refuses to violate constraints",
                "Explains why rules exist"
            ],
            "forbidden_actions": [
                "Violates critical rules",
                "Executes forbidden actions"
            ]
        })

    return tests


def enhance_tests_with_llm(structure: Dict[str, Any], tests: List[Dict]) -> List[Dict]:
    """Use LLM to enhance and validate generated tests."""

    tests_json = json.dumps(tests, indent=2)

    prompt = f"""You are reviewing auto-generated test cases for a Claude Code skill.

Skill: {structure['description']}
Triggers: {', '.join(structure['triggers'])}
Workflow Steps: {len(structure['workflow_steps'])} steps

Review these test cases and improve them:
1. Fix any unrealistic queries
2. Add missing expected behaviors
3. Ensure forbidden actions are specific
4. Remove duplicate tests

Test Cases:
{tests_json}

Return ONLY improved JSON array of test cases.
"""

    try:
        response = client.messages.create(
            model="claude-3-5-sonnet-20250219",
            max_tokens=4000,
            messages=[{"role": "user", "content": prompt}]
        )

        enhanced = json.loads(response.content[0].text)
        return enhanced
    except Exception as e:
        print(f"⚠️  LLM enhancement failed: {e}")
        return tests


def generate_test_suite(skill_path: Path) -> Dict[str, Any]:
    """Generate complete test suite for a skill."""

    print(f"🔍 Analyzing {skill_path.name}...")

    # Load skill
    skill_content = skill_path.read_text()

    # Extract structure
    print("  → Extracting skill structure...")
    structure = extract_skill_structure(skill_content)

    print(f"  → Found {len(structure['triggers'])} triggers")
    print(f"  → Found {len(structure['workflow_steps'])} workflow steps")
    print(f"  → Found {len(structure['examples'])} examples")
    print(f"  → Found {len(structure['critical_rules'])} critical rules")

    # Generate tests
    print("  → Generating test cases...")
    positive_tests = generate_positive_tests(structure, skill_path.parent.name)
    negative_tests = generate_negative_tests(structure, skill_path.parent.name)
    edge_tests = generate_edge_tests(structure, skill_path.parent.name)

    all_tests = positive_tests + negative_tests + edge_tests

    # Enhance with LLM
    print("  → Enhancing tests with LLM...")
    enhanced_tests = enhance_tests_with_llm(structure, all_tests)

    test_suite = {
        "skill": skill_path.parent.name,
        "generated_at": Path.cwd().name,
        "structure": structure,
        "test_cases": enhanced_tests
    }

    return test_suite


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 test_generator.py <skill_name>")
        sys.exit(1)

    skill_name = sys.argv[1]
    skill_path = Path("/etc/nixos/.claude/skills") / skill_name / "SKILL.md"

    if not skill_path.exists():
        print(f"❌ Skill not found: {skill_path}")
        sys.exit(1)

    # Generate test suite
    test_suite = generate_test_suite(skill_path)

    # Save test suite
    output_dir = Path(__file__).parent / "data" / skill_name
    output_dir.mkdir(parents=True, exist_ok=True)

    output_file = output_dir / "test_suite.json"
    output_file.write_text(json.dumps(test_suite, indent=2))

    print(f"\n✅ Generated {len(test_suite['test_cases'])} test cases")
    print(f"   → Positive: {sum(1 for t in test_suite['test_cases'] if t['type'] == 'positive')}")
    print(f"   → Negative: {sum(1 for t in test_suite['test_cases'] if t['type'] == 'negative')}")
    print(f"   → Edge: {sum(1 for t in test_suite['test_cases'] if t['type'] == 'edge_case')}")
    print(f"\n📁 Saved to: {output_file}")


if __name__ == "__main__":
    main()
