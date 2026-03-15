"""
Knowledge fusion using Reciprocal Rank Fusion (RRF).

Combines results from multiple knowledge sources into a single
ranked list, handling score normalization and duplicate detection.
"""

import logging
from typing import List, Dict, Any, Optional
from collections import defaultdict

from .core import KnowledgeChunk, KnowledgeResult, FabricContext, QueryIntent

logger = logging.getLogger(__name__)


class RRFFusion:
    """
    Reciprocal Rank Fusion for multi-source result merging.

    RRF Formula: score(d) = Σ (k / (k + rank_i(d)))

    Where:
    - k is a constant (typically 60)
    - rank_i(d) is the rank of document d in source i
    - Sum is over all sources that contain d

    RRF is robust to score scale differences and works well
    when combining ranked lists from heterogeneous sources.
    """

    DEFAULT_K = 60  # RRF constant (higher = more weight to lower ranks)

    def __init__(self, k: int = DEFAULT_K):
        """
        Initialize RRF fusion.

        Args:
            k: RRF constant (default 60 is standard)
        """
        self.k = k

    def fuse(
        self,
        results: List[KnowledgeResult],
        context: FabricContext
    ) -> List[KnowledgeChunk]:
        """
        Fuse multiple knowledge results using RRF.

        Args:
            results: List of KnowledgeResult from different sources
            context: The FabricContext for this query

        Returns:
            List of KnowledgeChunks sorted by fused RRF score
        """
        # Track RRF scores for each unique chunk
        rrf_scores: Dict[str, float] = defaultdict(float)
        chunk_data: Dict[str, KnowledgeChunk] = {}

        # Process each source's results
        for result in results:
            if not result.chunks:
                continue

            for rank, chunk in enumerate(result.chunks, start=1):
                # Create a unique key for deduplication
                # Use content hash or truncated content as key
                key = self._chunk_key(chunk)

                # Add RRF contribution: k / (k + rank)
                rrf_scores[key] += self.k / (self.k + rank)

                # Store chunk data on first occurrence
                if key not in chunk_data:
                    chunk_data[key] = chunk
                    # Preserve source metadata
                    if "sources" not in chunk.metadata:
                        chunk.metadata["sources"] = []
                    chunk.metadata["sources"].append(result.source_name)
                else:
                    # Track additional sources
                    if result.source_name not in chunk_data[key].metadata.get("sources", []):
                        chunk_data[key].metadata["sources"].append(result.source_name)

        # Build final sorted list
        fused_chunks = []
        for key, rrf_score in sorted(rrf_scores.items(), key=lambda x: x[1], reverse=True):
            chunk = chunk_data[key]
            chunk.score = rrf_score  # Replace original score with RRF score
            chunk.metadata["rrf_score"] = rrf_score
            fused_chunks.append(chunk)

        logger.debug(f"RRF fused {len(results)} sources into {len(fused_chunks)} chunks")
        return fused_chunks[:self._max_chunks(context)]

    def _chunk_key(self, chunk: KnowledgeChunk) -> str:
        """Create a unique key for deduplication."""
        # Use first 100 chars of content as simple dedup key
        content_preview = chunk.content[:100].strip()
        # Could also use URL, file path, or actual hash
        if "url" in chunk.metadata:
            return chunk.metadata["url"]
        if "file_path" in chunk.metadata:
            return chunk.metadata["file_path"]
        return content_preview

    def _max_chunks(self, context: FabricContext) -> int:
        """Determine max chunks to return based on query type."""
        # Code queries need fewer, more precise results
        if context.query_type == QueryIntent.CODE:
            return 5
        # Factual queries benefit from more context
        if context.query_type == QueryIntent.FACTUAL:
            return 10
        # Procedural often needs step-by-step detail
        if context.query_type == QueryIntent.PROCEDURAL:
            return 8
        # Default
        return 7


class ContextSynthesizer:
    """
    Synthesizes retrieved knowledge into LLM-ready context.

    Formats fused chunks into a coherent prompt that the LLM
    can use effectively, with source attribution and structure.
    """

    # Templates for different query types
    TEMPLATES = {
        QueryIntent.CODE: """The following code examples and implementations were found to help answer the query:

{chunks}

Use these code examples to provide an accurate implementation. If examples differ, explain the trade-offs.""",

        QueryIntent.PROCEDURAL: """The following step-by-step guides were found to help answer the query:

{chunks}

Follow these steps to provide clear instructions. Mention any prerequisites or warnings.""",

        QueryIntent.COMPARATIVE: """The following comparisons and alternatives were found:

{chunks}

Present a balanced comparison, highlighting key differences and trade-offs.""",

        QueryIntent.FACTUAL: """The following factual information was retrieved:

{chunks}

Use these facts to provide an accurate answer. Prioritize verified information.""",

        QueryIntent.REALTIME: """The following current information was retrieved:

{chunks}

Note the retrieval times and provide context about data freshness.""",

        QueryIntent.CONTEXTUAL: """The following contextual information was retrieved:

{chunks}

Synthesize this information to provide a comprehensive explanation.""",

        QueryIntent.UNKNOWN: """The following information was retrieved:

{chunks}

Use this information to help answer the query, supplementing with general knowledge as needed.""",
    }

    def synthesize(self, context: FabricContext) -> str:
        """
        Synthesize fused chunks into LLM context.

        Args:
            context: FabricContext with fused_chunks populated

        Returns:
            Formatted context string for LLM
        """
        if not context.fused_chunks:
            return ""

        # Format chunks based on query type
        formatted_chunks = self._format_chunks(context)

        # Get template
        template = self.TEMPLATES.get(
            context.query_type,
            self.TEMPLATES[QueryIntent.UNKNOWN]
        )

        # Build final context
        llm_context = template.format(chunks=formatted_chunks)

        # Add source attribution
        sources = set()
        for chunk in context.fused_chunks:
            sources.update(chunk.metadata.get("sources", [chunk.source]))

        if sources:
            llm_context += f"\n\nSources: {', '.join(sorted(sources))}"

        return llm_context

    def _format_chunks(self, context: FabricContext) -> str:
        """Format chunks based on query type."""
        parts = []

        for i, chunk in enumerate(context.fused_chunks, 1):
            source_str = chunk.metadata.get("sources", [chunk.source])[0]
            score = chunk.metadata.get("rrf_score", chunk.score)

            if context.query_type == QueryIntent.CODE:
                parts.append(
                    f"Example {i} (from {source_str}, score={score:.2f}):\n"
                    f"```\n{chunk.content}\n```"
                )
            elif context.query_type == QueryIntent.PROCEDURAL:
                parts.append(
                    f"Step {i} (from {source_str}):\n{chunk.content}"
                )
            elif context.query_type == QueryIntent.COMPARATIVE:
                parts.append(
                    f"Option {i} (from {source_str}):\n{chunk.content}"
                )
            else:
                # Default formatting
                parts.append(
                    f"[{i}] From {source_str} (score={score:.2f}):\n{chunk.content}"
                )

        return "\n\n".join(parts)


def create_fusion(k: int = 60) -> RRFFusion:
    """Factory function to create RRF fusion."""
    return RRFFusion(k=k)


def create_synthesizer() -> ContextSynthesizer:
    """Factory function to create context synthesizer."""
    return ContextSynthesizer()
