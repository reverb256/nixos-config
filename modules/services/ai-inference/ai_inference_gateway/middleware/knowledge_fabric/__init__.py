"""
Knowledge Fabric - Unified Knowledge Retrieval System

Combines RAG, MCP web search, SearXNG, and code search into one
coherent system with semantic routing, parallel retrieval, and RRF fusion.

Architecture:
- Core: Data structures and base abstractions
- Routing: Semantic query classification and source selection
- Sources: Adapters for heterogeneous knowledge systems
- Fusion: Reciprocal Rank Fusion (RRF) for multi-source merging
- Fabric: Main middleware orchestrator
"""

from .core import (
    SourcePriority,
    SourceCapability,
    KnowledgeChunk,
    KnowledgeResult,
    FabricContext,
    RetrieveFunc,
    KnowledgeSource,
)

from .routing import SemanticRouter, QueryIntent
from .fusion import (
    RRFFusion,
    ContextSynthesizer,
    create_fusion,
    create_synthesizer,
)
from .fabric import (
    KnowledgeFabricMiddleware,
    create_knowledge_fabric,
)
from .sources import (
    RAGKnowledgeSource,
    create_rag_source,
    WebSearchKnowledgeSource,
    create_web_search_source,
    SearXNGKnowledgeSource,
    create_searxng_source,
    CodeSearchKnowledgeSource,
    create_code_search_source,
)

__all__ = [
    # Core
    "SourcePriority",
    "SourceCapability",
    "KnowledgeChunk",
    "KnowledgeResult",
    "FabricContext",
    "RetrieveFunc",
    "KnowledgeSource",
    # Routing
    "SemanticRouter",
    "QueryIntent",
    # Fusion
    "RRFFusion",
    "ContextSynthesizer",
    "create_fusion",
    "create_synthesizer",
    # Fabric (Main Orchestrator)
    "KnowledgeFabricMiddleware",
    "create_knowledge_fabric",
    # Source Adapters
    "RAGKnowledgeSource",
    "create_rag_source",
    "WebSearchKnowledgeSource",
    "create_web_search_source",
    "SearXNGKnowledgeSource",
    "create_searxng_source",
    "CodeSearchKnowledgeSource",
    "create_code_search_source",
]
