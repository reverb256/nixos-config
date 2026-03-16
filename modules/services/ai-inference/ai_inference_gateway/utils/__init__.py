from .redis_client import RedisClient

__all__ = ["RedisClient"]

# Tool utilities for agentic workflows
try:
    from .tool_utils import (
        has_tool_calls,
        has_tool_calls_openai,
        has_tool_calls_anthropic,
        extract_tool_calls_openai,
        extract_tool_calls_anthropic,
        create_tool_result_openai,
        create_tool_result_anthropic,
        is_tool_response_format,
        ToolUtils,
    )

    __all__.extend([
        "has_tool_calls",
        "has_tool_calls_openai",
        "has_tool_calls_anthropic",
        "extract_tool_calls_openai",
        "extract_tool_calls_anthropic",
        "create_tool_result_openai",
        "create_tool_result_anthropic",
        "is_tool_response_format",
        "ToolUtils",
    ])
except ImportError:
    pass

# Optional imports
try:
    from .metrics import MetricsHelper  # noqa: F401

    __all__.append("MetricsHelper")
except ImportError:
    pass
