{
  cfg,
  pkgs,
  gatewayUrl,
  mkMcpServersJson,
}: {
  mkOmpConfig = pkgs.writeShellScript "generate-omp-config" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    ZAI_KEY_PATH="${cfg.zaiApiKeyFile}"
    ZAI_API_KEY=*** $ZAI_KEY_PATH 2>/dev/null || echo)"
    NVIDIA_KEY_PATH="${cfg.nvidiaNimApiKeyFile}"
    NVIDIA_NIM_API_KEY=*** $NVIDIA_KEY_PATH 2>/dev/null || echo)"

    mkdir -p "/home/${cfg.user}/.omp/agent"

    # Write mcp.json
    ${pkgs.jq}/bin/jq -n \
      --arg zai_key "$ZAI_API_KEY" \
      --arg nvidia_key "$NVIDIA_NIM_API_KEY" \
      --arg gateway_base "${gatewayUrl}/v1" \
      '{
        "settings": {"idleTimeout": 30},
        "mcpServers": {
          ${mkMcpServersJson {keyMode = "env";}}
        }
      }' > "/home/${cfg.user}/.omp/agent/mcp.json"

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
              {"id": "nvidia/nemotron-3-super-120b-a12b", "name": "Nemotron 3 Super 120B", "context": 1000000, "reasoning": true},
              {"id": "nvidia/nemotron-3-ultra-550b-a55b", "name": "Nemotron 3 Ultra 550B", "context": 1000000, "reasoning": true},
              {"id": "meta/llama-3.2-90b-vision-instruct", "name": "Llama 3.2 90B Vision", "vision": true},
              {"id": "mistralai/mistral-small-4-119b-2603", "name": "Mistral Small 4 119B", "context": 262144}
            ]
          },
          "gateway": {
            "baseUrl": ($gateway_base),
            "api": "openai-completions",
            "models": [
              {"id": "glm-5.1", "name": "GLM-5.1", "reasoning": true},
              {"id": "glm-5-turbo", "name": "GLM-5 Turbo", "reasoning": true},
              {"id": "glm-4.7", "name": "GLM-4.7", "reasoning": true}
            ]
          }
        },
        "modelRoles": {
          "default": "nvidia/nemotron-3-super-120b-a12b",
          "smol": "mistralai/mistral-small-4-119b-2603",
          "code": "nvidia/nemotron-3-super-120b-a12b"
        }
      }' > "/home/${cfg.user}/.omp/agent/models.json"

    chown -R ${cfg.user}:users "/home/${cfg.user}/.omp" 2>/dev/null || true
    chmod 644 "/home/${cfg.user}/.omp/agent/mcp.json" "/home/${cfg.user}/.omp/agent/models.json"
    echo "[ai-coding-tools] OMP config generated"
  '';
}
