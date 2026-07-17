# Z.AI GLM API Integration Issue - 2026-03-24

## Problem Summary

The Z.AI GLM models (glm-4.6, glm-4.7, glm-5) are returning completely empty responses when called via the OpenAI Python client, making them unusable for skill evaluation in the autoresearch system.

## Investigation Details

### API Configuration
```python
client = OpenAI(
    api_key=ZAI_API_KEY,
    base_url="https://api.z.ai/api/coding/paas/v4"
)
```

### Test Results

All GLM models tested with ultra-simple prompt:
- **glm-4.6**: `finish_reason: length`, `content: ''`
- **glm-4.7**: `finish_reason: length`, `content: ''`
- **glm-5**: `finish_reason: length`, `content: ''`

Test prompt: `"Return JSON: {"score": 50}"`

Even with max_tokens=2000, all models return empty responses with `finish_reason: length`, indicating the API is not generating any output at all.

### Root Cause

The `finish_reason: length` indicates the models are hitting the max_tokens limit before generating any content, which suggests:
1. The models may not be available via this API endpoint
2. There may be missing required parameters for GLM models
3. The OpenAI client may not be fully compatible with the Z.AI API
4. The API endpoint or authentication may be incorrect

### Resolution Implemented

Since the GLM API is non-functional, I've implemented a **rule-based evaluation fallback system** that:

1. **Detects when LLM evaluation fails** (empty response, JSON parse errors, API errors)
2. **Falls back to deterministic scoring** based on test case criteria:
   - Correct Triggering (0-20): Checks if skill triggered appropriately for test type
   - Workflow Adherence (0-20): Checks if expected behaviors appear in output
   - Error Avoidance (0-20): Verifies forbidden actions are not in output
   - Output Quality (0-20): Checks output length and completeness
   - User Intent (0-20): Overall assessment of whether user need was met

3. **Provides meaningful scores** instead of uniform 50/100 fallback

### Code Changes

**File**: `autoresearch.py`

Added `rule_based_evaluate()` function that implements deterministic scoring logic based on:
- Test case type (positive/negative/edge_case)
- Whether the skill triggered
- Expected behaviors in test case
- Forbidden actions in test case
- Output content analysis

Modified `evaluate_output()` to:
- Try LLM evaluation first
- Fall back to rule-based evaluation on any failure
- Log warnings when falling back

## Current Status

✅ **Autoresearch system is functional** with rule-based evaluation
❌ **GLM API integration is broken** - requires investigation
⚠️ **Evaluation quality may be lower** than with working LLM evaluation

## Next Steps

### Option 1: Fix GLM API Integration
- Research correct Z.AI API usage (documentation, examples)
- Try different API endpoints or parameters
- Contact Z.AI support for GLM API usage guidance
- Test with direct HTTP requests instead of OpenAI client

### Option 2: Use Alternative Models
- Test with local models (LM Studio, Qwen3.5)
- Try different cloud providers (Anthropic, OpenAI)
- Implement hybrid approach (local for testing, cloud for mutation)

### Option 3: Improve Rule-Based Evaluation
- Enhance deterministic scoring algorithms
- Add more sophisticated pattern matching
- Implement weighted scoring based on keyword importance
- Add test case-specific evaluation logic

## Recommendation

**For now, use the rule-based evaluation system** to continue autoresearch development. The rule-based system provides meaningful scores and allows the optimization loop to function, even if evaluation quality is not as nuanced as LLM-based evaluation.

**Long-term, fix the GLM API integration** or switch to a working LLM provider for better evaluation quality.

## Test Commands

```bash
# Test rule-based evaluation
cd /etc/nixos/.claude/skills/autoresearch-skills
./run.sh --once

# Debug GLM API
python3 debug_eval.py

# View results
cat data/results.jsonl | jq -r '.[] | "\(.timestamp) | \(.avg_score)"'
```

## Files Modified

1. `autoresearch.py` - Added rule-based evaluation fallback
2. `debug_eval.py` - Created to isolate GLM API issue
3. `check_prompt_length.py` - Created to analyze prompt size
4. This document - Created to document the issue

---

**Created**: 2026-03-24
**Status**: Rule-based evaluation implemented, GLM API issue documented
**Impact**: Autoresearch is functional but with simplified evaluation
