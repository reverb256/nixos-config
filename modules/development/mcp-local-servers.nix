# Local stdio MCP server definitions shared across the Droid / Claude Code /
# Crush / OpenCode generator scripts in
# modules/development/ai-coding-tools.nix.
#
# Exported as a flat attrset (NOT a NixOS module) so each `mkXxxMcpJson`
# writeShellScript block can spread the same name → command mapping
# into its generated JSON. Pulled out of the parent module on 2026-07-28
# per docs/audit-2026-07-27.md F-22 (de-monolithize ai-coding-tools.nix).
#
# For the actual wrapper commands (`mcp-filesystem`, `mcp-git`, etc.)
# see `modules/services/mcp-servers.nix` which provides the
# PATH-installed binaries referenced by `command =` below.

{
  filesystem = {
    command = "mcp-filesystem";
    args = [
      "/etc/nixos"
      "/home/j_kro"
    ];
  };

  git = {
    command = "mcp-git";
  };

  fetch = {
    command = "mcp-fetch";
  };

  playwright = {
    command = "mcp-playwright";
  };

  context7 = {
    command = "mcp-context7";
    env.CONTEXT7_API_KEY = "$CONTEXT7_API_KEY";
  };

  chrome-devtools = {
    command = "npx";
    args = [
      "-y"
      "chrome-devtools-mcp@latest"
    ];
  };

  gateway = {
    command = "mcp-gateway-bridge";
  };

  searxng = {
    command = "mcp-fetch";
    # SearXNG via fetch wrapper with custom URL.
    # TODO: replace with dedicated mcp-searxng wrapper if/when added.
  };

  hound = {
    command = "/data/agents/mcp-bridges/hound-mcp.sh";
    description = "Web fetch + crawl + search + Cloudflare bypass + PDF OCR";
  };
}
