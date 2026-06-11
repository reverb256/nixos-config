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
    ZAI_API_KEY="$(cat $ZAI_KEY_PATH 2>/dev/null || echo)"

    mkdir -p "/home/${cfg.user}/.omp/agent"

    # Write mcp.json
    ${pkgs.jq}/bin/jq -n       --arg zai_key "$ZAI_API_KEY"       --arg gateway_base "${gatewayUrl}/v1"       '{
        "settings": {"idleTimeout": 30},
        "mcpServers": {
          ${mkMcpServersJson {keyMode = "env";}}
        }
      }' > "/home/${cfg.user}/.omp/agent/mcp.json"

    # Write models.json
    ${pkgs.jq}/bin/jq -n       --arg gateway_base "${gatewayUrl}/v1"       '{
        "providers": {
          "gateway": {
            "baseUrl": ($gateway_base),
            "api": "openai-completions",
            "apiKey": "***",
            "models": [
              {"id": "glm-5.1", "name": "GLM-5.1", "reasoning": true},
              {"id": "glm-5-turbo", "name": "GLM-5 Turbo", "reasoning": true},
              {"id": "glm-4.7", "name": "GLM-4.7", "reasoning": true}
            ]
          },
          "local-vllm": {
            "baseUrl": "http://10.1.1.120:8040/v1",
            "api": "openai-completions",
            "models": [{"id": "qwen3.5-2b-awq", "name": "Qwen 3.5 2B"}]
          },
          "local-llama-zephyr": {
            "baseUrl": "http://10.1.1.110:1237/v1",
            "api": "openai-completions",
            "models": [{"id": "Qwen3.6-35B-A3B", "name": "Qwen3.6 35B"}]
          },
          "local-llama-sentry": {
            "baseUrl": "http://10.1.1.140:1235/v1",
            "api": "openai-completions",
            "models": [{"id": "Qwen3.5-4B", "name": "Qwen3.5 4B"}]
          }
        },
        "modelRoles": {
          "default": "glm-5.1",
          "smol": "glm-4.5-air",
          "code": "glm-4.7"
        }
      }' > "/home/${cfg.user}/.omp/agent/models.json"

    chown -R ${cfg.user}:users "/home/${cfg.user}/.omp" 2>/dev/null || true
    chmod 644 "/home/${cfg.user}/.omp/agent/mcp.json" "/home/${cfg.user}/.omp/agent/models.json"
    echo "[ai-coding-tools] OMP config generated"
  '';
}
