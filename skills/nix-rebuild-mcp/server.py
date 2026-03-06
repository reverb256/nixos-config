"""
MCP Server for nix-rebuild skill.
Provides tools for safe NixOS rebuilding workflow.
"""

import asyncio
import json
import logging
from typing import Any, Dict, List, Optional
from pathlib import Path
import subprocess
import os

try:
    from mcp.server import Server
    from mcp.types import Tool, TextContent
    import mcp.server.stdio

    MCP_AVAILABLE = True
except ImportError:
    print("MCP SDK not available. Install with: pip install mcp")
    MCP_AVAILABLE = False

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Default hostname from environment or fallback to "zephyr"
DEFAULT_HOST = os.getenv("NIX_HOST", "zephyr")

# Get project root (assuming /etc/nixos)
PROJECT_ROOT = Path("/etc/nixos")


async def execute_command(
    command: List[str], cwd: Optional[Path] = None
) -> Dict[str, Any]:
    """Execute a shell command and return result."""
    try:
        process = await asyncio.create_subprocess_exec(
            *command,
            cwd=cwd or PROJECT_ROOT,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        stdout, stderr = await process.communicate()

        if process.returncode == 0:
            return {
                "success": True,
                "stdout": stdout.decode().strip(),
                "stderr": stderr.decode().strip(),
                "returncode": process.returncode,
            }
        else:
            return {
                "success": False,
                "error": stderr.decode().strip(),
                "returncode": process.returncode,
            }
    except Exception as e:
        return {"success": False, "error": str(e)}


async def nix_flake_check() -> Dict[str, Any]:
    """Run nix flake check (fast syntax validation)."""
    logger.info("Running nix flake check...")
    result = await execute_command(["nix", "flake", "check"])
    return result


async def nixos_rebuild_build(hostname: str) -> Dict[str, Any]:
    """Build configuration without applying (validate without system modification)."""
    logger.info(f"Building configuration for host: {hostname}")
    result = await execute_command(
        ["sudo", "nixos-rebuild", "build", "--flake", f".#{hostname}"]
    )
    return result


async def nixos_rebuild_test(hostname: str) -> Dict[str, Any]:
    """Test configuration (applies changes, rolls back on next boot)."""
    logger.info(f"Testing configuration for host: {hostname}")
    result = await execute_command(
        ["sudo", "nixos-rebuild", "test", "--flake", f".#{hostname}"]
    )
    return result


async def nixos_rebuild_switch(hostname: str) -> Dict[str, Any]:
    """Switch to new configuration (persist across reboots)."""
    logger.info(f"Switching configuration for host: {hostname}")
    result = await execute_command(
        ["sudo", "nixos-rebuild", "switch", "--flake", f".#{hostname}"]
    )
    return result


async def nix_flake_update() -> Dict[str, Any]:
    """Update all flake inputs."""
    logger.info("Updating flake inputs...")
    result = await execute_command(["nix", "flake", "update"])
    return result


def create_server() -> Optional[Server]:
    """Create and configure MCP server."""
    if not MCP_AVAILABLE:
        return None

    server = Server("nix-rebuild-mcp")

    # Tool definitions
    tools: List[Tool] = [
        Tool(
            name="nix_flake_check",
            description="Run nix flake check for fast syntax validation (takes ~5 seconds)",
            inputSchema={"type": "object", "properties": {}, "required": []},
        ),
        Tool(
            name="nixos_rebuild_build",
            description="Build configuration without applying changes (1-2 minutes). Validates but doesn't modify system.",
            inputSchema={
                "type": "object",
                "properties": {
                    "hostname": {
                        "type": "string",
                        "description": "Hostname to build for (default: zephyr)",
                        "default": DEFAULT_HOST,
                        "enum": ["zephyr", "forge", "nexus", "sentry"],
                    }
                },
                "required": [],
            },
        ),
        Tool(
            name="nixos_rebuild_test",
            description="Test configuration by applying temporarily, rolls back on next reboot. Safe way to test changes.",
            inputSchema={
                "type": "object",
                "properties": {
                    "hostname": {
                        "type": "string",
                        "description": "Hostname to test for (default: zephyr)",
                        "default": DEFAULT_HOST,
                        "enum": ["zephyr", "forge", "nexus", "sentry"],
                    }
                },
                "required": [],
            },
        ),
        Tool(
            name="nixos_rebuild_switch",
            description="Switch to new configuration (persists across reboots). Use after successful test.",
            inputSchema={
                "type": "object",
                "properties": {
                    "hostname": {
                        "type": "string",
                        "description": "Hostname to switch for (default: zephyr)",
                        "default": DEFAULT_HOST,
                        "enum": ["zephyr", "forge", "nexus", "sentry"],
                    }
                },
                "required": [],
            },
        ),
        Tool(
            name="nix_flake_update",
            description="Update all flake inputs (fetches latest versions of dependencies)",
            inputSchema={"type": "object", "properties": {}, "required": []},
        ),
    ]

    # Register tool handlers
    @server.call_tool()
    async def handle_tool_call(
        name: str, arguments: Dict[str, Any]
    ) -> List[TextContent]:
        """Handle tool calls."""
        logger.info(f"Tool call: {name} with arguments: {arguments}")

        try:
            if name == "nix_flake_check":
                result = await nix_flake_check()
            elif name == "nixos_rebuild_build":
                hostname = arguments.get("hostname", DEFAULT_HOST)
                result = await nixos_rebuild_build(hostname)
            elif name == "nixos_rebuild_test":
                hostname = arguments.get("hostname", DEFAULT_HOST)
                result = await nixos_rebuild_test(hostname)
            elif name == "nixos_rebuild_switch":
                hostname = arguments.get("hostname", DEFAULT_HOST)
                result = await nixos_rebuild_switch(hostname)
            elif name == "nix_flake_update":
                result = await nix_flake_update()
            else:
                result = {"success": False, "error": f"Unknown tool: {name}"}

            # Format result for MCP
            return [TextContent(type="text", text=json.dumps(result, indent=2))]

        except Exception as e:
            logger.error(f"Error executing tool {name}: {e}", exc_info=True)
            return [
                TextContent(
                    type="text",
                    text=json.dumps({"success": False, "error": str(e)}, indent=2),
                )
            ]

    # List tools
    @server.list_tools()
    async def list_tools() -> List[Tool]:
        """List available tools."""
        return tools

    return server


async def main():
    """Main entry point."""
    logger.info("Starting nix-rebuild MCP server...")

    server = create_server()
    if not server:
        logger.error("Failed to create MCP server - MCP SDK not available")
        return

    # Run server using stdio transport
    async with mcp.server.stdio.stdio_server() as (read_stream, write_stream):
        await server.run(
            read_stream, write_stream, server.create_initialization_options()
        )


if __name__ == "__main__":
    asyncio.run(main())
