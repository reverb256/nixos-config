{
  cfg,
  pkgs,
  gatewayUrl,
  nvidiaNimBaseUrl,
  mkMcpServersJson,
}: {
  mkPiConfig = pkgs.writeShellScript "generate-pi-config" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail
    NVIDIA_NIM_KEY_PATH="${cfg.nvidiaNimApiKeyFile}"
    NVIDIA_NIM_API_KEY="$(cat $NVIDIA_NIM_KEY_PATH 2>/dev/null || echo)"
    mkdir -p "/home/${cfg.user}/.pi/agent"
    ${pkgs.jq}/bin/jq -n \
      --arg nvidia_key "$NVIDIA_NIM_API_KEY" \
      --arg gateway_base "${gatewayUrl}/v1" \
      --arg nvidia_base "${nvidiaNimBaseUrl}" \
      '{
        "providers": {
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
                "name": "Kimi K2.5 (NVIDIA NIM)",
                "reasoning": true,
                "input": ["text", "image", "video"],
                "contextWindow": 262144,
                "maxTokens": 262144,
                "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0}
              },
              {
                "id": "minimaxai/minimax-m2.5",
                "name": "MiniMax M2.5 (NVIDIA NIM)",
                "reasoning": true,
                "input": ["text"],
                "contextWindow": 1048576,
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
    ${pkgs.jq}/bin/jq -n \
      --argjson packages '${builtins.toJSON cfg.tools.pi.packages}' \
      '{
        "model": "ai-gateway/qwen3.5-4b",
        "lastChangelogVersion": "auto",
        "defaultProvider": "ai-gateway",
        "defaultModel": "qwen3.5-4b",
        "packages": $packages
      }' > "/home/${cfg.user}/.pi/agent/settings.json"
    chown -R ${cfg.user}:users "/home/${cfg.user}/.pi/agent"
    chmod 600 "/home/${cfg.user}/.pi/agent/models.json"
    chmod 600 "/home/${cfg.user}/.pi/agent/settings.json"
    echo "[ai-coding-tools] Pi config generated"
  '';
}
