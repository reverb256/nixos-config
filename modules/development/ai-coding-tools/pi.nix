{
  cfg,
  pkgs,
  gatewayUrl,
  mkMcpServersJson,
}: {
  mkPiConfig = pkgs.writeShellScript "generate-pi-config" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail


    mkdir -p "/home/${cfg.user}/.pi/agent"

    # Write mcp.json
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
            "models": [,,
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
