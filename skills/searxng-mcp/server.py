#!/usr/bin/env python3
"""
SearXNG MCP Server - Privacy-respecting metasearch integration

Provides tools for searching the web through local SearXNG instance.
Follows MCP best practices: clear tool names, structured output, actionable errors.
"""

import asyncio
import json
from typing import Any
from urllib.parse import urlencode, urlparse

import httpx
from mcp.server import Server
from mcp.server.stdio import stdio_server
from mcp.types import Tool, TextContent

# Configuration
SEARXNG_URL = "http://127.0.0.1:7777"
SEARCH_ENDPOINT = "/search"

# Initialize MCP server
server = Server("searxng-mcp")

# HTTP client with timeout
client = httpx.AsyncClient(timeout=30.0)


def format_search_result(result: dict[str, Any]) -> str:
    """Format a single search result with key information."""
    title = result.get("title", "Untitled")
    url = result.get("url", "")
    snippet = result.get("content", result.get("snippet", ""))
    engine = result.get("engine", "unknown")
    score = result.get("score", 0)

    return f"""
**{title}**
Source: {engine}
URL: {url}
Relevance: {score}

{snippet}
---
""".strip()


def format_error(message: str, suggestion: str | None = None) -> str:
    """Format an error message with optional suggestion."""
    error_msg = f"❌ Error: {message}"
    if suggestion:
        error_msg += f"\n\n💡 Suggestion: {suggestion}"
    return error_msg


@server.list_tools()
async def list_tools() -> list[Tool]:
    """List available SearXNG tools."""
    return [
        Tool(
            name="searxng_search",
            description="Search the web using SearXNG privacy-respecting metasearch engine. "
            "Returns relevant results from multiple search engines with no tracking.",
            inputSchema={
                "type": "object",
                "properties": {
                    "query": {
                        "type": "string",
                        "description": "Search query (e.g., 'NixOS flake configuration')",
                    },
                    "category": {
                        "type": "string",
                        "description": "Search category: general, images, videos, news, science, it, files, map, music",
                        "enum": ["general", "images", "videos", "news", "science", "it", "files", "map", "music"],
                        "default": "general",
                    },
                    "language": {
                        "type": "string",
                        "description": "Language code (e.g., 'en', 'en-US', 'all')",
                        "default": "all",
                    },
                    "time_range": {
                        "type": "string",
                        "description": "Time filter: day, week, month, year",
                        "enum": ["day", "week", "month", "year"],
                    },
                    "max_results": {
                        "type": "number",
                        "description": "Maximum number of results (1-50)",
                        "default": 10,
                        "minimum": 1,
                        "maximum": 50,
                    },
                },
                "required": ["query"],
            },
        ),
        Tool(
            name="searxng_ping",
            description="Check if SearXNG service is accessible and healthy.",
            inputSchema={
                "type": "object",
                "properties": {},
            },
        ),
    ]


@server.call_tool()
async def call_tool(name: str, arguments: dict[str, Any]) -> list[TextContent]:
    """Handle tool calls for SearXNG operations."""

    if name == "searxng_ping":
        return await searxng_ping()

    elif name == "searxng_search":
        return await searxng_search(arguments)

    else:
        return [TextContent(format_error(f"Unknown tool: {name}", "Available tools: searxng_search, searxng_ping"))]


async def searxng_ping() -> list[TextContent]:
    """Check SearXNG service health."""
    try:
        response = await client.get(f"{SEARXNG_URL}{SEARCH_ENDPOINT}", params={"q": "test"}, timeout=5.0)
        if response.status_code == 200:
            return [TextContent("✅ SearXNG is accessible and responsive")]
        else:
            return [TextContent(format_error(
                f"SearXNG returned HTTP {response.status_code}",
                "Check if SearXNG service is running: systemctl status searx"
            ))]
    except httpx.ConnectError:
        return [TextContent(format_error(
            "Cannot connect to SearXNG service",
            "1. Ensure SearXNG is enabled: services.searxng.enable = true\n"
            "2. Check service status: systemctl status searx\n"
            "3. Verify URL is correct: http://127.0.0.1:7777"
        ))]
    except Exception as e:
        return [TextContent(format_error(f"Unexpected error: {e}", "Check SearXNG logs: journalctl -u searx"))]


async def searxng_search(arguments: dict[str, Any]) -> list[TextContent]:
    """Perform search using SearXNG."""
    query = arguments.get("query", "").strip()
    category = arguments.get("category", "general")
    language = arguments.get("language", "all")
    time_range = arguments.get("time_range")
    max_results = min(arguments.get("max_results", 10), 50)

    if not query:
        return [TextContent(format_error("Query cannot be empty", "Provide a search query, e.g., 'NixOS configuration'"))]

    # Build query parameters
    params = {
        "q": query,
        "format": "json",
        "engines": ",".join(["google", "bing", "duckduckgo"]),  # Default engines
    }

    if category != "general":
        params["categories"] = category

    if language != "all":
        params["language"] = language

    if time_range:
        params["time_range"] = time_range

    try:
        response = await client.get(
            f"{SEARXNG_URL}/search",
            params=params,
            timeout=30.0
        )
        response.raise_for_status()

        data = response.json()
        results = data.get("results", [])

        if not results:
            return [TextContent(f"🔍 No results found for: {query}\n\nTry different search terms or broader category.")]

        # Limit results
        results = results[:max_results]

        # Format output
        formatted = f"🔍 Found {len(data.get('results', []))} results for: {query}\n\n"
        formatted += "\n".join(format_search_result(r) for r in results)

        return [TextContent(formatted)]

    except httpx.HTTPStatusError as e:
        return [TextContent(format_error(
            f"HTTP error from SearXNG: {e.response.status_code}",
            "Check SearXNG is configured correctly and accessible"
        ))]
    except httpx.ConnectError:
        return [TextContent(format_error(
            "Cannot connect to SearXNG",
            "1. Enable SearXNG in NixOS config\n"
            "2. Start service: systemctl start searx\n"
            "3. Check it's listening: curl http://127.0.0.1:7777/search?q=test"
        ))]
    except json.JSONDecodeError:
        return [TextContent(format_error(
            "Invalid JSON response from SearXNG",
            "SearXNG may be misconfigured. Check logs: journalctl -u searx -f"
        ))]
    except Exception as e:
        return [TextContent(format_error(f"Unexpected error: {e}", "Check SearXNG logs for details"))]


async def main():
    """Main entry point for the MCP server."""
    async with stdio_server() as (read_stream, write_stream):
        await server.run(
            read_stream,
            write_stream,
            server.create_initialization_options()
        )


if __name__ == "__main__":
    asyncio.run(main())
