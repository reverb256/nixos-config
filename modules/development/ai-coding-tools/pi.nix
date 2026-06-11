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

    mkdir -p "/home/${cfg.user}/.pi/agent"

    # Write mcp.json
    ${pkgs.jq}/bin/jq -n       --arg zai_key "$ZAI_API_KEY"       --arg gateway_base "${gatewayUrl}/v1"       '{
        "settings": {"idleTimeout": 10, "directTools": false},
        "mcpServers": {
          ${mkMcpServersJson {keyMode = "env";}}
        }
      }' > "/home/${cfg.user}/.pi/agent/mcp.json"

    # Write models.json
    ${pkgs.jq}/bin/jq -n       --arg gateway_base "${gatewayUrl}/v1"       '{
        "providers": {
          "gateway": {
            "baseUrl": ($gateway_base),
            "api": "openai-completions",
            "apiKey": "***",
            "models": [
              {"id": "glm-5.1", "name": "GLM-5.1"},
              {"id": "glm-5-turbo", "name": "GLM-5 Turbo"},
              {"id": "qwen/qwen3.5-397b-a17b", "name": "Qwen3.5-397B"}
            ]
          },
          "local-vllm": {
            "baseUrl": "http://10.1.1.120:8040/v1",
            "api": "openai-completions",
            "models": [{"id": "qwen3.5-2b-awq", "name": "Qwen 3.5 2B"}]
          }
        }
      }' > "/home/${cfg.user}/.pi/agent/models.json"

    chown -R ${cfg.user}:users "/home/${cfg.user}/.pi" 2>/dev/null || true
    chmod 644 "/home/${cfg.user}/.pi/agent/mcp.json" "/home/${cfg.user}/.pi/agent/models.json"
    echo "[ai-coding-tools] Pi config generated"
  '';
}
