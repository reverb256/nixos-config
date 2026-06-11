{
  cfg,
  pkgs,
  gatewayUrl,
  mkMcpServersJson,
}: let
  zaiCodingBaseUrl = gatewayUrl + "/v1";
  nvidiaNimBaseUrl = gatewayUrl + "/v1";
  opencodeGoBaseUrl = gatewayUrl + "/v1";
in {
  mkOpencodeConfig = pkgs.writeShellScript "generate-opencode-config" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail
    ZAI_KEY_PATH="${cfg.zaiApiKeyFile}"
    ZAI_API_KEY="$(cat $ZAI_KEY_PATH 2>/dev/null || echo)"
    CTX7_KEY_PATH="${cfg.context7ApiKeyFile}"
    CONTEXT7_API_KEY="$(cat $CTX7_KEY_PATH 2>/dev/null || echo)"
    NVIDIA_NIM_KEY_PATH="${cfg.nvidiaNimApiKeyFile}"
    NVIDIA_NIM_API_KEY="$(cat $NVIDIA_NIM_KEY_PATH 2>/dev/null || echo)"
    OPENCODE_GO_KEY_PATH="${cfg.opencodeGoApiKeyFile}"
    OPENCODE_GO_API_KEY="$(cat $OPENCODE_GO_KEY_PATH 2>/dev/null || echo)"
    ${pkgs.jq}/bin/jq -n \
      --arg zai_key "$ZAI_API_KEY" \
      --arg ctx7_key "$CONTEXT7_API_KEY" \
      --arg nvidia_key "$NVIDIA_NIM_API_KEY" \
      --arg opencode_go_key "$OPENCODE_GO_API_KEY" \
      --arg gateway_base "${gatewayUrl}/v1" \
      --arg zai_coding_base "${zaiCodingBaseUrl}" \
      --arg nvidia_base "${nvidiaNimBaseUrl}" \
      --arg opencode_go_base "${opencodeGoBaseUrl}" \
      '{
        "$schema": "https://opencode.ai/config.json",
        "comment": "Harmonized config - managed by NixOS ai-coding-tools module",
        "model": "opencode-go/deepseek-v4-flash",
        "small_model": "nvidia-nim/nvidia/nemotron-3-nano-30b-a3b",
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
          "nvidia-nim": {
            "npm": "@ai-sdk/openai-compatible",
            "name": "NVIDIA NIM (100+ Free LLM Models)",
            "options": {
              "baseURL": $nvidia_base,
              "apiKey": $nvidia_key
            },
            "models": {
          "nvidia-nim/nvidia/nemotron-3-nano-30b-a3b": {
            "name": "Nemotron 3 Nano 30B (NVIDIA NIM)",
            "description": "Lightweight 30B reasoning model, good for small tasks"
          }
        }
      },
      "opencode-go": {
        "npm": "@ai-sdk/openai-compatible",
        "name": "OpenCode Go (DeepSeek V4 Flash)",
        "options": {
          "baseURL": $opencode_go_base,
          "apiKey": $opencode_go_key
        },
        "models": {
          "opencode-go/deepseek-v4-flash": {
            "name": "DeepSeek V4 Flash",
            "description": "DeepSeek V4 Flash via OpenCode Go middleware"
          }
        }
      },
      "lmstudio": {
            "npm": "@ai-sdk/openai-compatible",
            "name": "LM Studio (Local)",
            "options": {
              "baseURL": "http://127.0.0.1:1234/v1"
            }
          },
          "llama-cpp": {
            "npm": "@ai-sdk/openai-compatible",
            "name": "llama.cpp Server (Zephyr 3090)",
            "options": {
              "baseURL": "http://10.1.1.110:1237/v1"
            }
          }
        },
        "enabled_providers": ["zai-coding-plan", "opencode-go", "nvidia-nim", "lmstudio", "llama-cpp"],
        "disabled_providers": ["openai", "anthropic", "google", "cohere"],
        "mcp": {
          ${mkMcpServersJson {keyMode = "env";}}
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
}
