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
}:
let
  cfg = config.services.ai-coding-tools;
  inherit (lib)
    mkEnableOption
    mkOption
    mkIf
    types
    optionalString
    concatStringsSep
    escapeJSON
    ;
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
  # NVIDIA NIM API base URL
  nvidiaNimBaseUrl = "https://integrate.api.nvidia.com/v1";
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
    args = [
      "-y"
      "@z_ai/mcp-server"
    ];
    env = {
      Z_AI_MODE = "ZAI";
      Z_AI_API_KEY = zaiApiKeyRef;
    };
  };
  # Local stdio MCP servers (use mcp-* wrappers from mcp-servers.nix)
  localStdioServers = {
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
      env.CONTEXT7_API_KEY = context7ApiKeyRef;
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
      # SearXNG via fetch wrapper with custom URL
      # Note: If a dedicated searxng MCP wrapper exists, replace this
    };
  };
  # Full MCP set: Z.AI stdio + Z.AI HTTP + local stdio
  fullMcpSet =
    localStdioServers
    // {
      "zai-mcp-server" = zaiStdioServer;
    }
    // zaiHttpServers;
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
    ZAI_KEY_PATH="${cfg.zaiApiKeyFile}"
    ZAI_API_KEY="$(cat $ZAI_KEY_PATH 2>/dev/null || echo)"
    CTX7_KEY_PATH="${cfg.context7ApiKeyFile}"
    CONTEXT7_API_KEY="$(cat $CTX7_KEY_PATH 2>/dev/null || echo)"
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
    ZAI_KEY_PATH="${cfg.zaiApiKeyFile}"
    ZAI_API_KEY="$(cat $ZAI_KEY_PATH 2>/dev/null || echo)"
    CTX7_KEY_PATH="${cfg.context7ApiKeyFile}"
    CONTEXT7_API_KEY="$(cat $CTX7_KEY_PATH 2>/dev/null || echo)"
    NVIDIA_NIM_KEY_PATH="${cfg.nvidiaNimApiKeyFile}"
    NVIDIA_NIM_API_KEY="$(cat $NVIDIA_NIM_KEY_PATH 2>/dev/null || echo)"
    ${pkgs.jq}/bin/jq -n \
      --arg zai_key "$ZAI_API_KEY" \
      --arg ctx7_key "$CONTEXT7_API_KEY" \
      --arg nvidia_key "$NVIDIA_NIM_API_KEY" \
      --arg zai_base "https://api.z.ai/api/coding/paas/v4" \
      --arg gateway_base "${gatewayUrl}/v1" \
      --arg nvidia_base "${nvidiaNimBaseUrl}" \
      '{
        "providers": {
          "zai": {
            "id": "zai",
            "name": "ZAI Provider",
            "base_url": $zai_base,
            "api_key": $zai_key
          },
          "ai-gateway": {
            "id": "ai-gateway",
            "name": "AI Gateway (K8s)",
            "base_url": $gateway_base
          },
          "nvidia-nim": {
            "id": "nvidia-nim",
            "name": "NVIDIA NIM",
            "base_url": $nvidia_base,
            "api_key": $nvidia_key
          },
          "lmstudio": {
            "id": "lmstudio",
            "name": "LM Studio (Local)",
            "base_url": "http://127.0.0.1:8080/v1"
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
    ZAI_KEY_PATH="${cfg.zaiApiKeyFile}"
    ZAI_API_KEY="$(cat $ZAI_KEY_PATH 2>/dev/null || echo)"
    CTX7_KEY_PATH="${cfg.context7ApiKeyFile}"
    CONTEXT7_API_KEY="$(cat $CTX7_KEY_PATH 2>/dev/null || echo)"
    NVIDIA_NIM_KEY_PATH="${cfg.nvidiaNimApiKeyFile}"
    NVIDIA_NIM_API_KEY="$(cat $NVIDIA_NIM_KEY_PATH 2>/dev/null || echo)"
    ${pkgs.jq}/bin/jq -n \
      --arg zai_key "$ZAI_API_KEY" \
      --arg ctx7_key "$CONTEXT7_API_KEY" \
      --arg nvidia_key "$NVIDIA_NIM_API_KEY" \
      --arg gateway_base "${gatewayUrl}/v1" \
      --arg zai_coding_base "${zaiCodingBaseUrl}" \
      --arg nvidia_base "${nvidiaNimBaseUrl}" \
      '{
        "$schema": "https://opencode.ai/config.json",
        "comment": "Harmonized config - managed by NixOS ai-coding-tools module",
        "model": "zai-coding-plan/glm-5.1",
        "small_model": "ai-gateway/qwen3.5-4b",
        "provider": {
          "zai-coding-plan": {
            "npm": "@ai-sdk/openai-compatible",
            "name": "Z.AI Coding Plan (GLM Models)",
            "options": {
              "baseURL": $zai_coding_base,
              "apiKey": $zai_key
            },
            "models": {
              "zai-coding-plan/glm-5.1": {
                "name": "GLM-5.1 (Z.AI)",
                "description": "GLM-5.1 orchestrator model via Z.AI"
              },
              "zai-coding-plan/glm-5": {
                "name": "GLM-5 (Z.AI)",
                "description": "GLM-5 744B MoE agentic model via Z.AI"
              },
              "zai-coding-plan/glm-5-turbo": {
                "name": "GLM-5 Turbo (Z.AI)",
                "description": "GLM-5 Turbo fast agentic model via Z.AI"
              },
              "zai-coding-plan/glm-4.7": {
                "name": "GLM-4.7 (Z.AI)",
                "description": "GLM-4.7 358B MoE coding model via Z.AI"
              },
              "zai-coding-plan/glm-4.7-flash": {
                "name": "GLM-4.7 Flash (Z.AI)",
                "description": "GLM-4.7 Flash 30B vision model via Z.AI"
              },
              "zai-coding-plan/glm-4.5-air": {
                "name": "GLM-4.5 Air (Z.AI)",
                "description": "GLM-4.5 Air lightweight model via Z.AI"
              }
            }
          },
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
          "nvidia-nim": {
            "npm": "@ai-sdk/openai-compatible",
            "name": "NVIDIA NIM (100+ Free LLM Models)",
            "options": {
              "baseURL": $nvidia_base,
              "apiKey": $nvidia_key
            },
            "models": {
              "nvidia-nim/llama-3.1-nemotron-70b-instruct": {
                "name": "Llama 3.1 Nemotron 70B (NVIDIA NIM)",
                "description": "NVIDIA fine-tuned Llama 3.1 70B instruct model"
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
        "enabled_providers": ["zai-coding-plan", "ai-gateway", "nvidia-nim", "lmstudio"],
        "disabled_providers": ["openai", "anthropic", "google", "cohere"],
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
  # Pi Coding Agent: ~/.pi/agent/settings.json + models.json
  mkPiConfig = pkgs.writeShellScript "generate-pi-config" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail
    ZAI_KEY_PATH="${cfg.zaiApiKeyFile}"
    ZAI_API_KEY="$(cat $ZAI_KEY_PATH 2>/dev/null || echo)"
    NVIDIA_NIM_KEY_PATH="${cfg.nvidiaNimApiKeyFile}"
    NVIDIA_NIM_API_KEY="$(cat $NVIDIA_NIM_KEY_PATH 2>/dev/null || echo)"
    mkdir -p "/home/${cfg.user}/.pi/agent"
    ${pkgs.jq}/bin/jq -n \
      --arg zai_key "$ZAI_API_KEY" \
      --arg nvidia_key "$NVIDIA_NIM_API_KEY" \
      --arg gateway_base "${gatewayUrl}/v1" \
      --arg nvidia_base "${nvidiaNimBaseUrl}" \
      '{
        "providers": {
          "zai": {
            "baseUrl": "https://api.z.ai/api/coding/paas/v4",
            "api": "openai-completions",
            "apiKey": $zai_key,
            "models": [
              {
                "id": "glm-5.1",
                "name": "GLM-5.1 (Z.AI)",
                "reasoning": true,
                "input": ["text"],
                "contextWindow": 200000,
                "maxTokens": 131072,
                "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0}
              },
              {
                "id": "glm-5",
                "name": "GLM-5 (Z.AI)",
                "reasoning": true,
                "input": ["text"],
                "contextWindow": 200000,
                "maxTokens": 131072,
                "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0}
              },
              {
                "id": "glm-5-turbo",
                "name": "GLM-5 Turbo (Z.AI)",
                "reasoning": true,
                "input": ["text"],
                "contextWindow": 200000,
                "maxTokens": 131072,
                "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0}
              },
              {
                "id": "glm-4.7",
                "name": "GLM-4.7 (Z.AI)",
                "reasoning": true,
                "input": ["text"],
                "contextWindow": 200000,
                "maxTokens": 131072,
                "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0}
              },
              {
                "id": "glm-4.7-flash",
                "name": "GLM-4.7 Flash (Z.AI)",
                "reasoning": true,
                "input": ["text"],
                "contextWindow": 131072,
                "maxTokens": 8192,
                "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0}
              },
              {
                "id": "glm-4.5-air",
                "name": "GLM-4.5 Air (Z.AI)",
                "reasoning": false,
                "input": ["text"],
                "contextWindow": 131072,
                "maxTokens": 8192,
                "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0}
              }
            ]
          },
          "ai-gateway": {
            "baseUrl": $gateway_base,
            "api": "openai-completions",
            "apiKey": "k8s-gateway",
            "models": [
              {
                "id": "qwen3.5-4b",
                "name": "Qwen3.5 4B (K8s Gateway)",
                "reasoning": true,
                "input": ["text"],
                "contextWindow": 32000,
                "maxTokens": 8192,
                "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0}
              },
              {
                "id": "qwen3.5-32b",
                "name": "Qwen3.5 32B (K8s Gateway)",
                "reasoning": true,
                "input": ["text"],
                "contextWindow": 32000,
                "maxTokens": 8192,
                "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0}
              },
              {
                "id": "deepseek-r1",
                "name": "DeepSeek R1 (K8s Gateway)",
                "reasoning": true,
                "input": ["text"],
                "contextWindow": 64000,
                "maxTokens": 8192,
                "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0}
              }
            ]
          },
          "nvidia-nim": {
            "baseUrl": $nvidia_base,
            "api": "openai-completions",
            "apiKey": $nvidia_key,
            "models": [
              {
                "id": "nvidia/nemotron-3-super-120b-a12b",
                "name": "Nemotron 3 Super 120B (NVIDIA NIM)",
                "reasoning": true,
                "input": ["text"],
                "contextWindow": 1048576,
                "maxTokens": 65536,
                "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0}
              },
              {
                "id": "nvidia/nemotron-3-nano-30b-a3b",
                "name": "Nemotron 3 Nano 30B (NVIDIA NIM)",
                "reasoning": true,
                "input": ["text"],
                "contextWindow": 1048576,
                "maxTokens": 65536,
                "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0}
              },
              {
                "id": "deepseek-ai/deepseek-v3.1",
                "name": "DeepSeek V3.1 (NVIDIA NIM)",
                "reasoning": true,
                "input": ["text"],
                "contextWindow": 131072,
                "maxTokens": 65536,
                "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0}
              },
              {
                "id": "moonshotai/kimi-k2.5",
                "name": "Kimi K2.5 1T (NVIDIA NIM)",
                "reasoning": true,
                "input": ["text"],
                "contextWindow": 262144,
                "maxTokens": 262144,
                "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0}
              },
              {
                "id": "minimaxai/minimax-m2.5",
                "name": "MiniMax M2.5 230B (NVIDIA NIM)",
                "reasoning": true,
                "input": ["text"],
                "contextWindow": 1048576,
                "maxTokens": 131072,
                "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0}
              },
              {
                "id": "z-ai/glm5",
                "name": "GLM-5 744B (NVIDIA NIM)",
                "reasoning": true,
                "input": ["text"],
                "contextWindow": 205000,
                "maxTokens": 131072,
                "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0}
              },
              {
                "id": "openai/gpt-oss-120b",
                "name": "GPT-OSS 120B (NVIDIA NIM)",
                "reasoning": true,
                "input": ["text"],
                "contextWindow": 131072,
                "maxTokens": 131072,
                "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0}
              },
              {
                "id": "openai/gpt-oss-20b",
                "name": "GPT-OSS 20B (NVIDIA NIM)",
                "reasoning": true,
                "input": ["text"],
                "contextWindow": 131072,
                "maxTokens": 131072,
                "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0}
              },
              {
                "id": "qwen/qwen3-coder-480b-a35b-instruct",
                "name": "Qwen3 Coder 480B (NVIDIA NIM)",
                "reasoning": true,
                "input": ["text"],
                "contextWindow": 1048576,
                "maxTokens": 65536,
                "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0}
              }
            ]
          },
          "lmstudio": {
            "baseUrl": "http://127.0.0.1:1234/v1",
            "api": "openai-completions",
            "apiKey": "lmstudio",
            "models": [
              {
                "id": "qwen3.5-4b",
                "name": "Qwen3.5 4B (LM Studio)",
                "reasoning": true,
                "input": ["text"],
                "contextWindow": 32000,
                "maxTokens": 8192,
                "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0}
              }
            ]
          }
        }
      }' > "/home/${cfg.user}/.pi/agent/models.json"
    # Build settings.json with model config + declarative packages
    ${pkgs.jq}/bin/jq -n \
      --argjson packages '${builtins.toJSON cfg.tools.pi.packages}' \
      '{
        "model": "zai/glm-5.1",
        "lastChangelogVersion": "auto",
        "defaultProvider": "zai",
        "defaultModel": "glm-5.1",
        "packages": $packages
      }' > "/home/${cfg.user}/.pi/agent/settings.json"
    chown -R ${cfg.user}:users "/home/${cfg.user}/.pi/agent"
    chmod 600 "/home/${cfg.user}/.pi/agent/models.json"
    chmod 600 "/home/${cfg.user}/.pi/agent/settings.json"
    echo "[ai-coding-tools] Pi config generated"
  '';
  # Factory Droid: ~/.factory/settings.json
  # Droid supports ${VAR} interpolation in settings.json, so we use env var references
  # instead of resolving keys at generation time.
  mkDroidSettings = pkgs.writeShellScript "generate-droid-settings" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail
    NVIDIA_NIM_KEY_PATH="${cfg.nvidiaNimApiKeyFile}"
    NVIDIA_NIM_API_KEY="$(cat $NVIDIA_NIM_KEY_PATH 2>/dev/null || echo)"
    ${pkgs.jq}/bin/jq -n \
      --arg nvidia_key "$NVIDIA_NIM_API_KEY" \
      '{
        "enabledPlugins": {
          "core@factory-plugins": true
        },
        "logoAnimation": "off",
        "customModels": [
          {
            "model": "glm-5.1",
            "id": "custom:GLM-5.1-Z.AI-Anthropic-0",
            "index": 0,
            "baseUrl": "https://api.z.ai/api/anthropic",
            "apiKey": "$ZAI_API_KEY",
            "displayName": "GLM-5.1 [Orchestrator Tier - Planning, Architecture, Review]",
            "maxOutputTokens": 131072,
            "noImageSupport": false,
            "provider": "anthropic"
          },
          {
            "model": "glm-5",
            "id": "custom:GLM-5-Z.AI-Anthropic-1",
            "index": 1,
            "baseUrl": "https://api.z.ai/api/anthropic",
            "apiKey": "$ZAI_API_KEY",
            "displayName": "GLM-5 [Orchestrator Tier - 744B MoE, Agentic]",
            "maxOutputTokens": 131072,
            "noImageSupport": false,
            "provider": "anthropic"
          },
          {
            "model": "glm-4.7",
            "id": "custom:GLM-4.7-Z.AI-Anthropic-2",
            "index": 2,
            "baseUrl": "https://api.z.ai/api/anthropic",
            "apiKey": "$ZAI_API_KEY",
            "displayName": "GLM-4.7 [Worker Tier - 358B MoE, Coding King]",
            "maxOutputTokens": 131072,
            "noImageSupport": false,
            "provider": "anthropic"
          },
          {
            "model": "glm-4.5-air",
            "id": "custom:GLM-4.5-Air-Z.AI-Anthropic-3",
            "index": 3,
            "baseUrl": "https://api.z.ai/api/anthropic",
            "apiKey": "$ZAI_API_KEY",
            "displayName": "GLM-4.5 Air [Validator Tier - Lightweight, Fast]",
            "maxOutputTokens": 131072,
            "noImageSupport": false,
            "provider": "anthropic"
          },
          {
            "model": "glm-5-turbo",
            "id": "custom:GLM-5-Turbo-Z.AI-Anthropic-4",
            "index": 4,
            "baseUrl": "https://api.z.ai/api/anthropic",
            "apiKey": "$ZAI_API_KEY",
            "displayName": "GLM-5 Turbo [Orchestrator Tier - Agentic, Fast]",
            "maxOutputTokens": 131072,
            "noImageSupport": true,
            "provider": "anthropic"
          },
          {
            "model": "glm-4.7-flash",
            "id": "custom:GLM-4.7-Flash-Z.AI-Anthropic-5",
            "index": 5,
            "baseUrl": "https://api.z.ai/api/anthropic",
            "apiKey": "$ZAI_API_KEY",
            "displayName": "GLM-4.7 Flash [Worker Tier - 30B MoE, Vision]",
            "maxOutputTokens": 131072,
            "noImageSupport": false,
            "provider": "anthropic"
          },
          {
            "model": "qwen3.5-4b",
            "id": "custom:Qwen3.5-4B-Gateway-OpenAI-6",
            "index": 6,
            "baseUrl": "http://ai-inference-gateway.ai-inference.svc.cluster.local:8080/v1",
            "apiKey": "k8s-gateway",
            "displayName": "Qwen 3.5 4B [K8s Gateway - llama.cpp]",
            "maxOutputTokens": 8192,
            "noImageSupport": true,
            "provider": "openai"
          },
          {
            "model": "qwen3.5-32b",
            "id": "custom:Qwen3.5-32B-Gateway-OpenAI-7",
            "index": 7,
            "baseUrl": "http://ai-inference-gateway.ai-inference.svc.cluster.local:8080/v1",
            "apiKey": "k8s-gateway",
            "displayName": "Qwen 3.5 32B [K8s Gateway - vLLM]",
            "maxOutputTokens": 8192,
            "noImageSupport": true,
            "provider": "openai"
          },
          {
            "model": "deepseek-r1",
            "id": "custom:DeepSeek-R1-Gateway-OpenAI-8",
            "index": 8,
            "baseUrl": "http://ai-inference-gateway.ai-inference.svc.cluster.local:8080/v1",
            "apiKey": "k8s-gateway",
            "displayName": "DeepSeek R1 [K8s Gateway - SGLang]",
            "maxOutputTokens": 8192,
            "noImageSupport": true,
            "provider": "openai"
          },
          {
            "model": "meta/llama-3.1-70b-instruct",
            "id": "custom:Llama-3.1-70B-NVIDIA-NIM-OpenAI-9",
            "index": 9,
            "baseUrl": "https://integrate.api.nvidia.com/v1",
            "apiKey": $nvidia_key,
            "displayName": "Llama 3.1 70B [NVIDIA NIM - Free]",
            "maxOutputTokens": 4096,
            "noImageSupport": true,
            "provider": "openai"
          }
        ],
        "sessionDefaultSettings": {
          "model": "custom:GLM-5.1-Z.AI-Anthropic-0",
          "reasoningEffort": "high",
          "interactionMode": "auto",
          "autonomyLevel": "high",
          "autonomyMode": "auto-high"
        },
        "hasSeenMissionOnboarding": true,
        "missionModelSettings": {
          "workerModel": "custom:GLM-4.7-Z.AI-Anthropic-2",
          "workerReasoningEffort": "none",
          "validationWorkerModel": "custom:GLM-5-Turbo-Z.AI-Anthropic-4",
          "validationWorkerReasoningEffort": "none"
        },
        "terminalColorMode": "dark",
        "cloudSessionSync": true,
        "ideAutoConnect": true
      }' > "/home/${cfg.user}/.factory/settings.json"
    chown ${cfg.user}:users "/home/${cfg.user}/.factory/settings.json"
    chmod 600 "/home/${cfg.user}/.factory/settings.json"
    echo "[ai-coding-tools] Droid settings generated with env var references"
  '';
in
{
  options.services.ai-coding-tools = {
    enable = mkEnableOption "Harmonized MCP configuration for all AI coding tools (Droid, Claude Code, Crush, OpenCode, Pi)";
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
    nvidiaNimApiKeyFile = mkOption {
      type = types.path;
      default = "/run/agenix/nvidia-api-key";
      description = "Path to NVIDIA NIM API key (agenix secret)";
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
      pi = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Generate Pi Coding Agent config (~/.pi/agent/settings.json, models.json)";
        };
        packages = mkOption {
          type = types.listOf types.str;
          default = [ ];
          example = [
            "npm:pi-lens@3.8.5"
            "npm:pi-powerline-footer@0.4.9"
          ];
          description = ''
            Declarative pi packages for global settings (~/.pi/agent/settings.json).
            These survive NixOS activation. Use `pi install -l <pkg>` for
            project-scoped packages (written to .pi/settings.json, not touched
            by this module).
          '';
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
      # Note: .factory/mcp.json is created as a FILE by the activation script,
      # NOT as a directory. Do NOT add a 'd' tmpfiles rule for it.
      "d /home/${cfg.user}/.config/claude 0755 ${cfg.user} users -"
      "d /home/${cfg.user}/.config/crush 0755 ${cfg.user} users -"
      "d /home/${cfg.user}/.config/crush/commands 0755 ${cfg.user} users -"
      "d /home/${cfg.user}/.opencode 0755 ${cfg.user} users -"
      "d /home/${cfg.user}/.pi/agent 0700 ${cfg.user} users -"
      "d /home/${cfg.user}/.pi/agent/sessions 0700 ${cfg.user} users -"
    ];
    # Shell environment variables (ZAI_API_KEY available to all tools)
    environment.sessionVariables = mkIf cfg.enableShellEnv {
      ZAI_API_KEY_FILE = cfg.zaiApiKeyFile;
      CONTEXT7_API_KEY_FILE = cfg.context7ApiKeyFile;
    };
    # Systemd service to generate all configs after secrets are available
    systemd.services.ai-coding-tools-config = {
      description = "Generate harmonized MCP configs for AI coding tools";
      after = [
        "agenix.service"
        "network.target"
      ];
      wants = [ "agenix.service" ];
      wantedBy = [ "multi-user.target" ];
      path = [
        pkgs.jq
        pkgs.coreutils
        pkgs.gnugrep
      ];
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
          "/home/${cfg.user}/.pi"
        ];
        ExecStart = pkgs.writeShellScript "ai-coding-tools-generate" ''
                set -euo pipefail
                # Wait for secrets to be available
                for secret in ${cfg.zaiApiKeyFile} ${cfg.context7ApiKeyFile} ${cfg.nvidiaNimApiKeyFile}; do
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
                export ZAI_KEY_PATH="${cfg.zaiApiKeyFile}"
          ZAI_API_KEY="$(cat $ZAI_KEY_PATH 2>/dev/null || echo)"
                export CTX7_KEY_PATH="${cfg.context7ApiKeyFile}"
          CONTEXT7_API_KEY="$(cat $CTX7_KEY_PATH 2>/dev/null || echo)"
                export NVIDIA_NIM_KEY_PATH="${cfg.nvidiaNimApiKeyFile}"
          NVIDIA_NIM_API_KEY="$(cat $NVIDIA_NIM_KEY_PATH 2>/dev/null || echo)"
                echo "[ai-coding-tools] Generating harmonized MCP configs..."
                ${optionalString cfg.tools.droid.enable ''
                  echo "[ai-coding-tools] Generating Droid settings..."
                  ${mkDroidSettings}
                  echo "[ai-coding-tools] Generating Droid MCP config..."
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
                ${optionalString cfg.tools.pi.enable ''
                  echo "[ai-coding-tools] Generating Pi config..."
                  ${mkPiConfig}
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
        ZAI_KEY_PATH="${cfg.zaiApiKeyFile}"
        export ZAI_API_KEY="$(cat $ZAI_KEY_PATH)"
      fi
      if [ -f ${cfg.context7ApiKeyFile} ]; then
        CTX7_KEY_PATH="${cfg.context7ApiKeyFile}"
        export CONTEXT7_API_KEY="$(cat $CTX7_KEY_PATH)"
      fi
    '';
    # CLI helper for manual regeneration
    environment.systemPackages = [
      # Crush wrapper - npm package @charmland/crush
      (pkgs.writeShellScriptBin "crush" ''
        export PATH="${pkgs.nodejs_22}/bin:$PATH"
        export npm_config_cache="/var/cache/ai-inference/npm"
        exec ${pkgs.nodejs_22}/bin/npx -y @charmland/crush@latest "$@"
      '')
      # Pi wrapper - npm package @mariozechner/pi-coding-agent
      (pkgs.writeShellScriptBin "pi" ''
        export PATH="${pkgs.nodejs_22}/bin:$PATH"
        export npm_config_cache="/var/cache/ai-inference/npm"
        exec ${pkgs.nodejs_22}/bin/npx -y @mariozechner/pi-coding-agent@latest "$@"
      '')
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
          "/home/${cfg.user}/.opencode/config.json" \
          "/home/${cfg.user}/.pi/agent/settings.json" \
          "/home/${cfg.user}/.pi/agent/models.json"; do
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
      ## Unified Provider Set
      | Provider | Endpoint | Key Source | Tools |
      |----------|----------|------------|-------|
      | Z.AI (Anthropic) | api.z.ai/api/anthropic | agenix | Droid |
      | Z.AI (OpenAI) | api.z.ai/api/coding/paas/v4 | agenix | OpenCode, Crush, Pi |
      | K8s AI Gateway | ai-inference-gateway:8080/v1 | None (internal) | OpenCode, Crush, Pi, Droid |
      | NVIDIA NIM | integrate.api.nvidia.com/v1 | agenix | OpenCode, Crush, Pi, Droid |
      | LM Studio | 127.0.0.1:8080/v1 | None (local) | OpenCode, Crush, Pi |
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
      | Pi Coding Agent | ~/.pi/agent/settings.json | Provider + models |
      ## CLI Wrappers
      | Tool | Command | Source |
      |------|---------|--------|
      | Crush | `crush` | npx @charmland/crush@latest |
      | Pi | `pi` | npx @mariozechner/pi-coding-agent@latest |
      ## API Keys
      All keys managed via agenix secrets:
      - zai-api-key → /run/agenix/zai-api-key
      - context7-api-key → /run/agenix/context7-api-key
      - nvidia-api-key → /run/agenix/nvidia-api-key
      Keys are loaded into shell environment (fish/bash) and referenced
      in configs at generation time. Z.AI HTTP servers use Bearer tokens.
    '';
  };
}
