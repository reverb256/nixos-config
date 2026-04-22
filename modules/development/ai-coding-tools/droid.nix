{
  cfg,
  pkgs,
  mkMcpServersJson,
}:
{
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
            "baseUrl": "http://10.1.1.120:8080/v1",
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
            "baseUrl": "http://10.1.1.120:8080/v1",
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
            "baseUrl": "http://10.1.1.120:8080/v1",
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
            "baseUrl": "http://10.1.1.120:8080/v1",
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
}
