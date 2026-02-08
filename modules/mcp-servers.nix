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
    enable = lib.mkEnableOption "MCP (Model Context Protocol) servers for all AI tools (OpenCode, Qwen, Kimi, )";
    
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
      
      github = {
        enable = lib.mkEnableOption "GitHub MCP server" // {default = false;};
        apiKey = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "GitHub API token";
        };
      };
       
      kubernetes = {
        enable = lib.mkEnableOption "Kubernetes MCP server for cluster management" // {default = false;};
        kubeconfig = lib.mkOption {
          type = lib.types.path;
          default = "";
          description = "Path to kubeconfig file";
        };
      };
      
      github-actions = {
        enable = lib.mkEnableOption "GitHub Actions MCP server for CI/CD automation" // {default = false;};
      };
      
      terraform = {
        enable = lib.mkEnableOption "Terraform MCP server for IaC automation" // {default = false;};
      };
      
      ansible = {
        enable = lib.mkEnableOption "Ansible MCP server for configuration management" // {default = false;};
      };
      
      n8n = {
        enable = lib.mkEnableOption "n8n workflow automation MCP server" // {default = false;};
        url = lib.mkOption {
          type = lib.types.str;
          default = "http://localhost:5678";
          description = "n8n instance URL";
        };
      };
      
      computer-use = {
        enable = lib.mkEnableOption "Computer use MCP server for desktop automation" // {default = false;};
        platform = lib.mkOption {
          type = lib.types.enum ["windows" "macos" "linux"];
          default = "linux";
          description = "Operating system platform";
        };
      };
      
      exa = {
        enable = lib.mkEnableOption "Exa web search MCP server" // {default = false;};
        apiKey = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Exa API key (use your key: 3a8a3e63-3267-492c-b078-543abb2ee144)";
        };
      };
      
      google-drive = {
        enable = lib.mkEnableOption "Google Drive MCP server for cloud storage" // {default = false;};
      };
    };
  };
  
  config = lib.mkIf cfg.enable {
    # Install MCP server wrapper packages
    environment.systemPackages = with pkgs;
      [
        nodejs_22
        (lib.optionalString (lib.hasAttr "uv" pkgs) uv)
      ]
      ++ lib.optionals cfg.servers.playwright.enable [
        playwright
      ]
      ++ [
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
          name = "fetch";
          package = "@modelcontextprotocol/server-fetch";
        })
        
        (mkNpmMcpServer {
          name = "context7";
          package = "@context7/context7-mcp";
        })
        
        (mkNpmMcpServer {
          name = "grep-app";
          package = "@grepapp/mcp-server";
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
        
        (mkNpmMcpServer {
          name = "github";
          package = "@modelcontextprotocol/server-github";
          env = lib.optionalAttrs (cfg.servers.github.apiKey != "") {
            GITHUB_API_TOKEN = cfg.servers.github.apiKey;
          };
        })

      ];
    
    # Install Playwright browsers
    system.activationScripts.playwright-browsers = lib.mkIf cfg.servers.playwright.enable {
      text = ''
        export PLAYWRIGHT_BROWSERS_PATH=/var/lib/playwright-browsers
        export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=0
        if [ ! -d "$PLAYWRIGHT_BROWSERS_PATH" ]; then
          mkdir -p $PLAYWRIGHT_BROWSERS_PATH
          ${pkgs.nodejs_22}/bin/npx playwright install chromium --with-deps || true
        fi
      '';
    };
    
    programs.nix-ld.enable = lib.mkDefault true;
    
    # Documentation
    environment.etc."mcp-servers/README.md".text = ''
      # Unified MCP Servers for All AI Tools
      
      MCP servers configured for: OpenCode, Qwen, Kimi, 
      
      ## Available Servers
      
      | Server | Type | Purpose |
      |--------|------|---------|
      | filesystem | STDIO | Local filesystem access |
      | git | STDIO | Git operations |
      | playwright | STDIO | Browser automation |
      | fetch | STDIO | Web fetching |
      | context7 | STDIO | Documentation search |
      | grep-app | STDIO | Code search |
      | chrome-devtools | STDIO | Chrome debugging |
       | github | STDIO | GitHub integration |
      
       ## Available MCP Server Commands
      
       MCP servers are installed as system packages and available via PATH:
      
       | Server | Command | Purpose |
       |--------|---------|---------|
       | filesystem | `mcp-filesystem` | Local filesystem access |
       | git | `mcp-git` | Git operations |
       | playwright | `mcp-playwright` | Browser automation |
       | fetch | `mcp-fetch` | Web fetching |
       | context7 | `mcp-context7` | Documentation search |
       | grep-app | `mcp-grep-app` | Code search |
        | chrome-devtools | `mcp-chrome-devtools` | Chrome debugging |
        | github | `mcp-github` | GitHub integration |
      
       ## Configuration
      
       Configure MCP servers manually in each tool's config file:
       
        - OpenCode: ~/.config/opencode/settings.json
        - Kilo Code: ~/.kilocode/cli/global/settings/mcp_settings.json
      
       Example MCP server config format:
        {
          "servers": {
            "filesystem": {
              "command": "mcp-filesystem",
              "args": ["/etc/nixos", "$HOME"]
            }
          }
        }
    '';
  };
}
