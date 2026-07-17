"""
SearXNG Knowledge Source Adapter for Knowledge Fabric

Provides HTTP-based meta-search capabilities through the local SearXNG instance.
SearXNG aggregates results from multiple search engines while respecting privacy.
"""

import logging
from dataclasses import dataclass
from typing import Any, Dict, List
import httpx
import time

from ..core import (
    KnowledgeChunk,
    KnowledgeResult,
    SourceCapability,
    SourcePriority,
)

logger = logging.getLogger(__name__)


@dataclass
class SearXNGKnowledgeSource:
    """
    SearXNG knowledge source for web-based meta-search.

    Provides privacy-respecting search results from multiple engines
    through the local SearXNG instance running in Kubernetes.

    Note: Uses cluster DNS (searxng.search.svc.cluster.local:8080) for internal K8s communication.
    """
    searxng_url: str = "http://searxng.search.svc.cluster.local:8080"  # Kubernetes service (cluster DNS)
    max_results: int = 5
    timeout: float = 30.0
    name: str = "searxng"
    description: str = "Privacy-respecting metasearch engine"
    priority: SourcePriority = SourcePriority.MEDIUM
    capabilities: SourceCapability = (
        SourceCapability.FACTUAL | SourceCapability.REALTIME | SourceCapability.COMPARATIVE
    )

    async def retrieve(self, query: str, **kwargs) -> KnowledgeResult:
        """
        Execute a search query against SearXNG.
        """
        start_time = time.time()

        # Extract optional parameters
        category = kwargs.get('category', 'general')
        language = kwargs.get('language', 'all')
        time_range = kwargs.get('time_range', None)
        engines = kwargs.get('engines', None)

        # Build request parameters
        params = {
            'q': query,
            'format': 'json',
        }

        if category != 'general':
            params['categories'] = category
        if language != 'all':
            params['language'] = language
        if time_range:
            params['time_range'] = time_range
        if engines:
            params['engines'] = engines

        chunks: List[KnowledgeChunk] = []
        metadata: Dict[str, Any] = {
            'category': category,
            'language': language,
            'engines_used': engines,
        }

        try:
            # Execute HTTP GET request to SearXNG
            async with httpx.AsyncClient(timeout=self.timeout) as client:
                response = await client.get(
                    f"{self.searxng_url}/search",
                    params=params,
                )
                response.raise_for_status()

                # Parse JSON response
                data = response.json()
                results = data.get('results', [])

                # Map each result to KnowledgeChunk
                for idx, result in enumerate(results[:self.max_results]):
                    # Extract content
                    content = (
                        result.get('content') or
                        result.get('snippet') or
                        result.get('title', '')
                    )

                    chunk = KnowledgeChunk(
                        content=content,
                        source='searxng',
                        score=1.0 - (idx * 0.1),  # Decay score by rank
                        metadata={
                            'url': result.get('url', ''),
                            'title': result.get('title', ''),
                            'engine': result.get('engine', ''),
                            'category': result.get('category', ''),
                        },
                        capabilities=SourceCapability.FACTUAL | SourceCapability.REALTIME,
                    )
                    chunks.append(chunk)

                metadata['total_results'] = len(results)

        except httpx.HTTPStatusError as e:
            logger.error(f"SearXNG HTTP error: {e.response.status_code}")
            metadata['error'] = f"HTTP {e.response.status_code}"
            metadata['error_type'] = 'http_error'

        except httpx.ConnectError as e:
            logger.error(f"SearXNG connection error: {e}")
            metadata['error'] = "Cannot connect to SearXNG service"
            metadata['error_type'] = 'connection_error'
            metadata['suggestion'] = "Check if SearXNG is running: systemctl status searx"

        except Exception as e:
            logger.exception(f"Unexpected error in SearXNG retrieval: {e}")
            metadata['error'] = str(e)
            metadata['error_type'] = type(e).__name__

        retrieval_time = time.time() - start_time

        return KnowledgeResult(
            source_name='searxng',
            chunks=chunks,
            query=query,
            retrieval_time=retrieval_time,
            metadata=metadata,
        )


def create_searxng_source(
    searxng_url: str = "http://searxng.search.svc.cluster.local:8080",
    max_results: int = 5,
) -> SearXNGKnowledgeSource:
    """
    Factory function to create SearXNG knowledge source.

    Args:
        searxng_url: SearXNG service URL
            - Inside K8s: http://searxng.search.svc.cluster.local:8080 (default)
            - Via Caddy ingress: https://search.cluster.local
            - Via NodePort: http://10.1.1.110:30080 (needs Host: search.cluster.local header)
        max_results: Maximum number of results to return

    Returns:
        Configured SearXNGKnowledgeSource instance
    """
    return SearXNGKnowledgeSource(
        searxng_url=searxng_url,
        max_results=max_results,
    )
