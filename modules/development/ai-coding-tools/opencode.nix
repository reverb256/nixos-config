{
  cfg,
  pkgs,
  gatewayUrl,
  nvidiaNimBaseUrl,
  mkMcpServersJson,
}: {
  mkOpencodeConfig = pkgs.writeShellScript "generate-opencode-config" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail
    CTX7_KEY_PATH="${cfg.context7ApiKeyFile}"
    CONTEXT7_API_KEY="$(cat $CTX7_KEY_PATH 2>/dev/null || echo)"
    NVIDIA_NIM_KEY_PATH="${cfg.nvidiaNimApiKeyFile}"
    NVIDIA_NIM_API_KEY="$(cat $NVIDIA_NIM_KEY_PATH 2>/dev/null || echo)"
    ${pkgs.jq}/bin/jq -n \
      --arg ctx7_key "$CONTEXT7_API_KEY" \
      --arg nvidia_key "$NVIDIA_NIM_API_KEY" \
      --arg gateway_base "${gatewayUrl}/v1" \
      --arg nvidia_base "${nvidiaNimBaseUrl}" \
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
          "nvidia-nim": {
            "npm": "@ai-sdk/openai-compatible",
            "name": "NVIDIA NIM",
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
        "enabled_providers": ["ai-gateway", "nvidia-nim", "lmstudio"],
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
