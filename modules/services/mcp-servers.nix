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
      # Set npm cache to writable location for systemd services
      export npm_config_cache="/var/cache/ai-inference/npm"
      export PATH="${pkgs.nodejs_22}/bin:$PATH"
      ${
        lib.concatStringsSep "\n" (lib.mapAttrsToList (
            k: v:
              if lib.hasSuffix "_FILE" k
              then ''
                # Read API key from file and export as base variable name
                if [ -f "${v}" ]; then
                  export ${lib.substring 0 (lib.stringLength k - 5) k}="$(cat ${v})"
                else
                  echo "Warning: API key file not found: ${v}" >&2
                fi
              ''
              else ''
                export ${k}="${v}"
              ''
          )
          env)
      }
      exec ${pkgs.nodejs_22}/bin/npx -y ${package} ${lib.concatStringsSep " " args} "$@"
    '';
  # Helper to create MCP server packages via Python uvx
in {
  options.services.mcp-servers = {
    enable = lib.mkEnableOption "MCP (Model Context Protocol) servers for all AI tools (OpenCode, Qwen, Kimi, )";

    servers = {
      filesystem = {
        enable = lib.mkEnableOption "Filesystem MCP server" // {default = true;};
        allowedPaths = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = ["$HOME" "/etc/nixos"];
          example = ["$HOME" "/etc/nixos" "/var/lib"];
          description = "Paths allowed for filesystem access";
        };
      };

      git = {
        enable = lib.mkEnableOption "Git MCP server" // {default = true;};
      };

      playwright = {
        enable = lib.mkEnableOption "Playwright MCP server for browser automation" // {default = true;};

        browser = lib.mkOption {
          type = lib.types.enum ["chrome" "firefox" "webkit" "msedge"];
          default = "chrome";
          example = "firefox";
          description = "Browser to use for Playwright automation";
        };

        capabilities = lib.mkOption {
          type = lib.types.listOf (lib.types.enum ["vision" "pdf"]);
          default = [];
          example = ["vision" "pdf"];
          description = "Additional capabilities to enable (vision, pdf)";
        };

        headless = lib.mkOption {
          type = lib.types.bool;
          default = false;
          example = true;
          description = "Run browser in headless mode";
        };

        device = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Device to emulate (e.g., 'iPhone 15', 'Desktop Chrome')";
        };

        viewportSize = lib.mkOption {
          type = lib.types.str;
          default = "1280x720";
          example = "1920x1080";
          description = "Browser viewport size in pixels (e.g., '1920x1080')";
        };

        userAgent = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Custom user agent string";
        };

        timeoutAction = lib.mkOption {
          type = lib.types.int;
          default = 5000;
          description = "Action timeout in milliseconds";
        };

        timeoutNavigation = lib.mkOption {
          type = lib.types.int;
          default = 60000;
          description = "Navigation timeout in milliseconds";
        };

        ignoreHttpsErrors = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Ignore HTTPS certificate errors";
        };

        blockServiceWorkers = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Block service workers";
        };

        saveTrace = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Save Playwright trace for debugging";
        };

        saveVideo = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Save video recording (e.g., '1920x1080')";
        };

        grantPermissions = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
          description = "Permissions to grant (geolocation, clipboard-read, clipboard-write, etc.)";
        };
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
        apiKeyFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          example = "/run/agenix/context7-api-key";
          description = "Path to file containing Context7 API key (takes precedence over apiKey)";
        };
      };

      grep-app = {
        enable = lib.mkEnableOption "Grep.app MCP server for code search" // {default = false;};
        # NOTE: Package @grepapp/mcp-server doesn't exist on npm
        # This server is disabled until a working package is found
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
          description = "Exa API key (set via environment variable or Agenix secret)";
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
        # Use nixpkgs' playwright-mcp which is properly wrapped for NixOS
        # with PLAYWRIGHT_BROWSERS_PATH pointing to playwright-driver.browsers
        playwright-mcp
        # Provide mcp-playwright command with NixOS sandbox workaround
        # Fixes issue #443704: permission denied in /nix/store by using writable directory
        (pkgs.writeShellScriptBin "mcp-playwright" ''
          set -euo pipefail

          # Critical: Set writable directory for browser profiles
          # Workaround for NixOS issue #443704: permission denied in /nix/store
          if [ -z "''${PWMCP_PROFILES_DIR_FOR_TEST:-}" ]; then
            export PWMCP_PROFILES_DIR_FOR_TEST="$PWD/.pwmcp-profiles"
            echo "[playwright] Using profile directory: $PWMCP_PROFILES_DIR_FOR_TEST"
          fi

          # Build Playwright MCP arguments from NixOS configuration
          args=()

          # Browser selection (chrome, firefox, webkit, msedge)
          args+=(--browser "${cfg.servers.playwright.browser}")

          # Additional capabilities (vision, pdf)
          ${lib.concatStringsSep "\n" (map (cap: "args+=(--caps ${cap})") cfg.servers.playwright.capabilities)}

          # Headless mode
          ${lib.optionalString cfg.servers.playwright.headless "args+=(--headless)"}

          # Device emulation
          ${lib.optionalString (cfg.servers.playwright.device != "") "args+=(--device \"${cfg.servers.playwright.device}\")"}

          # Viewport size
          args+=(--viewport-size "${cfg.servers.playwright.viewportSize}")

          # User agent
          ${lib.optionalString (cfg.servers.playwright.userAgent != "") "args+=(--user-agent \"${cfg.servers.playwright.userAgent}\")"}

          # Timeouts
          args+=(--timeout-action "${toString cfg.servers.playwright.timeoutAction}")
          args+=(--timeout-navigation "${toString cfg.servers.playwright.timeoutNavigation}")

          # Ignore HTTPS errors
          ${lib.optionalString cfg.servers.playwright.ignoreHttpsErrors "args+=(--ignore-https-errors)"}

          # Block service workers
          ${lib.optionalString cfg.servers.playwright.blockServiceWorkers "args+=(--block-service-workers)"}

          # Save trace for debugging
          ${lib.optionalString cfg.servers.playwright.saveTrace "args+=(--save-trace)"}

          # Save video
          ${lib.optionalString (cfg.servers.playwright.saveVideo != "") "args+=(--save-video \"${cfg.servers.playwright.saveVideo}\")"}

          # Grant permissions
          ${lib.optionalString (cfg.servers.playwright.grantPermissions != [])
            "args+=(--grant-permissions ${lib.concatStringsSep " " cfg.servers.playwright.grantPermissions})"}

          # Execute Playwright MCP server
          exec ${pkgs.playwright-mcp}/bin/mcp-server-playwright "''${args[@]}" "$@"
        '')

        # Additional browser-specific wrappers for convenience
        (pkgs.writeShellScriptBin "mcp-playwright-chrome" ''
          exec mcp-playwright --browser chrome "$@"
        '')

        (pkgs.writeShellScriptBin "mcp-playwright-firefox" ''
          exec mcp-playwright --browser firefox "$@"
        '')

        (pkgs.writeShellScriptBin "mcp-playwright-webkit" ''
          exec mcp-playwright --browser webkit "$@"
        '')

        # Headless mode wrapper
        (pkgs.writeShellScriptBin "mcp-playwright-headless" ''
          exec mcp-playwright --headless "$@"
        '')

        # Vision capability wrapper (for image analysis)
        (pkgs.writeShellScriptBin "mcp-playwright-vision" ''
          exec mcp-playwright --caps vision "$@"
        '')
      ]
      ++ [
        (mkNpmMcpServer {
          name = "filesystem";
          package = "@modelcontextprotocol/server-filesystem";
          args = cfg.servers.filesystem.allowedPaths;
        })

        # Git server is Python-based, use uvx
        (pkgs.writeShellScriptBin "mcp-git" ''
          export PATH="${pkgs.uv}/bin:$PATH"
          exec ${pkgs.uv}/bin/uvx --from mcp-server-git mcp-server-git "$@"
        '')

        (mkNpmMcpServer {
          name = "puppeteer";
          package = "@modelcontextprotocol/server-puppeteer";
        })

        # Fetch server is Python-based, use uvx
        (pkgs.writeShellScriptBin "mcp-fetch" ''
          export PATH="${pkgs.uv}/bin:$PATH"
          exec ${pkgs.uv}/bin/uvx --from mcp-server-fetch mcp-server-fetch "$@"
        '')

        # Context7 - fixed package name with API key support
        # Note: apiKeyFile is read and passed as CONTEXT7_API_KEY (not _FILE)
        # The @upstash/context7-mcp package expects CONTEXT7_API_KEY directly
        (mkNpmMcpServer {
          name = "context7";
          package = "@upstash/context7-mcp";
          env =
            lib.optionalAttrs (cfg.servers.context7.apiKeyFile != null) {
              CONTEXT7_API_KEY = builtins.readFile cfg.servers.context7.apiKeyFile;
            }
            // lib.optionalAttrs (cfg.servers.context7.apiKeyFile == null && cfg.servers.context7.apiKey != "") {
              CONTEXT7_API_KEY = cfg.servers.context7.apiKey;
            };
        })

        # Note: grep-app MCP server (@grepapp/mcp-server) does not exist in npm
        # Alternatives for code search:
        # - Use the filesystem MCP server (already available) with glob patterns
        # - Use ripgrep/rg directly via shell commands
        # - Use official @modelcontextprotocol/server-github for repo search

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

        # MCP Gateway Bridge - stdio to HTTP proxy for AI Inference Gateway
        # Enables stdio-based MCP clients (Claude Code, LM Studio, OpenCode)
        # to access all gateway MCP tools via a single stdio connection
        (pkgs.writeShellScriptBin "mcp-gateway-bridge" ''
          exec ${pkgs.python3}/bin/python3 /etc/nixos/scripts/mcp-gateway-bridge "$@"
        '')
      ];

    # Note: playwright-mcp from nixpkgs is already wrapped with proper
    # PLAYWRIGHT_BROWSERS_PATH and browser binaries from playwright-driver.browsers.
    # No activation script needed - browsers are in the Nix store.

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
       | playwright | STDIO | Browser automation (Nix-provided browsers) |
      | fetch | STDIO | Web fetching |
      | context7 | STDIO | Documentation search |
      | grep-app | STDIO | Code search |
      | chrome-devtools | STDIO | Chrome debugging |
       | github | STDIO | GitHub integration |
      | **gateway** | **Bridge** | **HTTP→stdio proxy to AI Inference Gateway** |

       ## Available MCP Server Commands

       MCP servers are installed as system packages and available via PATH:

       | Server | Command | Purpose |
       |--------|---------|---------|
       | filesystem | `mcp-filesystem` | Local filesystem access |
       | git | `mcp-git` | Git operations |
        | playwright | `mcp-playwright` | Browser automation (uses Nix-provided browsers) |
        | playwright (chrome) | `mcp-playwright-chrome` | Browser automation with Chrome |
        | playwright (firefox) | `mcp-playwright-firefox` | Browser automation with Firefox |
        | playwright (webkit) | `mcp-playwright-webkit` | Browser automation with WebKit |
        | playwright (headless) | `mcp-playwright-headless` | Browser automation in headless mode |
        | playwright (vision) | `mcp-playwright-vision` | Browser automation with vision/AI capabilities |
       | fetch | `mcp-fetch` | Web fetching |
       | context7 | `mcp-context7` | Documentation search |
       | grep-app | `mcp-grep-app` | Code search |
        | chrome-devtools | `mcp-chrome-devtools` | Chrome debugging |
        | github | `mcp-github` | GitHub integration |
        | **gateway** | `mcp-gateway-bridge` | **Bridge to AI Inference Gateway (all tools)** |

       ## MCP Gateway Bridge

       The `mcp-gateway-bridge` command provides a stdio-to-HTTP proxy, enabling stdio-based
       MCP clients (Claude Code, LM Studio, OpenCode) to access all AI Inference Gateway tools:

       **Gateway Tools Available via Bridge:**
       - Context7: `resolve-library-id`, `query-docs`
       - NixOS: `nix_flake_check`, `nixos_rebuild_*`, `nix_flake_update`
       - Web: `webReader`, `web_search_prime`
       - GitHub: `search_doc`, `read_file`, `get_repo_structure`
       - Add-service: `create_service_module`, `register_module`, `enable_service`
       - And more...

       **Configuration:**

       ```json
       {
         "mcpServers": {
           "gateway": {
             "command": "mcp-gateway-bridge"
           }
         }
       }
       ```

       **Benefits:**
       - Single stdio connection replaces multiple direct MCP servers
       - Shared authentication and caching via the gateway
       - Remote access to gateway-hosted tools (ZAI APIs, etc.)
       - Unified observability and logging

       ## Playwright Configuration

       The Playwright MCP server can be configured via NixOS:

       ```nix
       services.mcp-servers.playwright = {
         enable = true;
         browser = "chrome";  # chrome, firefox, webkit, msedge
         capabilities = ["vision" "pdf"];  # Additional capabilities
         headless = false;
         device = "";  # e.g., "iPhone 15"
         viewportSize = "1280x720";
         timeoutAction = 5000;
         timeoutNavigation = 60000;
         ignoreHttpsErrors = false;
         blockServiceWorkers = false;
         saveTrace = false;
         saveVideo = "";  # e.g., "1920x1080"
         grantPermissions = ["geolocation"];
       };
       ```

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
