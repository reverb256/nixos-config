{ cfg, pkgs }:
let
  gatewayUrl = "http://ai-inference-gateway.ai-inference.svc.cluster.local:8080";
  nvidiaNimBaseUrl = "https://integrate.api.nvidia.com/v1";
in
{
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
            ],
          },
          "sentry-local": {
            "baseUrl": "http://sentry:1235/v1",
            "api": "openai-completions",
            "apiKey": "unused",
            "models": [
              {
                "id": "Qwen3.5-4B.Q4_K_M.gguf",
                "name": "Qwen3.5-4B (Local Sentry - RX5600 6GB)",
                "reasoning": false,
                "input": ["text"],
                "contextWindow": 262144,
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
        "model": "zai/glm-5.1",
        "lastChangelogVersion": "auto",
        "defaultProvider": "zai",
        "defaultModel": "glm-5.1",
        "packages": $packages,
        "selfLearning": {
          "enabled": true,
          "autoAfterTask": true,
          "storage": {
            "mode": "global",
            "projectPath": "brain/self-learning",
            "globalPath": "~/brain"
          },
          "git": {
            "enabled": true,
            "autoCommit": true
          },
          "context": {
            "enabled": true,
            "includeCore": true,
            "includeLatestMonthly": false,
            "includeLastNDaily": 0,
            "maxChars": 12000,
            "instructionMode": "strict"
          },
          "model": {
            "provider": "zai",
            "id": "glm-5-turbo"
          }
        },
        "localModelDiscovery": {
          "providers": {
            "lmstudio": { "port": 1234, "apiKey": "lmstudio" },
            "llama-cpp": { "port": 1235, "apiKey": "unused" }
          },
          "excludePatterns": ["text-embedding-*"],
          "defaultContextWindow": 131072,
          "defaultMaxTokens": 8192
        }
      }' > "/home/${cfg.user}/.pi/agent/settings.json"
    chown -R ${cfg.user}:users "/home/${cfg.user}/.pi/agent"
    chmod 600 "/home/${cfg.user}/.pi/agent/models.json"
    chmod 600 "/home/${cfg.user}/.pi/agent/settings.json"
    echo "[ai-coding-tools] Pi config generated"
  '';
}
