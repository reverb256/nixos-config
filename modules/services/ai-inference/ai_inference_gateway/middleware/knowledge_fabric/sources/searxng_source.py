"""
SearXNG Knowledge Source Adapter for Knowledge Fabric

Provides SearXNG metasearch integration for comprehensive web results.
"""

import logging
from dataclasses import dataclass
from typing import Any, Dict, List
import httpx

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
    SearXNG metasearch knowledge source.

    Provides aggregated search results from multiple search engines
    through SearXNG instance.
    """
    searxng_url: str = "http://127.0.0.1:8888"
    max_results: int = 5
    timeout: float = 30.0
    name: str = "searxng"
    description: str = "SearXNG metasearch"
    priority: SourcePriority = SourcePriority.MEDIUM
    capabilities: SourceCapability = (
        SourceCapability.REALTIME |
        SourceCapability.FACTUAL |
        SourceCapability.COMPARATIVE
    )

    async def retrieve(self, query: str, **kwargs) -> KnowledgeResult:
        """
        Execute search via SearXNG API.

        Returns results aggregated from multiple search engines.
        """
        import time
        start = time.time()

        sanitized_query = query[:500]

        chunks = []
        metadata = {
            "tool": "SearXNG",
            "engine": "metasearch",
        }

        try:
            params = {
                "q": sanitized_query,
                "format": "json",
                "engines": ["google", "bing", "duckduckgo"],
            }

            async with httpx.AsyncClient(timeout=self.timeout) as client:
                response = await client.get(
                    self.searxng_url,
                    params=params,
                )

                if response.status_code == 200:
                    data = response.json()

                    if data.get("results"):
                        for idx, result in enumerate(data["results"][:self.max_results]):
                            title = result.get("title", "")
                            snippet = result.get("content", result.get("snippet", ""))
                            url = result.get("url", "")

                            content_text = f"{title}\n{snippet}"

                            chunk = KnowledgeChunk(
                                content=content_text,
                                source=self.name,
                                score=1.0 - (idx * 0.1),
                                metadata={
                                    "url": url,
                                    "title": title,
                                    "engine": result.get("engine", ""),
                                },
                                capabilities=self.capabilities,
                            )
                            chunks.append(chunk)

                        metadata["total_results"] = len(chunks)
                else:
                    metadata["error"] = f"HTTP {response.status_code}"
                    logger.warning(f"SearXNG returned status {response.status_code}")

        except httpx.ConnectError as e:
            metadata["error"] = "Cannot connect to SearXNG"
            metadata["error_type"] = "connection_error"
            logger.error(f"SearXNG connection error: {e}")

        except httpx.TimeoutException:
            metadata["error"] = "Request timeout"
            metadata["error_type"] = "timeout"
            logger.error(f"SearXNG timeout after {self.timeout}s")

        except Exception as e:
            metadata["error"] = str(e)
            metadata["error_type"] = type(e).__name__
            logger.exception(f"SearXNG unexpected error: {e}")

        retrieval_time = time.time() - start

        return KnowledgeResult(
            source_name=self.name,
            chunks=chunks,
            query=query,
            retrieval_time=retrieval_time,
            metadata=metadata,
        )


def create_searxng_source(
    searxng_url: str = "http://127.0.0.1:8888",
    max_results: int = 5,
) -> SearXNGKnowledgeSource:
    """Factory function to create SearXNG knowledge source."""
    return SearXNGKnowledgeSource(
        searxng_url=searxng_url,
        max_results=max_results,
    )
