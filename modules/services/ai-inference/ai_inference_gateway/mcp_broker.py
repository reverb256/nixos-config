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

            # For remote servers, we'd need to implement the actual MCP protocol
            # For now, return placeholder tools for known servers
            if server.type == MCPServerType.REMOTE:
                # Placeholder tools for known remote servers
                known_tools = {
                    "web-search-prime": ["web_search"],
                    "web-reader": ["fetch_url"],
                    "zread": ["github_repo", "github_file"],
                    "zai-mcp-server": ["zai_analyze", "zai_query"],
                }
                for tool in known_tools.get(name, []):
                    all_tools.append({
                        "server": name,
                        "name": tool,
                        "description": f"Tool from {name}",
                        "type": "remote"
                    })
            else:
                # Local server - would need to implement stdio communication
                all_tools.append({
                    "server": name,
                    "name": "local_tool",
                    "description": f"Tool from local server {name}",
                    "type": "local"
                })

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
        Call a tool on a remote MCP server via HTTP.

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

            # Make HTTP call to the MCP server
            # Note: This is a simplified implementation. Real MCP protocol would use
            # the proper JSON-RPC format and endpoints.
            async with httpx.AsyncClient(timeout=30.0) as client:
                response = await client.post(
                    f"{server.url}/tools/{tool_name}",
                    json=arguments,
                    headers=headers
                )
                response.raise_for_status()
                return response.json()

        except httpx.HTTPError as e:
            logger.error(f"Error calling remote tool {tool_name} on {server.name}: {e}")
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
                async with httpx.AsyncClient(timeout=5.0) as client:
                    response = await client.get(
                        f"{server.url}/health",
                        headers=server.headers or {}
                    )
                    return response.status_code == 200
            except Exception:
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
    # Check if MCP broker is enabled
    if not hasattr(config, 'mcp') or not config.mcp.enabled:
        logger.info("MCP broker disabled in configuration")
        return None

    servers = []

    # Add configured servers
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
