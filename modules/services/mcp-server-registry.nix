# Shared MCP Server Registry
#
# Single source of truth for MCP server definitions used by:
#   - modules/services/mcp-servers.nix (wrapper script generation)
#   - modules/development/ai-coding-tools/mcp-defs.nix (JSON config generation)
#
# Adding a new MCP server only requires adding an entry here.
# Both modules will pick it up automatically.
#
# Each server has:
#   name:     identifier used as mcp-<name> command
#   type:     "npm" (npx package), "uvx" (Python), "custom" (manual wrapper)
#   package:  package name for npm/uvx types
#   args:     default arguments (can be overridden per-tool)
#   env:      default environment variables
{ lib }:
let
  # Server definitions
  servers = {
    filesystem = {
      type = "npm";
      package = "@modelcontextprotocol/server-filesystem";
      args = [
        "/etc/nixos"
        "/home/j_kro"
      ];
    };

    git = {
      type = "uvx";
      package = "mcp-server-git";
      entrypoint = "mcp-server-git";
    };

    fetch = {
      type = "uvx";
      package = "mcp-server-fetch";
      entrypoint = "mcp-server-fetch";
    };

    playwright = {
      type = "custom";
      # Uses nixpkgs playwright-mcp package with custom wrapper
    };

    context7 = {
      type = "npm";
      package = "@upstash/context7-mcp";
      env = {
        CONTEXT7_API_KEY_FILE = ""; # Set by mcp-servers.nix from apiKeyFile option
      };
    };

    chrome-devtools = {
      type = "npm";
      package = "chrome-devtools-mcp@latest";
    };

    lightpanda = {
      type = "custom";
      # Uses /opt/lightpanda/lightpanda binary directly
    };

    gateway = {
      type = "custom";
      # Uses python3 mcp-gateway-bridge script
    };

    puppeteer = {
      type = "npm";
      package = "@modelcontextprotocol/server-puppeteer";
    };

    brave-search = {
      type = "npm";
      package = "@modelcontextprotocol/server-brave-search";
      env = {
        BRAVE_API_KEY = ""; # Set by mcp-servers.nix from apiKey option
      };
    };

    github = {
      type = "npm";
      package = "@modelcontextprotocol/server-github";
      env = {
        GITHUB_API_TOKEN = ""; # Set by mcp-servers.nix from apiKey option
      };
    };
  };

  # Derive the command name from server name
  mkCommand = name: "mcp-${name}";
in
{
  inherit servers mkCommand;
}
