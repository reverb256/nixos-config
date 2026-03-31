# AI Coding Tools - Harmonized MCP Configuration
# Generates unified MCP server configs for: Droid (Factory), Claude Code, Crush, OpenCode
# All tools get the same MCP server set: Z.AI HTTP + local stdio servers
#
# API keys are read from agenix secrets at runtime (never hardcoded).
# Required secrets: zai-api-key, context7-api-key
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.ai-coding-tools;
  inherit (lib) mkEnableOption mkOption mkIf types optionalString concatStringsSep escapeJSON;

  # Read API key from agenix at runtime
  readSecret = path: "$(cat ${path} 2>/dev/null || echo '')";

  # Z.AI API base URL and key references
  zaiApiKeyRef = "$ZAI_API_KEY";
  zaiApiBaseUrl = "https://api.z.ai/api/anthropic";
  zaiCodingBaseUrl = "https://api.z.ai/api/coding/paas/v4";
  zaiMcpBearer = "Bearer $ZAI_API_KEY";

  # SearXNG URL (internal cluster service)
  searxngUrl = "https://search.reverb256.ca";

  # AI Gateway URL (Kubernetes service)
  gatewayUrl = "http://ai-inference-gateway.ai-inference.svc.cluster.local:8080";

  # Context7 API key reference
  context7ApiKeyRef = "$CONTEXT7_API_KEY";

  # ---------------------------------------------------------------------------
  # Shared MCP server definitions (tool-agnostic)
  # These map to mcp-* wrapper scripts installed by modules/services/mcp-servers.nix
  # ---------------------------------------------------------------------------

  # Z.AI HTTP MCP servers (identical across all tools)
  zaiHttpServers = {
    web-search-prime = {
      type = "http";
      url = "https://api.z.ai/api/mcp/web_search_prime/mcp";
      headers.Authorization = zaiMcpBearer;
    };
    web-reader = {
      type = "http";
      url = "https://api.z.ai/api/mcp/web_reader/mcp";
      headers.Authorization = zaiMcpBearer;
    };
    zread = {
      type = "http";
      url = "https://api.z.ai/api/mcp/zread/mcp";
      headers.Authorization = zaiMcpBearer;
    };
  };

  # Z.AI stdio MCP server
  zaiStdioServer = {
    type = "stdio";
    command = "npx";
    args = ["-y" "@z_ai/mcp-server"];
    env = {
      Z_AI_MODE = "ZAI";
      Z_AI_API_KEY = zaiApiKeyRef;
    };
  };

  # Local stdio MCP servers (use mcp-* wrappers from mcp-servers.nix)
  localStdioServers = {
    filesystem = {
      command = "mcp-filesystem";
      args = ["/etc/nixos" "/home/j_kro"];
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
      env.CONTEXT7_API_KEY = context7ApiKeyRef;
    };
    chrome-devtools = {
      command = "npx";
      args = ["-y" "chrome-devtools-mcp@latest"];
    };
    gateway = {
      command = "mcp-gateway-bridge";
    };
    searxng = {
      command = "mcp-fetch";
      # SearXNG via fetch wrapper with custom URL
      # Note: If a dedicated searxng MCP wrapper exists, replace this
    };
  };

  # Full MCP set: Z.AI stdio + Z.AI HTTP + local stdio
  fullMcpSet = localStdioServers // {
    "zai-mcp-server" = zaiStdioServer;
  } // zaiHttpServers;

  # ---------------------------------------------------------------------------
  # Config generators per tool
  # ---------------------------------------------------------------------------

  # Factory Droid: ~/.factory/mcp.json
  # Droid supports ${VAR} interpolation in mcp.json, so we use env var references
  # instead of resolving the key at generation time. This keeps the key out of the
  # generated file and allows Droid to read it from the environment at runtime.
  mkDroidMcpJson = pkgs.writeShellScript "generate-droid-mcp" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    ${pkgs.jq}/bin/jq -n \
      '{
        "mcpServers": {
          "zai-mcp-server": {
            "type": "stdio",
            "command": "npx",
            "args": ["-y", "@z_ai/mcp-server"],
            "env": {
              "Z_AI_MODE": "ZAI",
              "Z_AI_API_KEY": "$ZAI_API_KEY"
            },
            "disabled": false
          },
          "web-search-prime": {
            "type": "http",
            "url": "https://api.z.ai/api/mcp/web_search_prime/mcp",
            "headers": { "Authorization": ("Bearer $ZAI_API_KEY") },
            "disabled": false
          },
          "web-reader": {
            "type": "http",
            "url": "https://api.z.ai/api/mcp/web_reader/mcp",
            "headers": { "Authorization": ("Bearer $ZAI_API_KEY") },
            "disabled": false
          },
          "zread": {
            "type": "http",
            "url": "https://api.z.ai/api/mcp/zread/mcp",
            "headers": { "Authorization": ("Bearer $ZAI_API_KEY") },
            "disabled": false
          },
          "filesystem": {
            "command": "mcp-filesystem",
            "args": ["/etc/nixos", "/home/${cfg.user}"],
            "disabled": false
          },
          "git": {
            "command": "mcp-git",
            "disabled": false
          },
          "fetch": {
            "command": "mcp-fetch",
            "disabled": false
          },
          "playwright": {
            "command": "mcp-playwright",
            "disabled": false
          },
          "context7": {
            "command": "mcp-context7",
            "env": { "CONTEXT7_API_KEY": "$CONTEXT7_API_KEY" },
            "disabled": false
          },
          "chrome-devtools": {
            "command": "npx",
            "args": ["-y", "chrome-devtools-mcp@latest"],
            "disabled": false
          },
          "gateway": {
            "command": "mcp-gateway-bridge",
            "disabled": false
          }
        }
      }' > "/home/${cfg.user}/.factory/mcp.json"

    chown ${cfg.user}:users "/home/${cfg.user}/.factory/mcp.json"
    chmod 600 "/home/${cfg.user}/.factory/mcp.json"
    echo "[ai-coding-tools] Droid MCP config generated with env var references"
  '';

  # Claude Code: ~/.config/claude/mcp.json
  mkClaudeMcpJson = pkgs.writeShellScript "generate-claude-mcp" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    ZAI_API_KEY=$(cat ${cfg.zaiApiKeyFile} 2>/dev/null || echo "")
    CONTEXT7_API_KEY=$(cat ${cfg.context7ApiKeyFile} 2>/dev/null || echo "")

    ${pkgs.jq}/bin/jq -n \
      --arg zai_key "$ZAI_API_KEY" \
      --arg ctx7_key "$CONTEXT7_API_KEY" \
      '{
        "mcpServers": {
          "zai-mcp-server": {
            "command": "npx",
            "args": ["-y", "@z_ai/mcp-server"],
            "env": {
              "Z_AI_MODE": "ZAI",
              "Z_AI_API_KEY": $zai_key
            }
          },
          "web-search-prime": {
            "type": "http",
            "url": "https://api.z.ai/api/mcp/web_search_prime/mcp",
            "headers": { "Authorization": ("Bearer " + $zai_key) }
          },
          "web-reader": {
            "type": "http",
            "url": "https://api.z.ai/api/mcp/web_reader/mcp",
            "headers": { "Authorization": ("Bearer " + $zai_key) }
          },
          "zread": {
            "type": "http",
            "url": "https://api.z.ai/api/mcp/zread/mcp",
            "headers": { "Authorization": ("Bearer " + $zai_key) }
          },
          "filesystem": {
            "command": "mcp-filesystem",
            "args": ["/etc/nixos", "/home/j_kro"]
          },
          "git": {
            "command": "mcp-git"
          },
          "fetch": {
            "command": "mcp-fetch"
          },
          "playwright": {
            "command": "mcp-playwright"
          },
          "context7": {
            "command": "mcp-context7",
            "env": { "CONTEXT7_API_KEY": $ctx7_key }
          },
          "chrome-devtools": {
            "command": "npx",
            "args": ["-y", "chrome-devtools-mcp@latest"]
          },
          "gateway": {
            "command": "mcp-gateway-bridge"
          },
          "nixos": {
            "command": "uvx",
            "args": ["mcp-nixos"]
          }
        }
      }' > "/home/${cfg.user}/.config/claude/mcp.json"

    chown ${cfg.user}:users "/home/${cfg.user}/.config/claude/mcp.json"
    chmod 644 "/home/${cfg.user}/.config/claude/mcp.json"
    echo "[ai-coding-tools] Claude Code MCP config generated"
  '';

  # Crush: ~/.config/crush/crush.json
  mkCrushConfig = pkgs.writeShellScript "generate-crush-config" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    ZAI_API_KEY=$(cat ${cfg.zaiApiKeyFile} 2>/dev/null || echo "")
    CONTEXT7_API_KEY=$(cat ${cfg.context7ApiKeyFile} 2>/dev/null || echo "")

    ${pkgs.jq}/bin/jq -n \
      --arg zai_key "$ZAI_API_KEY" \
      --arg ctx7_key "$CONTEXT7_API_KEY" \
      --arg zai_base "https://api.z.ai/api/coding/paas/v4" \
      '{
        "providers": {
          "zai": {
            "id": "zai",
            "name": "ZAI Provider",
            "base_url": $zai_base,
            "api_key": $zai_key
          }
        },
        "mcp": {
          "zai-mcp-server": {
            "type": "stdio",
            "command": "npx",
            "args": ["-y", "@z_ai/mcp-server"],
            "env": {
              "Z_AI_MODE": "ZAI",
              "Z_AI_API_KEY": $zai_key
            }
          },
          "web-search-prime": {
            "type": "http",
            "url": "https://api.z.ai/api/mcp/web_search_prime/mcp",
            "headers": { "Authorization": ("Bearer " + $zai_key) }
          },
          "web-reader": {
            "type": "http",
            "url": "https://api.z.ai/api/mcp/web_reader/mcp",
            "headers": { "Authorization": ("Bearer " + $zai_key) }
          },
          "zread": {
            "type": "http",
            "url": "https://api.z.ai/api/mcp/zread/mcp",
            "headers": { "Authorization": ("Bearer " + $zai_key) }
          },
          "filesystem": {
            "command": "mcp-filesystem",
            "args": ["/etc/nixos", "/home/j_kro"]
          },
          "git": {
            "command": "mcp-git"
          },
          "fetch": {
            "command": "mcp-fetch"
          },
          "playwright": {
            "command": "mcp-playwright"
          },
          "context7": {
            "command": "mcp-context7",
            "env": { "CONTEXT7_API_KEY": $ctx7_key }
          },
          "chrome-devtools": {
            "command": "npx",
            "args": ["-y", "chrome-devtools-mcp@latest"]
          },
          "gateway": {
            "command": "mcp-gateway-bridge"
          }
        }
      }' > "/home/${cfg.user}/.config/crush/crush.json"

    chown ${cfg.user}:users "/home/${cfg.user}/.config/crush/crush.json"
    chmod 600 "/home/${cfg.user}/.config/crush/crush.json"
    echo "[ai-coding-tools] Crush config generated"
  '';

  # OpenCode: ~/.opencode/config.json (adds MCP servers to existing provider config)
  mkOpencodeConfig = pkgs.writeShellScript "generate-opencode-config" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    CONTEXT7_API_KEY=$(cat ${cfg.context7ApiKeyFile} 2>/dev/null || echo "")

    ${pkgs.jq}/bin/jq -n \
      --arg ctx7_key "$CONTEXT7_API_KEY" \
      --arg gateway_base "${gatewayUrl}/v1" \
      '{
        "$schema": "https://opencode.ai/config.json",
        "comment": "Harmonized config - managed by NixOS ai-coding-tools module",
        "model": "ai-gateway/qwen3.5-4b",
        "small_model": "ai-gateway/qwen3.5-4b",
        "provider": {
          "ai-gateway": {
            "npm": "@ai-sdk/openai-compatible",
            "name": "AI Gateway (Kubernetes llama.cpp/vLLM/SGLang)",
            "options": {
              "baseURL": $gateway_base,
              "apiKey": "k8s-gateway"
            },
            "models": {
              "ai-gateway/qwen3.5-4b": {
                "name": "Qwen 3.5 4B (via llama.cpp)",
                "description": "Qwen 3.5 4B model served by llama.cpp in Kubernetes"
              },
              "ai-gateway/qwen3.5-32b": {
                "name": "Qwen 3.5 32B (via vLLM)",
                "description": "Qwen 3.5 32B model served by vLLM in Kubernetes"
              },
              "ai-gateway/deepseek-r1": {
                "name": "DeepSeek R1 (via SGLang)",
                "description": "DeepSeek R1 reasoning model served by SGLang"
              }
            }
          },
          "lmstudio": {
            "npm": "@ai-sdk/openai-compatible",
            "name": "LM Studio (Local Fallback)",
            "options": {
              "baseURL": "http://127.0.0.1:8080/v1"
            }
          }
        },
        "enabled_providers": ["ai-gateway", "lmstudio"],
        "disabled_providers": ["openai", "anthropic", "google", "cohere", "zai-coding-plan"],
        "mcp": {
          "zai-mcp-server": {
            "type": "stdio",
            "command": "npx",
            "args": ["-y", "@z_ai/mcp-server"],
            "env": {
              "Z_AI_MODE": "ZAI",
              "Z_AI_API_KEY": "''${ZAI_API_KEY}"
            }
          },
          "web-search-prime": {
            "type": "http",
            "url": "https://api.z.ai/api/mcp/web_search_prime/mcp",
            "headers": { "Authorization": "Bearer ''${ZAI_API_KEY}" }
          },
          "web-reader": {
            "type": "http",
            "url": "https://api.z.ai/api/mcp/web_reader/mcp",
            "headers": { "Authorization": "Bearer ''${ZAI_API_KEY}" }
          },
          "zread": {
            "type": "http",
            "url": "https://api.z.ai/api/mcp/zread/mcp",
            "headers": { "Authorization": "Bearer ''${ZAI_API_KEY}" }
          },
          "filesystem": {
            "command": "mcp-filesystem",
            "args": ["/etc/nixos", "/home/j_kro"]
          },
          "git": {
            "command": "mcp-git"
          },
          "fetch": {
            "command": "mcp-fetch"
          },
          "playwright": {
            "command": "mcp-playwright"
          },
          "context7": {
            "command": "mcp-context7",
            "env": { "CONTEXT7_API_KEY": $ctx7_key }
          },
          "chrome-devtools": {
            "command": "npx",
            "args": ["-y", "chrome-devtools-mcp@latest"]
          },
          "gateway": {
            "command": "mcp-gateway-bridge"
          }
        },
        "default_agent": "build",
        "logLevel": "INFO",
        "snapshot": true,
        "share": "manual",
        "autoupdate": "notify"
      }' > "/home/${cfg.user}/.opencode/config.json"

    chown ${cfg.user}:users "/home/${cfg.user}/.opencode/config.json"
    chmod 644 "/home/${cfg.user}/.opencode/config.json"
    echo "[ai-coding-tools] OpenCode config generated"
  '';
in {
  options.services.ai-coding-tools = {
    enable = mkEnableOption "Harmonized MCP configuration for all AI coding tools (Droid, Claude Code, Crush, OpenCode)";

    user = mkOption {
      type = types.str;
      default = "j_kro";
      description = "User for AI coding tool configs";
    };

    zaiApiKeyFile = mkOption {
      type = types.path;
      default = "/run/agenix/zai-api-key";
      description = "Path to Z.AI API key (agenix secret)";
    };

    context7ApiKeyFile = mkOption {
      type = types.path;
      default = "/run/agenix/context7-api-key";
      description = "Path to Context7 API key (agenix secret)";
    };

    tools = {
      droid = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Generate Factory Droid MCP config (~/.factory/mcp.json)";
        };
      };

      claude = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Generate Claude Code MCP config (~/.config/claude/mcp.json)";
        };
      };

      crush = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Generate Crush MCP config (~/.config/crush/crush.json)";
        };
      };

      opencode = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Generate OpenCode config with MCP servers (~/.opencode/config.json)";
        };
      };
    };

    # Environment variables for Z.AI API (used by Claude Code env, shell sessions)
    enableShellEnv = mkOption {
      type = types.bool;
      default = true;
      description = "Set ZAI_API_KEY and related env vars in shell session";
    };
  };

  config = mkIf cfg.enable {
    # Ensure MCP servers module is enabled (provides mcp-* commands)
    services.mcp-servers = {
      enable = true;
      servers.playwright.enable = true;
      servers.context7.apiKeyFile = cfg.context7ApiKeyFile;
    };

    # Ensure required directories exist
    systemd.tmpfiles.rules = [
      "d /home/${cfg.user}/.factory 0700 ${cfg.user} users -"
      "d /home/${cfg.user}/.factory/mcp.json 0600 ${cfg.user} users -"
      "d /home/${cfg.user}/.config/claude 0755 ${cfg.user} users -"
      "d /home/${cfg.user}/.config/crush 0755 ${cfg.user} users -"
      "d /home/${cfg.user}/.config/crush/commands 0755 ${cfg.user} users -"
      "d /home/${cfg.user}/.opencode 0755 ${cfg.user} users -"
    ];

    # Shell environment variables (ZAI_API_KEY available to all tools)
    environment.sessionVariables = mkIf cfg.enableShellEnv {
      ZAI_API_KEY_FILE = cfg.zaiApiKeyFile;
      CONTEXT7_API_KEY_FILE = cfg.context7ApiKeyFile;
    };

    # Systemd service to generate all configs after secrets are available
    systemd.services.ai-coding-tools-config = {
      description = "Generate harmonized MCP configs for AI coding tools";
      after = ["agenix.service" "network.target"];
      wants = ["agenix.service"];
      wantedBy = ["multi-user.target"];

      path = [pkgs.jq pkgs.coreutils pkgs.gnugrep];

      serviceConfig = {
        Type = "oneshot";
        User = "root";
        Group = "root";
        RemainAfterExit = true;

        # Security
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = "no";
        ReadWritePaths = [
          "/home/${cfg.user}/.factory"
          "/home/${cfg.user}/.config/claude"
          "/home/${cfg.user}/.config/crush"
          "/home/${cfg.user}/.opencode"
        ];

        ExecStart = pkgs.writeShellScript "ai-coding-tools-generate" ''
          set -euo pipefail

          # Wait for secrets to be available
          for secret in ${cfg.zaiApiKeyFile} ${cfg.context7ApiKeyFile}; do
            for i in {1..30}; do
              if [ -f "$secret" ] && [ -s "$secret" ]; then
                break
              fi
              if [ "$i" -eq 30 ]; then
                echo "[ai-coding-tools] WARNING: Secret not available: $secret"
              fi
              sleep 1
            done
          done

          export ZAI_API_KEY=$(cat ${cfg.zaiApiKeyFile} 2>/dev/null || echo "")
          export CONTEXT7_API_KEY=$(cat ${cfg.context7ApiKeyFile} 2>/dev/null || echo "")

          echo "[ai-coding-tools] Generating harmonized MCP configs..."

          ${optionalString cfg.tools.droid.enable ''
            echo "[ai-coding-tools] Generating Droid config..."
            ${mkDroidMcpJson}
          ''}

          ${optionalString cfg.tools.claude.enable ''
            echo "[ai-coding-tools] Generating Claude Code config..."
            ${mkClaudeMcpJson}
          ''}

          ${optionalString cfg.tools.crush.enable ''
            echo "[ai-coding-tools] Generating Crush config..."
            ${mkCrushConfig}
          ''}

          ${optionalString cfg.tools.opencode.enable ''
            echo "[ai-coding-tools] Generating OpenCode config..."
            ${mkOpencodeConfig}
          ''}

          echo "[ai-coding-tools] All configs generated successfully"
        '';
      };
    };

    # Fish shell integration (read secrets into env for interactive use)
    programs.fish.interactiveShellInit = mkIf cfg.enableShellEnv ''
      # AI Coding Tools - Load API keys from agenix secrets
      if test -f ${cfg.zaiApiKeyFile}
        set -gx ZAI_API_KEY (cat ${cfg.zaiApiKeyFile})
      end
      if test -f ${cfg.context7ApiKeyFile}
        set -gx CONTEXT7_API_KEY (cat ${cfg.context7ApiKeyFile})
      end
    '';

    # Bash integration
    programs.bash.interactiveShellInit = mkIf cfg.enableShellEnv ''
      # AI Coding Tools - Load API keys from agenix secrets
      if [ -f ${cfg.zaiApiKeyFile} ]; then
        export ZAI_API_KEY=$(cat ${cfg.zaiApiKeyFile})
      fi
      if [ -f ${cfg.context7ApiKeyFile} ]; then
        export CONTEXT7_API_KEY=$(cat ${cfg.context7ApiKeyFile})
      fi
    '';

    # CLI helper for manual regeneration
    environment.systemPackages = [
      (pkgs.writeShellScriptBin "ai-tools-regenerate" ''
        #!/bin/bash
        echo "Regenerating all AI coding tool MCP configs..."
        sudo systemctl restart ai-coding-tools-config.service
        journalctl -u ai-coding-tools-config.service -n 20 --no-pager
      '')
      (pkgs.writeShellScriptBin "ai-tools-status" ''
        #!/bin/bash
        echo "=== AI Coding Tools Status ==="
        echo ""
        echo "Config files:"
        for f in \
          "/home/${cfg.user}/.factory/mcp.json" \
          "/home/${cfg.user}/.config/claude/mcp.json" \
          "/home/${cfg.user}/.config/crush/crush.json" \
          "/home/${cfg.user}/.opencode/config.json"; do
          if [ -f "$f" ]; then
            servers=$(${pkgs.jq}/bin/jq -r '[.mcpServers // .mcp | keys[]] | length' "$f" 2>/dev/null || echo "?")
            echo "  ✓ $f ($servers MCP servers)"
          else
            echo "  ✗ $f (missing)"
          fi
        done
        echo ""
        echo "Secrets:"
        for s in ${cfg.zaiApiKeyFile} ${cfg.context7ApiKeyFile}; do
          if [ -f "$s" ] && [ -s "$s" ]; then
            echo "  ✓ $s"
          else
            echo "  ✗ $s (missing)"
          fi
        done
        echo ""
        echo "MCP wrapper commands:"
        for cmd in mcp-filesystem mcp-git mcp-fetch mcp-playwright mcp-context7 mcp-gateway-bridge; do
          if command -v "$cmd" &>/dev/null; then
            echo "  ✓ $cmd"
          else
            echo "  ✗ $cmd (not in PATH)"
          fi
        done
      '')
    ];

    # Documentation
    environment.etc."ai-coding-tools/README.md".text = ''
      # AI Coding Tools - Harmonized MCP Configuration

      Managed by: `services.ai-coding-tools` NixOS module
      Regenerate: `ai-tools-regenerate`
      Status:     `ai-tools-status`

      ## Unified MCP Server Set

      | Server | Type | Purpose | All Tools |
      |--------|------|---------|-----------|
      | zai-mcp-server | stdio | Z.AI image/video/analysis | Yes |
      | web-search-prime | HTTP | Z.AI web search | Yes |
      | web-reader | HTTP | Z.AI URL reader | Yes |
      | zread | HTTP | Z.AI GitHub repo reader | Yes |
      | filesystem | stdio | Local filesystem access | Yes |
      | git | stdio | Git operations | Yes |
      | fetch | stdio | Web fetching | Yes |
      | playwright | stdio | Browser automation | Yes |
      | context7 | stdio | Documentation search | Yes |
      | chrome-devtools | stdio | Chrome debugging | Yes |
      | gateway | stdio | AI Inference Gateway bridge | Yes |
      | nixos | stdio | NixOS helper (uvx) | Claude only |

      ## Tool Config Locations

      | Tool | Config Path | Format |
      |------|------------|--------|
      | Droid (Factory) | ~/.factory/mcp.json | MCP servers only |
      | Claude Code | ~/.config/claude/mcp.json | MCP servers only |
      | Crush | ~/.config/crush/crush.json | Provider + MCP |
      | OpenCode | ~/.opencode/config.json | Provider + MCP |

      ## API Keys

      All keys managed via agenix secrets:
      - ZAI_API_KEY: /run/agenix/zai-api-key
      - CONTEXT7_API_KEY: /run/agenix/context7-api-key

      Keys are loaded into shell environment (fish/bash) and referenced
      in configs at generation time. Z.AI HTTP servers use Bearer tokens.
    '';
  };
}
