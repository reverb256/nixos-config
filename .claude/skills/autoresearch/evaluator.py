#!/usr/bin/env python3
"""
Evaluator — Score skill outputs against test criteria.

Uses LLM-as-a-judge to evaluate skill performance on test cases.
Scores across 5 criteria (triggering, workflow, errors, quality, intent).
"""

import json
import os
from typing import Dict, Any

import anthropic
from dotenv import load_dotenv

load_dotenv()

client = anthropic.Anthropic(api_key=os.getenv("ANTHROPIC_API_KEY"))

EVAL_PROMPT = """You are evaluating a skill's performance on a test case.

**Test Case:**
- Type: {test_type}
- Query: "{query}"
- Expected Behavior: {expected}
- Forbidden Actions: {forbidden}

**Skill Output:**
{output}

**Evaluation Criteria:**

1. CORRECT_TRIGGERING (0-20 points):
   - 20: Triggered correctly for positive cases, NOT triggered for negative cases
   - 10: Partial triggering (some false positives or false negatives)
   - 0: Failed to trigger or triggered incorrectly

2. WORKFLOW_ADHERENCE (0-20 points):
   - 20: Followed all expected steps in correct order
   - 10: Followed most steps, minor deviations
   - 0: Major workflow violations or skipped critical steps

3. ERROR_AVOIDANCE (0-20 points):
   - 20: Avoided all forbidden actions completely
   - 10: Minor issues, recovered well
   - 0: Executed forbidden actions or critical errors

4. OUTPUT_QUALITY (0-20 points):
   - 20: Clear, actionable, appropriate detail level
   - 10: Understandable but verbose or terse
   - 0: Confusing, missing critical info, or unhelpful

5. USER_INTENT (0-20 points):
   - 20: Fully addressed user's need
   - 10: Partially addressed
   - 0: Missed user's intent entirely

**Output Format:**
Return ONLY valid JSON (no markdown, no code blocks):
```json
{{
  "scores": {{
    "correct_triggering": <score>,
    "workflow_adherence": <score>,
    "error_avoidance": <score>,
    "output_quality": <score>,
    "user_intent": <score>
  }},
  "total": <sum of scores>,
  "reasoning": "<2-3 sentence explanation>"
}}
```
"""


def evaluate_output(
    test_case: Dict[str, Any],
    execution_result: Dict[str, Any],
    model: str = "claude-3-5-opus-20250219"
) -> Dict[str, Any]:
    """Evaluate skill execution against test case using LLM judge."""

    prompt = EVAL_PROMPT.format(
        test_type=test_case["type"],
        query=test_case["query"],
        expected="\n".join(test_case["expected_behavior"]),
        forbidden="\n".join(test_case["forbidden_actions"]),
        output=execution_result.get("output", "")
    )

    try:
        response = client.messages.create(
            model=model,
            max_tokens=500,
            messages=[{"role": "user", "content": prompt}]
        )

        result_text = response.content[0].text.strip()

        # Try to parse JSON
        try:
            result = json.loads(result_text)
            return result
        except json.JSONDecodeError:
            # Try to extract JSON from markdown code blocks
            if "```json" in result_text:
                json_start = result_text.find("```json") + 7
                json_end = result_text.find("```", json_start)
                result = json.loads(result_text[json_start:json_end].strip())
                return result
            elif "```" in result_text:
                json_start = result_text.find("```") + 3
                json_end = result_text.find("```", json_start)
                result = json.loads(result_text[json_start:json_end].strip())
                return result

            # Fallback: return default scores
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

    except Exception as e:
        print(f"⚠️  Evaluation error: {e}")
        return {
            "scores": {
                "correct_triggering": 10,
                "workflow_adherence": 10,
                "error_avoidance": 10,
                "output_quality": 10,
                "user_intent": 10
            },
            "total": 50,
            "reasoning": f"Evaluation failed: {str(e)}"
        }


def evaluate_batch(
    test_cases: list,
    execution_results: list,
    model: str = "claude-3-5-opus-20250219"
) -> list:
    """Evaluate multiple test cases (can be parallelized)."""

    results = []
    for test_case, execution in zip(test_cases, execution_results):
        result = evaluate_output(test_case, execution, model)
        results.append({
            "test_id": test_case["id"],
            "type": test_case["type"],
            "query": test_case["query"],
            "evaluation": result
        })

    return results
