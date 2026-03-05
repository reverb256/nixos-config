"""
MCP Broker for AI Inference Gateway.

Proxies requests to configured MCP servers, both local (stdio)
and remote (SSE/HTTP). Provides unified API for all MCP tools.

This is a foundational implementation that can be extended with:
- Full MCP protocol support (stdio, SSE, HTTP transports)
- Tool schema caching and validation
- Request/response logging
- Health monitoring and circuit breaking
"""

import asyncio
import json
import logging
from typing import Dict, List, Optional, Any
from dataclasses import dataclass
from enum import Enum
import httpx

logger = logging.getLogger(__name__)


class MCPServerType(Enum):
    """MCP server types."""
    LOCAL = "local"   # stdio-based servers
    REMOTE = "remote" # HTTP/SSE servers


@dataclass
class MCPServer:
    """MCP server configuration."""
    name: str
    type: MCPServerType
    command: Optional[List[str]] = None
    url: Optional[str] = None
    headers: Dict[str, str] = None
    environment: Dict[str, str] = None
    process: Optional[asyncio.subprocess.Process] = None


class MCPBroker:
    """
    Manages MCP server connections and tool calls.

    Provides unified access to MCP tools from multiple servers.
    """

    def __init__(self, servers: List[MCPServer]):
        """
        Initialize MCP broker.

        Args:
            servers: List of MCP server configurations
        """
        self.servers = {server.name: server for server in servers}
        self.active_connections: Dict[str, Any] = {}
        logger.info(f"MCP Broker initialized with {len(servers)} servers")

    async def list_servers(self) -> List[Dict]:
        """
        List all configured MCP servers.

        Returns:
            List of server information dicts
        """
        servers_list = []
        for name, server in self.servers.items():
            servers_list.append({
                "name": server.name,
                "type": server.type.value,
                "url": server.url if server.type == MCPServerType.REMOTE else None,
                "healthy": await self.health_check(name)
            })
        return servers_list

    async def get_tools(self, server_name: Optional[str] = None) -> List[Dict]:
        """
        Get available tools from server(s).

        Args:
            server_name: Optional server name. If None, returns tools from all servers.

        Returns:
            List of available tools
        """
        if server_name:
            servers_to_check = [server_name]
        else:
            servers_to_check = list(self.servers.keys())

        all_tools = []
        for name in servers_to_check:
            if name not in self.servers:
                logger.warning(f"Server {name} not found")
                continue

            server = self.servers[name]

            # For remote servers, use MCP protocol to list tools
            if server.type == MCPServerType.REMOTE and server.url:
                try:
                    headers = {"Content-Type": "application/json"}
                    if server.headers:
                        headers.update(server.headers)

                    # Use MCP JSON-RPC protocol to list tools
                    mcp_request = {
                        "jsonrpc": "2.0",
                        "id": 1,
                        "method": "tools/list"
                    }

                    # ZAI MCP servers require SSE-capable Accept header
                    headers["Accept"] = "application/json, text/event-stream"

                    async with httpx.AsyncClient(timeout=10.0) as client:
                        response = await client.post(
                            server.url,
                            json=mcp_request,
                            headers=headers
                        )

                        if response.status_code == 200:
                            # Check if response is SSE format
                            content_type = response.headers.get("content-type", "")
                            if "text/event-stream" in content_type:
                                # Parse SSE response to get tools list
                                async for line in response.aiter_lines():
                                    if line.startswith("data:"):
                                        try:
                                            data = json.loads(line[5:].strip())
                                            if "result" in data and "tools" in data["result"]:
                                                for tool in data["result"]["tools"]:
                                                    all_tools.append({
                                                        "server": name,
                                                        "name": tool.get("name"),
                                                        "description": tool.get("description", ""),
                                                        "type": "remote"
                                                    })
                                                break  # Got the tools, stop parsing
                                        except json.JSONDecodeError:
                                            continue
                            else:
                                result = response.json()
                                # Check for JSON-RPC error
                                if "error" in result:
                                    logger.warning(f"MCP server {name} returned error: {result['error']}")
                                elif "result" in result and "tools" in result["result"]:
                                    # Extract tools from MCP response
                                    for tool in result["result"]["tools"]:
                                        all_tools.append({
                                            "server": name,
                                            "name": tool.get("name"),
                                            "description": tool.get("description", ""),
                                            "type": "remote"
                                        })
                                else:
                                    logger.warning(f"Unexpected response from MCP server {name}")
                        else:
                            logger.warning(f"Failed to list tools from {name}: HTTP {response.status_code}")

                except Exception as e:
                    logger.error(f"Error listing tools from {name}: {e}")
                    # Fallback to known tools for ZAI servers
                    known_tools = {
                        "web-search-prime": [{"name": "web_search", "description": "Web search via ZAI"}],
                        "web-reader": [{"name": "fetch_url", "description": "Fetch URL content"}],
                        "zread": [
                            {"name": "github_repo", "description": "GitHub repository analysis"},
                            {"name": "github_file", "description": "GitHub file reader"}
                        ],
                        "4-5v-mcp-server": [{"name": "analyze_image", "description": "Image analysis"}]
                    }
                    if name in known_tools:
                        for tool in known_tools[name]:
                            all_tools.append({
                                "server": name,
                                **tool
                            })
            else:
                # Local server - would need to implement stdio communication
                logger.warning(f"Local MCP server {name} not yet supported")

        return all_tools

    async def call_tool(
        self,
        server_name: str,
        tool_name: str,
        arguments: Dict
    ) -> Dict:
        """
        Call a tool on a specific MCP server.

        Args:
            server_name: Name of the MCP server
            tool_name: Name of the tool to call
            arguments: Tool arguments

        Returns:
            Tool execution result
        """
        if server_name not in self.servers:
            return {
                "error": f"Server {server_name} not found",
                "available_servers": list(self.servers.keys())
            }

        server = self.servers[server_name]

        if server.type == MCPServerType.REMOTE and server.url:
            # For remote servers, make HTTP call
            return await self._call_remote_tool(server, tool_name, arguments)
        else:
            # For local servers, would need to implement stdio communication
            return {
                "error": "Local MCP servers not yet implemented",
                "note": "This is a foundational implementation. Local stdio-based MCP servers need full protocol implementation."
            }

    async def _call_remote_tool(self, server: MCPServer, tool_name: str, arguments: Dict) -> Dict:
        """
        Call a tool on a remote MCP server via HTTP using MCP JSON-RPC protocol.

        Args:
            server: MCP server configuration
            tool_name: Name of the tool to call
            arguments: Tool arguments

        Returns:
            Tool execution result
        """
        try:
            # Build headers
            headers = {
                "Content-Type": "application/json"
            }
            if server.headers:
                headers.update(server.headers)

            # Use standard MCP JSON-RPC protocol
            # https://modelcontextprotocol.io/beta/docs/specification/
            mcp_request = {
                "jsonrpc": "2.0",
                "id": 1,
                "method": "tools/call",
                "params": {
                    "name": tool_name,
                    "arguments": arguments
                }
            }

            # ZAI MCP servers require SSE-capable Accept header
            headers["Accept"] = "application/json, text/event-stream"

            # Debug logging
            logger.debug(f"Calling MCP tool: {server.name}.{tool_name}")
            logger.debug(f"Request URL: {server.url}")
            logger.debug(f"Request headers: {headers}")
            logger.debug(f"Request body: {mcp_request}")

            async with httpx.AsyncClient(timeout=30.0) as client:
                response = await client.post(
                    server.url,
                    json=mcp_request,
                    headers=headers
                )
                logger.debug(f"Response status: {response.status_code}")

                # Handle SSE response from ZAI MCP servers
                if response.status_code == 200:
                    # Check if response is SSE format
                    content_type = response.headers.get("content-type", "")
                    if "text/event-stream" in content_type:
                        # Parse SSE response
                        async for line in response.aiter_lines():
                            if line.startswith("data:"):
                                try:
                                    data = json.loads(line[5:].strip())
                                    # Check for JSON-RPC response
                                    if "result" in data:
                                        return data["result"]
                                    elif "error" in data:
                                        return {
                                            "error": data["error"],
                                            "server": server.name,
                                            "tool": tool_name
                                        }
                                except json.JSONDecodeError:
                                    continue
                        return {
                            "error": "No valid data in SSE response",
                            "server": server.name,
                            "tool": tool_name
                        }
                    else:
                        # Regular JSON response
                        result = response.json()
                        # Check for JSON-RPC error response
                        if "error" in result:
                            return {
                                "error": result["error"],
                                "server": server.name,
                                "tool": tool_name
                            }
                        # Return the result part of JSON-RPC response
                        return result.get("result", result)
                else:
                    return {
                        "error": f"HTTP {response.status_code}: {response.text[:200]}",
                        "server": server.name,
                        "tool": tool_name
                    }

        except httpx.HTTPError as e:
            logger.error(f"HTTP error calling remote tool {tool_name} on {server.name}: {e}")
            return {
                "error": str(e),
                "server": server.name,
                "tool": tool_name
            }
        except Exception as e:
            logger.error(f"Unexpected error calling remote tool: {e}")
            return {
                "error": f"Unexpected error: {str(e)}",
                "server": server.name,
                "tool": tool_name
            }

    async def health_check(self, server_name: str) -> bool:
        """
        Check if MCP server is responsive.

        Args:
            server_name: Name of the server to check

        Returns:
            True if server is healthy, False otherwise
        """
        if server_name not in self.servers:
            return False

        server = self.servers[server_name]

        if server.type == MCPServerType.REMOTE and server.url:
            try:
                headers = {
                    "Content-Type": "application/json",
                    "Accept": "application/json, text/event-stream"
                }
                if server.headers:
                    headers.update(server.headers)

                # Try to ping the server using MCP initialize method
                mcp_request = {
                    "jsonrpc": "2.0",
                    "id": 1,
                    "method": "initialize",
                    "params": {
                        "protocolVersion": "2024-11-05",
                        "capabilities": {},
                        "clientInfo": {
                            "name": "ai-inference-gateway",
                            "version": "2.0.0"
                        }
                    }
                }

                async with httpx.AsyncClient(timeout=5.0) as client:
                    response = await client.post(
                        server.url,
                        json=mcp_request,
                        headers=headers
                    )
                    # Accept any 2xx response as healthy
                    return 200 <= response.status_code < 300
            except Exception as e:
                logger.debug(f"Health check failed for {server_name}: {e}")
                return False
        else:
            # For local servers, we'd check if the process is running
            return server.process is not None if server.process else False


async def create_mcp_broker_from_config(config) -> Optional[MCPBroker]:
    """
    Create MCP broker from gateway configuration.

    Args:
        config: Gateway configuration

    Returns:
        MCPBroker instance or None if MCP is disabled
    """
    import os
    import json

    # Check if MCP broker is enabled via config
    mcp_enabled = False
    if hasattr(config, 'mcp') and hasattr(config.mcp, 'enabled'):
        mcp_enabled = config.mcp.enabled

    # Also check environment variable for Nix-based configuration
    if os.getenv("MCP_ENABLED"):
        mcp_enabled = os.getenv("MCP_ENABLED").lower() == "true"

    if not mcp_enabled:
        logger.info("MCP broker disabled in configuration")
        return None

    servers = []

    # Try to load from environment variable (Nix format)
    mcp_servers_json = os.getenv("MCP_SERVERS")
    if mcp_servers_json:
        try:
            mcp_servers_dict = json.loads(mcp_servers_json)
            logger.info(f"Loading MCP servers from environment: {list(mcp_servers_dict.keys())}")

            for server_name, server_config in mcp_servers_dict.items():
                # Check if server is enabled
                if not server_config.get("enabled", True):
                    continue

                # Read API key from file if specified in headers
                headers = dict(server_config.get("headers", {}))
                for header_name, header_value in list(headers.items()):
                    if isinstance(header_value, str) and "/run/" in header_value and "-key" in header_value:
                        try:
                            # Extract file path from "Bearer /path/to/key" or just "/path/to/key"
                            if header_value.startswith("Bearer "):
                                file_path = header_value.split(" ", 1)[1].strip()
                                use_bearer = True
                            else:
                                file_path = header_value
                                use_bearer = False

                            with open(file_path, "r") as f:
                                api_key = f.read().strip()
                                if use_bearer:
                                    headers[header_name] = f"Bearer {api_key}"
                                else:
                                    headers[header_name] = api_key
                            logger.info(f"Loaded API key from {file_path} for {server_name}/{header_name}")
                        except Exception as e:
                            logger.warning(f"Failed to read API key from {header_value}: {e}")

                server = MCPServer(
                    name=server_name,
                    type=MCPServerType.REMOTE,  # Nix config only supports remote servers
                    url=server_config.get("url"),
                    headers=headers,
                    command=None,
                    environment=None
                )
                servers.append(server)
                logger.info(f"Added MCP server: {server.name} (remote)")
        except json.JSONDecodeError as e:
            logger.error(f"Failed to parse MCP_SERVERS environment variable: {e}")
            return None
    elif hasattr(config, 'mcp') and hasattr(config.mcp, 'servers'):
        # Fallback to config object (Python-based configuration)
        for server_config in config.mcp.servers:
            server_type = MCPServerType.LOCAL if server_config.type == "local" else MCPServerType.REMOTE

            server = MCPServer(
                name=server_config.name,
                type=server_type,
                command=server_config.command,
                url=server_config.url,
                headers=server_config.headers,
                environment=server_config.environment
            )
            servers.append(server)
            logger.info(f"Added MCP server: {server.name} ({server_type.value})")

    if not servers:
        logger.warning("MCP broker enabled but no servers configured")
        return None

    return MCPBroker(servers=servers)
