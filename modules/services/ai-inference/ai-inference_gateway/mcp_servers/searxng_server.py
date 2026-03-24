"""
SearXNG MCP Server for AI Inference Gateway

Provides Model Context Protocol server implementation for SearXNG search integration.
"""

import logging
import json
from typing import Any, Dict, List, Optional
from http.server import BaseHTTPRequestHandler, HTTPServer
import urllib.parse
import asyncio
import httpx

logger = logging.getLogger(__name__)


class SearXNGMCPServer:
    """
    MCP Server for SearXNG search capabilities.

    Exposes SearXNG search functionality via the Model Context Protocol.
    """

    def __init__(
        self,
        searxng_url: str = "http://searxng.search.svc.cluster.local:8080",
        host: str = "0.0.0.0",
        port: int = 8081,
    ):
        self.searxng_url = searxng_url
        self.host = host
        self.port = port
        self.server = None

    async def search(self, query: str, **kwargs) -> Dict[str, Any]:
        """
        Execute a search query against SearXNG.

        Args:
            query: Search query string
            **kwargs: Additional parameters (category, language, engines, etc.)

        Returns:
            Dict with search results and metadata
        """
        category = kwargs.get('category', 'general')
        language = kwargs.get('language', 'all')
        time_range = kwargs.get('time_range', None)
        engines = kwargs.get('engines', None)

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

        try:
            async with httpx.AsyncClient(timeout=30.0) as client:
                response = await client.get(
                    f"{self.searxng_url}/search",
                    params=params,
                )
                response.raise_for_status()
                data = response.json()

                results = []
                for idx, result in enumerate(data.get('results', [])):
                    results.append({
                        'title': result.get('title', ''),
                        'url': result.get('url', ''),
                        'content': result.get('content') or result.get('snippet', ''),
                        'engine': result.get('engine', ''),
                        'category': result.get('category', ''),
                        'score': 1.0 - (idx * 0.1),
                    })

                return {
                    'success': True,
                    'query': query,
                    'results': results,
                    'total_results': len(data.get('results', [])),
                    'metadata': {
                        'category': category,
                        'language': language,
                        'engines': list(set(r.get('engine') for r in data.get('results', []))),
                    }
                }

        except httpx.HTTPStatusError as e:
            logger.error(f"SearXNG HTTP error: {e.response.status_code}")
            return {
                'success': False,
                'error': f"HTTP {e.response.status_code}",
                'query': query,
            }

        except httpx.ConnectError as e:
            logger.error(f"SearXNG connection error: {e}")
            return {
                'success': False,
                'error': "Cannot connect to SearXNG service",
                'query': query,
                'suggestion': "Check if SearXNG is running in the search namespace",
            }

        except Exception as e:
            logger.exception(f"Unexpected error in SearXNG search: {e}")
            return {
                'success': False,
                'error': str(e),
                'query': query,
            }

    async def handle_request(self, method: str, params: Dict[str, Any]) -> Dict[str, Any]:
        """
        Handle MCP request.

        Args:
            method: MCP method name
            params: Method parameters

        Returns:
            MCP response dict
        """
        if method == 'tools/search':
            return await self.search(params.get('query', ''), **params.get('kwargs', {}))
        elif method == 'tools/list':
            return {
                'tools': [
                    {
                        'name': 'search',
                        'description': 'Search the web using SearXNG',
                        'inputSchema': {
                            'type': 'object',
                            'properties': {
                                'query': {'type': 'string', 'description': 'Search query'},
                                'category': {'type': 'string', 'description': 'Search category (general, images, videos, etc.)'},
                                'language': {'type': 'string', 'description': 'Language filter'},
                            },
                            'required': ['query'],
                        },
                    }
                ]
            }
        else:
            return {
                'error': f'Unknown method: {method}',
            }

    def run(self):
        """Start the MCP server (blocking)."""
        # For now, just log that server would start
        logger.info(f"SearXNG MCP server would start on {self.host}:{self.port}")
        logger.info(f"Connected to SearXNG at: {self.searxng_url}")
        logger.info("MCP server running in async mode - use async methods instead")


async def test_searxng_connection():
    """Test SearXNG connection."""
    server = SearXNGMCPServer()
    result = await server.search("test query")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    import sys
    logging.basicConfig(level=logging.INFO)
    asyncio.run(test_searxng_connection())
