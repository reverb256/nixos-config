{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.mcp-servers;

  # Helper to create MCP server packages via npm/npx
  mkNpmMcpServer = {
    name,
    package,
    args ? [],
    env ? {},
  }:
    pkgs.writeShellScriptBin "mcp-${name}" ''
      export PATH="${pkgs.nodejs_22}/bin:$PATH"
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "export ${k}=\"${v}\"") env)}
      exec ${pkgs.nodejs_22}/bin/npx -y ${package} ${lib.concatStringsSep " " args} "$@"
    '';
in {
  options.services.mcp-servers = {
    enable = lib.mkEnableOption "MCP (Model Context Protocol) servers for AI coding assistants";

    kimi-code = {
      enable = lib.mkEnableOption "Kimi Code CLI MCP configuration" // {default = true;};
      configPath = lib.mkOption {
        type = lib.types.str;
        default = "$HOME/.kimi/mcp.json";
        description = "Path to Kimi MCP configuration file";
      };
    };

    kilo-code = {
      enable = lib.mkEnableOption "Kilo Code CLI MCP configuration" // {default = true;};
      configPath = lib.mkOption {
        type = lib.types.str;
        default = "$HOME/.kilocode/cli/global/settings/mcp_settings.json";
        description = "Path to Kilo Code MCP configuration file";
      };
    };

    servers = {
      filesystem = {
        enable = lib.mkEnableOption "Filesystem MCP server" // {default = true;};
        allowedPaths = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = ["$HOME" "/etc/nixos"];
          description = "Paths allowed for filesystem access";
        };
      };

      git = {
        enable = lib.mkEnableOption "Git MCP server" // {default = true;};
      };

      playwright = {
        enable = lib.mkEnableOption "Playwright MCP server for browser automation" // {default = true;};
      };

      puppeteer = {
        enable = lib.mkEnableOption "Puppeteer MCP server (deprecated, use Playwright)" // {default = false;};
      };

      fetch = {
        enable = lib.mkEnableOption "Fetch MCP server for web content" // {default = true;};
      };

      context7 = {
        enable = lib.mkEnableOption "Context7 MCP server for documentation" // {default = true;};
        apiKey = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Context7 API key (optional, for higher rate limits)";
        };
      };

      grep-app = {
        enable = lib.mkEnableOption "Grep.app MCP server for code search" // {default = true;};
      };

      brave-search = {
        enable = lib.mkEnableOption "Brave Search MCP server" // {default = false;};
        apiKey = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Brave Search API key";
        };
      };

      chrome-devtools = {
        enable = lib.mkEnableOption "Chrome DevTools MCP server" // {default = true;};
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # Install MCP server wrapper packages
    environment.systemPackages = with pkgs;
      [
        # Node.js for npm-based MCP servers
        nodejs_22

        # UV for Python-based MCP servers (if available)
        (lib.optionalString (lib.hasAttr "uv" pkgs) uv)

        # Playwright for browser automation (browsers installed via activation script)
      ]
      ++ lib.optionals cfg.servers.playwright.enable [
        playwright
      ]
      ++ [
        # MCP server wrappers
        (mkNpmMcpServer {
          name = "filesystem";
          package = "@modelcontextprotocol/server-filesystem";
          args = cfg.servers.filesystem.allowedPaths;
        })

        (mkNpmMcpServer {
          name = "git";
          package = "@modelcontextprotocol/server-git";
        })

        (mkNpmMcpServer {
          name = "playwright";
          package = "@playwright/mcp@latest";
        })

        (mkNpmMcpServer {
          name = "puppeteer";
          package = "@modelcontextprotocol/server-puppeteer";
        })

        (mkNpmMcpServer {
          name = "brave-search";
          package = "@modelcontextprotocol/server-brave-search";
          env = lib.optionalAttrs (cfg.servers.brave-search.apiKey != "") {
            BRAVE_API_KEY = cfg.servers.brave-search.apiKey;
          };
        })

        (mkNpmMcpServer {
          name = "chrome-devtools";
          package = "chrome-devtools-mcp@latest";
        })
      ];

    # Install Playwright browsers on system activation
    system.activationScripts.playwright-browsers = lib.mkIf cfg.servers.playwright.enable {
      text = ''
        # Install Playwright browsers if not already present
        export PLAYWRIGHT_BROWSERS_PATH=/var/lib/playwright-browsers
        export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=0

        if [ ! -d "$PLAYWRIGHT_BROWSERS_PATH" ]; then
          echo "Installing Playwright browsers..."
          mkdir -p $PLAYWRIGHT_BROWSERS_PATH
          ${pkgs.nodejs_22}/bin/npx playwright install chromium --with-deps || true
        fi
      '';
    };

    # Enable nix-ld for dynamically linked executables (needed for uvx)
    programs.nix-ld.enable = lib.mkDefault true;

    # Create MCP configuration files
    system.activationScripts.mcp-config = lib.mkIf (cfg.kimi-code.enable || cfg.kilo-code.enable) {
      text = ''
        # Create directories
        ${lib.optionalString cfg.kimi-code.enable "mkdir -p $(dirname ${cfg.kimi-code.configPath})"}
        ${lib.optionalString cfg.kilo-code.enable "mkdir -p $(dirname ${cfg.kilo-code.configPath})"}

        # Set ownership
        ${lib.optionalString cfg.kimi-code.enable "chown j_kro:j_kro $(dirname ${cfg.kimi-code.configPath}) 2>/dev/null || true"}
        ${lib.optionalString cfg.kilo-code.enable "chown j_kro:j_kro $(dirname ${cfg.kilo-code.configPath}) 2>/dev/null || true"}
      '';
    };

    # Documentation
    environment.etc."mcp-servers/README.md".text = ''
      # MCP Servers Configuration

      This directory contains MCP (Model Context Protocol) server configurations
      for AI coding assistants.

      ## Available Servers

      | Server | Type | Purpose | Status |
      |--------|------|---------|--------|
      | context7 | HTTP | Documentation search | ✓ Working |
      | grep_app | HTTP | Code search | ✓ Working |
      | github | HTTP | GitHub integration | ⚠ Auth required |
      | sentry | HTTP | Error monitoring | ⚠ Auth required |
      | filesystem | STDIO | Local filesystem | ✓ Working |
      | git | STDIO | Git operations | ✓ Working |
      | playwright | STDIO | Browser automation | ✓ Working |
      | puppeteer | STDIO | Browser automation | ⚠ Deprecated |
      | chrome-devtools | STDIO | Chrome debugging | ✓ Working |
      | brave-search | STDIO | Web search | ⚠ API key needed |
      | fetch | STDIO | Web fetching | ⚠ Needs uvx |

      ## Configuration Files

      - Kimi Code: `~/.kimi/mcp.json`
      - Kilo Code: `~/.kilocode/cli/global/settings/mcp_settings.json`

      ## Usage

      Test servers with:
      ```bash
      kimi mcp list
      kimi mcp test <server-name>
      ```

      ## NixOS Integration

      MCP servers are managed via the `services.mcp-servers` module.
      See `/etc/nixos/modules/mcp-servers.nix` for configuration options.
    '';
  };
}
