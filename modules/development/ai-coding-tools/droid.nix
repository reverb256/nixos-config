{
  cfg,
  pkgs,
  gatewayUrl,
  mkMcpServersJson,
}: {
  mkDroidMcpJson = pkgs.writeShellScript "generate-droid-mcp" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail
    ${pkgs.jq}/bin/jq -n \
      '{
        "mcpServers": {
          ${mkMcpServersJson {
      keyMode = "env";
      disabled = true;
    }}
        }
      }' > "/home/${cfg.user}/.factory/mcp.json"
    chown ${cfg.user}:users "/home/${cfg.user}/.factory/mcp.json"
    chmod 600 "/home/${cfg.user}/.factory/mcp.json"
    echo "[ai-coding-tools] Droid MCP config generated with env var references"
  '';

  mkDroidSettings = pkgs.writeShellScript "generate-droid-settings" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail
    NVIDIA_NIM_KEY_PATH="${cfg.nvidiaNimApiKeyFile}"
    NVIDIA_NIM_API_KEY="$(cat $NVIDIA_NIM_KEY_PATH 2>/dev/null || echo)"
    ${pkgs.jq}/bin/jq -n \
      --arg nvidia_key "$NVIDIA_NIM_API_KEY" \
      --arg gateway_base "${gatewayUrl}" \
      '{
        "enabledPlugins": {
          "core@factory-plugins": true
        },
        "logoAnimation": "off",
        "customModels": [
          {
            "model": "qwen3-coder-480b",
            "id": "custom:opencode-zen-deepseek",
            "index": 0,
                        "displayName": "OpenCode-5.1 [Orchestrator Tier - Planning, Architecture, Review]",
            "maxOutputTokens": 131072,
            "noImageSupport": false,
            "provider": "anthropic"
          },
          {
            "model": "qwen3-coder-480b",
            "id": "custom:opencode-zen-deepseek",
            "index": 1,
                        "displayName": "OpenCode-5 [Orchestrator Tier - 744B MoE, Agentic]",
            "maxOutputTokens": 131072,
            "noImageSupport": false,
            "provider": "anthropic"
          },
          {
            "model": "qwen3-coder-480b",
            "id": "custom:opencode-zen-deepseek",
            "index": 2,
                        "displayName": "OpenCode-4.7 [Worker Tier - 358B MoE, Coding King]",
            "maxOutputTokens": 131072,
            "noImageSupport": false,
            "provider": "anthropic"
          },
          {
            "model": "qwen3-coder-480b-turbo",
            "id": "custom:OpenCode-5-Turbo-Z.AI-Anthropic-4",
            "index": 4,
                        "displayName": "OpenCode-5 Turbo [Orchestrator Tier - Agentic, Fast]",
            "maxOutputTokens": 131072,
            "noImageSupport": true,
            "provider": "anthropic"
          },
          {
            "model": "qwen3-coder-480b-flash",
            "id": "custom:OpenCode-4.7-Flash-Z.AI-Anthropic-5",
            "index": 5,
                        "displayName": "OpenCode-4.7 Flash [Worker Tier - 30B MoE, Vision]",
            "maxOutputTokens": 8192,
            "noImageSupport": false,
            "provider": "anthropic"
          },
          {
            "model": "qwen3.5-4b",
            "id": "custom:Qwen3.5-4B-Gateway-OpenAI-6",
            "index": 6,
            "baseUrl": ($gateway_base + "/v1"),
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
            "baseUrl": ($gateway_base + "/v1"),
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
            "baseUrl": ($gateway_base + "/v1"),
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
            "baseUrl": ($gateway_base + "/v1"),
            "apiKey": $nvidia_key,
            "displayName": "Llama 3.1 70B [NVIDIA NIM - Free]",
            "maxOutputTokens": 4096,
            "noImageSupport": true,
            "provider": "openai"
          }
        ],
        "sessionDefaultSettings": {
          "model": "custom:opencode-zen-deepseek",
          "reasoningEffort": "high",
          "interactionMode": "auto",
          "autonomyLevel": "high",
          "autonomyMode": "auto-high"
        },
        "hasSeenMissionOnboarding": true,
        "missionModelSettings": {
          "workerModel": "custom:opencode-zen-deepseek",
          "workerReasoningEffort": "none",
          "validationWorkerModel": "custom:OpenCode-5-Turbo-Z.AI-Anthropic-4",
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
}
