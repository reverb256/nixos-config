"""
Knowledge Fabric Middleware

Provides unified knowledge retrieval from multiple sources.
"""

from .core import (
    KnowledgeChunk,
    KnowledgeResult,
    SourceCapability,
    SourcePriority,
)

from .sources.searxng_source import (
    SearXNGKnowledgeSource,
    create_searxng_source,
)

__all__ = [
    'KnowledgeChunk',
    'KnowledgeResult',
    'SourceCapability',
    'SourcePriority',
    'SearXNGKnowledgeSource',
    'create_searxng_source',
]
