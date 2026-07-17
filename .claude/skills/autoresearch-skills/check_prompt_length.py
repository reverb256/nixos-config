#!/usr/bin/env python3
"""Check EVAL_PROMPT length."""

import json
import os
from pathlib import Path

EVAL_PROMPT = """You are evaluating a skill's performance on a test case.

Test Case: positive
User Query: "zephyr"
Expected Behavior: Question**: Which host? (Options: zephyr, forge, nexus, sentry)
Default**: zephyr (if user doesn't specify)
Forbidden Actions: Execute destructive commands without confirmation

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

print(f"Prompt length: {len(EVAL_PROMPT)} characters")
print(f"Prompt lines: {len(EVAL_PROMPT.splitlines())}")
print(f"Estimated tokens: ~{len(EVAL_PROMPT.split())} (rough estimate)")
