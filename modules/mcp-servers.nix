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
    enable = lib.mkEnableOption "MCP (Model Context Protocol) servers for all AI tools (OpenCode, Qwen, Kimi, OpenClaw)";

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

      openclaw = {
        enable = lib.mkEnableOption "OpenClaw MCP server (exposes Gateway tools)" // {default = true;};
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

        (mkNpmMcpServer {
          name = "openclaw";
          package = "@openclaw/mcp-server";
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

    # Create MCP directories
    system.activationScripts.mcp-dirs = {
      text = ''
        mkdir -p ~/.config/opencode
        mkdir -p ~/.claude
        mkdir -p ~/.kilocode/cli/global/settings
        mkdir -p ~/.openclaw
        chown j_kro:j_kro ~/.config/opencode ~/.claude ~/.kilocode ~/.openclaw 2>/dev/null || true
      '';
    };

    # Unified MCP configuration for ALL AI tools
    home-manager.users.j_kro = {
      home.stateVersion = "24.05";

      # OpenCode MCP configuration
      programs.opencode = {
        enable = true;
        settings.mcp = {
          servers = lib.filterAttrs (n: v: v.enable) {
            filesystem = {
              command = "mcp-filesystem";
              args = cfg.servers.filesystem.allowedPaths;
            };
            git = {
              command = "mcp-git";
            };
            playwright = {
              command = "mcp-playwright";
            };
            fetch = {
              command = "mcp-fetch";
            };
            context7 = {
              command = "mcp-context7";
            };
            grep-app = {
              command = "mcp-grep-app";
            };
            chrome-devtools = {
              command = "mcp-chrome-devtools";
            };
            github = lib.optionalAttrs (cfg.servers.github.enable && cfg.servers.github.apiKey != "") {
              command = "mcp-github";
              env = {
                GITHUB_API_TOKEN = cfg.servers.github.apiKey;
              };
            };
            openclaw = lib.optionalAttrs cfg.servers.openclaw.enable {
              command = "mcp-openclaw";
            };
          };
        };
      };

      # OpenClaw MCP configuration
      programs.openclaw.config.mcp = {
        servers = lib.filterAttrs (n: v: v.enable) {
          filesystem = {
            command = "mcp-filesystem";
            args = cfg.servers.filesystem.allowedPaths;
          };
          git = {
            command = "mcp-git";
          };
          playwright = {
            command = "mcp-playwright";
          };
          fetch = {
            command = "mcp-fetch";
          };
          context7 = {
            command = "mcp-context7";
          };
          grep-app = {
            command = "mcp-grep-app";
          };
          chrome-devtools = {
            command = "mcp-chrome-devtools";
          };
          github = lib.optionalAttrs (cfg.servers.github.enable && cfg.servers.github.apiKey != "") {
            command = "mcp-github";
            env = {
              GITHUB_API_TOKEN = cfg.servers.github.apiKey;
            };
          };
          openclaw = lib.optionalAttrs cfg.servers.openclaw.enable {
            command = "mcp-openclaw";
          };
        };
      };
    };

    # Documentation
    environment.etc."mcp-servers/README.md".text = ''
      # Unified MCP Servers for All AI Tools

      MCP servers configured for: OpenCode, Qwen, Kimi, OpenClaw

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
      | openclaw | STDIO | OpenClaw Gateway tools |

      ## Tools Using These MCP Servers

      - **OpenCode**: `~/.config/opencode/settings.json`
      - **OpenClaw**: `~/.openclaw/openclaw.json` (mcp.servers)
      - **Kimi/Kilo**: `~/.kilocode/cli/global/settings/mcp_settings.json`

      ## NixOS Integration

      Configure in `/etc/nixos/modules/mcp-servers.nix`
    '';
  };
}
