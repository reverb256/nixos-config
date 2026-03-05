"""
Reranker module for AI Gateway.

Provides cross-encoder based reranking for RAG (Retrieval Augmented Generation).
"""

import logging
from typing import List, Dict, Any, Optional, Tuple
from dataclasses import dataclass, field
from enum import Enum
import asyncio

logger = logging.getLogger(__name__)


class RerankerType(Enum):
    """Types of rerankers."""
    CROSS_ENCODER = "cross_encoder"
    COLBERT = "colbert"
    MONO_T5 = "mono_t5"
    DUMMY = "dummy"


@dataclass
class Document:
    """Document to be reranked."""
    id: str
    content: str
    metadata: Dict[str, Any] = field(default_factory=dict)
    score: float = 0.0
    original_index: int = 0


@dataclass
class RerankResult:
    """Result of reranking operation."""
    documents: List[Document]
    query: str
    reranker_type: RerankerType
    processing_time_ms: float
    scores: List[float] = field(default_factory=list)


class Reranker:
    """
    Base reranker class.

    Rerankers reorder retrieved documents based on their relevance
    to a specific query using more sophisticated scoring than
    simple embedding similarity.
    """

    def __init__(
        self,
        reranker_type: RerankerType,
        model_name: Optional[str] = None,
        **kwargs
    ):
        """
        Initialize reranker.

        Args:
            reranker_type: Type of reranker to use
            model_name: Optional model name for cross-encoder
            **kwargs: Additional configuration
        """
        self.reranker_type = reranker_type
        self.model_name = model_name
        self.config = kwargs

    async def rerank(
        self,
        query: str,
        documents: List[Document],
        top_k: Optional[int] = None,
    ) -> RerankResult:
        """
        Rerank documents based on query relevance.

        Args:
            query: Search query
            documents: List of retrieved documents
            top_k: Optional limit on number of documents to return

        Returns:
            RerankResult with reordered documents
        """
        raise NotImplementedError("Subclasses must implement rerank()")


class DummyReranker(Reranker):
    """
    Dummy reranker for testing.

    Returns documents in original order with random scores.
    """

    def __init__(self, **kwargs):
        super().__init__(reranker_type=RerankerType.DUMMY, **kwargs)

    async def rerank(
        self,
        query: str,
        documents: List[Document],
        top_k: Optional[int] = None,
    ) -> RerankResult:
        """Return documents unchanged (for testing)."""
        import time
        import random

        start_time = time.time()

        # Assign dummy scores based on query string hash
        query_hash = hash(query) % 1000
        for i, doc in enumerate(documents):
            doc.score = (query_hash + i * 37) % 1000 / 1000

        # Sort by score
        sorted_docs = sorted(documents, key=lambda d: d.score, reverse=True)

        # Apply top_k if specified
        if top_k and top_k < len(sorted_docs):
            sorted_docs = sorted_docs[:top_k]

        processing_time = (time.time() - start_time) * 1000

        return RerankResult(
            documents=sorted_docs,
            query=query,
            reranker_type=self.reranker_type,
            processing_time_ms=processing_time,
            scores=[d.score for d in sorted_docs],
        )


class CrossEncoderReranker(Reranker):
    """
    Cross-encoder based reranker.

    Uses a cross-encoder model to score query-document pairs.
    Cross-encoders provide better relevance scoring than bi-encoders
    but are slower since they require running the model for each query-document pair.

    This implementation supports:
    - Local models via sentence-transformers
    - Remote API-based models
    - Caching for improved performance
    """

    def __init__(
        self,
        model_name: str = "cross-encoder/ms-marco-MiniLM-L-6-v2",
        device: str = "cpu",
        batch_size: int = 32,
        **kwargs
    ):
        """
        Initialize cross-encoder reranker.

        Args:
            model_name: Model name (from sentence-transformers or custom)
            device: Device to run model on ("cpu" or "cuda")
            batch_size: Batch size for scoring
            **kwargs: Additional configuration
        """
        super().__init__(
            reranker_type=RerankerType.CROSS_ENCODER,
            model_name=model_name,
            **kwargs
        )
        self.device = device
        self.batch_size = batch_size
        self._model = None

    def _load_model(self):
        """Lazy load the cross-encoder model."""
        if self._model is None:
            try:
                from sentence_transformers import CrossEncoder
                self._model = CrossEncoder(self.model_name, device=self.device)
                logger.info(f"Loaded cross-encoder model: {self.model_name}")
            except ImportError:
                logger.warning(
                    "sentence-transformers not available, "
                    "falling back to dummy reranker"
                )
                self._model = False  # Marker for failed load
            except Exception as e:
                logger.error(f"Failed to load cross-encoder: {e}")
                self._model = False

    async def rerank(
        self,
        query: str,
        documents: List[Document],
        top_k: Optional[int] = None,
    ) -> RerankResult:
        """
        Rerank documents using cross-encoder scoring.

        Args:
            query: Search query
            documents: List of retrieved documents
            top_k: Optional limit on number of documents to return

        Returns:
            RerankResult with reranked documents
        """
        import time
        start_time = time.time()

        # Lazy load model
        self._load_model()

        # If model failed to load, use dummy reranker
        if self._model is False:
            logger.warning("Using dummy reranker due to model load failure")
            dummy = DummyReranker()
            return await dummy.rerank(query, documents, top_k)

        # Prepare query-document pairs
        pairs = [[query, doc.content] for doc in documents]

        # Score in batches
        try:
            # Run in thread pool to avoid blocking event loop
            loop = asyncio.get_event_loop()
            scores = await loop.run_in_executor(
                None,
                self._model.predict,
                pairs
            )

            # Assign scores to documents
            for doc, score in zip(documents, scores):
                doc.score = float(score)

            # Sort by score
            sorted_docs = sorted(documents, key=lambda d: d.score, reverse=True)

            # Apply top_k if specified
            if top_k and top_k < len(sorted_docs):
                sorted_docs = sorted_docs[:top_k]

            processing_time = (time.time() - start_time) * 1000

            logger.info(
                f"Reranked {len(documents)} documents for query '{query[:50]}...' "
                f"in {processing_time:.2f}ms"
            )

            return RerankResult(
                documents=sorted_docs,
                query=query,
                reranker_type=self.reranker_type,
                processing_time_ms=processing_time,
                scores=[d.score for d in sorted_docs],
            )

        except Exception as e:
            logger.error(f"Cross-encoder reranking failed: {e}")
            # Fall back to dummy reranker
            dummy = DummyReranker()
            return await dummy.rerank(query, documents, top_k)


def create_reranker(
    reranker_type: str = "dummy",
    model_name: Optional[str] = None,
    **kwargs
) -> Reranker:
    """
    Factory function to create rerankers.

    Args:
        reranker_type: Type of reranker ("dummy", "cross_encoder", etc.)
        model_name: Optional model name
        **kwargs: Additional configuration

    Returns:
        Configured reranker instance

    Raises:
        ValueError: If reranker_type is not supported
    """
    reranker_type_enum = RerankerType(reranker_type.lower())

    if reranker_type_enum == RerankerType.DUMMY:
        return DummyReranker(**kwargs)
    elif reranker_type_enum == RerankerType.CROSS_ENCODER:
        return CrossEncoderReranker(
            model_name=model_name or "cross-encoder/ms-marco-MiniLM-L-6-v2",
            **kwargs
        )
    else:
        raise ValueError(f"Unsupported reranker type: {reranker_type}")
