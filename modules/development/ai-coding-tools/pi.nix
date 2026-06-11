{
  cfg,
  pkgs,
  gatewayUrl,
  mkMcpServersJson,
}: {
  mkPiConfig = pkgs.writeShellScript "generate-pi-config" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    ZAI_KEY_PATH="${cfg.zaiApiKeyFile}"
    ZAI_API_KEY="$(cat $ZAI_KEY_PATH 2>/dev/null || echo)"
    NVIDIA_KEY_PATH="${cfg.nvidiaNimApiKeyFile}"
    NVIDIA_NIM_API_KEY="$(cat $NVIDIA_KEY_PATH 2>/dev/null || echo)"

    mkdir -p "/home/${cfg.user}/.pi/agent"

    # Write mcp.json
    ${pkgs.jq}/bin/jq -n \
      --arg zai_key "$ZAI_API_KEY" \
      --arg nvidia_key "$NVIDIA_NIM_API_KEY" \
      --arg gateway_base "${gatewayUrl}/v1" \
      '{
        "settings": {"idleTimeout": 10, "directTools": false},
        "mcpServers": {
          ${mkMcpServersJson {keyMode = "env";}}
        }
      }' > "/home/${cfg.user}/.pi/agent/mcp.json"

    # Write models.json — NIM direct primary, gateway fallback
    ${pkgs.jq}/bin/jq -n \
      --arg nvidia_key "$NVIDIA_NIM_API_KEY" \
      --arg gateway_base "${gatewayUrl}/v1" \
      '{
        "providers": {
          "nvidia-nim": {
            "baseUrl": "https://integrate.api.nvidia.com/v1",
            "api": "openai-completions",
            "apiKey": $nvidia_key,
            "models": [
              {"id": "nvidia/nemotron-3-super-120b-a12b", "name": "Nemotron 3 Super 120B", "context": 1000000},
              {"id": "nvidia/nemotron-3-ultra-550b-a55b", "name": "Nemotron 3 Ultra 550B", "context": 1000000},
              {"id": "meta/llama-3.2-90b-vision-instruct", "name": "Llama 3.2 90B Vision", "context": 131072},
              {"id": "mistralai/mistral-small-4-119b-2603", "name": "Mistral Small 4 119B", "context": 262144},
              {"id": "mistralai/mistral-large-3-675b-instruct-2512", "name": "Mistral Large 3 675B", "context": 262144}
            ]
          },
          "gateway": {
            "baseUrl": ($gateway_base),
            "api": "openai-completions",
            "apiKey": "internal",
            "models": [
              {"id": "glm-5.1", "name": "GLM-5.1"},
              {"id": "glm-5-turbo", "name": "GLM-5 Turbo"},
              {"id": "qwen/qwen3.5-397b-a17b", "name": "Qwen3.5-397B"}
            ]
          }
        }
      }' > "/home/${cfg.user}/.pi/agent/models.json"

    chown -R ${cfg.user}:users "/home/${cfg.user}/.pi" 2>/dev/null || true
    chmod 644 "/home/${cfg.user}/.pi/agent/mcp.json" "/home/${cfg.user}/.pi/agent/models.json"
    echo "[ai-coding-tools] Pi config generated"
  '';
}
