{
  cfg,
  pkgs,
  gatewayUrl,
  nvidiaNimBaseUrl,
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
    echo "[ai-coding-tools] Droid MCP config generated"
  '';

  mkDroidSettings = pkgs.writeShellScript "generate-droid-settings" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail
    NVIDIA_NIM_KEY_PATH="${cfg.nvidiaNimApiKeyFile}"
    NVIDIA_NIM_API_KEY="$(cat $NVIDIA_NIM_KEY_PATH 2>/dev/null || echo)"
    ${pkgs.jq}/bin/jq -n \
      --arg nvidia_key "$NVIDIA_NIM_API_KEY" \
      --arg gateway_base "${gatewayUrl}/v1" \
      --arg nvidia_base "${nvidiaNimBaseUrl}" \
      '{
        "enabledPlugins": {
          "core@factory-plugins": true
        },
        "logoAnimation": "off",
        "customModels": [
          {
            "model": "qwen3.5-4b",
            "id": "custom:Qwen3.5-4B-Gateway-OpenAI-0",
            "index": 0,
            "baseUrl": ($gateway_base),
            "apiKey": "k8s-gateway",
            "displayName": "Qwen 3.5 4B [K8s Gateway - llama.cpp]",
            "maxOutputTokens": 8192,
            "noImageSupport": true,
            "provider": "openai"
          },
          {
            "model": "qwen3.5-32b",
            "id": "custom:Qwen3.5-32B-Gateway-OpenAI-1",
            "index": 1,
            "baseUrl": ($gateway_base),
            "apiKey": "k8s-gateway",
            "displayName": "Qwen 3.5 32B [K8s Gateway - vLLM]",
            "maxOutputTokens": 8192,
            "noImageSupport": true,
            "provider": "openai"
          },
          {
            "model": "deepseek-r1",
            "id": "custom:DeepSeek-R1-Gateway-OpenAI-2",
            "index": 2,
            "baseUrl": ($gateway_base),
            "apiKey": "k8s-gateway",
            "displayName": "DeepSeek R1 [K8s Gateway - SGLang]",
            "maxOutputTokens": 8192,
            "noImageSupport": true,
            "provider": "openai"
          },
          {
            "model": "meta/llama-3.1-70b-instruct",
            "id": "custom:Llama-3.1-70B-NVIDIA-NIM-OpenAI-3",
            "index": 3,
            "baseUrl": ($nvidia_base),
            "apiKey": $nvidia_key,
            "displayName": "Llama 3.1 70B [NVIDIA NIM]",
            "maxOutputTokens": 4096,
            "noImageSupport": true,
            "provider": "openai"
          }
        ],
        "sessionDefaultSettings": {
          "model": "custom:Qwen3.5-4B-Gateway-OpenAI-0",
          "reasoningEffort": "high",
          "interactionMode": "auto",
          "autonomyLevel": "high",
          "autonomyMode": "auto-high"
        },
        "hasSeenMissionOnboarding": true,
        "missionModelSettings": {
          "workerModel": "custom:Qwen3.5-4B-Gateway-OpenAI-0",
          "workerReasoningEffort": "none",
          "validationWorkerModel": "custom:Qwen3.5-32B-Gateway-OpenAI-1",
          "validationWorkerReasoningEffort": "none"
        },
        "terminalColorMode": "dark",
        "cloudSessionSync": true,
        "ideAutoConnect": true
      }' > "/home/${cfg.user}/.factory/settings.json"
    chown ${cfg.user}:users "/home/${cfg.user}/.factory/settings.json"
    chmod 600 "/home/${cfg.user}/.factory/settings.json"
    echo "[ai-coding-tools] Droid settings generated"
  '';
}
