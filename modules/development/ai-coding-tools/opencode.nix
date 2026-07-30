{
  cfg,
  pkgs,
  gatewayUrl,
  zaiCodingBaseUrl,
  nvidiaNimBaseUrl,
  mkMcpServersJson,
}: {
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
