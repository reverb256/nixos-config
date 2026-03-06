"""
Model-specific default parameters for Qwen3.5 models.

Provides optimal temperature, top_p, max_tokens, and other parameters
based on model size and capabilities.

Based on: docs/qwen3.5-best-practices.md
"""

from typing import Dict, Optional, Any
import logging

logger = logging.getLogger(__name__)


# Vision-specific temperature overrides
VISION_TEMPERATURE_OVERRIDES = {
    "0.8b": 0.7,  # Vision requires lower temp for consistency
    "2b": 0.7,
}


# Model parameter patterns
# These map model name patterns to their optimal defaults
MODEL_DEFAULTS = {
    # 35B-A3B (Mixture-of-Experts) - Best for Cortex, long context
    "35b-a3b": {
        "temperature": 0.6,
        "top_p": 0.95,
        "max_tokens": 32768,
        "context_length": 262144,  # 256K
        "description": "Mixture-of-Experts, optimal for long-context reasoning",
        "use_case": "cortex",
        "quantization": "Q4_K_M",
        "kv_cache_quant": "Q4_0",  # Required for 256K context
    },

    # 27B - Dense quality priority
    "27b": {
        "temperature": 0.6,
        "top_p": 0.95,
        "max_tokens": 32768,
        "context_length": 262144,  # 256K with KV cache
        "description": "Dense quality priority",
        "use_case": "high_quality",
        "quantization": "Q4_K_M",
    },

    # 9B models (base + distilled) - General reasoning
    "9b": {
        "temperature": 0.6,  # Lower for reasoning
        "top_p": 0.95,
        "max_tokens": 32768,
        "context_length": 32768,  # 32K (128K max)
        "description": "General reasoning, chain-of-thought",
        "use_case": "general",
        "quantization": "IQ4_NL",
    },

    # Distilled 9B variants (Claude-style)
    "9b-claude": {
        "temperature": 0.6,
        "top_p": 0.95,
        "max_tokens": 32768,
        "context_length": 32768,
        "description": "Claude-distilled, use structured prompts",
        "use_case": "reasoning",
        "quantization": "IQ4_NL",
        "prompt_style": "claude",
    },

    # CROW 9B distill
    "crow-9b": {
        "temperature": 0.6,
        "top_p": 0.95,
        "max_tokens": 32768,
        "context_length": 32768,
        "description": "Jackrong's CROW distill, CoT with  tags",
        "use_case": "reasoning",
        "quantization": "IQ4_NL",
        "prompt_style": "cot",
    },

    # 4B - Multimodal agents, modest GPUs
    "4b": {
        "temperature": 0.6,
        "top_p": 0.95,
        "max_tokens": 16384,
        "context_length": 32768,  # 32K
        "description": "Multimodal agents, 8GB GPUs",
        "use_case": "multimodal",
        "quantization": "Q4_K_S",
    },

    # 2B - Edge devices, basic tasks
    "2b": {
        "temperature": 1.0,  # Higher for text
        "top_p": 0.95,
        "max_tokens": 8192,
        "context_length": 8192,  # 8K (32K max)
        "description": "Edge devices, basic tasks",
        "use_case": "edge",
        "quantization": "IQ4_NL",
    },

    # 0.8B - Edge devices, simple tasks
    "0.8b": {
        "temperature": 1.0,
        "top_p": 0.95,
        "max_tokens": 4096,
        "context_length": 8192,  # 8K
        "description": "Edge devices, simple tasks",
        "use_case": "edge",
        "quantization": "IQ4_NL",
    },
}


def get_model_defaults(model_id: str) -> Dict[str, Any]:
    """
    Get optimal default parameters for a model.

    Args:
        model_id: Model identifier (e.g., "qwen3.5-9b", "qwen/qwen3.5-35b-a3b")

    Returns:
        Dict with default parameters:
        - temperature: float
        - top_p: float
        - max_tokens: int
        - context_length: int
        - description: str
        - use_case: str
    """
    model_lower = model_id.lower()

    # Match model pattern
    for pattern, defaults in MODEL_DEFAULTS.items():
        if pattern in model_lower:
            logger.debug(f"Matched model '{model_id}' to pattern '{pattern}'")
            return defaults.copy()

    # Fallback to sensible defaults
    logger.warning(f"No specific defaults for model '{model_id}', using generic defaults")
    return {
        "temperature": 0.7,
        "top_p": 0.95,
        "max_tokens": 4096,
        "context_length": 8192,
        "description": "Generic defaults",
        "use_case": "unknown",
    }


def apply_model_defaults(
    model_id: str,
    request_params: Dict[str, Any],
    override: bool = False,
    is_vision_request: bool = False
) -> Dict[str, Any]:
    """
    Apply model-specific defaults to request parameters.

    Args:
        model_id: Model identifier
        request_params: Original request parameters
        override: If True, defaults override user params.
                   If False (default), only fill missing values.
        is_vision_request: If True, use vision-specific temperature

    Returns:
        Updated request parameters with defaults applied
    """
    defaults = get_model_defaults(model_id)
    result = request_params.copy()

    # For vision requests, override temperature to be more conservative
    if is_vision_request:
        for pattern, vision_temp in VISION_TEMPERATURE_OVERRIDES.items():
            if pattern in model_id.lower():
                defaults["temperature"] = vision_temp
                logger.debug(f"Using vision-specific temperature {vision_temp} for {model_id}")
                break

    # Apply defaults
    if override:
        # Force defaults
        result.setdefault("temperature", defaults["temperature"])
        result.setdefault("top_p", defaults["top_p"])
        result.setdefault("max_tokens", defaults["max_tokens"])
    else:
        # Only fill missing values
        if "temperature" not in result:
            result["temperature"] = defaults["temperature"]
        if "top_p" not in result:
            result["top_p"] = defaults["top_p"]
        if "max_tokens" not in result:
            result["max_tokens"] = defaults["max_tokens"]

    # Log what we're using
    logger.info(
        f"Model '{model_id}': "
        f"temperature={result.get('temperature')}, "
        f"top_p={result.get('top_p')}, "
        f"max_tokens={result.get('max_tokens')}"
        + (f" [vision request]" if is_vision_request else "")
    )

    return result


def get_model_recommendation(model_id: str) -> Dict[str, str]:
    """
    Get recommendation details for a model.

    Args:
        model_id: Model identifier

    Returns:
        Dict with:
        - description: What the model is best for
        - use_case: Recommended use case
        - quantization: Recommended quantization
        - prompt_style: Recommended prompt style (if applicable)
    """
    defaults = get_model_defaults(model_id)

    return {
        "description": defaults.get("description", "Unknown"),
        "use_case": defaults.get("use_case", "general"),
        "quantization": defaults.get("quantization", "Q4_K_M"),
        "prompt_style": defaults.get("prompt_style", "standard"),
        "context_length": defaults.get("context_length", 8192),
    }


def suggest_model_for_task(task: str, context_length: int = 4096) -> str:
    """
    Suggest the best Qwen3.5 model for a given task.

    Args:
        task: Task description (e.g., "reasoning", "chat", "code")
        context_length: Required context length in tokens

    Returns:
        Recommended model ID
    """
    task_lower = task.lower()

    # Long context required
    if context_length > 128000:
        return "qwen3.5-35b-a3b"  # Best for 256K context

    # Complex reasoning
    if any(keyword in task_lower for keyword in ["reasoning", "complex", "analysis", "cortex"]):
        if context_length > 64000:
            return "qwen3.5-35b-a3b"
        return "qwen3.5-9b-claude-4.6-opus-distilled-32k"

    # Code generation
    if "code" in task_lower or "programming" in task_lower:
        return "qwen3.5-9b"  # Good balance of quality/speed

    # Fast responses
    if any(keyword in task_lower for keyword in ["fast", "quick", "simple"]):
        return "qwen3.5-4b"

    # Edge deployment
    if "edge" in task_lower or "mobile" in task_lower:
        return "qwen3.5-0.8b"

    # Default: balanced option
    return "qwen3.5-9b"


# Export for use in other modules
__all__ = [
    'get_model_defaults',
    'apply_model_defaults',
    'get_model_recommendation',
    'suggest_model_for_task',
    'MODEL_DEFAULTS',
]
