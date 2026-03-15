#!/usr/bin/env python3
"""
SearXNG MCP Server

Exposes SearXNG metasearch as MCP tools for AI agents.
Based on the official MCP server pattern from modelcontextprotocol/servers.

Usage:
    python -m ai_inference_gateway.mcp_servers.searxng_server

Environment Variables:
    SEARXNG_URL: SearXNG instance URL (default: http://127.0.0.1:7777)
    SEARXNG_CACHE_TTL: Cache TTL in seconds (default: 300)

Configuration for Claude.app/Cursor:
    {
      "mcpServers": {
        "searxng": {
          "command": "python",
          "args": ["-m", "ai_inference_gateway.mcp_servers.searxng_server"],
          "env": {
            "SEARXNG_URL": "http://127.0.0.1:7777"
          }
        }
      }
    }
"""

import asyncio
import json
import logging
import os
from typing import Annotated

from mcp.server import Server
from mcp.server.stdio import stdio_server
from mcp.types import TextContent, Tool
from pydantic import BaseModel, Field

# Import SearXNG integration
try:
    from ai_inference_gateway.searxng_integration import SearxngIntegration
    SEARXNG_AVAILABLE = True
except ImportError:
    SEARXNG_AVAILABLE = False
    SearxngIntegration = None

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Server metadata
SERVER_NAME = "mcp-searxng"
SERVER_VERSION = "1.0.0"

# SearXNG configuration
SEARXNG_URL = os.getenv("SEARXNG_URL", "http://127.0.0.1:7777")
SEARXNG_CACHE_TTL = int(os.getenv("SEARXNG_CACHE_TTL", "300"))


# ============================================================================
# INPUT SCHEMAS (Pydantic models for validation)
# ============================================================================

class WebSearchParams(BaseModel):
    """Parameters for web search."""

    query: Annotated[str, Field(description="Search query string")]
    category: Annotated[
        str,
        Field(
            description="Search category",
            default="general",
        ),
    ]
    max_results: Annotated[
        int,
        Field(
            default=10,
            description="Maximum number of results to return",
            ge=1,
            le=50,
        ),
    ]
    language: Annotated[
        str,
        Field(
            default="all",
            description="Language filter (e.g., 'en', 'fr', 'de', 'all')",
        ),
    ]
    time_range: Annotated[
        str | None,
        Field(
            default=None,
            description="Time range filter (day, week, month, year)",
        ),
    ]
    use_cache: Annotated[
        bool,
        Field(
            default=True,
            description="Use cached results if available",
        ),
    ]


class EmptyParams(BaseModel):
    """Empty parameters for stats/cache operations."""
    pass


# ============================================================================
# TOOL DEFINITIONS
# ============================================================================

TOOLS: list[Tool] = [
    Tool(
        name="web_search",
        description=(
            "Perform web search using SearXNG metasearch engine. "
            "Aggregates results from multiple search engines (Google, Bing, DuckDuckGo, etc.). "
            "Returns relevant results with auto-improving features like query pattern learning "
            "and adaptive engine selection. Supports different categories: general, images, videos, "
            "news, science, IT, files, music, map."
        ),
        inputSchema=WebSearchParams.model_json_schema,
    ),
    Tool(
        name="search_stats",
        description=(
            "Get SearXNG learning statistics including query patterns, "
            "engine performance metrics, cache size, and top cached queries. "
            "Useful for understanding what the system has learned from previous searches."
        ),
        inputSchema=EmptyParams.model_json_schema,
    ),
    Tool(
        name="clear_search_cache",
        description=(
            "Clear the SearXNG response cache. Useful when you want fresh results "
            "or to free up memory. Cached results are automatically refreshed after 5 minutes."
        ),
        inputSchema=EmptyParams.model_json_schema,
    ),
    Tool(
        name="ping_searxng",
        description=(
            "Check if SearXNG service is accessible and healthy. "
            "Returns status and connection information."
        ),
        inputSchema=EmptyParams.model_json_schema,
    ),
]


# ============================================================================
# SERVER IMPLEMENTATION
# ============================================================================

async def serve() -> None:
    """Run the SearXNG MCP server."""
    if not SEARXNG_AVAILABLE:
        logger.error("SearXNG integration not available. Exiting.")
        logger.error("Ensure searxng_integration.py is in the Python path.")
        return

    # Initialize SearXNG integration
    searxng = SearxngIntegration(cache_ttl=SEARXNG_CACHE_TTL)
    logger.info(f"SearXNG MCP Server initialized (url={SEARXNG_URL}, cache_ttl={SEARXNG_CACHE_TTL}s)")

    # Create MCP server
    server = Server(SERVER_NAME)

    @server.list_tools()
    async def list_tools() -> list[Tool]:
        """List available tools."""
        return TOOLS

    @server.call_tool()
    async def call_tool(name: str, arguments: dict) -> list[TextContent]:
        """Handle tool calls."""

        try:
            if name == "web_search":
                params = WebSearchParams(**arguments)
                result = await searxng.search(
                    query=params.query,
                    category=params.category,
                    max_results=params.max_results,
                    language=params.language,
                    time_range=params.time_range,
                    use_cache=params.use_cache,
                    learning_enabled=True,
                )

                # Format results for AI consumption
                if "error" in result:
                    return [TextContent(
                        type="text",
                        text=f"Search Error: {result['error']}"
                    )]

                if not result.get("results"):
                    return [TextContent(
                        type="text",
                        text=f"No results found for query: '{params.query}'"
                    )]

                # Build formatted response
                lines = []
                lines.append(f"# Search Results for: {params.query}")
                lines.append(f"**Category:** {result.get('category', 'general')}")
                lines.append(f"**Cached:** {result.get('cached', False)}")
                lines.append(f"**Engines:** {', '.join(result.get('engines_used', []))}")
                lines.append("")

                for i, item in enumerate(result.get("results", [])[:params.max_results], 1):
                    lines.append(f"## {i}. {item.get('title', 'Untitled')}")
                    lines.append(f"- **URL:** {item.get('url', 'N/A')}")
                    lines.append(f"- **Engine:** {item.get('engine', 'unknown')}")

                    if item.get('content'):
                        # Truncate long content
                        content = item['content'][:300]
                        if len(item['content']) > 300:
                            content += "..."
                        lines.append(f"- **Snippet:** {content}")
                    lines.append("")

                # Include suggestions if available
                if result.get("suggestions"):
                    lines.append("## Suggestions")
                    for suggestion in result["suggestions"]:
                        lines.append(f"- **{suggestion.get('suggestion', '')}:** {suggestion.get('reason', '')}")

                return [TextContent(
                    type="text",
                    text="\n".join(lines)
                )]

            elif name == "search_stats":
                stats = await searxng.get_learning_stats()
                return [TextContent(
                    type="text",
                    text=json.dumps(stats, indent=2)
                )]

            elif name == "clear_search_cache":
                searxng.clear_cache()
                return [TextContent(
                    type="text",
                    text="SearXNG cache cleared successfully"
                )]

            elif name == "ping_searxng":
                import httpx

                try:
                    async with httpx.AsyncClient(timeout=5.0) as client:
                        response = await client.get(f"{SEARXNG_URL}/")
                        if response.status_code == 200:
                            return [TextContent(
                                type="text",
                                text=json.dumps({
                                    "status": "healthy",
                                    "service": "SearXNG",
                                    "url": SEARXNG_URL,
                                    "cache_ttl": SEARXNG_CACHE_TTL
                                }, indent=2)
                            )]
                        else:
                            return [TextContent(
                                type="text",
                                text=f"SearXNG unhealthy: HTTP {response.status_code}"
                            )]
                except Exception as e:
                    return [TextContent(
                        type="text",
                        text=f"SearXNG unreachable: {str(e)}"
                    )]

            else:
                return [TextContent(
                    type="text",
                    text=f"Unknown tool: {name}"
                )]

        except Exception as e:
            logger.exception(f"Error in tool call ({name}): {e}")
            return [TextContent(
                type="text",
                text=f"Error: {str(e)}"
            )]


# ============================================================================
# MAIN ENTRY POINT
# ============================================================================

def main():
    """Main entry point for SearXNG MCP server."""
    logger.info(f"Starting {SERVER_NAME} v{SERVER_VERSION}")
    logger.info(f"SearXNG URL: {SEARXNG_URL}")
    logger.info(f"Cache TTL: {SEARXNG_CACHE_TTL}s")

    async with stdio_server() as (read_stream, write_stream):
        await serve()


if __name__ == "__main__":
    asyncio.run(main())
