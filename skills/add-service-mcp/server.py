"""
MCP Server for add-service skill.
Provides tools for creating systemd service modules.
"""

import asyncio
import json
import logging
from typing import Any, Dict, List
from pathlib import Path
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

# Project paths
PROJECT_ROOT = Path("/etc/nixos")
MODULES_DIR = PROJECT_ROOT / "modules"
SERVICES_DIR = MODULES_DIR / "services"
HOSTS_DIR = PROJECT_ROOT / "hosts"


# Service template
SERVICE_TEMPLATE = """{ config, lib, pkgs, ... }:
let
  cfg = config.services.SERVICE-NAME;
  inherit (lib) mkEnableOption mkOption types mkIf;
in
{{
  options.services.SERVICE-NAME = {{
    enable = mkEnableOption "SERVICE-NAME service";

    SERVICE-OPTIONS
  }};

  config = mkIf cfg.enable {{
    # Add packages
    environment.systemPackages = with pkgs; [
      PACKAGE-NAME
    ];

    # Add systemd service
    systemd.services.SERVICE-NAME = {{
      description = "SERVICE-NAME service";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      serviceConfig = {{
        ExecStart = "${{pkgs.PACKAGE-NAME}}/bin/BINARY";
        Restart = "on-failure";
        DynamicUser = true;
      }};
    }};

    # Optional: Open firewall ports
    # networking.firewall.allowedTCPPorts = [ cfg.port ];
  }};
}}"""


async def create_service_module(
    service_name: str, description: str, hostname: str = "zephyr"
) -> Dict[str, Any]:
    """Create a new systemd service module."""
    try:
        # Validate service name (kebab-case)
        service_slug = service_name.lower().replace("_", "-").replace(" ", "-")

        # Create service directory
        service_dir = SERVICES_DIR / service_slug
        service_dir.mkdir(parents=True, exist_ok=True)

        # Create module file
        module_file = service_dir / f"{service_slug}.nix"

        # Generate template with placeholders
        template = SERVICE_TEMPLATE.replace("SERVICE-NAME", service_slug)

        with open(module_file, "w") as f:
            f.write(f"# {description}\n\n")
            f.write(template)

        return {
            "success": True,
            "path": str(module_file),
            "message": f"Created service module at {module_file}",
        }
    except Exception as e:
        return {"success": False, "error": str(e)}


async def register_module_in_default(
    service_name: str, service_path: str
) -> Dict[str, Any]:
    """Register module in modules/default.nix."""
    try:
        default_file = MODULES_DIR / "default.nix"

        if not default_file.exists():
            return {"success": False, "error": f"{default_file} not found"}

        # Read current content
        with open(default_file, "r") as f:
            content = f.read()

        # Check if already registered
        import_line = f"services.{service_name} = import ./services/{service_name}/{service_name}.nix;"
        if import_line in content:
            return {
                "success": True,
                "already_registered": True,
                "message": f"Module {service_name} already registered",
            }

        # Find imports section and add new import
        if "imports = [" in content:
            # Add to existing imports list
            new_line = (
                f"    ./services/{service_name}/{service_name}.nix  # {service_name}"
            )
            content = content.replace("imports = [", f"imports = [\n{new_line},")
        else:
            # Create imports section
            content = content.replace(
                "{",
                "{\n  imports = [\n    ./services/{service_name}/{service_name}.nix  # {service_name}\n  ];",
            )

        # Write back
        with open(default_file, "w") as f:
            f.write(content)

        return {
            "success": True,
            "path": str(default_file),
            "message": f"Registered {service_name} in {default_file}",
        }
    except Exception as e:
        return {"success": False, "error": str(e)}


async def enable_service_on_host(
    service_name: str, hostname: str = "zephyr"
) -> Dict[str, Any]:
    """Enable service on host configuration."""
    try:
        host_file = HOSTS_DIR / hostname / "configuration.nix"

        if not host_file.exists():
            return {"success": False, "error": f"Host config {host_file} not found"}

        # Read current content
        with open(host_file, "r") as f:
            content = f.read()

        # Check if already enabled
        enable_line = f"services.{service_name}.enable = true;"
        if enable_line in content:
            return {
                "success": True,
                "already_enabled": True,
                "message": f"Service {service_name} already enabled on {hostname}",
            }

        # Add enable line (after existing services)
        if "services {" in content:
            # Find services section and add
            content = content.replace(
                "services {",
                f"services {{\n  {service_name}.enable = true;  # Added by add-service MCP",
            )
        else:
            # Add new services section
            content = (
                content.rstrip()
                + f"\nservices {{\n  {service_name}.enable = true;  # Added by add-service MCP\n}}"
            )

        # Write back
        with open(host_file, "w") as f:
            f.write(content)

        return {
            "success": True,
            "path": str(host_file),
            "message": f"Enabled {service_name} on {hostname}",
        }
    except Exception as e:
        return {"success": False, "error": str(e)}


async def get_service_template() -> Dict[str, Any]:
    """Get service module template for reference."""
    return {
        "success": True,
        "template": SERVICE_TEMPLATE,
        "notes": "Replace placeholders: SERVICE-NAME, SERVICE-OPTIONS, PACKAGE-NAME, BINARY",
    }


def create_server() -> Server:
    """Create and configure MCP server."""
    if not MCP_AVAILABLE:
        return None

    server = Server("add-service-mcp")

    # Tool definitions
    tools: List[Tool] = [
        Tool(
            name="create_service_module",
            description="Create a new systemd service module at modules/services/SERVICE-NAME/",
            inputSchema={
                "type": "object",
                "properties": {
                    "service_name": {
                        "type": "string",
                        "description": "Service name (will be converted to kebab-case)",
                        "examples": ["my-web-service", "database-worker", "api-server"],
                    },
                    "description": {
                        "type": "string",
                        "description": "Human-readable description of what the service does",
                        "examples": [
                            "Web API server",
                            "Background worker",
                            "Database service",
                        ],
                    },
                },
                "required": ["service_name", "description"],
            },
        ),
        Tool(
            name="register_module",
            description="Register service module in modules/default.nix imports",
            inputSchema={
                "type": "object",
                "properties": {
                    "service_name": {
                        "type": "string",
                        "description": "Service name (kebab-case)",
                        "examples": ["my-web-service", "database-worker"],
                    }
                },
                "required": ["service_name"],
            },
        ),
        Tool(
            name="enable_service",
            description="Enable service on host configuration file",
            inputSchema={
                "type": "object",
                "properties": {
                    "service_name": {
                        "type": "string",
                        "description": "Service name to enable",
                        "examples": ["my-web-service"],
                    },
                    "hostname": {
                        "type": "string",
                        "description": "Target hostname",
                        "default": "zephyr",
                        "enum": ["zephyr", "forge", "nexus", "sentry"],
                    },
                },
                "required": ["service_name"],
            },
        ),
        Tool(
            name="get_service_template",
            description="Get systemd service module template for reference",
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
            if name == "create_service_module":
                result = await create_service_module(
                    service_name=arguments["service_name"],
                    description=arguments["description"],
                    hostname=arguments.get("hostname", "zephyr"),
                )
            elif name == "register_module":
                result = await register_module_in_default(
                    service_name=arguments["service_name"], service_path=""
                )
            elif name == "enable_service":
                result = await enable_service_on_host(
                    service_name=arguments["service_name"],
                    hostname=arguments.get("hostname", "zephyr"),
                )
            elif name == "get_service_template":
                result = await get_service_template()
            else:
                result = {"success": False, "error": f"Unknown tool: {name}"}

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
    logger.info("Starting add-service MCP server...")

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
